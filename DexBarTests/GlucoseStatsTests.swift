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
