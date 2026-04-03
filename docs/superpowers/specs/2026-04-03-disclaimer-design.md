# First-launch Disclaimer Dialog — Design Spec

**Date:** 2026-04-03  
**Status:** Approved

---

## Overview

Show a modal disclaimer window on the very first launch of DexBar. The user must either accept (proceed) or decline (quit the app). Once accepted, the dialog never appears again. Nothing in `AppDelegate` initialises until acceptance is recorded.

---

## New Files

Both files go in `DexBar/` alongside the rest of the app source.

### `DisclaimerView.swift`

A self-contained SwiftUI view. Responsibilities:

- Render four disclaimer sections (see *Content* below), each with an SF Symbol icon, a bold title, and a short body paragraph.
- Show two buttons at the bottom:
  - **"I understand and accept"** — primary style, `.keyboardShortcut(.defaultAction)` (Return key activates it). Calls `onAccept`.
  - **"I do not accept — close the app"** — no keyboard shortcut. Calls `onDecline`.
- Fixed width of 440 pt; height auto-sized by SwiftUI layout (no hardcoded height).
- Receives two callbacks: `onAccept: () -> Void` and `onDecline: () -> Void`.

#### Content (four sections)

| SF Symbol | Bold title | Body text |
|---|---|---|
| `person.fill` | Personal use only | Hobby project. Not affiliated with, endorsed by, or sponsored by Dexcom or Glooko. Non-commercial. |
| `exclamationmark.triangle.fill` | Unofficial & undocumented APIs | Uses private/undocumented APIs that may change or disappear at any time. Continued use may violate Dexcom's and/or Glooko's Terms of Service. |
| `cross.circle.fill` | Not medical advice | DexBar is **not** a medical device and is **not** approved for clinical use. Never make treatment or dosing decisions based on data shown here. Always rely on your approved CGM device and consult your healthcare provider. |
| `exclamationmark.shield.fill` | No warranties or guarantees | Provided as-is with no warranty of any kind. Data may be inaccurate, delayed, or missing. You are solely responsible for any consequences of using this software. |

---

### `DisclaimerWindowController.swift`

An `NSWindowController` subclass. Responsibilities:

- **`static func showIfNeeded(then proceed: @escaping () -> Void)`** — the single public API.
  - Reads `UserDefaults.standard.bool(forKey: "hasAcceptedDisclaimer")`.
    - `true` → call `proceed()` immediately and return. No window is created.
    - `false` → create the window, show it centred, activate the app.
  - The `proceed` callback is stored and called only after the user taps accept.

- **UserDefaults key**: `"hasAcceptedDisclaimer"` (Bool).
  - Deleting this key from `UserDefaults` (e.g. via `defaults delete com.oskarhagberg.DexBar hasAcceptedDisclaimer` in Terminal) resets the disclaimer for testing.
  - A comment in the source explains this.

- **Window configuration**:
  - `styleMask`: `.titled`, `.closable` (red ✕ is visible but intercepted — see below).
  - Title: `"DexBar — Before You Continue"`.
  - No resize handle.
  - Content view: `NSHostingView` wrapping `DisclaimerView`.
  - Centred on screen via `window.center()`.
  - `NSApp.activate(ignoringOtherApps: true)` so the window comes to front.

- **Red ✕ close button = quit**: The controller acts as its own `NSWindowDelegate`. `windowShouldClose(_:)` calls `NSApp.terminate(nil)` and returns `false` — identical semantics to the decline button. There is no way to dismiss the dialog without choosing one of the two options.

- **Accept flow**:
  1. Set `UserDefaults.standard.set(true, forKey: "hasAcceptedDisclaimer")`.
  2. Close the window.
  3. Call `proceed()`.

- **Decline flow**:
  1. `NSApp.terminate(nil)`.

---

## Wiring into AppDelegate

In `AppDelegate.applicationDidFinishLaunching(_:)`, wrap all existing startup logic:

```swift
func applicationDidFinishLaunching(_ notification: Notification) {
    DisclaimerWindowController.showIfNeeded { [weak self] in
        guard let self else { return }
        // ... existing startup code verbatim ...
    }
}
```

`showIfNeeded` calls `proceed` synchronously when the disclaimer has already been accepted, so there is no observable startup delay on subsequent launches.

---

## What Is Not Changing

- No changes to `DexBarApp.swift`.
- No changes to `GlucoseWebViewController`, `DexcomClient`, `GlucoseStats`, or any other file.
- The disclaimer does **not** block `NSStatusItem` creation — that happens inside the closure after acceptance.

---

## Testing

- Delete `hasAcceptedDisclaimer` from `UserDefaults` to re-trigger the dialog.
- Verify Return key triggers accept.
- Verify red ✕ and decline button both quit the app.
- Verify that on subsequent launches the dialog is skipped entirely and the app starts normally.
