//  GlucoseWebViewController.swift
//  DexBar

import Cocoa
import WebKit

class GlucoseWebViewController: NSViewController {

    // MARK: - Properties

    private var webView: WKWebView!
    private var overlayView: NSView!
    private var isLoaded = false
    private var pendingReading: DexcomReading?

    /// Set this to show or hide the "sign in" overlay over the chart.
    var isAuthenticated: Bool = false {
        didSet { updateOverlay() }
    }

    // MARK: - View lifecycle

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        // Match the chart's background colour so there's no bleed
        view.layer?.backgroundColor = NSColor(
            red: 9/255, green: 9/255, blue: 15/255, alpha: 1
        ).cgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupWebView()
        setupOverlay()
        loadHTML()
    }

    // MARK: - Setup

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        // Transparent background so our view's dark layer shows through
        webView.setValue(false, forKey: "drawsBackground")
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    private func setupOverlay() {
        overlayView = NSView()
        overlayView.wantsLayer = true
        overlayView.layer?.backgroundColor = NSColor(
            red: 9/255, green: 9/255, blue: 15/255, alpha: 0.97
        ).cgColor
        overlayView.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: "Sign in to see your glucose data")
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        let button = NSButton(title: "Open Preferences", target: self, action: #selector(openPreferencesAction))
        button.bezelStyle = .rounded
        button.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [label, button])
        stack.orientation = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        overlayView.addSubview(stack)
        view.addSubview(overlayView)

        NSLayoutConstraint.activate([
            overlayView.topAnchor.constraint(equalTo: view.topAnchor),
            overlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            overlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.centerXAnchor.constraint(equalTo: overlayView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: overlayView.centerYAnchor)
        ])

        updateOverlay()
    }

    private func loadHTML() {
        guard let url = Bundle.main.url(forResource: "bundle-native", withExtension: "html") else {
            dlog("[GlucoseWebVC] bundle-native.html not found in bundle")
            return
        }
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    private func updateOverlay() {
        overlayView?.isHidden = isAuthenticated
    }

    // MARK: - Public API

    /// Call this with the historical readings buffer before or after page load.
    /// Installs a WKUserScript so the chart boots with data, and also
    /// updates window.__INITIAL_DATA__ directly if the page is already loaded.
    func injectHistory(_ readings: [GraphDatum]) {
        let points = readings.map { r -> [String: Double] in
            ["time": r.timestamp.timeIntervalSince1970 * 1000, "value": r.value]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: points),
              let json = String(data: data, encoding: .utf8) else { return }

        // Replace any previously installed history script
        webView.configuration.userContentController.removeAllUserScripts()
        let script = WKUserScript(
            source: "window.__INITIAL_DATA__ = \(json);",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        webView.configuration.userContentController.addUserScript(script)

        if isLoaded {
            webView.evaluateJavaScript("window.__INITIAL_DATA__ = \(json);")
        }
    }

    /// Call this whenever a new live reading arrives.
    /// Queues the reading if the page hasn't finished loading yet.
    func pushReading(_ reading: DexcomReading) {
        let payload: [String: Any] = [
            "value":     reading.valueMmol,
            "trend":     GlucoseFormatter.normalisedTrend(reading.trend),
            "timestamp": reading.timestamp.timeIntervalSince1970 * 1000
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }

        if isLoaded {
            webView.evaluateJavaScript("window.updateReading(\(json));")
        } else {
            pendingReading = reading
        }
    }

    // MARK: - Actions

    @objc private func openPreferencesAction() {
        NSApp.sendAction(#selector(AppDelegate.openPreferences), to: nil, from: self)
    }
}

// MARK: - WKNavigationDelegate

extension GlucoseWebViewController: WKNavigationDelegate {

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoaded = true
        if let reading = pendingReading {
            pushReading(reading)
            pendingReading = nil
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        dlog("[GlucoseWebVC] Navigation failed:", error)
    }

    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        dlog("[GlucoseWebVC] Provisional navigation failed:", error)
    }
}
