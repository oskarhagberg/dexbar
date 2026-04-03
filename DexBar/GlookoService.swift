//  GlookoService.swift
//  DexBar

import Foundation

// MARK: - Public model

struct PumpEvent: Decodable {
    let timestamp: TimeInterval  // Unix milliseconds (from pumpTimestamp)
    let units: Double            // insulinDelivered
    let carbs: Double            // carbsInput (0.0 for correction boluses)
    let bg: Double               // bloodGlucoseInput / 1000, or 0 if null
}

// MARK: - Service

class GlookoService {

    // MARK: - Private raw response types

    private struct HistoriesResponse: Decodable {
        let histories: [HistoryEntry]
    }

    private struct HistoryEntry: Decodable {
        let type: String
        let softDeleted: Bool
        let item: HistoryItem?
    }

    private struct HistoryItem: Decodable {
        let pumpTimestamp: String?
        let insulinDelivered: Double?
        let carbsInput: Double?
        let bloodGlucoseInput: Double?
        let softDeleted: Bool?
    }

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso8601NoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    // MARK: - Static testable helpers

    /// Extracts `_logbook-web_session=<value>` from the Set-Cookie response header.
    /// Returns nil if the header is absent or does not contain the expected key.
    static func extractSessionCookie(from response: HTTPURLResponse) -> String? {
        guard let header = response.allHeaderFields["Set-Cookie"] as? String else { return nil }
        return GlookoService.sessionCookie(from: header)
    }

    /// Extracts `_logbook-web_session=<value>` from a raw Set-Cookie header string.
    /// Apple coalesces multiple Set-Cookie headers with newline separators when parsing
    /// real HTTP responses; the `headerFields` dict initialiser joins them with commas.
    /// Both separators are handled here.
    static func sessionCookie(from header: String) -> String? {
        // Split on newline (real network traffic) or comma (HTTPURLResponse dict init / some proxies).
        let candidates = header.components(separatedBy: CharacterSet(charactersIn: "\n,"))
        for candidate in candidates {
            let parts = candidate.components(separatedBy: ";")
            if let first = parts.first?.trimmingCharacters(in: .whitespaces),
               first.hasPrefix("_logbook-web_session=") {
                return first
            }
        }
        return nil
    }

    /// Parses raw histories JSON data into PumpEvent array.
    /// Filters: only pumps_normal_boluses, both softDeleted flags false, insulinDelivered > 0.
    /// Results are sorted ascending by timestamp.
    static func parsePumpEvents(from data: Data) -> [PumpEvent] {
        guard let response = try? JSONDecoder().decode(HistoriesResponse.self, from: data) else {
            dlog("[Glooko] parsePumpEvents: decode error")
            return []
        }
        var events: [PumpEvent] = []
        for entry in response.histories {
            guard entry.type == "pumps_normal_boluses",
                  !entry.softDeleted,
                  let item = entry.item,
                  item.softDeleted != true,   // nil (field absent from JSON) is treated as not deleted
                  let tsString = item.pumpTimestamp,
                  let date = iso8601.date(from: tsString) ?? iso8601NoFraction.date(from: tsString),
                  let units = item.insulinDelivered,
                  units > 0 else { continue }
            let carbs = item.carbsInput ?? 0.0
            // bloodGlucoseInput is in mmol/L × 1000 (Glooko's internal representation); divide by 1000 to get mmol/L
            let bg = (item.bloodGlucoseInput ?? 0.0) / 1000.0
            events.append(PumpEvent(
                timestamp: date.timeIntervalSince1970 * 1000,
                units: units,
                carbs: carbs,
                bg: bg
            ))
        }
        return events.sorted { $0.timestamp < $1.timestamp }
    }
}
