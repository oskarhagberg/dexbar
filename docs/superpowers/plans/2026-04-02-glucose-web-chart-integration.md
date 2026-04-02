# Glucose Web Chart Integration — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the SwiftUI popover chart with a `WKWebView` that renders `bundle-native.html`, add `GlucoseStats` with TIR calculation, and wire a `showTimeInRange` flag to the status bar title.

**Architecture:** `GlucoseWebViewController` (new file) owns the `WKWebView` and a native unauthenticated overlay; `AppDelegate` is wired to create it upfront and call `injectHistory`/`pushReading` on each data update. `GlucoseStats` (new file) is a pure function over `[GraphDatum]`; `GlucoseFormatter` gains TIR threshold constants and a trend-normalisation helper.

**Tech Stack:** Swift 5, AppKit, WebKit (`WKWebView`), Swift Testing framework (existing test suite pattern)

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `DexBar/GlucoseFormatter.swift` | Modify | Add `tirLow`, `tirHigh` constants; add `normalisedTrend(_:)` |
| `DexBar/GlucoseStats.swift` | Create | `GlucoseStats` struct + `glucoseStats(from:hours:)` free function |
| `DexBar/GlucoseWebViewController.swift` | Create | WKWebView owner, history injection, live push, unauthenticated overlay |
| `DexBar/AppDelegate.swift` | Modify | Wire web VC into popover; add `showTimeInRange`, stats, `latestReading`; remove SwiftUI chart code |
| `DexBarTests/GlucoseStatsTests.swift` | Create | Unit tests for `GlucoseStats` using Swift Testing |
| `bundle-native.html` | Add to Xcode target | Must be in Copy Bundle Resources (Xcode GUI step) |

---

## Task 1: Add `bundle-native.html` to the Xcode target

**Files:**
- No code changes — Xcode project GUI step + build verification

- [ ] **Step 1: Add the file to Copy Bundle Resources**

  In Xcode:
  1. In the Project navigator, right-click on the `DexBar` group (the blue folder, not the project root)
  2. Choose **Add Files to "DexBar"…**
  3. Navigate to the repo root and select `bundle-native.html`
  4. Ensure **"Copy items if needed"** is **unchecked** (the file is already in the repo)
  5. Ensure the **DexBar** target checkbox is checked
  6. Click **Add**

- [ ] **Step 2: Verify it appears in Build Phases**

  Select the **DexBar** target → **Build Phases** → **Copy Bundle Resources**. Confirm `bundle-native.html` is listed.

- [ ] **Step 3: Verify it is accessible from code**

  Add this temporary line anywhere reachable at launch (e.g. top of `applicationDidFinishLaunching`), build and run, check the console:

  ```swift
  dlog("[Bundle] html:", Bundle.main.url(forResource: "bundle-native", withExtension: "html") as Any)
  ```

  Expected console output: a non-nil file URL ending in `bundle-native.html`. Remove the line after confirming.

- [ ] **Step 4: Commit**

  ```bash
  git add DexBar.xcodeproj/project.pbxproj
  git commit -m "chore: add bundle-native.html to Copy Bundle Resources"
  ```

---

## Task 2: Add TIR constants and trend normalisation to `GlucoseFormatter`

**Files:**
- Modify: `DexBar/GlucoseFormatter.swift`

- [ ] **Step 1: Add constants and `normalisedTrend` to `GlucoseFormatter`**

  Replace the entire contents of `DexBar/GlucoseFormatter.swift` with:

  ```swift
  //  GlucoseFormatter.swift
  //  DexBar

  enum GlucoseFormatter {

      static let lowThreshold = 4.0

      // TIR thresholds — used by GlucoseStats and must match the web chart
      static let tirLow  = 4.5   // mmol/L
      static let tirHigh = 10.0  // mmol/L

      private static let trendArrows: [String: String] = [
          "None":           "",
          "DoubleUp":       "↑↑",
          "SingleUp":       "↑",
          "FortyFiveUp":    "↗",
          "Flat":           "→",
          "FortyFiveDown":  "↘",
          "SingleDown":     "↓",
          "DoubleDown":     "↓↓",
          "NotComputable":  "?",
          "RateOutOfRange": "-"
      ]

      private static let trendNormalised: [String: String] = [
          "DoubleUp":       "risingRapidly",
          "SingleUp":       "rising",
          "FortyFiveUp":    "risingSlightly",
          "Flat":           "flat",
          "FortyFiveDown":  "fallingSlightly",
          "SingleDown":     "falling",
          "DoubleDown":     "fallingRapidly",
          "None":           "unknown",
          "NotComputable":  "unknown",
          "RateOutOfRange": "unknown"
      ]

      static func arrow(for trend: String) -> String {
          trendArrows[trend] ?? "?"
      }

      /// Maps Dexcom trend strings (e.g. "SingleUp") to simple display strings
      /// for the web chart (e.g. "rising").
      static func normalisedTrend(_ raw: String) -> String {
          trendNormalised[raw] ?? "unknown"
      }

      static func isLow(_ value: Double) -> Bool {
          value < lowThreshold
      }

      static func statusLabel(valueMmol: Double, trend: String) -> String {
          let arrow = arrow(for: trend)
          let formatted = String(format: "%.1f", valueMmol)
          if isLow(valueMmol) {
              return "⚠️ \(formatted) \(arrow)"
          }
          return "\(formatted) \(arrow)"
      }
  }
  ```

- [ ] **Step 2: Build to confirm no errors**

  ```bash
  xcodebuild build -scheme DexBar -destination 'platform=macOS,arch=arm64' 2>&1 | grep -E "error:|warning:|BUILD"
  ```

  Expected: `BUILD SUCCEEDED` (or `BUILD SUCCEEDED` with pre-existing warnings only).

- [ ] **Step 3: Run existing formatter tests**

  ```bash
  xcodebuild test -scheme DexBar -destination 'platform=macOS,arch=arm64' -only-testing:DexBarTests/GlucoseFormatterTests 2>&1 | grep -E "Test.*passed|Test.*failed|error:"
  ```

  Expected: all 8 existing tests pass.

- [ ] **Step 4: Commit**

  ```bash
  git add DexBar/GlucoseFormatter.swift
  git commit -m "feat: add TIR thresholds and normalisedTrend to GlucoseFormatter"
  ```

---

## Task 3: Create `GlucoseStats` (TDD)

**Files:**
- Create: `DexBar/GlucoseStats.swift`
- Create: `DexBarTests/GlucoseStatsTests.swift`

- [ ] **Step 1: Write the failing tests**

  Create `DexBarTests/GlucoseStatsTests.swift`:

  ```swift
  //  GlucoseStatsTests.swift
  //  DexBarTests

  import Testing
  @testable import DexBar

  @Suite("GlucoseStats")
  struct GlucoseStatsTests {

      // Helper — creates a GraphDatum with a timestamp `hoursAgo` hours in the past
      private func datum(_ value: Double, hoursAgo: Double = 1) -> GraphDatum {
          GraphDatum(value: value, timestamp: Date().addingTimeInterval(-hoursAgo * 3600))
      }

      @Test func emptyReadingsReturnsNil() {
          #expect(glucoseStats(from: []) == nil)
      }

      @Test func allInRangeReturns100Percent() {
          let readings = (0..<10).map { _ in datum(6.0) }
          let stats = glucoseStats(from: readings)
          #expect(stats != nil)
          #expect(stats?.timeInRangePercent == 100)
          #expect(stats?.readingCount == 10)
          #expect(abs((stats?.average ?? 0) - 6.0) < 0.001)
          #expect(abs((stats?.periodLow ?? 0) - 6.0) < 0.001)
      }

      @Test func mixedReadingsCorrectPercentage() {
          // 8 readings in range (6.0) + 2 below TIR (3.0) = 80%
          let inRange = (0..<8).map { _ in datum(6.0) }
          let below   = (0..<2).map { _ in datum(3.0) }
          let stats = glucoseStats(from: inRange + below)
          #expect(stats?.timeInRangePercent == 80)
          #expect(abs((stats?.periodLow ?? 0) - 3.0) < 0.001)
          #expect(stats?.readingCount == 10)
      }

      @Test func readingsOutsideWindowAreExcluded() {
          let recent = datum(6.0, hoursAgo: 1)
          let old    = datum(3.0, hoursAgo: 25) // outside default 24h window
          let stats = glucoseStats(from: [recent, old])
          #expect(stats?.readingCount == 1)
          #expect(stats?.timeInRangePercent == 100)
      }

      @Test func exactlyAtTirBoundariesIsInRange() {
          let atLow  = datum(GlucoseFormatter.tirLow)   // 4.5 — in range
          let atHigh = datum(GlucoseFormatter.tirHigh)  // 10.0 — in range
          let stats = glucoseStats(from: [atLow, atHigh])
          #expect(stats?.timeInRangePercent == 100)
      }
  }
  ```

- [ ] **Step 2: Run tests to confirm they fail**

  ```bash
  xcodebuild test -scheme DexBar -destination 'platform=macOS,arch=arm64' -only-testing:DexBarTests/GlucoseStatsTests 2>&1 | grep -E "error:|cannot find|BUILD"
  ```

  Expected: build error — `cannot find 'glucoseStats' in scope` (the function doesn't exist yet).

- [ ] **Step 3: Create the implementation**

  Create `DexBar/GlucoseStats.swift`:

  ```swift
  //  GlucoseStats.swift
  //  DexBar

  struct GlucoseStats {
      let timeInRange: Double       // 0.0–1.0 fraction of readings in TIR
      let timeInRangePercent: Int   // Int(timeInRange * 100)
      let average: Double           // mmol/L
      let periodLow: Double         // mmol/L (lowest reading in window)
      let readingCount: Int
  }

  /// Returns nil if `readings` is empty.
  /// Only includes readings within the last `hours` hours from now.
  func glucoseStats(from readings: [GraphDatum], hours: Double = 24) -> GlucoseStats? {
      let cutoff = Date().addingTimeInterval(-hours * 3600)
      let window = readings.filter { $0.timestamp >= cutoff }
      guard !window.isEmpty else { return nil }

      let inRange = window.filter {
          $0.value >= GlucoseFormatter.tirLow && $0.value <= GlucoseFormatter.tirHigh
      }
      let tir = Double(inRange.count) / Double(window.count)
      let avg = window.map(\.value).reduce(0, +) / Double(window.count)
      let low = window.map(\.value).min()!   // safe: window is non-empty

      return GlucoseStats(
          timeInRange: tir,
          timeInRangePercent: Int(tir * 100),
          average: avg,
          periodLow: low,
          readingCount: window.count
      )
  }
  ```

- [ ] **Step 4: Run tests to confirm they pass**

  ```bash
  xcodebuild test -scheme DexBar -destination 'platform=macOS,arch=arm64' -only-testing:DexBarTests/GlucoseStatsTests 2>&1 | grep -E "Test.*passed|Test.*failed|error:"
  ```

  Expected: all 5 tests pass.

- [ ] **Step 5: Commit**

  ```bash
  git add DexBar/GlucoseStats.swift DexBarTests/GlucoseStatsTests.swift
  git commit -m "feat: add GlucoseStats with TIR calculation and unit tests"
  ```

---

## Task 4: Create `GlucoseWebViewController`

**Files:**
- Create: `DexBar/GlucoseWebViewController.swift`

No unit tests for this task — it owns a `WKWebView` and requires a running macOS environment to verify.

- [ ] **Step 1: Create the file**

  Create `DexBar/GlucoseWebViewController.swift`:

  ```swift
  //  GlucoseWebViewController.swift
  //  DexBar

  import Cocoa
  import WebKit

  class GlucoseWebViewController: NSViewController {

      // MARK: - Properties

      private var webView: WKWebView!
      private var overlayView: NSView!
      private var isLoaded = false
      private var pendingReading: DexcomReading?

      /// Set this to show or hide the "sign in" overlay over the chart.
      var isAuthenticated: Bool = false {
          didSet { updateOverlay() }
      }

      // MARK: - View lifecycle

      override func loadView() {
          view = NSView()
          view.wantsLayer = true
          // Match the chart's background colour so there's no bleed
          view.layer?.backgroundColor = NSColor(
              red: 9/255, green: 9/255, blue: 15/255, alpha: 1
          ).cgColor
      }

      override func viewDidLoad() {
          super.viewDidLoad()
          setupWebView()
          setupOverlay()
          loadHTML()
      }

      // MARK: - Setup

      private func setupWebView() {
          let config = WKWebViewConfiguration()
          webView = WKWebView(frame: .zero, configuration: config)
          webView.navigationDelegate = self
          // Transparent background so our view's dark layer shows through
          webView.setValue(false, forKey: "drawsBackground")
          webView.translatesAutoresizingMaskIntoConstraints = false
          view.addSubview(webView)
          NSLayoutConstraint.activate([
              webView.topAnchor.constraint(equalTo: view.topAnchor),
              webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
              webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
              webView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
          ])
      }

      private func setupOverlay() {
          overlayView = NSView()
          overlayView.wantsLayer = true
          overlayView.layer?.backgroundColor = NSColor(
              red: 9/255, green: 9/255, blue: 15/255, alpha: 0.97
          ).cgColor
          overlayView.translatesAutoresizingMaskIntoConstraints = false

          let label = NSTextField(labelWithString: "Sign in to see your glucose data")
          label.textColor = .secondaryLabelColor
          label.alignment = .center
          label.translatesAutoresizingMaskIntoConstraints = false

          let button = NSButton(title: "Open Preferences", target: self, action: #selector(openPreferencesAction))
          button.bezelStyle = .rounded
          button.translatesAutoresizingMaskIntoConstraints = false

          let stack = NSStackView(views: [label, button])
          stack.orientation = .vertical
          stack.spacing = 16
          stack.translatesAutoresizingMaskIntoConstraints = false
          overlayView.addSubview(stack)
          view.addSubview(overlayView)

          NSLayoutConstraint.activate([
              overlayView.topAnchor.constraint(equalTo: view.topAnchor),
              overlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
              overlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
              overlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
              stack.centerXAnchor.constraint(equalTo: overlayView.centerXAnchor),
              stack.centerYAnchor.constraint(equalTo: overlayView.centerYAnchor)
          ])

          updateOverlay()
      }

      private func loadHTML() {
          guard let url = Bundle.main.url(forResource: "bundle-native", withExtension: "html") else {
              dlog("[GlucoseWebVC] bundle-native.html not found in bundle")
              return
          }
          webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
      }

      private func updateOverlay() {
          overlayView?.isHidden = isAuthenticated
      }

      // MARK: - Public API

      /// Call this with the historical readings buffer before or after page load.
      /// Installs a WKUserScript so the chart boots with data, and also
      /// updates window.__INITIAL_DATA__ directly if the page is already loaded.
      func injectHistory(_ readings: [GraphDatum]) {
          let points = readings.map { r -> [String: Double] in
              ["time": r.timestamp.timeIntervalSince1970 * 1000, "value": r.value]
          }
          guard let data = try? JSONSerialization.data(withJSONObject: points),
                let json = String(data: data, encoding: .utf8) else { return }

          // Replace any previously installed history script
          webView.configuration.userContentController.removeAllUserScripts()
          let script = WKUserScript(
              source: "window.__INITIAL_DATA__ = \(json);",
              injectionTime: .atDocumentStart,
              forMainFrameOnly: true
          )
          webView.configuration.userContentController.addUserScript(script)

          if isLoaded {
              webView.evaluateJavaScript("window.__INITIAL_DATA__ = \(json);")
          }
      }

      /// Call this whenever a new live reading arrives.
      /// Queues the reading if the page hasn't finished loading yet.
      func pushReading(_ reading: DexcomReading) {
          let payload: [String: Any] = [
              "value":     reading.valueMmol,
              "trend":     GlucoseFormatter.normalisedTrend(reading.trend),
              "timestamp": reading.timestamp.timeIntervalSince1970 * 1000
          ]
          guard let data = try? JSONSerialization.data(withJSONObject: payload),
                let json = String(data: data, encoding: .utf8) else { return }

          if isLoaded {
              webView.evaluateJavaScript("window.updateReading(\(json));")
          } else {
              pendingReading = reading
          }
      }

      // MARK: - Actions

      @objc private func openPreferencesAction() {
          NSApp.sendAction(#selector(AppDelegate.openPreferences), to: nil, from: self)
      }
  }

  // MARK: - WKNavigationDelegate

  extension GlucoseWebViewController: WKNavigationDelegate {

      func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
          isLoaded = true
          if let reading = pendingReading {
              pushReading(reading)
              pendingReading = nil
          }
      }

      func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
          dlog("[GlucoseWebVC] Navigation failed:", error)
      }

      func webView(_ webView: WKWebView,
                   didFailProvisionalNavigation navigation: WKNavigation!,
                   withError error: Error) {
          dlog("[GlucoseWebVC] Provisional navigation failed:", error)
      }
  }
  ```

- [ ] **Step 2: Build to confirm no errors**

  ```bash
  xcodebuild build -scheme DexBar -destination 'platform=macOS,arch=arm64' 2>&1 | grep -E "error:|BUILD"
  ```

  Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

  ```bash
  git add DexBar/GlucoseWebViewController.swift
  git commit -m "feat: add GlucoseWebViewController with WKWebView and unauthenticated overlay"
  ```

---

## Task 5: Wire `GlucoseWebViewController` into `AppDelegate`

**Files:**
- Modify: `DexBar/AppDelegate.swift`

This task makes the following changes to `AppDelegate.swift`:
1. Remove `import Charts` (no longer used)
2. Remove `var popoverHostingController` property
3. Add `glucoseWebVC`, `showTimeInRange`, `currentStats`, `latestReading` properties
4. Rewrite `applicationDidFinishLaunching` to set up the web VC popover upfront
5. Simplify `togglePopover`
6. Update `updateUI` to drive the web VC and compute stats
7. Update `markUnauthenticated` to propagate auth state
8. Remove `updatePopoverContent()` and `makePopoverView()`
9. Add `updateStatusBarTitle()`
10. Remove `PopoverContentView`, `GlucoseChartView`, and `HoverReadout` inner types (no longer used)

- [ ] **Step 1: Remove `import Charts` and `popoverHostingController`; add new properties**

  In `AppDelegate.swift`:

  Replace:
  ```swift
  import Cocoa
  import SwiftUI
  import Charts
  import Security
  import ServiceManagement
  ```
  With:
  ```swift
  import Cocoa
  import SwiftUI
  import Security
  import ServiceManagement
  ```

  Replace:
  ```swift
      var popover: NSPopover?
      var popoverHostingController: NSHostingController<PopoverContentView>?
      var graphData: [GraphDatum] = []
      var preferencesWindow: NSWindow?
      var isAuthenticated = false
  ```
  With:
  ```swift
      var popover: NSPopover?
      var glucoseWebVC: GlucoseWebViewController?
      /// Feature flag: when true, appends "  74%" TIR suffix to the status bar title.
      var showTimeInRange: Bool = false
      var graphData: [GraphDatum] = []
      var currentStats: GlucoseStats?
      var latestReading: DexcomReading?
      var preferencesWindow: NSWindow?
      var isAuthenticated = false
  ```

- [ ] **Step 2: Rewrite `applicationDidFinishLaunching` to set up web VC popover upfront**

  Replace:
  ```swift
      func applicationDidFinishLaunching(_ notification: Notification) {
          statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
          statusItem.button?.target = self
          statusItem.button?.action = #selector(handleStatusItemClick(_:))
          statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

          if KeychainHelper.load(for: "username") != nil {
              setStatusTitle("…")
              startPolling()
          } else {
              setStatusTitle("🚫")
          }
      }
  ```
  With:
  ```swift
      func applicationDidFinishLaunching(_ notification: Notification) {
          statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
          statusItem.button?.target = self
          statusItem.button?.action = #selector(handleStatusItemClick(_:))
          statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

          let vc = GlucoseWebViewController()
          glucoseWebVC = vc

          let p = NSPopover()
          p.behavior = .transient
          p.contentViewController = vc
          p.contentSize = CGSize(width: 640, height: 520)
          p.appearance = NSAppearance(named: .darkAqua)
          popover = p

          if KeychainHelper.load(for: "username") != nil {
              setStatusTitle("…")
              startPolling()
          } else {
              setStatusTitle("🚫")
          }
      }
  ```

- [ ] **Step 3: Simplify `togglePopover`**

  Replace:
  ```swift
      @objc func togglePopover(_ sender: Any?) {
          if popover == nil {
              let hc = NSHostingController(rootView: makePopoverView())
              popoverHostingController = hc
              let p = NSPopover()
              p.behavior = .transient
              p.contentViewController = hc
              popover = p
          } else {
              popoverHostingController?.rootView = makePopoverView()
          }

          if let button = statusItem.button, let popover = popover {
              if popover.isShown {
                  popover.performClose(sender)
              } else {
                  popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
              }
          }
      }
  ```
  With:
  ```swift
      @objc func togglePopover(_ sender: Any?) {
          guard let button = statusItem.button, let popover = popover else { return }
          if popover.isShown {
              popover.performClose(sender)
          } else {
              // Refresh history on every open so the chart is up to date
              if !graphData.isEmpty {
                  glucoseWebVC?.injectHistory(graphData)
              }
              popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
          }
      }
  ```

- [ ] **Step 4: Update `updateUI` to drive the web VC and compute stats**

  Replace:
  ```swift
      func updateUI(with readings: [DexcomReading]) {
          guard let latest = readings.first else { return }

          isAuthenticated = true
          graphData = readings.reversed().map { GraphDatum(value: $0.valueMmol, timestamp: $0.timestamp) }

          let label = GlucoseFormatter.statusLabel(valueMmol: latest.valueMmol, trend: latest.trend)
          if GlucoseFormatter.isLow(latest.valueMmol) {
              setStatusTitle(label, color: .red)
          } else {
              setStatusTitle(label)
          }
          updatePopoverContent()
      }
  ```
  With:
  ```swift
      func updateUI(with readings: [DexcomReading]) {
          guard let latest = readings.first else { return }

          isAuthenticated = true
          latestReading = latest
          graphData = readings.reversed().map { GraphDatum(value: $0.valueMmol, timestamp: $0.timestamp) }

          glucoseWebVC?.isAuthenticated = true
          glucoseWebVC?.injectHistory(graphData)
          glucoseWebVC?.pushReading(latest)

          currentStats = glucoseStats(from: graphData)
          updateStatusBarTitle()
      }
  ```

- [ ] **Step 5: Update `markUnauthenticated` to propagate auth state to web VC**

  Replace:
  ```swift
      func markUnauthenticated() {
          isAuthenticated = false
          setStatusTitle("🚫")
          updatePopoverContent()
      }
  ```
  With:
  ```swift
      func markUnauthenticated() {
          isAuthenticated = false
          setStatusTitle("🚫")
          glucoseWebVC?.isAuthenticated = false
      }
  ```

- [ ] **Step 6: Remove `updatePopoverContent()` and `makePopoverView()`**

  Delete these two methods in their entirety:

  ```swift
      func updatePopoverContent() {
          DispatchQueue.main.async {
              self.popoverHostingController?.rootView = self.makePopoverView()
          }
      }

      func makePopoverView() -> PopoverContentView {
          PopoverContentView(
              isAuthenticated: isAuthenticated,
              data: graphData,
              onOpenPreferences: { [weak self] in self?.openPreferences() }
          )
      }
  ```

- [ ] **Step 7: Add `updateStatusBarTitle()`**

  Add this new method anywhere after `setStatusTitle` (e.g. immediately after it):

  ```swift
      func updateStatusBarTitle() {
          guard let reading = latestReading else { return }
          let label = GlucoseFormatter.statusLabel(valueMmol: reading.valueMmol, trend: reading.trend)
          let title: String
          if showTimeInRange, let tir = currentStats?.timeInRangePercent {
              title = "\(label)  \(tir)%"
          } else {
              title = label
          }
          if GlucoseFormatter.isLow(reading.valueMmol) {
              setStatusTitle(title, color: .red)
          } else {
              setStatusTitle(title)
          }
      }
  ```

- [ ] **Step 8: Remove unused inner types**

  Delete the `PopoverContentView`, `GlucoseChartView`, and `HoverReadout` struct definitions from inside the `AppDelegate` class body. These are the blocks starting at:
  - `struct PopoverContentView: View {` (through its closing `}`)
  - `struct GlucoseChartView: View {` (through its closing `}`)
  - `private struct HoverReadout: View {` (through its closing `}`)

  `PreferencesView` must be kept — it is still used for the preferences window.

- [ ] **Step 9: Build to confirm no errors**

  ```bash
  xcodebuild build -scheme DexBar -destination 'platform=macOS,arch=arm64' 2>&1 | grep -E "error:|BUILD"
  ```

  Expected: `BUILD SUCCEEDED`.

- [ ] **Step 10: Run all tests**

  ```bash
  xcodebuild test -scheme DexBar -destination 'platform=macOS,arch=arm64' 2>&1 | grep -E "Test.*passed|Test.*failed|error:|BUILD"
  ```

  Expected: all tests pass (GlucoseStatsTests, GlucoseFormatterTests, DexcomReadingTests, DexcomClientTests).

- [ ] **Step 11: Commit**

  ```bash
  git add DexBar/AppDelegate.swift
  git commit -m "feat: replace SwiftUI chart popover with GlucoseWebViewController"
  ```

---

## Verification Checklist (manual, after all tasks)

Run the app and verify each item:

- [ ] Opening the popover shows the glucose chart with historical data
- [ ] The popover is 640×520, chart fills the area without scrollbars
- [ ] No console errors in the WKWebView (Develop menu → Connect Web Inspector, or Xcode console)
- [ ] When not signed in, the popover shows the "Sign in" overlay with an "Open Preferences" button
- [ ] "Open Preferences" button in the overlay opens the Preferences window
- [ ] New readings update the live dot (check by waiting for the 60s poll or temporarily reducing the timer interval)
- [ ] `showTimeInRange = true` in the debugger shows TIR suffix in the status bar title
- [ ] `showTimeInRange = false` (default) shows only the BG value

---

## Known Follow-up

If `window.updateReading(...)` does not visibly move the live dot on the chart, the React state hook in `bundle-native.html` may not be wired to the exposed function. This is flagged as a follow-up — `injectHistory` on every popover open ensures the chart always shows correct historical data regardless.
