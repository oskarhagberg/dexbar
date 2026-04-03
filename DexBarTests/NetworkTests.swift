//  NetworkTests.swift
//  DexBarTests

import Testing
import Foundation
@testable import DexBar

/// Parent suite forces DexcomClient and GlookoService network tests to run
/// sequentially, preventing races on MockURLProtocol.handler.
@Suite("Network", .serialized)
struct NetworkTests {

    @Suite("DexcomClient", .serialized)
    struct DexcomClientTests {

        private let session: URLSession
        private let client: DexcomClient

        init() {
            let s = MockURLProtocol.makeSession()
            session = s
            client = DexcomClient(session: s)
        }

        // MARK: postJSON

        @Test func postJSONReturnsDecodedString() async throws {
            MockURLProtocol.handler = { req in
                let url = req.url!
                return MockURLProtocol.respond(with: "abc-account-id", url: url)
            }
            let result: String? = await withCheckedContinuation { cont in
                client.postJSON(endpoint: "General/AuthenticatePublisherAccount",
                                body: ["accountName": "user", "password": "pass", "applicationId": "id"]) {
                    cont.resume(returning: $0)
                }
            }
            #expect(result == "abc-account-id")
        }

        @Test func postJSONReturnsNilOnNetworkError() async {
            MockURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
            let result: String? = await withCheckedContinuation { cont in
                client.postJSON(endpoint: "General/AuthenticatePublisherAccount", body: [:]) {
                    cont.resume(returning: $0)
                }
            }
            #expect(result == nil)
        }

        @Test func postJSONSetsMethodAndHeaders() async {
            var capturedRequest: URLRequest?
            MockURLProtocol.handler = { req in
                capturedRequest = req
                return MockURLProtocol.respond(with: "id", url: req.url!)
            }
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                client.postJSON(endpoint: "General/AuthenticatePublisherAccount",
                                body: ["accountName": "user", "password": "pass", "applicationId": "id"]) { _ in
                    cont.resume()
                }
            }
            #expect(capturedRequest?.httpMethod == "POST")
            #expect(capturedRequest?.value(forHTTPHeaderField: "Content-Type") == "application/json")
            #expect(capturedRequest?.value(forHTTPHeaderField: "Accept") == "application/json")
            // URLSession moves httpBody to httpBodyStream before handing the request to URLProtocol;
            // read from whichever source is available.
            let bodyData: Data? = capturedRequest?.httpBody ?? {
                guard let stream = capturedRequest?.httpBodyStream else { return nil }
                stream.open()
                defer { stream.close() }
                var data = Data()
                let bufferSize = 1024
                let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
                defer { buffer.deallocate() }
                while stream.hasBytesAvailable {
                    let read = stream.read(buffer, maxLength: bufferSize)
                    if read > 0 { data.append(buffer, count: read) }
                }
                return data
            }()
            if let body = bodyData,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: String] {
                #expect(json["accountName"] == "user")
                #expect(json["password"] == "pass")
                #expect(json["applicationId"] == "id")
            } else {
                Issue.record("Request body was nil or not valid JSON")
            }
        }

        // MARK: fetchReadings

        @Test func fetchReadingsDecodesArray() async throws {
            let json = """
            [
              {"Value": 108, "Trend": "Flat", "WT": "Date(1000)"},
              {"Value":  90, "Trend": "SingleDown", "WT": "Date(2000)"}
            ]
            """.data(using: .utf8)!

            MockURLProtocol.handler = { req in
                MockURLProtocol.respond(with: json, url: req.url!)
            }
            let readings: [DexcomReading]? = await withCheckedContinuation { cont in
                client.fetchReadings(sessionId: "test-session") { cont.resume(returning: $0) }
            }
            #expect(readings?.count == 2)
            #expect(readings?[0].trend == "Flat")
        }

        @Test func fetchReadingsReturnsNilOnBadJSON() async {
            MockURLProtocol.handler = { req in
                MockURLProtocol.respond(with: "not json".data(using: .utf8)!, url: req.url!)
            }
            let readings: [DexcomReading]? = await withCheckedContinuation { cont in
                client.fetchReadings(sessionId: "test-session") { cont.resume(returning: $0) }
            }
            #expect(readings == nil)
        }

        @Test func fetchReadingsUsesGETMethod() async {
            var capturedRequest: URLRequest?
            MockURLProtocol.handler = { req in
                capturedRequest = req
                return MockURLProtocol.respond(with: "[]".data(using: .utf8)!, url: req.url!)
            }
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                client.fetchReadings(sessionId: "s") { _ in cont.resume() }
            }
            // URLSession defaults to GET when httpMethod is not set; nil means GET
            #expect(capturedRequest?.httpMethod == nil || capturedRequest?.httpMethod == "GET")
        }

        @Test func fetchReadingsIncludesSessionIdInQuery() async {
            var capturedURL: URL?
            MockURLProtocol.handler = { req in
                capturedURL = req.url
                return MockURLProtocol.respond(with: "[]".data(using: .utf8)!, url: req.url!)
            }
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                client.fetchReadings(sessionId: "my-session-id") { _ in cont.resume() }
            }
            let components = URLComponents(url: capturedURL!, resolvingAgainstBaseURL: false)
            let sessionParam = components?.queryItems?.first(where: { $0.name == "sessionId" })
            #expect(sessionParam?.value == "my-session-id")
        }

        // MARK: authenticate

        @Test func authenticateReturnSessionIdOnSuccess() async {
            var callCount = 0
            MockURLProtocol.handler = { req in
                callCount += 1
                // First call returns accountId, second returns sessionId
                let value = callCount == 1 ? "account-123" : "session-456"
                return MockURLProtocol.respond(with: value, url: req.url!)
            }
            let sessionId: String? = await withCheckedContinuation { cont in
                client.authenticate(username: "u", password: "p") { cont.resume(returning: $0) }
            }
            #expect(sessionId == "session-456")
            // callCount is safe to read here: the async `withCheckedContinuation` only resumes after
            // the service calls `completion`, which happens after both network calls have completed.
            // The await provides the memory ordering barrier.
            #expect(callCount == 2)
        }

        @Test func authenticateReturnsNilWhenAccountIdFails() async {
            MockURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
            let sessionId: String? = await withCheckedContinuation { cont in
                client.authenticate(username: "u", password: "p") { cont.resume(returning: $0) }
            }
            #expect(sessionId == nil)
        }
    }

    @Suite("GlookoService network", .serialized)
    struct GlookoServiceNetworkTests {

        private let session: URLSession
        private let svc: GlookoService

        init() {
            session = MockURLProtocol.makeSession()
            svc = GlookoService(session: session)
        }

        @Test func authenticateSuccessStoresCookieAndCode() async {
            var callCount = 0
            MockURLProtocol.handler = { req in
                callCount += 1
                let url = req.url!
                if callCount == 1 {
                    // Sign-in — return session cookie
                    let data = #"{"two_fa_required":false,"success":true}"#.data(using: .utf8)!
                    let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                        headerFields: ["Set-Cookie": "_logbook-web_session=tok123; domain=glooko.com; path=/"])!
                    return (data, response)
                } else {
                    // session/users — return glookoCode
                    let data = #"{"currentUser":{"glookoCode":"eu-west-1-test-code","timezone":"Europe/Stockholm","meterUnits":"mmoll"}}"#.data(using: .utf8)!
                    let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                    return (data, response)
                }
            }
            let result: (Bool, String?) = await withCheckedContinuation { cont in
                svc.authenticate(email: "user@test.com", password: "pass") { ok, err in
                    cont.resume(returning: (ok, err))
                }
            }
            #expect(result.0 == true)
            #expect(result.1 == nil)
            // callCount is safe to read here: the async `withCheckedContinuation` only resumes after
            // the service calls `completion`, which happens after both network calls have completed.
            // The await provides the memory ordering barrier.
            #expect(callCount == 2)
        }

        @Test func authenticateFailsWhenSignInReturnsNoSetCookie() async {
            MockURLProtocol.handler = { req in
                let data = #"{"two_fa_required":false,"success":true}"#.data(using: .utf8)!
                let response = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (data, response)
            }
            let result: (Bool, String?) = await withCheckedContinuation { cont in
                svc.authenticate(email: "user@test.com", password: "pass") { ok, err in
                    cont.resume(returning: (ok, err))
                }
            }
            #expect(result.0 == false)
            #expect(result.1 != nil)
        }

        @Test func authenticateFailsOnNetworkError() async {
            MockURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
            let result: (Bool, String?) = await withCheckedContinuation { cont in
                svc.authenticate(email: "u", password: "p") { ok, err in cont.resume(returning: (ok, err)) }
            }
            #expect(result.0 == false)
        }

        @Test func fetchPumpEventsReturnsNilWhenNotAuthenticated() async {
            let events: [PumpEvent]? = await withCheckedContinuation { cont in
                svc.fetchPumpEvents(from: Date().addingTimeInterval(-3600), to: Date()) {
                    cont.resume(returning: $0)
                }
            }
            #expect(events == nil)
        }

        @Test func clearSessionResetsState() async {
            svc.clearSession()
            let events: [PumpEvent]? = await withCheckedContinuation { cont in
                svc.fetchPumpEvents(from: Date().addingTimeInterval(-3600), to: Date()) {
                    cont.resume(returning: $0)
                }
            }
            #expect(events == nil)
        }

        @Test func authenticate_withValidCachedCookie_skipsSignIn() async {
            var callCount = 0
            MockURLProtocol.handler = { req in
                callCount += 1
                // Only session/users should be called — sign_in must be skipped
                let data = #"{"currentUser":{"glookoCode":"eu-west-1-code","timezone":"UTC","meterUnits":"mmoll"}}"#.data(using: .utf8)!
                return (data, HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            let result: (Bool, String?) = await withCheckedContinuation { cont in
                svc.authenticate(email: "u@test.com", password: "p",
                                 cachedCookie: "_logbook-web_session=cached123") { ok, err in
                    cont.resume(returning: (ok, err))
                }
            }
            #expect(result.0 == true)
            #expect(callCount == 1)  // only session/users, no sign_in
        }

        @Test func authenticate_withInvalidCachedCookie_fallsBackToSignIn() async {
            var callCount = 0
            MockURLProtocol.handler = { req in
                callCount += 1
                let url = req.url!
                if callCount == 1 {
                    // fetchGlookoCode with stale cookie — bad JSON triggers fallback
                    return ("{\"error\":\"unauthorized\"}".data(using: .utf8)!,
                            HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil)!)
                } else if callCount == 2 {
                    // sign_in — return new cookie
                    let data = #"{"two_fa_required":false,"success":true}"#.data(using: .utf8)!
                    let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                        headerFields: ["Set-Cookie": "_logbook-web_session=newcookie456; domain=glooko.com; path=/"])!
                    return (data, response)
                } else {
                    // fetchGlookoCode with new cookie — succeed
                    let data = #"{"currentUser":{"glookoCode":"eu-west-1-code","timezone":"UTC","meterUnits":"mmoll"}}"#.data(using: .utf8)!
                    return (data, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
                }
            }
            var capturedCookie: String?
            svc.onNewSessionCookie = { capturedCookie = $0 }
            let result: (Bool, String?) = await withCheckedContinuation { cont in
                svc.authenticate(email: "u@test.com", password: "p",
                                 cachedCookie: "_logbook-web_session=stale") { ok, err in
                    cont.resume(returning: (ok, err))
                }
            }
            #expect(result.0 == true)
            #expect(callCount == 3)
            #expect(capturedCookie == "_logbook-web_session=newcookie456")
        }

        @Test func authenticate_firesOnNewSessionCookieCallback() async {
            MockURLProtocol.handler = { req in
                let data = #"{"currentUser":{"glookoCode":"code","timezone":"UTC","meterUnits":"mmoll"}}"#.data(using: .utf8)!
                return (data, HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            var capturedCookie: String?
            svc.onNewSessionCookie = { capturedCookie = $0 }

            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                svc.authenticate(email: "u@test.com", password: "p",
                                 cachedCookie: "_logbook-web_session=cached999") { _, _ in cont.resume() }
            }
            #expect(capturedCookie == "_logbook-web_session=cached999")
        }
    }
}
