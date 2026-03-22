import Testing
@testable import DexBar

@Suite("GlucoseFormatter")
struct GlucoseFormatterTests {

    @Test func knownTrendsMappedToArrows() {
        let cases: [(String, String)] = [
            ("DoubleUp",       "↑↑"),
            ("SingleUp",       "↑"),
            ("FortyFiveUp",    "↗"),
            ("Flat",           "→"),
            ("FortyFiveDown",  "↘"),
            ("SingleDown",     "↓"),
            ("DoubleDown",     "↓↓"),
            ("None",           ""),
            ("NotComputable",  "?"),
            ("RateOutOfRange", "-"),
        ]
        for (trend, expected) in cases {
            #expect(GlucoseFormatter.arrow(for: trend) == expected,
                    "Trend '\(trend)' should map to '\(expected)'")
        }
    }

    @Test func unknownTrendFallsBackToQuestionMark() {
        #expect(GlucoseFormatter.arrow(for: "SomeNewTrend") == "?")
    }

    @Test func valueBelowThresholdIsLow() {
        #expect(GlucoseFormatter.isLow(3.9) == true)
    }

    @Test func valueAtThresholdIsNotLow() {
        #expect(GlucoseFormatter.isLow(4.0) == false)
    }

    @Test func valueAboveThresholdIsNotLow() {
        #expect(GlucoseFormatter.isLow(5.5) == false)
    }

    @Test func statusLabelNormalReading() {
        let label = GlucoseFormatter.statusLabel(valueMmol: 6.5, trend: "Flat")
        #expect(label == "6.5 →")
    }

    @Test func statusLabelLowReadingIncludesWarning() {
        let label = GlucoseFormatter.statusLabel(valueMmol: 3.5, trend: "SingleDown")
        #expect(label == "⚠️ 3.5 ↓")
    }

    @Test func statusLabelUnknownTrendUsesFallbackArrow() {
        let label = GlucoseFormatter.statusLabel(valueMmol: 7.2, trend: "SomeUnknownTrend")
        #expect(label == "7.2 ?")
    }
}
