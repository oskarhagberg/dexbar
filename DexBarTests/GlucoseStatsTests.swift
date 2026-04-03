//  GlucoseStatsTests.swift
//  DexBarTests

import Foundation
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
        #expect(stats?.rangeLabel == "24H")
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
        let atLow  = datum(GlucoseThresholds.default.low)
        let atHigh = datum(GlucoseThresholds.default.high)
        let stats = glucoseStats(from: [atLow, atHigh])
        #expect(stats?.timeInRangePercent == 100)
    }

    @Test func customRangeAllInRange() {
        // Custom thresholds: 3.9–8.5 (narrower high than default)
        let thresholds = GlucoseThresholds(low: 3.9, high: 8.5)
        let readings = (0..<5).map { _ in datum(6.0) } // 6.0 is in 3.9–8.5
        let stats = glucoseStats(from: readings, thresholds: thresholds)
        #expect(stats?.timeInRangePercent == 100)
        #expect(stats?.readingCount == 5)
    }

    @Test func customRangeMixedReadings() {
        // Custom thresholds: 3.9–8.5
        // 3 readings at 6.0 (in range), 2 readings at 9.0 (above high=8.5, so OUT of range)
        let thresholds = GlucoseThresholds(low: 3.9, high: 8.5)
        let inRange = (0..<3).map { _ in datum(6.0) }
        let above   = (0..<2).map { _ in datum(9.0) }
        let stats = glucoseStats(from: inRange + above, thresholds: thresholds)
        #expect(stats?.timeInRangePercent == 60)
        #expect(stats?.readingCount == 5)
    }

    @Test func defaultThresholdsMatchExpectedValues() {
        // Verify GlucoseThresholds.default is (low: 3.9, high: 9.9)
        #expect(GlucoseThresholds.default.low == 3.9)
        #expect(GlucoseThresholds.default.high == 9.9)

        // A reading at 9.5 is IN the default range (≤ 9.9) but would be OUT of old hardcoded 4.5–10.0
        // (9.5 is in both actually, but 9.5 IS in 3.9–9.9, verify that)
        let stats = glucoseStats(from: [datum(9.5)])
        #expect(stats?.timeInRangePercent == 100)
    }

    @Test func rangeLabelMatchesPassedValue() {
        let stats3h  = glucoseStats(from: [datum(6.0)], hours: 3,  rangeLabel: "3H")
        let stats6h  = glucoseStats(from: [datum(6.0)], hours: 6,  rangeLabel: "6H")
        let stats12h = glucoseStats(from: [datum(6.0)], hours: 12, rangeLabel: "12H")
        #expect(stats3h?.rangeLabel  == "3H")
        #expect(stats6h?.rangeLabel  == "6H")
        #expect(stats12h?.rangeLabel == "12H")
    }
}
