//  DexcomClient.swift
//  DexBar

import Foundation

struct DexcomClient {

    private let baseURL = "https://shareous1.dexcom.com/ShareWebServices/Services/"
    private let applicationId = "d89443d2-327c-4a6f-89e5-496bbb0317db"
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func postJSON(endpoint: String, body: [String: String], completion: @escaping (String?) -> Void) {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else { completion(nil); return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { completion(nil); return }
        request.httpBody = httpBody
        session.dataTask(with: request) { data, response, error in
            if let error = error {
                dlog("[\(endpoint)] Request failed:", error)
                completion(nil)
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let raw = data.flatMap { String(data: $0, encoding: .utf8) } ?? "<no body>"
            dlog("[\(endpoint)] HTTP \(status), body: \(raw)")
            guard let data = data, let value = try? JSONDecoder().decode(String.self, from: data) else {
                completion(nil)
                return
            }
            completion(value)
        }.resume()
    }

    func fetchReadings(sessionId: String, completion: @escaping ([DexcomReading]?) -> Void) {
        var components = URLComponents(string: "\(baseURL)Publisher/ReadPublisherLatestGlucoseValues")!
        components.queryItems = [
            URLQueryItem(name: "sessionId", value: sessionId),
            URLQueryItem(name: "minutes",   value: "1440"),
            URLQueryItem(name: "maxCount",  value: "288")
        ]
        guard let url = components.url else { completion(nil); return }
        dlog("[Readings] Fetching:", url)
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        session.dataTask(with: request) { data, response, error in
            if let error = error {
                dlog("[Readings] Request failed:", error)
                completion(nil)
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let raw = data.flatMap { String(data: $0, encoding: .utf8) } ?? "<no body>"
            dlog("[Readings] HTTP \(status), body: \(raw)")
            guard let data = data else { completion(nil); return }
            do {
                let readings = try JSONDecoder().decode([DexcomReading].self, from: data)
                dlog("[Readings] Decoded \(readings.count) readings")
                completion(readings)
            } catch {
                dlog("[Readings] Decode error:", error)
                completion(nil)
            }
        }.resume()
    }

    func authenticate(username: String, password: String, completion: @escaping (String?) -> Void) {
        postJSON(
            endpoint: "General/AuthenticatePublisherAccount",
            body: ["accountName": username, "password": password, "applicationId": applicationId]
        ) { accountId in
            guard let accountId else {
                dlog("[Auth] Failed to get account ID")
                completion(nil)
                return
            }
            dlog("[Auth] Got account ID: \(accountId)")
            self.postJSON(
                endpoint: "General/LoginPublisherAccountById",
                body: ["accountId": accountId, "password": password, "applicationId": self.applicationId]
            ) { sessionId in
                if let sessionId { dlog("[Auth] Got session ID: \(sessionId)") }
                else              { dlog("[Auth] Failed to get session ID") }
                completion(sessionId)
            }
        }
    }
}
