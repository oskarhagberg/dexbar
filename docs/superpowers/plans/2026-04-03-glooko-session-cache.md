# Glooko Session Cookie Cache — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cache the Glooko session cookie in the Keychain so rapid app restarts skip the `sign_in` request that can be rate-limited.

**Architecture:** Three layers — `KeychainHelper` gains cookie storage, `GlookoService.authenticate` gains an optional `cachedCookie` parameter and an `onNewSessionCookie` callback, and `AppDelegate` wires them together. `GlookoService` stays Keychain-free; `AppDelegate` owns persistence.

**Tech Stack:** Swift, Foundation, Security (Keychain via `KeychainHelper`), Swift Testing, `MockURLProtocol`.

---

## File Map

| Action | Path |
|--------|------|
| Modify | `DexBar/AppDelegate.swift` — `KeychainHelper` struct (lines 14–97) + `applicationDidFinishLaunching` closure + `glookoSignOut()` |
| Modify | `DexBar/GlookoService.swift` — `authenticate`, new private `fullSignIn`, new property |
| Modify | `DexBarTests/NetworkTests.swift` — add three new tests inside `GlookoServiceNetworkTests` |

---

## Task 1: KeychainHelper — cookie storage

**Files:**
- Modify: `DexBar/AppDelegate.swift` — `AllCredentials` struct + `KeychainHelper` Glooko section

No unit tests for Keychain (external dependency; correct behaviour confirmed by integration in Task 3).

- [ ] **Step 1: Add `glookoSessionCookie` to `AllCredentials`**

In `DexBar/AppDelegate.swift`, find `AllCredentials` (around line 20) and add the new field:

```swift
private struct AllCredentials: Codable {
    var username: String?
    var password: String?
    var glookoEmail: String?
    var glookoPassword: String?
    var glookoSessionCookie: String?
}
```

- [ ] **Step 2: Add save/load methods for the cookie**

Find the `// MARK: - Glooko credentials` block (around line 76) and add two methods **after** `deleteGlookoCredentials`:

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

- [ ] **Step 3: Extend `deleteGlookoCredentials` to also clear the cookie**

Find `deleteGlookoCredentials` and update it:

```swift
static func deleteGlookoCredentials() {
    var all = loadAll()
    all.glookoEmail = nil
    all.glookoPassword = nil
    all.glookoSessionCookie = nil
    saveAll(all)
}
```

- [ ] **Step 4: Build**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -scheme DexBar -destination 'platform=macOS' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add DexBar/AppDelegate.swift
git commit -m "feat: add glookoSessionCookie to KeychainHelper"
```

---

## Task 2: GlookoService — cached cookie support

**Files:**
- Modify: `DexBar/GlookoService.swift`
- Modify: `DexBarTests/NetworkTests.swift` (add tests inside `GlookoServiceNetworkTests`)

- [ ] **Step 1: Write the three failing tests**

In `DexBarTests/NetworkTests.swift`, inside `GlookoServiceNetworkTests` (after `clearSessionResetsState`), add:

```swift
@Test func authenticate_withValidCachedCookie_skipsSignIn() async {
    var callCount = 0
    MockURLProtocol.handler = { req in
        callCount += 1
        // Only session/users should be called — sign_in must be skipped
        let data = #"{"currentUser":{"glookoCode":"eu-west-1-code","timezone":"UTC","meterUnits":"mmoll"}}"#.data(using: .utf8)!
        return (data, HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
    let result: (Bool, String?) = await withCheckedContinuation { cont in
        svc.authenticate(email: "u@test.com", password: "p",
                         cachedCookie: "_logbook-web_session=cached123") { ok, err in
            cont.resume(returning: (ok, err))
        }
    }
    #expect(result.0 == true)
    #expect(callCount == 1)  // only session/users, no sign_in
}

@Test func authenticate_withInvalidCachedCookie_fallsBackToSignIn() async {
    var callCount = 0
    MockURLProtocol.handler = { req in
        callCount += 1
        let url = req.url!
        if callCount == 1 {
            // fetchGlookoCode with stale cookie — bad JSON triggers fallback
            return ("{\"error\":\"unauthorized\"}".data(using: .utf8)!,
                    HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil)!)
        } else if callCount == 2 {
            // sign_in — return new cookie
            let data = #"{"two_fa_required":false,"success":true}"#.data(using: .utf8)!
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                headerFields: ["Set-Cookie": "_logbook-web_session=newcookie456; domain=glooko.com; path=/"])!
            return (data, response)
        } else {
            // fetchGlookoCode with new cookie — succeed
            let data = #"{"currentUser":{"glookoCode":"eu-west-1-code","timezone":"UTC","meterUnits":"mmoll"}}"#.data(using: .utf8)!
            return (data, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
    }
    let result: (Bool, String?) = await withCheckedContinuation { cont in
        svc.authenticate(email: "u@test.com", password: "p",
                         cachedCookie: "_logbook-web_session=stale") { ok, err in
            cont.resume(returning: (ok, err))
        }
    }
    #expect(result.0 == true)
    #expect(callCount == 3)
}

@Test func authenticate_firesOnNewSessionCookieCallback() async {
    MockURLProtocol.handler = { req in
        let data = #"{"currentUser":{"glookoCode":"code","timezone":"UTC","meterUnits":"mmoll"}}"#.data(using: .utf8)!
        return (data, HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
    var capturedCookie: String?
    svc.onNewSessionCookie = { capturedCookie = $0 }

    await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
        svc.authenticate(email: "u@test.com", password: "p",
                         cachedCookie: "_logbook-web_session=cached999") { _, _ in cont.resume() }
    }
    #expect(capturedCookie == "_logbook-web_session=cached999")
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild test -scheme DexBar -destination 'platform=macOS' \
  -only-testing:DexBarTests/NetworkTests/GlookoService\ network \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO 2>&1 | tail -15
```
Expected: compile error — `cachedCookie` parameter and `onNewSessionCookie` property do not exist yet.

- [ ] **Step 3: Add `onNewSessionCookie` property and modify `GlookoService`**

Open `DexBar/GlookoService.swift`.

**3a.** After `private var cachedPassword: String?` (around line 26), add:

```swift
/// Called whenever the service obtains a new valid session cookie.
/// AppDelegate uses this to persist the cookie to the Keychain.
var onNewSessionCookie: ((String) -> Void)?
```

**3b.** Replace the existing `authenticate(email:password:completion:)` method and add a new private `fullSignIn` helper. Find the `// MARK: - Public API` section and replace `authenticate` (the whole method, lines ~34–53) with:

```swift
func authenticate(
    email: String,
    password: String,
    cachedCookie: String? = nil,
    completion: @escaping (Bool, String?) -> Void
) {
    cachedEmail = email
    cachedPassword = password
    if let cached = cachedCookie {
        fetchGlookoCode(cookie: cached) { [weak self] code in
            guard let self else { return }
            if let code {
                self.sessionCookie = cached
                self.glookoCode = code
                dlog("[Glooko] Resumed session with cached cookie. glookoCode: \(code)")
                self.onNewSessionCookie?(cached)
                completion(true, nil)
            } else {
                dlog("[Glooko] Cached cookie rejected — falling back to sign_in")
                self.fullSignIn(email: email, password: password, completion: completion)
            }
        }
    } else {
        fullSignIn(email: email, password: password, completion: completion)
    }
}

private func fullSignIn(email: String, password: String, completion: @escaping (Bool, String?) -> Void) {
    signIn(email: email, password: password) { [weak self] cookie in
        guard let self, let cookie else {
            completion(false, "Could not sign in to Glooko. Check your email and password.")
            return
        }
        self.onNewSessionCookie?(cookie)
        self.fetchGlookoCode(cookie: cookie) { [weak self] code in
            guard let self, let code else {
                completion(false, "Signed in but could not retrieve Glooko patient ID.")
                return
            }
            self.sessionCookie = cookie
            self.glookoCode = code
            dlog("[Glooko] Authenticated. glookoCode: \(code)")
            completion(true, nil)
        }
    }
}
```

Note: the `doFetchHistories` 401-retry path calls `self.authenticate(email:password:)` with no `cachedCookie` — it will use `fullSignIn` automatically. `onNewSessionCookie` will fire and the new cookie will be persisted via `AppDelegate`'s callback.

- [ ] **Step 4: Run tests**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild test -scheme DexBar -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO 2>&1 | grep -E "passed|failed|error:" | tail -20
```
Expected: all tests pass, including the three new ones.

- [ ] **Step 5: Commit**

```bash
git add DexBar/GlookoService.swift DexBarTests/NetworkTests.swift
git commit -m "feat: add session cookie cache support to GlookoService"
```

---

## Task 3: AppDelegate — wire it up

**Files:**
- Modify: `DexBar/AppDelegate.swift` — `applicationDidFinishLaunching` closure + `glookoSignOut()`

- [ ] **Step 1: Wire callback and cached cookie in startup**

In `DexBar/AppDelegate.swift`, find the Glooko block inside `applicationDidFinishLaunching` (inside the `showIfNeeded` closure):

```swift
// Load Glooko credentials and authenticate in background if present
if let glookoCreds = KeychainHelper.loadGlookoCredentials() {
    glooko.authenticate(email: glookoCreds.email, password: glookoCreds.password) { [weak self] ok, _ in
        guard let self, ok else { return }
        self.fetchGlookoData()
        DispatchQueue.main.async { self.startGlookoPolling() }
    }
}
```

Replace it with:

```swift
// Load Glooko credentials and authenticate in background if present
if let glookoCreds = KeychainHelper.loadGlookoCredentials() {
    glooko.onNewSessionCookie = { KeychainHelper.saveGlookoSessionCookie($0) }
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

- [ ] **Step 2: Clear cookie on sign-out**

Find `glookoSignOut()` (around line 427). `deleteGlookoCredentials()` already clears the cookie (extended in Task 1), so no further change is needed here — just verify the call is present:

```swift
func glookoSignOut() {
    glookoTimer?.invalidate()
    glookoTimer = nil
    glooko.clearSession()
    KeychainHelper.deleteGlookoCredentials()   // now also clears cookie
    glookoPumpEvents = []
    // Push empty events to clear chart dots
    guard let latest = latestReading else { return }
    let t = GlucoseThresholdsStore.current
    // ... rest unchanged
```

If the body already matches, no edit is needed.

- [ ] **Step 3: Build**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -scheme DexBar -destination 'platform=macOS' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Run all tests**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild test -scheme DexBar -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO 2>&1 | grep -E "passed|failed|error:" | tail -20
```
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add DexBar/AppDelegate.swift
git commit -m "feat: wire Glooko session cookie cache in AppDelegate"
```
