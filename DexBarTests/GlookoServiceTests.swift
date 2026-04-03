// DexBarTests/GlookoServiceTests.swift
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
        // Timestamp must be Unix ms for 2026-04-02T15:45:42Z
        let date = Date(timeIntervalSince1970: ev.timestamp / 1000)
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents(in: TimeZone(identifier: "UTC")!, from: date)
        #expect(comps.hour == 15)
        #expect(comps.minute == 45)
        #expect(comps.second == 42)
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
}
