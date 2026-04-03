//  DisclaimerWindowControllerTests.swift
//  DexBarTests

import Testing
import Foundation
@testable import DexBar

@Suite("DisclaimerWindowController", .serialized)
struct DisclaimerWindowControllerTests {

    // Cleanup helper — always remove the key so tests are isolated
    private func cleanUp() {
        UserDefaults.standard.removeObject(forKey: "hasAcceptedDisclaimer")
        DisclaimerWindowController._resetForTesting()
    }

    @Test func showIfNeeded_whenAlreadyAccepted_callsProceedSynchronously() {
        UserDefaults.standard.set(true, forKey: "hasAcceptedDisclaimer")
        defer { cleanUp() }

        var called = false
        DisclaimerWindowController.showIfNeeded { called = true }

        #expect(called == true)
    }

    @Test func showIfNeeded_whenNotYetAccepted_doesNotCallProceedImmediately() {
        cleanUp()   // ensure key is absent
        defer { cleanUp() }

        var called = false
        // showIfNeeded will try to create a window; in the test runner there is no
        // screen, so we rely only on observing that `proceed` is NOT called synchronously.
        // The window controller holds itself alive via `shared`; terminate is not called.
        DisclaimerWindowController.showIfNeeded { called = true }

        #expect(called == false)
    }
}
