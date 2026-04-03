//  DisclaimerWindowController.swift
//  DexBar

import AppKit
import SwiftUI

final class DisclaimerWindowController: NSWindowController, NSWindowDelegate {

    // UserDefaults key that gates the disclaimer.
    // To reset for testing: defaults delete com.oskarhagberg.DexBar hasAcceptedDisclaimer
    static let acceptedKey = "hasAcceptedDisclaimer"

    // Retained for the lifetime of the dialog.
    private static var shared: DisclaimerWindowController?

    private var onProceed: (() -> Void)?

    // MARK: - Public API

    static func showIfNeeded(then proceed: @escaping () -> Void) {
        if UserDefaults.standard.bool(forKey: acceptedKey) {
            proceed()
            return
        }
        // NSWindow and NSHostingView must be created on the main thread.
        DispatchQueue.main.async {
            shared = DisclaimerWindowController(onProceed: proceed)
            shared?.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Init

    private init(onProceed: @escaping () -> Void) {
        self.onProceed = onProceed

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "DexBar — Before You Continue"
        window.isReleasedWhenClosed = false

        super.init(window: window)

        window.delegate = self

        let view = DisclaimerView(
            onAccept: { [weak self] in self?.accept() },
            onDecline: { NSApp.terminate(nil) }
        )
        let hosting = NSHostingView(rootView: view)
        window.contentView = hosting
        window.setContentSize(hosting.fittingSize)
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: - Testing support

    #if DEBUG
    /// Resets shared state between unit tests. Do not call from production code.
    static func _resetForTesting() {
        DispatchQueue.main.async {
            shared?.window?.close()
            shared = nil
        }
    }
    #endif

    // MARK: - Actions

    private func accept() {
        UserDefaults.standard.set(true, forKey: Self.acceptedKey)
        window?.close()
        let proceed = onProceed
        Self.shared = nil   // release the controller
        proceed?()
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Red ✕ button quits — same as declining.
        NSApp.terminate(nil)
        return false
    }
}
