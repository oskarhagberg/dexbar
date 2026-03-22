//
//  AppDelegate.swift
//  DexBar
//
//  Created by Oskar Hagberg on 2025-08-21.
//

import Cocoa
import SwiftUI
import Charts
import Security
import ServiceManagement

// MARK: - Keychain

struct KeychainHelper {
    private static let service = Bundle.main.bundleIdentifier ?? "com.oskarhagberg.DexBar"

    static func save(_ value: String, for key: String) {
        let data = Data(value.utf8)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData] = data
        SecItemAdd(item as CFDictionary, nil)
    }

    static func load(for key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(for key: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Dexcom Share API Models

struct DexcomReading: Decodable {
    let valueMmol: Double   // converted from mg/dL to mmol/L
    let trend: String
    let timestamp: Date

    enum CodingKeys: String, CodingKey {
        case value = "Value"
        case trend = "Trend"
        case wt = "WT"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let mgdl = try container.decode(Int.self, forKey: .value)
        valueMmol = (Double(mgdl) * 0.0555 * 10).rounded() / 10

        trend = try container.decode(String.self, forKey: .trend)

        // Parse "Date(1774107279261)" — milliseconds since Unix epoch
        let wt = try container.decode(String.self, forKey: .wt)
        let msString = wt
            .replacingOccurrences(of: "Date(", with: "")
            .replacingOccurrences(of: ")", with: "")
        let ms = Double(msString) ?? 0
        timestamp = Date(timeIntervalSince1970: ms / 1000.0)
    }
}

struct GraphDatum: Identifiable {
    let id = UUID()
    let value: Double
    let timestamp: Date
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var timer: Timer?
    var popover: NSPopover?
    var popoverHostingController: NSHostingController<PopoverContentView>?
    var graphData: [GraphDatum] = []
    var preferencesWindow: NSWindow?
    var isAuthenticated = false

    private let dexcom = DexcomClient()
    private var username: String { KeychainHelper.load(for: "username") ?? "" }
    private var password: String { KeychainHelper.load(for: "password") ?? "" }
    private var sessionId: String?


    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(handleStatusItemClick(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        if KeychainHelper.load(for: "username") != nil {
            setStatusTitle("…")
            startPolling()
        } else {
            setStatusTitle("🚫")
        }
    }

    func setStatusTitle(_ title: String, color: NSColor? = nil) {
        DispatchQueue.main.async {
            if let color {
                self.statusItem.button?.attributedTitle = NSAttributedString(string: title, attributes: [.foregroundColor: color])
            } else {
                self.statusItem.button?.attributedTitle = NSAttributedString(string: title)
            }
        }
    }

    var launchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @objc func handleStatusItemClick(_ sender: Any?) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            let launchTitle = launchAtLoginEnabled ? "✓ Launch at Login" : "Launch at Login"
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: "Preferences", action: #selector(openPreferences), keyEquivalent: ","))
            menu.addItem(.separator())
            menu.addItem(NSMenuItem(title: launchTitle, action: #selector(toggleLaunchAtLogin), keyEquivalent: ""))
            menu.addItem(.separator())
            menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            togglePopover(sender)
        }
    }

    @objc func toggleLaunchAtLogin() {
        do {
            if launchAtLoginEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            dlog("[LaunchAtLogin] Failed to toggle:", error)
        }
    }

    @objc func openPreferences() {
        if preferencesWindow == nil {
            let view = PreferencesView(
                onSignIn: { [weak self] username, password, completion in
                    self?.signIn(username: username, password: password, completion: completion)
                },
                onSignOut: { [weak self] in
                    self?.signOut()
                }
            )
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 360, height: 260),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Preferences"
            window.contentViewController = NSHostingController(rootView: view)
            window.isReleasedWhenClosed = false
            window.center()
            preferencesWindow = window
        }
        preferencesWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func startPolling() {
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            self.fetchData()
        }
        timer?.tolerance = 5
        fetchData()
    }

    /// Called from Preferences: saves credentials then verifies them end-to-end.
    func signIn(username: String, password: String, completion: @escaping (Bool, String?) -> Void) {
        KeychainHelper.save(username, for: "username")
        KeychainHelper.save(password, for: "password")
        sessionId = nil
        dexcom.authenticate(username: username, password: password) { [weak self] sid in
            guard let self, let sid else {
                self?.markUnauthenticated()
                completion(false, "Could not sign in. Check your username and password.")
                return
            }
            self.sessionId = sid
            self.dexcom.fetchReadings(sessionId: sid) { readings in
                if let readings, !readings.isEmpty {
                    self.updateUI(with: readings)
                    DispatchQueue.main.async {
                        if self.timer == nil { self.startPolling() }
                    }
                    completion(true, nil)
                } else {
                    self.markUnauthenticated()
                    completion(false, "Signed in but no glucose data was found.")
                }
            }
        }
    }

    func fetchData() {
        let doFetch = { [weak self] (sid: String) in
            self?.dexcom.fetchReadings(sessionId: sid) { readings in
                guard let readings = readings else {
                    // Decode failure likely means expired session — clear for next poll
                    self?.sessionId = nil
                    return
                }
                if !readings.isEmpty {
                    self?.updateUI(with: readings)
                }
            }
        }

        if let sid = sessionId {
            doFetch(sid)
        } else {
            dexcom.authenticate(username: username, password: password) { [weak self] sid in
                guard let sid = sid else {
                    dlog("Authentication failed")
                    self?.markUnauthenticated()
                    return
                }
                self?.sessionId = sid
                doFetch(sid)
            }
        }
    }

    func markUnauthenticated() {
        isAuthenticated = false
        setStatusTitle("🚫")
        updatePopoverContent()
    }

    func signOut() {
        timer?.invalidate()
        timer = nil
        sessionId = nil
        graphData = []
        KeychainHelper.delete(for: "username")
        KeychainHelper.delete(for: "password")
        markUnauthenticated()
    }

    func updateUI(with readings: [DexcomReading]) {
        guard let latest = readings.first else { return }

        isAuthenticated = true
        graphData = readings.reversed().map { GraphDatum(value: $0.valueMmol, timestamp: $0.timestamp) }

        let label = GlucoseFormatter.statusLabel(valueMmol: latest.valueMmol, trend: latest.trend)
        if GlucoseFormatter.isLow(latest.valueMmol) {
            setStatusTitle(label, color: .red)
        } else {
            setStatusTitle(label)
        }
        updatePopoverContent()
    }

    func updatePopoverContent() {
        DispatchQueue.main.async {
            self.popoverHostingController?.rootView = self.makePopoverView()
        }
    }

    func makePopoverView() -> PopoverContentView {
        PopoverContentView(
            isAuthenticated: isAuthenticated,
            data: graphData,
            onOpenPreferences: { [weak self] in self?.openPreferences() }
        )
    }

    @objc func togglePopover(_ sender: Any?) {
        if popover == nil {
            let hc = NSHostingController(rootView: makePopoverView())
            popoverHostingController = hc
            let p = NSPopover()
            p.behavior = .transient
            p.contentViewController = hc
            popover = p
        } else {
            popoverHostingController?.rootView = makePopoverView()
        }

        if let button = statusItem.button, let popover = popover {
            if popover.isShown {
                popover.performClose(sender)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
        }
    }

    struct PopoverContentView: View {
        let isAuthenticated: Bool
        let data: [GraphDatum]
        let onOpenPreferences: () -> Void

        var body: some View {
            ZStack(alignment: .topTrailing) {
                if isAuthenticated {
                    GlucoseChartView(data: data)
                } else {
                    VStack(spacing: 16) {
                        Text("Sign in with your (or dependent's) credentials")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                        Button("Open Preferences") {
                            onOpenPreferences()
                        }
                    }
                    .padding(32)
                    .frame(width: 300, height: 160)
                }

                Button(action: onOpenPreferences) {
                    Image(systemName: "gearshape")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(10)
            }
        }
    }

    struct GlucoseChartView: View {
        let data: [GraphDatum]
        @State private var selectedX: Date?
        @State private var hours: Double = 6

        var visibleData: [GraphDatum] {
            let cutoff = Date().addingTimeInterval(-hours * 3600)
            return data.filter { $0.timestamp >= cutoff }
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 0) {
                    ForEach([3.0, 6.0, 12.0, 24.0], id: \.self) { h in
                        Button("\(Int(h))h") { hours = h }
                            .buttonStyle(.plain)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 12)
                            .background(hours == h ? Color.primary.opacity(0.1) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .fontWeight(hours == h ? .semibold : .regular)
                    }
                }
                .padding(.horizontal, 4)

                Chart {
                    // Draw background range FIRST so it stays behind
                    RectangleMark(
                        xStart: .value("Time", domainX.lowerBound),
                        xEnd: .value("Time", domainX.upperBound),
                        yStart: .value("Range", 4),
                        yEnd: .value("Range", 8)
                    )
                    .foregroundStyle(Color.green.opacity(0.2))

                    // Then plot the data as a connected line with points
                    ForEach(visibleData) { point in
                        LineMark(
                            x: .value("Time", point.timestamp),
                            y: .value("Glucose", point.value)
                        )
                        .foregroundStyle(.black)

                        PointMark(
                            x: .value("Time", point.timestamp),
                            y: .value("Glucose", point.value)
                        )
                        .symbol(Circle().strokeBorder(lineWidth: 1))
                        .foregroundStyle(.black)
                        .symbolSize(20)
                    }

                    // Threshold rules
                    RuleMark(y: .value("Threshold", GlucoseFormatter.lowThreshold))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                        .foregroundStyle(.red)

                    RuleMark(y: .value("Threshold", 12))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                        .foregroundStyle(.red)

                    // Vertical cursor line — follows the drag position
                    if let sel = selectedX {
                        RuleMark(x: .value("Cursor", sel))
                            .lineStyle(StrokeStyle(lineWidth: 1))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .chartXAxisLabel("Time")
                .chartYAxisLabel("Glucose (mmol/L)")
                .chartXScale(domain: domainX)
                .frame(width: 420, height: 260)
                .chartXSelection(value: $selectedX)
                .chartOverlay { proxy in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    if let x: Date = proxy.value(atX: value.location.x) {
                                        selectedX = x
                                    }
                                }
                                .onEnded { _ in
                                    selectedX = nil
                                }
                        )
                }
                .overlay(alignment: .topLeading) {
                    if let sel = selectedX, let nearest = nearestPoint(to: sel) {
                        HoverReadout(point: nearest)
                            .padding(8)
                            .background(.regularMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .padding()
                    }
                }
            }
            .padding()
            .frame(minWidth: 440, minHeight: 300)
        }

        private var domainX: ClosedRange<Date> {
            let now = Date()
            return now.addingTimeInterval(-hours * 3600)...now
        }

        private func nearestPoint(to date: Date) -> GraphDatum? {
            guard !visibleData.isEmpty else { return nil }
            return visibleData.min(by: { abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date)) })
        }
    }

    private struct PreferencesView: View {
        let onSignIn: (String, String, @escaping (Bool, String?) -> Void) -> Void
        let onSignOut: () -> Void

        @State private var username: String = KeychainHelper.load(for: "username") ?? ""
        @State private var password: String = KeychainHelper.load(for: "password") ?? ""

        enum SignInStatus { case idle, loading, success, failure(String) }
        @State private var status: SignInStatus = .idle

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text("Dexcom Account")
                    .font(.headline)

                Text("Sign in with your (or dependent's) credentials, not the follower's or manager's")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 8) {
                    TextField("Username", text: $username)
                        .textFieldStyle(.roundedBorder)
                    SecureField("Password", text: $password)
                        .textFieldStyle(.roundedBorder)
                }

                HStack(spacing: 10) {
                    Button(action: performSignIn) {
                        if case .loading = status {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Sign In")
                        }
                    }
                    .disabled(username.isEmpty || password.isEmpty || { if case .loading = status { return true }; return false }())

                    Button("Sign Out") {
                        username = ""
                        password = ""
                        status = .idle
                        onSignOut()
                    }
                    .disabled({ if case .loading = status { return true }; return false }())

                    switch status {
                    case .idle:
                        EmptyView()
                    case .loading:
                        EmptyView()
                    case .success:
                        Label("Connected", systemImage: "circle.fill")
                            .foregroundStyle(.green)
                            .labelStyle(.titleAndIcon)
                    case .failure(let message):
                        Label(message, systemImage: "circle.fill")
                            .foregroundStyle(.red)
                            .labelStyle(.titleAndIcon)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }


                Divider()

                HStack {
                    Spacer()
                    Text("DexBar \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(24)
            .frame(width: 360)
        }

        private func performSignIn() {
            status = .loading
            onSignIn(username, password) { success, error in
                DispatchQueue.main.async {
                    status = success ? .success : .failure(error ?? "Unknown error")
                }
            }
        }
    }

    private struct HoverReadout: View {
        let point: GraphDatum
        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(point.value, specifier: "%.1f") mmol/L").bold()
                Text(point.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @objc func quit() {
        NSApplication.shared.terminate(self)
    }
}
