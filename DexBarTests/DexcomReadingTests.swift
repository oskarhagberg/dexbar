import Testing
import Foundation
@testable import DexBar

@Suite("DexcomReading")
struct DexcomReadingTests {

    // Helper: decode a single reading from a JSON dict
    private func decode(_ dict: [String: Any]) throws -> DexcomReading {
        let data = try JSONSerialization.data(withJSONObject: [dict])
        return try JSONDecoder().decode([DexcomReading].self, from: data)[0]
    }

    @Test func mgdlConvertedToMmol() throws {
        // 180 mg/dL * 0.0555 = 9.99 → rounded to 10.0
        let r = try decode(["Value": 180, "Trend": "Flat", "WT": "Date(0)"])
        #expect(r.valueMmol == 10.0)
    }

    @Test func lowValueRounded() throws {
        // 72 mg/dL * 0.0555 = 3.996 → rounded to 4.0
        let r = try decode(["Value": 72, "Trend": "Flat", "WT": "Date(0)"])
        #expect(r.valueMmol == 4.0)
    }

    @Test func trendPassedThrough() throws {
        let r = try decode(["Value": 100, "Trend": "SingleUp", "WT": "Date(0)"])
        #expect(r.trend == "SingleUp")
    }

    @Test func timestampParsedFromMilliseconds() throws {
        // 1000 ms = 1 second after epoch
        let r = try decode(["Value": 100, "Trend": "Flat", "WT": "Date(1000)"])
        #expect(r.timestamp == Date(timeIntervalSince1970: 1.0))
    }

    @Test func largeTimestamp() throws {
        // Real Dexcom timestamp (ms)
        let ms = 1_774_107_279_261.0
        let r = try decode(["Value": 100, "Trend": "Flat", "WT": "Date(\(Int(ms)))"])
        #expect(r.timestamp == Date(timeIntervalSince1970: ms / 1000.0))
    }

    @Test func invalidWTDefaultsToEpoch() throws {
        let r = try decode(["Value": 100, "Trend": "Flat", "WT": "Date(notanumber)"])
        #expect(r.timestamp == Date(timeIntervalSince1970: 0))
    }

    @Test func missingFieldThrows() {
        #expect(throws: (any Error).self) {
            _ = try self.decode(["Value": 100, "Trend": "Flat"]) // missing WT
        }
    }
}
