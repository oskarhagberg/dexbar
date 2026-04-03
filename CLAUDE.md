# DexBar — Project Guide for Claude Code

DexBar is a macOS status bar app that polls the Dexcom Share API and displays live blood glucose readings. The popover chart is rendered by a self-contained HTML/JS bundle loaded into a `WKWebView`.

---

## Architecture Overview

The app has two distinct layers that communicate through a strict contract. **Never blur the boundary between them.**

```
┌─────────────────────────────────────────────────┐
│  Swift layer (AppKit + SwiftUI)                 │
│  • Fetches data from Dexcom Share API           │
│  • Owns all calculation logic (stats, TIR etc.) │
│  • Manages app lifecycle, polling, credentials  │
│  • Drives the status bar title                  │
└────────────────────┬────────────────────────────┘
                     │ JS contract (see below)
┌────────────────────▼────────────────────────────┐
│  HTML/JS layer  (bundle-native.html)            │
│  • Pure renderer — displays what Swift sends    │
│  • No data fetching, no calculations            │
│  • React + SVG chart, system fonts              │
│  • Self-contained, zero external dependencies  │
└─────────────────────────────────────────────────┘
```

---

## Key Files

| File | Purpose |
|---|---|
| `AppDelegate.swift` | App entry point. Owns `NSStatusItem`, `NSPopover`, polling timer, and the `PreferencesView` SwiftUI struct. Central coordinator. |
| `GlucoseWebViewController.swift` | `NSViewController` subclass owning the `WKWebView`. Exposes `injectHistory(_:)` and `pushReading(_:)`. Responsible for the JS contract. |
| `DexcomClient.swift` | Handles Dexcom Share API authentication and reading fetch. Callback-based. |
| `GlucoseStats.swift` | `GlucoseStats` struct + `glucoseStats(from:hours:thresholds:)` free function. All TIR/average/low calculation lives here. |
| `GlucoseFormatter.swift` | Pure display helper. Formats values and trend arrows for the status bar title. No calculation logic. |
| `GlucoseThresholds.swift` | `GlucoseThresholds` model + `GlucoseThresholdsStore` (UserDefaults persistence). Single source of truth for low/high thresholds. |
| `bundle-native.html` | **Do not edit directly.** Built from a separate React/TypeScript project. See *Rebuilding the Bundle* below. |

---

## Data Flow

```
Dexcom Share API
      │  JSON (mg/dL, Dexcom trend strings)
      ▼
DexcomClient.fetchReadings()
      │  [DexcomReading]  — already converted to mmol/L
      ▼
AppDelegate.updateUI(with:)
      │
      ├─► graphData: [GraphDatum]   (reversed, chronological)
      │
      ├─► glucoseStats(from: graphData, thresholds: ...)
      │         └─► currentStats: GlucoseStats
      │
      ├─► updateStatusBarTitle()    (uses GlucoseFormatter + currentStats)
      │
      └─► GlucoseWebViewController
              ├─► injectHistory(graphData)   — on first load / popover open
              └─► pushReading(latest)        — on every poll
```

---

## Units

**All internal values are mmol/L.** Conversion from mg/dL happens exactly once: in `DexcomReading.init(from:)` in `AppDelegate.swift`. No other file should perform unit conversion. Do not introduce mg/dL anywhere.

```swift
valueMmol = (Double(mgdl) * 0.0555 * 10).rounded() / 10
```

---

## Dexcom Trend Strings

The API returns PascalCase trend strings. These flow through the app in two forms:

| API string | Arrow (status bar) | Normalised (JS chart) |
|---|---|---|
| `DoubleUp` | ↑↑ | _(passed as-is to JS)_ |
| `SingleUp` | ↑ | |
| `FortyFiveUp` | ↗ | |
| `Flat` | → | |
| `FortyFiveDown` | ↘ | |
| `SingleDown` | ↓ | |
| `DoubleDown` | ↓↓ | |
| `NotComputable` | ? | |
| `RateOutOfRange` | - | |
| `None` | _(empty)_ | |

`GlucoseFormatter` handles arrow rendering for the status bar. The JS bundle has its own `DEXCOM_TREND_MAP` and expects the raw API strings — pass them unchanged.

---

## Swift ↔ JS Contract

`bundle-native.html` exposes two integration points. Both are the exclusive responsibility of `GlucoseWebViewController`.

### 1. Initial data injection (`__INITIAL_DATA__`)

Injected via `WKUserScript` at `.atDocumentStart` **before** the page loads. The chart renders immediately with real data — no flash of empty state.

```swift
window.__INITIAL_DATA__ = {
  "readings": [
    { "time": 1743670800000, "value": 7.2 },  // time = Unix ms, value = mmol/L
    ...
  ],
  "thresholds": {
    "low": 3.9,   // mmol/L — lower dashed line + TIR lower bound
    "high": 9.9   // mmol/L — upper dashed line + TIR upper bound
  },
  "stats": {
    // Keyed by range label — must include all four windows.
    // The JS picks the correct entry when the user switches range.
    "3h":  { "timeInRangePercent": 80, "average": 7.1, "periodLow": 5.2, "rangeLabel": "3H"  },
    "6h":  { "timeInRangePercent": 74, "average": 7.4, "periodLow": 4.8, "rangeLabel": "6H"  },
    "12h": { "timeInRangePercent": 71, "average": 7.6, "periodLow": 4.6, "rangeLabel": "12H" },
    "24h": { "timeInRangePercent": 68, "average": 7.8, "periodLow": 4.3, "rangeLabel": "24H" }
  },
  "currentReading": {
    "value": 7.2,
    "trend": "Flat",              // raw Dexcom API string
    "timestamp": 1743670800000   // Unix ms
  }
}
```

If `__INITIAL_DATA__` is absent or `readings` is empty, the chart shows a "Waiting for data" state rather than crashing. If stats for a particular range key are missing, that range shows "No data for this range" in the pills — so always provide all four keys.

### 2. Live reading push (`window.updateReading`)

Called via `evaluateJavaScript` on every successful poll. Appends a new point to the chart and updates all displayed values.

```swift
window.updateReading({
  "value": 7.5,
  "trend": "FortyFiveUp",
  "timestamp": 1743671100000,
  "stats": {
    "3h":  { "timeInRangePercent": 81, "average": 7.2, "periodLow": 5.2, "rangeLabel": "3H"  },
    "6h":  { "timeInRangePercent": 75, "average": 7.5, "periodLow": 4.8, "rangeLabel": "6H"  },
    "12h": { "timeInRangePercent": 72, "average": 7.7, "periodLow": 4.6, "rangeLabel": "12H" },
    "24h": { "timeInRangePercent": 69, "average": 7.9, "periodLow": 4.3, "rangeLabel": "24H" }
  },
  "thresholds": {                  // optional — omit if unchanged
    "low": 3.9,
    "high": 9.9
  }
})
```

`thresholds` in `updateReading` is optional. Only include it when thresholds have changed (e.g. user saves new values in Preferences). When included, the chart lines and badge logic update immediately without requiring a reload.

### Contract rules — never violate these

- **Swift owns all numbers.** `timeInRangePercent`, `average`, `periodLow` are calculated in `glucoseStats()` for all four time windows and passed to JS. The JS bundle contains no calculation logic — it only selects the correct pre-computed stats entry based on the active range. The status bar title uses the `"24h"` entry from `currentStats`.
- **No mock or fallback data in the bundle.** If there is no data, the empty state is shown. Do not add sample data to `bundle-native.html`.
- **Timestamps are Unix milliseconds** (`Date.timeIntervalSince1970 * 1000`), not seconds.
- **Readings array is chronological** (oldest first). `AppDelegate.updateUI` reverses the Dexcom response before storing in `graphData`.
- **Thresholds come from `GlucoseThresholdsStore`**, not from `GlucoseFormatter` or hardcoded values.

---

## Thresholds

Single source of truth: `GlucoseThresholdsStore` (UserDefaults, JSON-encoded).

```swift
GlucoseThresholds.default  // low: 3.9, high: 9.9
```

`GlucoseFormatter` is a display/formatting helper only — it must not contain threshold values. `glucoseStats(from:hours:thresholds:)` takes thresholds as a parameter. All call sites should pass `GlucoseThresholdsStore.current`.

---

## Popover and WKWebView

- Popover size: `CGSize(width: 640, height: 600)`, `NSAppearance.darkAqua`
- `WKWebView.drawsBackground = false` — prevents light bleed at popover edges
- `bundle-native.html` is added to the Xcode target via Copy Bundle Resources
- Loaded with `loadFileURL(_:allowingReadAccessTo:)` from `Bundle.main`
- On every popover open, `injectHistory` is called to refresh the chart — see `togglePopover` in `AppDelegate`

---

## Credentials

Stored in macOS Keychain via `KeychainHelper` (in `AppDelegate.swift`). Keys: `"username"`, `"password"`. Never store credentials in `UserDefaults` or in code.

---

## Preferences Window

`PreferencesView` is a private SwiftUI struct nested inside `AppDelegate`. It communicates with `AppDelegate` exclusively through callbacks (`onSignIn`, `onSignOut`, `onSaveThresholds`). The window is created lazily in `openPreferences()` and kept alive (`isReleasedWhenClosed = false`). When adding new settings, follow the existing callback pattern rather than giving `PreferencesView` direct access to `AppDelegate`.

---

## Polling

- Interval: 60 seconds, tolerance 5 seconds
- Session ID is cached; on decode failure (expired session) it is cleared and re-authenticated on the next poll
- `updateUI(with:)` always dispatches to main queue before touching UI or calling into `GlucoseWebViewController`

---

## Logging

Use `dlog(...)` (not `print`) for debug output throughout the app. It is already defined somewhere in the project.

---

## Testing

Unit tests live in the test target. Currently cover `glucoseStats()`. When adding new calculation logic, add it to a free function or `struct` (not inside `AppDelegate`) so it is testable without instantiating the full app.

Test data conventions:
- Use fixed `Date` values, not `Date()` — tests must be deterministic
- Always test the boundary values: readings exactly at `low`, exactly at `high`, one point below, one point above
- When testing TIR, verify both the percentage and that `readingCount` is correct

---

## Rebuilding `bundle-native.html`

`bundle-native.html` is **not hand-edited**. The source lives in `WebChart/` at the root of this repository. The only file that normally changes is `WebChart/src/App.tsx`.

### Directory structure

```
WebChart/
  src/
    App.tsx          ← the only file you should edit
    main.tsx         ← entry point, do not edit
    index.css        ← Tailwind base, do not edit
    lib/utils.ts     ← shadcn utility, do not edit
  index.html         ← HTML entry point, do not edit
  build.sh           ← run this to produce bundle-native.html
  package.json
  pnpm-lock.yaml
  tailwind.config.js
  tsconfig.json
  vite.config.ts
  .parcelrc
bundle-native.html   ← output, committed, used by Xcode target
```

### Build steps

```bash
cd WebChart
bash build.sh
```

The script will:
1. Run `pnpm install` if `node_modules` is absent
2. Type-check with `tsc --noEmit` — fix any errors before proceeding
3. Build with Parcel
4. Inline all JS and CSS into a single self-contained HTML file
5. Strip Google Fonts links (the bundle uses system fonts only)
6. Assert that no mock data (`generateGlucoseData`) is present
7. Copy the result to `bundle-native.html` in the project root

**Requirements:** Node 18+, pnpm (`npm install -g pnpm`), Python 3 (macOS system Python is fine).

### After rebuilding

- If Xcode shows `bundle-native.html` as modified, that is expected — commit it
- No Xcode build step is needed; the file is already in the app bundle via Copy Bundle Resources
- Verify the app still behaves correctly by opening the popover and confirming data loads

### What not to change in `App.tsx`

- Do not re-add `generateGlucoseData` or any mock/fallback data
- Do not add client-side calculation of TIR, average, or period low — these come from Swift
- Do not change the shapes of `InitialData`, `LiveUpdate`, or `GlucoseThresholds` without a matching update to `GlucoseWebViewController.swift`
- Do not import external fonts — use system font stack only (`-apple-system`, `SF Mono`, etc.)

---

## What Not to Do

- **Do not add calculations to `bundle-native.html`** — TIR, average, low are Swift's responsibility
- **Do not add mock/sample data to `bundle-native.html`** — the empty state exists for a reason
- **Do not perform unit conversion outside `DexcomReading.init`** — everything is mmol/L after decoding
- **Do not hardcode threshold values** (`4.5`, `10.0`, etc.) anywhere — use `GlucoseThresholds.default` or `GlucoseThresholdsStore.current`
- **Do not give `PreferencesView` direct access to app state** — use the callback pattern
- **Do not dispatch UI updates from background threads** — `updateUI(with:)` already handles this; don't add new Dexcom callback paths that skip `DispatchQueue.main.async`
- **Do not store sensitive data outside Keychain** — credentials stay in `KeychainHelper`
