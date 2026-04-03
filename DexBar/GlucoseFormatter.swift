//  GlucoseFormatter.swift
//  DexBar

enum GlucoseFormatter {

    static let lowThreshold = 4.0

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
