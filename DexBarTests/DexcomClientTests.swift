import Testing
import Foundation
@testable import DexBar

@Suite("DexcomClient", .serialized)
struct DexcomClientTests {

    private let session = MockURLProtocol.makeSession()
    private var client: DexcomClient { DexcomClient(session: session) }

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
            client.postJSON(endpoint: "General/AuthenticatePublisherAccount", body: [:]) { _ in
                cont.resume()
            }
        }
        #expect(capturedRequest?.httpMethod == "POST")
        #expect(capturedRequest?.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(capturedRequest?.value(forHTTPHeaderField: "Accept") == "application/json")
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
