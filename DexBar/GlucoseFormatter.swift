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

    static func arrow(for trend: String) -> String {
        trendArrows[trend] ?? "?"
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
