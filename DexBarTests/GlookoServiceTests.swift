//  GlookoServiceTests.swift
//  DexBarTests
import Foundation
import Testing
@testable import DexBar

@Suite("GlookoService")
struct GlookoServiceTests {

    // MARK: - extractSessionCookie

    @Test func extractsCookieFromSetCookieHeader() {
        let response = HTTPURLResponse(
            url: URL(string: "https://eu.api.glooko.com/api/v3/users/sign_in")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Set-Cookie": "_logbook-web_session=abc123tok; domain=glooko.com; path=/; secure; HttpOnly"]
        )!
        let cookie = GlookoService.extractSessionCookie(from: response)
        #expect(cookie == "_logbook-web_session=abc123tok")
    }

    @Test func returnsNilWhenCookieHeaderAbsent() {
        let response = HTTPURLResponse(
            url: URL(string: "https://eu.api.glooko.com/api/v3/users/sign_in")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: [:]
        )!
        #expect(GlookoService.extractSessionCookie(from: response) == nil)
    }

    @Test func returnsNilWhenSessionCookieKeyNotPresent() {
        let response = HTTPURLResponse(
            url: URL(string: "https://eu.api.glooko.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Set-Cookie": "other_cookie=xyz; path=/"]
        )!
        #expect(GlookoService.extractSessionCookie(from: response) == nil)
    }

    @Test func extractsCorrectCookieWhenMultipleCookiesPresent() {
        // HTTPURLResponse(headerFields:) joins multiple values for the same key with ",".
        // Real HTTP traffic uses "\n". Both are handled by sessionCookie(from:).
        let cookie = GlookoService.sessionCookie(
            from: "_logbook-web_session=tok456; path=/\nother_cookie=xyz; path=/"
        )
        #expect(cookie == "_logbook-web_session=tok456")
    }

    // MARK: - parsePumpEvents

    @Test func parsesValidBolus() throws {
        let json = """
        {
          "histories": [
            {
              "type": "pumps_normal_boluses",
              "softDeleted": false,
              "item": {
                "pumpTimestamp": "2026-04-02T15:45:42.000Z",
                "insulinDelivered": 3.5,
                "carbsInput": 45.0,
                "bloodGlucoseInput": 7600.0,
                "softDeleted": false
              }
            }
          ]
        }
        """.data(using: .utf8)!
        let events = GlookoService.parsePumpEvents(from: json)
        #expect(events.count == 1)
        let ev = try #require(events.first)
        #expect(abs(ev.units - 3.5) < 0.001)
        #expect(abs(ev.carbs - 45.0) < 0.001)
        #expect(abs(ev.bg - 7.6) < 0.001)
        // 2026-04-02T15:45:42.000Z = Unix epoch 1775144742 seconds
        #expect(ev.timestamp == 1775144742000)
    }

    @Test func filtersOutSoftDeletedOuter() {
        let json = """
        {
          "histories": [
            {
              "type": "pumps_normal_boluses",
              "softDeleted": true,
              "item": {
                "pumpTimestamp": "2026-04-02T10:00:00.000Z",
                "insulinDelivered": 2.0,
                "carbsInput": 30.0,
                "bloodGlucoseInput": 8000.0,
                "softDeleted": false
              }
            }
          ]
        }
        """.data(using: .utf8)!
        #expect(GlookoService.parsePumpEvents(from: json).isEmpty)
    }

    @Test func filtersOutSoftDeletedItem() {
        let json = """
        {
          "histories": [
            {
              "type": "pumps_normal_boluses",
              "softDeleted": false,
              "item": {
                "pumpTimestamp": "2026-04-02T10:00:00.000Z",
                "insulinDelivered": 2.0,
                "carbsInput": 30.0,
                "bloodGlucoseInput": 8000.0,
                "softDeleted": true
              }
            }
          ]
        }
        """.data(using: .utf8)!
        #expect(GlookoService.parsePumpEvents(from: json).isEmpty)
    }

    @Test func filtersOutZeroInsulin() {
        let json = """
        {
          "histories": [
            {
              "type": "pumps_normal_boluses",
              "softDeleted": false,
              "item": {
                "pumpTimestamp": "2026-04-02T10:00:00.000Z",
                "insulinDelivered": 0.0,
                "carbsInput": 20.0,
                "bloodGlucoseInput": 8000.0,
                "softDeleted": false
              }
            }
          ]
        }
        """.data(using: .utf8)!
        #expect(GlookoService.parsePumpEvents(from: json).isEmpty)
    }

    @Test func filtersOutNonBolusTypes() {
        let json = """
        {
          "histories": [
            { "type": "pumps_alarms",    "softDeleted": false, "item": {} },
            { "type": "pumps_alerts",    "softDeleted": false, "item": {} },
            { "type": "pumps_readings",  "softDeleted": false, "item": {} },
            { "type": "notes",           "softDeleted": false, "item": {} }
          ]
        }
        """.data(using: .utf8)!
        #expect(GlookoService.parsePumpEvents(from: json).isEmpty)
    }

    @Test func treatsNullBloodGlucoseAsZero() throws {
        let json = """
        {
          "histories": [
            {
              "type": "pumps_normal_boluses",
              "softDeleted": false,
              "item": {
                "pumpTimestamp": "2026-04-02T10:00:00.000Z",
                "insulinDelivered": 1.5,
                "carbsInput": 0.0,
                "bloodGlucoseInput": null,
                "softDeleted": false
              }
            }
          ]
        }
        """.data(using: .utf8)!
        let events = GlookoService.parsePumpEvents(from: json)
        let ev = try #require(events.first)
        #expect(ev.bg == 0.0)
    }

    @Test func resultsSortedAscendingByTimestamp() throws {
        let json = """
        {
          "histories": [
            {
              "type": "pumps_normal_boluses",
              "softDeleted": false,
              "item": {
                "pumpTimestamp": "2026-04-02T16:00:00.000Z",
                "insulinDelivered": 2.0,
                "carbsInput": 0.0,
                "bloodGlucoseInput": null,
                "softDeleted": false
              }
            },
            {
              "type": "pumps_normal_boluses",
              "softDeleted": false,
              "item": {
                "pumpTimestamp": "2026-04-02T10:00:00.000Z",
                "insulinDelivered": 3.0,
                "carbsInput": 40.0,
                "bloodGlucoseInput": 7600.0,
                "softDeleted": false
              }
            }
          ]
        }
        """.data(using: .utf8)!
        let events = GlookoService.parsePumpEvents(from: json)
        #expect(events.count == 2)
        #expect(events[0].timestamp < events[1].timestamp)
    }

    @Test func parsesTimestampWithoutFractionalSeconds() throws {
        let json = """
        {
          "histories": [
            {
              "type": "pumps_normal_boluses",
              "softDeleted": false,
              "item": {
                "pumpTimestamp": "2026-04-02T15:45:42Z",
                "insulinDelivered": 2.0,
                "carbsInput": 0.0,
                "bloodGlucoseInput": null,
                "softDeleted": false
              }
            }
          ]
        }
        """.data(using: .utf8)!
        let events = GlookoService.parsePumpEvents(from: json)
        #expect(events.count == 1)
        let ev = try #require(events.first)
        // 2026-04-02T15:45:42Z = 1775144742 seconds since epoch
        #expect(ev.timestamp == 1775144742000)
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
}
