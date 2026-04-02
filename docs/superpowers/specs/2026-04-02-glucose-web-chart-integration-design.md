# Design: Integrate Web Glucose Chart into macOS Status Bar App

**Date:** 2026-04-02  
**Status:** Approved

---

## Overview

Replace the existing SwiftUI `PopoverContentView` / `GlucoseChartView` in the `NSPopover` with a `WKWebView` that renders `bundle-native.html` — a self-contained React glucose chart. Add `GlucoseStats` calculation and wire the TIR percentage into the status bar title behind a feature flag.

---

## Existing Codebase Facts

| Aspect | Detail |
|---|---|
| Reading model | `DexcomReading` — `valueMmol: Double`, `trend: String`, `timestamp: Date` |
| History buffer | `AppDelegate.graphData: [GraphDatum]` — `value: Double`, `timestamp: Date` (no trend) |
| Popover owner | `AppDelegate` — `var popover: NSPopover?` |
| Current content VC | `NSHostingController<PopoverContentView>` (SwiftUI) |
| Auth state | `AppDelegate.isAuthenticated: Bool` — popover currently shows sign-in prompt when false |
| Thresholds file | `GlucoseFormatter.swift` — `lowThreshold = 4.0` |
| No WKWebView | WebKit not yet imported anywhere |
| Trend strings | Dexcom API sends `"SingleUp"`, `"FortyFiveDown"`, `"Flat"`, etc. |

---

## Files

| File | Action | Purpose |
|---|---|---|
| `DexBar/GlucoseWebViewController.swift` | **New** | WKWebView owner; history injection; live push; unauthenticated overlay |
| `DexBar/GlucoseStats.swift` | **New** | `GlucoseStats` struct + `glucoseStats(from:hours:)` free function |
| `DexBar/GlucoseFormatter.swift` | **Edit** | Add `tirLow`, `tirHigh` constants; add `normalisedTrend(_:)` helper |
| `DexBar/AppDelegate.swift` | **Edit** | Wire new VC; add `showTimeInRange` flag; call `pushReading` + stats on each update |
| `DexBarTests/GlucoseStatsTests.swift` | **New** | Unit tests for `GlucoseStats` |
| `bundle-native.html` | **Add to target** | Must appear in Copy Bundle Resources build phase |

---

## Section 1: `bundle-native.html` Bundle Resource

`bundle-native.html` (currently in the repo root) must be added to the Xcode target's **Copy Bundle Resources** build phase so it is accessible via `Bundle.main.url(forResource:withExtension:)`.

Move or copy it to `DexBar/Resources/bundle-native.html` (or keep at root — either works as long as it is added to the target). Verify with:

```swift
Bundle.main.url(forResource: "bundle-native", withExtension: "html") != nil
```

---

## Section 2: `GlucoseFormatter` additions

Add to `GlucoseFormatter.swift`:

```swift
// TIR thresholds — used by GlucoseStats and must match web chart
static let tirLow  = 4.5   // mmol/L
static let tirHigh = 10.0  // mmol/L

// Maps Dexcom trend strings to simple display strings for the web chart
static func normalisedTrend(_ raw: String) -> String {
    switch raw {
    case "DoubleUp":       return "risingRapidly"
    case "SingleUp":       return "rising"
    case "FortyFiveUp":    return "risingSlightly"
    case "Flat":           return "flat"
    case "FortyFiveDown":  return "fallingSlightly"
    case "SingleDown":     return "falling"
    case "DoubleDown":     return "fallingRapidly"
    default:               return "unknown"
    }
}
```

---

## Section 3: `GlucoseStats`

New file `GlucoseStats.swift`:

```swift
struct GlucoseStats {
    let timeInRange: Double       // 0.0–1.0
    let timeInRangePercent: Int   // Int(timeInRange * 100)
    let average: Double           // mmol/L
    let periodLow: Double         // mmol/L
    let readingCount: Int
}

/// Returns nil if readings is empty.
/// Only includes readings within the last `hours` hours.
func glucoseStats(from readings: [GraphDatum], hours: Double = 24) -> GlucoseStats? {
    let cutoff = Date().addingTimeInterval(-hours * 3600)
    let window = readings.filter { $0.timestamp >= cutoff }
    guard !window.isEmpty else { return nil }

    let inRange = window.filter {
        $0.value >= GlucoseFormatter.tirLow && $0.value <= GlucoseFormatter.tirHigh
    }
    let tir = Double(inRange.count) / Double(window.count)
    let avg = window.map(\.value).reduce(0, +) / Double(window.count)
    let low = window.map(\.value).min()!   // safe: window non-empty

    return GlucoseStats(
        timeInRange: tir,
        timeInRangePercent: Int(tir * 100),
        average: avg,
        periodLow: low,
        readingCount: window.count
    )
}
```

---

## Section 4: `GlucoseWebViewController`

New file `GlucoseWebViewController.swift`. `NSViewController` subclass.

### View hierarchy

```
view (NSView, background #09090f)
  ├── WKWebView — pinned to all edges, drawsBackground = false
  └── overlayView (NSView, semi-transparent dark background)
        ├── NSTextField — "Sign in to see your glucose data"
        └── NSButton — "Open Preferences"
```

### Key properties

```swift
var isAuthenticated: Bool = false {
    didSet { updateOverlay() }
}
```

### Load sequence

1. `viewDidLoad`: configure `WKWebViewConfiguration`, create `WKWebView`, add overlay, load HTML.
2. `injectHistory(_ readings: [GraphDatum])`:
   - Serialise to `[{ time: ms, value: mmol }]` JSON.
   - Install as `WKUserScript` at `.atDocumentStart` that sets `window.__INITIAL_DATA__`.
   - If page already loaded, call `evaluateJavaScript("window.__INITIAL_DATA__ = \(json)")` directly (chart reads this on time-range switch).
3. `pushReading(_ reading: DexcomReading)`:
   - Serialise to `{ value: mmol, trend: normalisedTrend, timestamp: ms }` JSON.
   - If `isLoaded`: call `evaluateJavaScript("window.updateReading(\(json))")`.
   - If not loaded: store as `pendingReading`; flush in `webView(_:didFinish:)`.

### Page load tracking

Conforms to `WKNavigationDelegate`. Sets `isLoaded = true` in `webView(_:didFinish:)`. Flushes `pendingReading` if present.

### Unauthenticated overlay

`updateOverlay()` sets `overlayView.isHidden = isAuthenticated`. The overlay covers the entire view with a dark background and a centred "Open Preferences" button that calls `NSApp.sendAction(#selector(AppDelegate.openPreferences), to: nil, from: nil)`.

### Appearance

```swift
popover.appearance = NSAppearance(named: .darkAqua)
webView.setValue(false, forKey: "drawsBackground")
view.wantsLayer = true
view.layer?.backgroundColor = NSColor(hex: "#09090f").cgColor
```

---

## Section 5: `AppDelegate` wiring

### New properties

```swift
var glucoseWebVC: GlucoseWebViewController?
var showTimeInRange: Bool = false        // feature flag; toggle to add TIR to status bar
var currentStats: GlucoseStats?
```

### `applicationDidFinishLaunching` changes

Replace the `NSHostingController` setup:

```swift
let vc = GlucoseWebViewController()
glucoseWebVC = vc
popover = NSPopover()
popover?.contentViewController = vc
popover?.contentSize = CGSize(width: 640, height: 520)
popover?.behavior = .transient
popover?.appearance = NSAppearance(named: .darkAqua)
```

### `updateUI(with readings:)` changes

After the existing `graphData` assignment, add:

```swift
// Update web chart
glucoseWebVC?.injectHistory(graphData)
if let latest = readings.first {
    glucoseWebVC?.pushReading(latest)
}

// Update stats
currentStats = glucoseStats(from: graphData)
updateStatusBarTitle()
```

### Auth state propagation

Wherever `isAuthenticated` changes, also set:

```swift
glucoseWebVC?.isAuthenticated = isAuthenticated
```

### Status bar title

```swift
func updateStatusBarTitle() {
    guard let label = currentReading.map({ GlucoseFormatter.statusLabel(valueMmol: $0.valueMmol, trend: $0.trend) }) else { return }
    if showTimeInRange, let tir = currentStats?.timeInRangePercent {
        statusItem.button?.title = "\(label)  \(tir)%"
    } else {
        statusItem.button?.title = label
    }
}
```

`currentReading` — store the latest `DexcomReading` as a property (currently the status bar title is set directly in `updateUI`; extract it so `updateStatusBarTitle` can be called independently).

### Popover show

In `togglePopover` (or `NSPopoverDelegate.popoverWillShow`), call `injectHistory` again immediately before showing if `graphData` is non-empty — ensures chart is fresh on each open even if no new reading has arrived.

---

## Section 6: Unit Tests — `GlucoseStatsTests`

Three test cases:

| Case | Input | Expected |
|---|---|---|
| Empty | `[]` | `nil` |
| All in range | 10 readings, all `value = 6.0`, within last 24h | `timeInRangePercent == 100`, `average == 6.0`, `periodLow == 6.0` |
| Mixed | 8 readings in range + 2 below (value = 3.0), within 24h | `timeInRangePercent == 80`, `periodLow == 3.0` |

Also test that readings outside the time window are excluded.

---

## JS Contract (read-only reference)

`bundle-native.html` is treated as a black box. It expects:

```typescript
// Set before page load:
window.__INITIAL_DATA__: Array<{ time: number, value: number }>
// time = Unix ms, value = mmol/L

// Called after page load for live updates:
window.updateReading({ value: number, trend: string, timestamp: number })
// timestamp = Unix ms
```

If `window.updateReading` does not visibly update the chart, the React state hook may not be wired to the exposed function — this is flagged as a known follow-up, not a blocker.

---

## Success Criteria

1. Opening the popover shows the glucose chart with real historical data.
2. New readings from the polling pipeline update the live dot on the chart.
3. No console errors in the WKWebView (verify via Xcode Web Inspector).
4. Popover is 640×520, chart fills content area without scrollbars.
5. `GlucoseStats` unit tests pass: empty → nil, all-in-range → 100%, mixed → correct %.
6. Status bar title updates on each new reading; `showTimeInRange = true` appends TIR suffix.
7. Unauthenticated state shows the overlay with "Open Preferences" button over the dark web view background.

---

## Out of Scope

- Modifying `bundle-native.html`
- Changes to Dexcom API integration or `DexcomClient`
- Unit tests beyond `GlucoseStatsTests`
