//
//  AppDelegate.swift
//  DexBar
//
//  Created by Oskar Hagberg on 2025-08-21.
//

import Cocoa
import SwiftUI
import Security
import ServiceManagement

// MARK: - Keychain

struct KeychainHelper {
    private static let service = Bundle.main.bundleIdentifier ?? "com.oskarhagberg.DexBar"
    private static let credentialsAccount = "credentials"
    private static let glookoAccount = "glookoCredentials"

    static func saveCredentials(username: String, password: String) {
        guard let data = try? JSONEncoder().encode(["username": username, "password": password]) else { return }
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: credentialsAccount
        ]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData] = data
        SecItemAdd(item as CFDictionary, nil)
    }

    /// Returns (username, password), or nil if no credentials are stored.
    static func loadCredentials() -> (username: String, password: String)? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: credentialsAccount,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let dict = try? JSONDecoder().decode([String: String].self, from: data),
              let username = dict["username"],
              let password = dict["password"] else { return nil }
        return (username, password)
    }

    static func deleteCredentials() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: credentialsAccount
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func saveGlookoCredentials(email: String, password: String) {
        guard let data = try? JSONEncoder().encode(["email": email, "password": password]) else { return }
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: glookoAccount
        ]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData] = data
        SecItemAdd(item as CFDictionary, nil)
    }

    /// Returns (email, password), or nil if no Glooko credentials are stored.
    static func loadGlookoCredentials() -> (email: String, password: String)? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: glookoAccount,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let dict = try? JSONDecoder().decode([String: String].self, from: data),
              let email = dict["email"],
              let password = dict["password"] else { return nil }
        return (email, password)
    }

    static func deleteGlookoCredentials() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: glookoAccount
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
    var glucoseWebVC: GlucoseWebViewController?
    /// Feature flag: when true, appends "  74%" TIR suffix to the status bar title.
    var showTimeInRange: Bool = false
    var currentStats: GlucoseStats?
    var latestReading: DexcomReading?
    var graphData: [GraphDatum] = []
    var preferencesWindow: NSWindow?
    var isAuthenticated = false

    private let dexcom = DexcomClient()
    private var username: String = ""
    private var password: String = ""
    private var sessionId: String?
    private let glooko = GlookoService()
    private var glookoPumpEvents: [PumpEvent] = []
    private var glookoTimer: Timer?


    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(handleStatusItemClick(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        let vc = GlucoseWebViewController()
        glucoseWebVC = vc

        let p = NSPopover()
        p.behavior = .transient
        p.contentViewController = vc
        p.contentSize = CGSize(width: 640, height: 600)
        p.appearance = NSAppearance(named: .darkAqua)
        popover = p

        // Load credentials once at startup — single Keychain prompt.
        if let creds = KeychainHelper.loadCredentials() {
            username = creds.username
            password = creds.password
        }

        if !username.isEmpty {
            setStatusTitle("…")
            startPolling()
        } else {
            setStatusTitle("🚫")
        }

        // Load Glooko credentials and authenticate in background if present
        if let glookoCreds = KeychainHelper.loadGlookoCredentials() {
            glooko.authenticate(email: glookoCreds.email, password: glookoCreds.password) { [weak self] ok, _ in
                guard let self, ok else { return }
                self.fetchGlookoData()
                DispatchQueue.main.async { self.startGlookoPolling() }
            }
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

    func updateStatusBarTitle() {
        guard let reading = latestReading else { return }
        let label = GlucoseFormatter.statusLabel(valueMmol: reading.valueMmol, trend: reading.trend)
        let title: String
        if showTimeInRange, let tir = currentStats?.timeInRangePercent {
            title = "\(label)  \(tir)%"
        } else {
            title = label
        }
        if GlucoseFormatter.isLow(reading.valueMmol) {
            setStatusTitle(title, color: .red)
        } else {
            setStatusTitle(title)
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
                },
                onSaveThresholds: { [weak self] thresholds in
                    guard let self else { return }
                    GlucoseThresholdsStore.current = thresholds
                    // Recompute stats for all windows and push update to the web chart
                    let allStats = allWindowStats(from: self.graphData, thresholds: thresholds)
                    self.currentStats = allStats["24h"]
                    self.updateStatusBarTitle()
                    if let latest = self.latestReading {
                        self.glucoseWebVC?.pushReading(latest, stats: allStats, thresholds: thresholds, pumpEvents: self.glookoPumpEvents)
                    }
                },
                onGlookoSignIn: { [weak self] email, password, completion in
                    self?.glookoSignIn(email: email, password: password, completion: completion)
                },
                onGlookoSignOut: { [weak self] in
                    self?.glookoSignOut()
                }
            )
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 360, height: 360),
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
        self.username = username
        self.password = password
        KeychainHelper.saveCredentials(username: username, password: password)
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
        DispatchQueue.main.async {
            self.isAuthenticated = false
            self.setStatusTitle("🚫")
            self.glucoseWebVC?.isAuthenticated = false
        }
    }

    func signOut() {
        timer?.invalidate()
        timer = nil
        sessionId = nil
        username = ""
        password = ""
        graphData = []
        KeychainHelper.deleteCredentials()
        markUnauthenticated()
    }

    func startGlookoPolling() {
        glookoTimer = Timer.scheduledTimer(withTimeInterval: 5 * 60, repeats: true) { _ in
            self.fetchGlookoData()
        }
        glookoTimer?.tolerance = 60
    }

    func fetchGlookoData() {
        let now = Date()
        let start = now.addingTimeInterval(-24 * 3600)
        glooko.fetchPumpEvents(from: start, to: now) { [weak self] events in
            guard let self, let events else { return }
            DispatchQueue.main.async {
                self.glookoPumpEvents = events
                guard let latest = self.latestReading else { return }
                let t = GlucoseThresholdsStore.current
                let allStats = allWindowStats(from: self.graphData, thresholds: t)
                self.glucoseWebVC?.pushReading(latest, stats: allStats, thresholds: t, pumpEvents: events)
            }
        }
    }

    func glookoSignIn(email: String, password: String, completion: @escaping (Bool, String?) -> Void) {
        KeychainHelper.saveGlookoCredentials(email: email, password: password)
        glooko.authenticate(email: email, password: password) { [weak self] ok, error in
            guard let self else { return }
            if ok {
                self.fetchGlookoData()
                DispatchQueue.main.async {
                    if self.glookoTimer == nil { self.startGlookoPolling() }
                }
            }
            completion(ok, error)
        }
    }

    func glookoSignOut() {
        glookoTimer?.invalidate()
        glookoTimer = nil
        glooko.clearSession()
        KeychainHelper.deleteGlookoCredentials()
        glookoPumpEvents = []
        // Push empty events to clear chart dots
        guard let latest = latestReading else { return }
        let t = GlucoseThresholdsStore.current
        let allStats = allWindowStats(from: graphData, thresholds: t)
        glucoseWebVC?.pushReading(latest, stats: allStats, thresholds: t, pumpEvents: [])
    }

    func updateUI(with readings: [DexcomReading]) {
        guard let latest = readings.first else { return }
        DispatchQueue.main.async {
            self.isAuthenticated = true
            self.latestReading = latest
            self.graphData = readings.reversed().map { GraphDatum(value: $0.valueMmol, timestamp: $0.timestamp) }

            let t = GlucoseThresholdsStore.current
            let allStats = allWindowStats(from: self.graphData, thresholds: t)
            self.currentStats = allStats["24h"]

            self.glucoseWebVC?.isAuthenticated = true
            self.glucoseWebVC?.injectHistory(self.graphData, stats: allStats, thresholds: t, pumpEvents: self.glookoPumpEvents)
            self.glucoseWebVC?.pushReading(latest, stats: allStats, thresholds: t, pumpEvents: self.glookoPumpEvents)

            self.updateStatusBarTitle()
        }
    }

    @objc func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button, let popover = popover else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            // Refresh history on every open so the chart is up to date
            if !graphData.isEmpty {
                let t = GlucoseThresholdsStore.current
                glucoseWebVC?.injectHistory(graphData, stats: allWindowStats(from: graphData, thresholds: t), thresholds: t, pumpEvents: glookoPumpEvents)
            }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private struct PreferencesView: View {
        let onSignIn: (String, String, @escaping (Bool, String?) -> Void) -> Void
        let onSignOut: () -> Void
        let onSaveThresholds: (GlucoseThresholds) -> Void
        let onGlookoSignIn: (String, String, @escaping (Bool, String?) -> Void) -> Void
        let onGlookoSignOut: () -> Void

        @State private var username: String
        @State private var password: String
        @State private var lowText: String = String(format: "%.1f", GlucoseThresholdsStore.current.low)
        @State private var highText: String = String(format: "%.1f", GlucoseThresholdsStore.current.high)
        @State private var thresholdError: String? = nil

        enum SignInStatus { case idle, loading, success, failure(String) }
        @State private var status: SignInStatus = .idle
        @State private var glookoEmail: String
        @State private var glookoPassword: String
        enum GlookoStatus { case idle, loading, success, failure(String) }
        @State private var glookoStatus: GlookoStatus = .idle

        init(
            onSignIn: @escaping (String, String, @escaping (Bool, String?) -> Void) -> Void,
            onSignOut: @escaping () -> Void,
            onSaveThresholds: @escaping (GlucoseThresholds) -> Void,
            onGlookoSignIn: @escaping (String, String, @escaping (Bool, String?) -> Void) -> Void,
            onGlookoSignOut: @escaping () -> Void
        ) {
            self.onSignIn = onSignIn
            self.onSignOut = onSignOut
            self.onSaveThresholds = onSaveThresholds
            self.onGlookoSignIn = onGlookoSignIn
            self.onGlookoSignOut = onGlookoSignOut
            let creds = KeychainHelper.loadCredentials()
            _username = State(initialValue: creds?.username ?? "")
            _password = State(initialValue: creds?.password ?? "")
            let glooko = KeychainHelper.loadGlookoCredentials()
            _glookoEmail = State(initialValue: glooko?.email ?? "")
            _glookoPassword = State(initialValue: glooko?.password ?? "")
        }

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

                Text("Glooko Account")
                    .font(.headline)

                Text("Sign in with your Glooko patient account to display insulin bolus events on the chart")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 8) {
                    TextField("Email", text: $glookoEmail)
                        .textFieldStyle(.roundedBorder)
                    SecureField("Password", text: $glookoPassword)
                        .textFieldStyle(.roundedBorder)
                }

                HStack(spacing: 10) {
                    Button(action: performGlookoSignIn) {
                        if case .loading = glookoStatus {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Sign In")
                        }
                    }
                    .disabled(glookoEmail.isEmpty || glookoPassword.isEmpty || { if case .loading = glookoStatus { return true }; return false }())

                    Button("Sign Out") {
                        glookoEmail = ""
                        glookoPassword = ""
                        glookoStatus = .idle
                        onGlookoSignOut()
                    }
                    .disabled({ if case .loading = glookoStatus { return true }; return false }())

                    switch glookoStatus {
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

                VStack(alignment: .leading, spacing: 8) {
                    Text("Target Range (mmol/L)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        TextField("Low", text: $lowText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                        Text("Low")
                            .foregroundStyle(.secondary)
                        TextField("High", text: $highText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                        Text("High")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Save") { saveThresholds() }
                    }

                    if let error = thresholdError {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
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

        private func saveThresholds() {
            guard let low = Double(lowText), let high = Double(highText) else {
                thresholdError = "Enter valid numbers for low and high."
                return
            }
            guard low >= 2.0, low <= 6.0 else {
                thresholdError = "Low must be between 2.0 and 6.0 mmol/L."
                return
            }
            guard high >= 8.0, high <= 15.0 else {
                thresholdError = "High must be between 8.0 and 15.0 mmol/L."
                return
            }
            guard low < high else {
                thresholdError = "Low must be less than high."
                return
            }
            thresholdError = nil
            onSaveThresholds(GlucoseThresholds(low: low, high: high))
        }

        private func performSignIn() {
            status = .loading
            onSignIn(username, password) { success, error in
                DispatchQueue.main.async {
                    status = success ? .success : .failure(error ?? "Unknown error")
                }
            }
        }

        private func performGlookoSignIn() {
            glookoStatus = .loading
            onGlookoSignIn(glookoEmail, glookoPassword) { success, error in
                DispatchQueue.main.async {
                    glookoStatus = success ? .success : .failure(error ?? "Unknown error")
                }
            }
        }
    }

    @objc func quit() {
        NSApplication.shared.terminate(self)
    }
}

// MARK: - Stats helpers

private func allWindowStats(from readings: [GraphDatum], thresholds: GlucoseThresholds) -> [String: GlucoseStats] {
    let windows: [(key: String, hours: Double, label: String)] = [
        ("3h",  3,  "3H"),
        ("6h",  6,  "6H"),
        ("12h", 12, "12H"),
        ("24h", 24, "24H"),
    ]
    var result: [String: GlucoseStats] = [:]
    for w in windows {
        if let stats = glucoseStats(from: readings, hours: w.hours, thresholds: thresholds, rangeLabel: w.label) {
            result[w.key] = stats
        }
    }
    return result
}
