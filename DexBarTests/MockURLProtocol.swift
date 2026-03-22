import Foundation

/// A URLProtocol subclass that intercepts all requests and returns
/// a pre-configured response without making real network calls.
final class MockURLProtocol: URLProtocol {

    /// Set this before each test: `(Data?, HTTPURLResponse?, Error?)`
    static var handler: ((URLRequest) throws -> (Data, HTTPURLResponse))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError:
                URLError(.unknown, userInfo: [NSLocalizedDescriptionKey: "No handler set"]))
            return
        }
        do {
            let (data, response) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: - Convenience helpers

extension MockURLProtocol {

    /// Returns a URLSession wired to use MockURLProtocol.
    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    /// Helper: build a 200-OK response carrying a JSON string body.
    static func respond(with jsonString: String, url: URL) -> (Data, HTTPURLResponse) {
        // Dexcom returns bare quoted strings, e.g. "\"someSessionId\""
        let body = "\"\(jsonString)\"".data(using: .utf8)!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (body, response)
    }

    /// Helper: build a 200-OK response carrying a raw data body.
    static func respond(with data: Data, url: URL, status: Int = 200) -> (Data, HTTPURLResponse) {
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (data, response)
    }
}
