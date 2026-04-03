//  GlucoseThresholds.swift
//  DexBar

import Foundation

struct GlucoseThresholds: Codable, Equatable {
    let low: Double   // mmol/L
    let high: Double  // mmol/L

    static let `default` = GlucoseThresholds(low: 3.9, high: 9.9)
}

enum GlucoseThresholdsStore {
    private static let key = "glucoseThresholds"

    static var current: GlucoseThresholds {
        get {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let t = try? JSONDecoder().decode(GlucoseThresholds.self, from: data)
            else { return .default }
            return t
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: key)
            }
        }
    }
}
