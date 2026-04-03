# First-launch Disclaimer Dialog — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a one-time disclaimer dialog on first launch; nothing in AppDelegate initialises until the user accepts.

**Architecture:** Two new files (`DisclaimerView.swift`, `DisclaimerWindowController.swift`) in `DexBar/`. `applicationDidFinishLaunching` in `AppDelegate.swift` is wrapped in a `DisclaimerWindowController.showIfNeeded { ... }` call. If the user has already accepted, the closure fires synchronously and startup is unchanged.

**Tech Stack:** Swift, SwiftUI (`DisclaimerView`), AppKit (`NSWindowController`, `NSHostingView`), Swift Testing (unit test), `UserDefaults`.

---

## File Map

| Action | Path |
|--------|------|
| Create | `DexBar/DisclaimerView.swift` |
| Create | `DexBar/DisclaimerWindowController.swift` |
| Modify | `DexBar/AppDelegate.swift` — `applicationDidFinishLaunching` only |
| Create  | `DexBarTests/DisclaimerWindowControllerTests.swift` |

---

## Task 1: DisclaimerView

**Files:**
- Create: `DexBar/DisclaimerView.swift`

- [ ] **Step 1: Create the file**

Create `DexBar/DisclaimerView.swift` with this exact content:

```swift
//  DisclaimerView.swift
//  DexBar

import SwiftUI

struct DisclaimerView: View {
    let onAccept: () -> Void
    let onDecline: () -> Void

    private struct Section {
        let symbol: String
        let title: String
        let body: String
    }

    private let sections: [Section] = [
        Section(
            symbol: "person.fill",
            title: "Personal use only",
            body: "Hobby project. Not affiliated with, endorsed by, or sponsored by Dexcom or Glooko. Non-commercial."
        ),
        Section(
            symbol: "exclamationmark.triangle.fill",
            title: "Unofficial & undocumented APIs",
            body: "Uses private/undocumented APIs that may change or disappear at any time. Continued use may violate Dexcom's and/or Glooko's Terms of Service."
        ),
        Section(
            symbol: "cross.circle.fill",
            title: "Not medical advice",
            body: "DexBar is not a medical device and is not approved for clinical use. Never make treatment or dosing decisions based on data shown here. Always rely on your approved CGM device and consult your healthcare provider."
        ),
        Section(
            symbol: "exclamationmark.shield.fill",
            title: "No warranties or guarantees",
            body: "Provided as-is with no warranty of any kind. Data may be inaccurate, delayed, or missing. You are solely responsible for any consequences of using this software."
        )
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Before You Continue")
                .font(.title2)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 4)

            ForEach(sections, id: \.title) { section in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: section.symbol)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(section.title)
                            .fontWeight(.semibold)
                        Text(section.body)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            HStack {
                Button("I do not accept — close the app", action: onDecline)
                Spacer()
                Button("I understand and accept", action: onAccept)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}
```

- [ ] **Step 2: Add file to Xcode target**

In Xcode, right-click the `DexBar` group → Add Files → select `DisclaimerView.swift`. Confirm it is added to the `DexBar` target (not the test target).

- [ ] **Step 3: Build to verify no compile errors**

In Xcode: Product → Build (⌘B).  
Expected: Build Succeeded. No errors in `DisclaimerView.swift`.

- [ ] **Step 4: Commit**

```bash
git add DexBar/DisclaimerView.swift
git commit -m "feat: add DisclaimerView with four disclaimer sections"
```

---

## Task 2: DisclaimerWindowController

**Files:**
- Create: `DexBar/DisclaimerWindowController.swift`
- Create: `DexBarTests/DisclaimerWindowControllerTests.swift`

- [ ] **Step 1: Write the failing test**

Create `DexBarTests/DisclaimerWindowControllerTests.swift`:

```swift
//  DisclaimerWindowControllerTests.swift
//  DexBarTests

import Testing
import Foundation
@testable import DexBar

@Suite("DisclaimerWindowController")
struct DisclaimerWindowControllerTests {

    // Cleanup helper — always remove the key so tests are isolated
    private func cleanUp() {
        UserDefaults.standard.removeObject(forKey: "hasAcceptedDisclaimer")
    }

    @Test func showIfNeeded_whenAlreadyAccepted_callsProceedSynchronously() {
        UserDefaults.standard.set(true, forKey: "hasAcceptedDisclaimer")
        defer { cleanUp() }

        var called = false
        DisclaimerWindowController.showIfNeeded { called = true }

        #expect(called == true)
    }

    @Test func showIfNeeded_whenNotYetAccepted_doesNotCallProceedImmediately() {
        cleanUp()   // ensure key is absent
        defer { cleanUp() }

        var called = false
        // showIfNeeded will try to create a window; in the test runner there is no
        // screen, so we rely only on observing that `proceed` is NOT called synchronously.
        // The window controller holds itself alive via `shared`; terminate is not called.
        DisclaimerWindowController.showIfNeeded { called = true }

        #expect(called == false)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

In Xcode: Product → Test (⌘U), or run:
```bash
xcodebuild test -scheme DexBar -destination 'platform=macOS' -only-testing:DexBarTests/DisclaimerWindowControllerTests 2>&1 | tail -20
```
Expected: compile error — `DisclaimerWindowController` does not exist yet.

- [ ] **Step 3: Create DisclaimerWindowController.swift**

Create `DexBar/DisclaimerWindowController.swift`:

```swift
//  DisclaimerWindowController.swift
//  DexBar

import AppKit
import SwiftUI

final class DisclaimerWindowController: NSWindowController, NSWindowDelegate {

    // UserDefaults key that gates the disclaimer.
    // To reset for testing: defaults delete com.oskarhagberg.DexBar hasAcceptedDisclaimer
    static let acceptedKey = "hasAcceptedDisclaimer"

    // Retained for the lifetime of the dialog.
    private static var shared: DisclaimerWindowController?

    private var onProceed: (() -> Void)?

    // MARK: - Public API

    static func showIfNeeded(then proceed: @escaping () -> Void) {
        if UserDefaults.standard.bool(forKey: acceptedKey) {
            proceed()
            return
        }
        shared = DisclaimerWindowController(onProceed: proceed)
        shared?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Init

    private init(onProceed: @escaping () -> Void) {
        self.onProceed = onProceed

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "DexBar — Before You Continue"
        window.isReleasedWhenClosed = false

        super.init(window: window)

        window.delegate = self

        let view = DisclaimerView(
            onAccept: { [weak self] in self?.accept() },
            onDecline: { NSApp.terminate(nil) }
        )
        let hosting = NSHostingView(rootView: view)
        window.contentView = hosting
        window.setContentSize(hosting.fittingSize)
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: - Actions

    private func accept() {
        UserDefaults.standard.set(true, forKey: Self.acceptedKey)
        window?.close()
        let proceed = onProceed
        Self.shared = nil   // release the controller
        proceed?()
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Red ✕ button quits — same as declining.
        NSApp.terminate(nil)
        return false
    }
}
```

- [ ] **Step 4: Add both files to Xcode targets**

- `DexBar/DisclaimerWindowController.swift` → add to `DexBar` target
- `DexBarTests/DisclaimerWindowControllerTests.swift` → add to `DexBarTests` target

- [ ] **Step 5: Run the tests to verify they pass**

```bash
xcodebuild test -scheme DexBar -destination 'platform=macOS' -only-testing:DexBarTests/DisclaimerWindowControllerTests 2>&1 | tail -20
```
Expected: Both tests pass. `showIfNeeded_whenAlreadyAccepted_callsProceedSynchronously` — PASS. `showIfNeeded_whenNotYetAccepted_doesNotCallProceedImmediately` — PASS.

- [ ] **Step 6: Commit**

```bash
git add DexBar/DisclaimerWindowController.swift DexBarTests/DisclaimerWindowControllerTests.swift
git commit -m "feat: add DisclaimerWindowController with UserDefaults gate"
```

---

## Task 3: Wire into AppDelegate

**Files:**
- Modify: `DexBar/AppDelegate.swift` — `applicationDidFinishLaunching` only

- [ ] **Step 1: Replace applicationDidFinishLaunching**

In `DexBar/AppDelegate.swift`, find the method starting at line 161 and replace it entirely with:

```swift
func applicationDidFinishLaunching(_ notification: Notification) {
    DisclaimerWindowController.showIfNeeded { [weak self] in
        guard let self else { return }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(handleStatusItemClick(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        let vc = GlucoseWebViewController()
        glucoseWebVC = vc

        let p = NSPopover()
        p.behavior = .transient
        p.contentViewController = vc
        p.contentSize = CGSize(width: 640, height: 600)
        p.appearance = NSAppearance(named: .darkAqua)
        popover = p

        // Load credentials once at startup — single Keychain prompt.
        if let creds = KeychainHelper.loadCredentials() {
            username = creds.username
            password = creds.password
        }

        if !username.isEmpty {
            setStatusTitle("…")
            startPolling()
        } else {
            setStatusTitle("🚫")
        }

        // Load Glooko credentials and authenticate in background if present
        if let glookoCreds = KeychainHelper.loadGlookoCredentials() {
            glooko.authenticate(email: glookoCreds.email, password: glookoCreds.password) { [weak self] ok, _ in
                guard let self, ok else { return }
                self.fetchGlookoData()
                DispatchQueue.main.async { self.startGlookoPolling() }
            }
        }
    }
}
```

- [ ] **Step 2: Build to verify no compile errors**

Product → Build (⌘B).  
Expected: Build Succeeded.

- [ ] **Step 3: Run all tests**

```bash
xcodebuild test -scheme DexBar -destination 'platform=macOS' 2>&1 | grep -E "Test Suite|passed|failed|error:"
```
Expected: All existing tests still pass.

- [ ] **Step 4: Manual smoke test — first launch**

1. Delete the accepted key to simulate first launch:
   ```bash
   defaults delete com.oskarhagberg.DexBar hasAcceptedDisclaimer
   ```
2. Run the app (⌘R in Xcode).
3. Expected: disclaimer window appears centred, in front. Status bar item is NOT yet visible.
4. Press Return (or click "I understand and accept"). Expected: window closes, status bar item appears, app starts normally.
5. Quit and relaunch. Expected: disclaimer does NOT appear, app starts immediately.

- [ ] **Step 5: Manual smoke test — decline / red ✕**

1. Delete the key again:
   ```bash
   defaults delete com.oskarhagberg.DexBar hasAcceptedDisclaimer
   ```
2. Run the app. Click "I do not accept — close the app". Expected: app quits.
3. Delete the key again. Run the app. Click the red ✕ close button. Expected: app quits.

- [ ] **Step 6: Commit**

```bash
git add DexBar/AppDelegate.swift
git commit -m "feat: gate app startup behind first-launch disclaimer"
```
