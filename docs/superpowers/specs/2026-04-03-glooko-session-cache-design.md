# Glooko Session Cookie Cache — Design Spec

**Date:** 2026-04-03  
**Status:** Approved

---

## Problem

On every app launch, DexBar calls `signIn` (POST `/api/v3/users/sign_in`) to obtain a fresh Glooko session cookie. During rapid restarts (e.g. development) the endpoint rate-limits and returns no cookie, causing Glooko data to silently fail to load.

---

## Solution

Cache the session cookie in the Keychain alongside the existing Glooko credentials. On startup, attempt to reuse the cached cookie. Only call `signIn` if no cached cookie is available or if the cached cookie is rejected.

---

## Architecture

Three layers of change, each with a single responsibility:

1. **`KeychainHelper`** — stores and loads the cached cookie
2. **`GlookoService`** — tries the cached cookie before signing in; fires a callback when a new cookie is obtained
3. **`AppDelegate`** — wires the callback so new cookies are persisted; clears the cache on sign-out

`GlookoService` never accesses the Keychain directly.

---

## Changes

### 1. `KeychainHelper` (in `AppDelegate.swift`)

Add `glookoSessionCookie: String?` to `AllCredentials`:

```swift
private struct AllCredentials: Codable {
    var username: String?
    var password: String?
    var glookoEmail: String?
    var glookoPassword: String?
    var glookoSessionCookie: String?   // NEW
}
```

Add two new static methods:

```swift
static func saveGlookoSessionCookie(_ cookie: String) {
    var all = loadAll()
    all.glookoSessionCookie = cookie
    saveAll(all)
}

static func loadGlookoSessionCookie() -> String? {
    return loadAll().glookoSessionCookie
}
```

Cookie is cleared by setting `glookoSessionCookie = nil` and calling `saveAll`. The existing `deleteGlookoCredentials()` must be extended to also clear the cookie so sign-out leaves no stale cookie.

### 2. `GlookoService`

**New property:**

```swift
var onNewSessionCookie: ((String) -> Void)?
```

Called whenever the service obtains a new valid session cookie — both from a fresh `signIn` and from a 401-triggered re-auth. `GlookoService` does not persist the cookie itself.

**Modified `authenticate` signature:**

```swift
func authenticate(
    email: String,
    password: String,
    cachedCookie: String? = nil,
    completion: @escaping (Bool, String?) -> Void
)
```

New behaviour when `cachedCookie` is provided:
1. Try `fetchGlookoCode(cookie: cachedCookie)` directly (skip `signIn`).
2. If `fetchGlookoCode` succeeds → store `sessionCookie` and `glookoCode` in memory, fire `onNewSessionCookie(cachedCookie)`, call `completion(true, nil)`.
3. If `fetchGlookoCode` fails (nil) → fall through to the normal `signIn` path.

When `signIn` produces a cookie, fire `onNewSessionCookie(cookie)` before calling `fetchGlookoCode`.

**401 retry path** (already in `doFetchHistories`): calls `self.authenticate(email:password:)` — no cached cookie is passed, so it always does a full `signIn`. The `onNewSessionCookie` callback fires naturally when sign-in succeeds, persisting the new cookie automatically.

### 3. `AppDelegate`

In `applicationDidFinishLaunching` (inside the `showIfNeeded` closure), when setting up Glooko:

```swift
// Wire cookie persistence before authenticating
glooko.onNewSessionCookie = { KeychainHelper.saveGlookoSessionCookie($0) }

if let glookoCreds = KeychainHelper.loadGlookoCredentials() {
    let cachedCookie = KeychainHelper.loadGlookoSessionCookie()
    glooko.authenticate(
        email: glookoCreds.email,
        password: glookoCreds.password,
        cachedCookie: cachedCookie
    ) { [weak self] ok, _ in
        guard let self, ok else { return }
        self.fetchGlookoData()
        DispatchQueue.main.async { self.startGlookoPolling() }
    }
}
```

In `deleteGlookoCredentials` (called on Glooko sign-out, via `glookoSignOut()`): extend to also call `KeychainHelper.deleteGlookoSessionCookie()` — or simply clear the field inside the existing `deleteGlookoCredentials` implementation.

---

## Error Handling

- If `fetchGlookoCode` fails with a cached cookie, the service silently falls back to `signIn`. No error is surfaced to the user.
- If `signIn` also fails (rate limit, bad credentials, network), `completion(false, errorMessage)` is called as today — no change to error reporting.
- The Keychain is not cleared on `fetchGlookoCode` failure to avoid unnecessary writes; the new cookie from `signIn` will overwrite it.

---

## What Is Not Changing

- `fetchPumpEvents` and `doFetchHistories` — no changes
- The 401 retry logic inside `doFetchHistories` — no changes, it already re-auths correctly; the `onNewSessionCookie` callback will fire and persist the result
- `GlucoseStats`, `DexcomClient`, or any other file — untouched
- The public `clearSession()` method on `GlookoService` — no change (in-memory only, as today)

---

## Testing

- **`GlookoServiceTests`**: add tests for `authenticate` with a valid cached cookie (skips `signIn`), with an invalid cached cookie (falls back to `signIn`), and that `onNewSessionCookie` fires in both success paths.
- **`KeychainHelper`**: no unit tests needed (Keychain is an external dependency; tested via integration).
- Existing `GlookoServiceNetworkTests` must still pass unchanged.
