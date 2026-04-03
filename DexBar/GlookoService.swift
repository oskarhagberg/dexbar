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

    private let baseURL = "https://eu.api.glooko.com"
    private let session: URLSession

    private var sessionCookie: String?
    private var glookoCode: String?
    // Kept only for 401 retry — never persisted to disk or Keychain
    private var cachedEmail: String?
    private var cachedPassword: String?

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Public API

    func authenticate(email: String, password: String, completion: @escaping (Bool, String?) -> Void) {
        cachedEmail = email
        cachedPassword = password
        signIn(email: email, password: password) { [weak self] cookie in
            guard let self, let cookie else {
                completion(false, "Could not sign in to Glooko. Check your email and password.")
                return
            }
            self.fetchGlookoCode(cookie: cookie) { code in
                guard let code else {
                    completion(false, "Signed in but could not retrieve Glooko patient ID.")
                    return
                }
                self.sessionCookie = cookie
                self.glookoCode = code
                dlog("[Glooko] Authenticated. glookoCode: \(code)")
                completion(true, nil)
            }
        }
    }

    func fetchPumpEvents(from startDate: Date, to endDate: Date, completion: @escaping ([PumpEvent]?) -> Void) {
        guard sessionCookie != nil, glookoCode != nil else {
            dlog("[Glooko] fetchPumpEvents: no session — authenticate first")
            completion(nil)
            return
        }
        doFetchHistories(from: startDate, to: endDate, retry: true, completion: completion)
    }

    func clearSession() {
        sessionCookie = nil
        glookoCode = nil
    }

    // MARK: - Private network

    private func signIn(email: String, password: String, completion: @escaping (String?) -> Void) {
        guard let url = URL(string: "\(baseURL)/api/v3/users/sign_in") else { completion(nil); return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["user": ["email": email, "password": password]]
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { completion(nil); return }
        request.httpBody = httpBody

        session.dataTask(with: request) { _, response, error in
            if let error { dlog("[Glooko] sign_in error:", error); completion(nil); return }
            guard let http = response as? HTTPURLResponse else { completion(nil); return }
            let cookie = GlookoService.extractSessionCookie(from: http)
            if cookie == nil { dlog("[Glooko] sign_in: no session cookie in response") }
            completion(cookie)
        }.resume()
    }

    private func fetchGlookoCode(cookie: String, completion: @escaping (String?) -> Void) {
        guard let url = URL(string: "\(baseURL)/api/v3/session/users") else { completion(nil); return }
        var request = URLRequest(url: url)
        request.setValue(cookie, forHTTPHeaderField: "Cookie")

        session.dataTask(with: request) { data, _, error in
            if let error { dlog("[Glooko] session/users error:", error); completion(nil); return }
            guard let data else { completion(nil); return }
            struct SessionResponse: Decodable {
                struct User: Decodable { let glookoCode: String }
                let currentUser: User
            }
            guard let resp = try? JSONDecoder().decode(SessionResponse.self, from: data) else {
                dlog("[Glooko] session/users: decode error")
                completion(nil)
                return
            }
            completion(resp.currentUser.glookoCode)
        }.resume()
    }

    private func doFetchHistories(from startDate: Date, to endDate: Date, retry: Bool, completion: @escaping ([PumpEvent]?) -> Void) {
        guard let cookie = sessionCookie, let code = glookoCode else { completion(nil); return }

        guard var components = URLComponents(string: "\(baseURL)/api/v3/users/summary/histories") else {
            completion(nil); return
        }
        components.queryItems = [
            URLQueryItem(name: "patient",   value: code),
            URLQueryItem(name: "startDate", value: GlookoService.iso8601.string(from: startDate)),
            URLQueryItem(name: "endDate",   value: GlookoService.iso8601.string(from: endDate))
        ]
        guard let url = components.url else { completion(nil); return }
        var request = URLRequest(url: url)
        request.setValue(cookie, forHTTPHeaderField: "Cookie")

        session.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            if let error { dlog("[Glooko] histories error:", error); completion(nil); return }

            if let http = response as? HTTPURLResponse, http.statusCode == 401, retry {
                dlog("[Glooko] 401 — clearing session and re-authenticating")
                self.sessionCookie = nil
                self.glookoCode = nil
                guard let email = self.cachedEmail, let password = self.cachedPassword else {
                    completion(nil); return
                }
                self.authenticate(email: email, password: password) { [weak self] ok, _ in
                    guard let self, ok else { completion(nil); return }
                    self.doFetchHistories(from: startDate, to: endDate, retry: false, completion: completion)
                }
                return
            }

            guard let data else { completion(nil); return }
            let events = GlookoService.parsePumpEvents(from: data)
            dlog("[Glooko] Fetched \(events.count) pump events")
            completion(events)
        }.resume()
    }

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

    static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Parses pump timestamps as local device time.
    /// Glooko stores the pump's local clock in pumpTimestamp but incorrectly labels it
    /// with a Z/+00:00 designator. Strip the timezone suffix and parse as local time,
    /// matching how the official Glooko app displays these events.
    private static let pumpLocalFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let pumpLocalFormatterNoMs: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
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

    /// Parses a Glooko pumpTimestamp as local device time.
    /// Strips any trailing timezone designator (Z or +HH:MM) before parsing,
    /// so "2026-04-03T11:58:10.000Z" → 11:58:10 in the device's local timezone.
    static func parseLocalPumpTimestamp(_ raw: String) -> Date? {
        // Everything before the timezone designator (Z or +/-)
        let stripped = raw.components(separatedBy: CharacterSet(charactersIn: "Z+")).first ?? raw
        return pumpLocalFormatter.date(from: stripped) ?? pumpLocalFormatterNoMs.date(from: stripped)
    }

    /// Parses raw histories JSON data into a PumpEvent array.
    ///
    /// Filter rules applied:
    ///   - Only "pumps_normal_boluses" type entries
    ///   - Both outer and item-level softDeleted must be false (nil treated as false)
    ///   - insulinDelivered must be present in JSON
    ///   - Excluded only if both insulinDelivered == 0 AND carbsInput == 0 (noise)
    ///   - Correction boluses (units > 0, carbs == 0) are included
    ///   - Zero-dose meal logs (units == 0, carbs > 0) are included
    ///
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
                  let date = GlookoService.parseLocalPumpTimestamp(tsString),
                  let units = item.insulinDelivered else { continue }
            let carbs = item.carbsInput ?? 0.0
            guard units > 0 || carbs > 0 else { continue }
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
