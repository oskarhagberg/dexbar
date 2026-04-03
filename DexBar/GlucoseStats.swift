//  GlucoseStats.swift
//  DexBar

import Foundation

struct GlucoseStats {
    let timeInRange: Double       // 0.0–1.0 fraction of readings in TIR
    let timeInRangePercent: Int   // Int(timeInRange * 100)
    let average: Double           // mmol/L
    let periodLow: Double         // mmol/L (lowest reading in window)
    let readingCount: Int
    let rangeLabel: String        // e.g. "24H"
}

/// Returns nil if `readings` is empty.
/// Only includes readings within the last `hours` hours from now.
func glucoseStats(from readings: [GraphDatum], hours: Double = 24, thresholds: GlucoseThresholds = .default, rangeLabel: String = "24H") -> GlucoseStats? {
    let cutoff = Date().addingTimeInterval(-hours * 3600)
    let window = readings.filter { $0.timestamp >= cutoff }
    guard !window.isEmpty else { return nil }

    let inRange = window.filter {
        $0.value >= thresholds.low && $0.value <= thresholds.high
    }
    let tir = Double(inRange.count) / Double(window.count)
    let avg = window.map { $0.value }.reduce(0, +) / Double(window.count)
    let low = window.map { $0.value }.min()!   // safe: window is non-empty

    return GlucoseStats(
        timeInRange: tir,
        timeInRangePercent: Int((tir * 100).rounded()),
        average: avg,
        periodLow: low,
        readingCount: window.count,
        rangeLabel: rangeLabel
    )
}
