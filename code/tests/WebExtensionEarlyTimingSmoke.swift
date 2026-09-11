import AppKit
import WebKit

@MainActor
final class WebExtensionEarlyTimingSmoke: NSObject, WKWebExtensionControllerDelegate,
    WKWebExtensionWindow, WKWebExtensionTab, WKNavigationDelegate {
    let extensionDirectory: URL
    let pageURL: URL
    var controller: WKWebExtensionController?
    var context: WKWebExtensionContext?
    var webView: WKWebView?
    var hostWindow: NSWindow?
    var exposesTab = false
    var probeAttempts = 0

    init(extensionDirectory: URL, pageURL: URL) {
        self.extensionDirectory = extensionDirectory
        self.pageURL = pageURL
    }

    func start() async throws {
        let extensionObject = try await WKWebExtension(resourceBaseURL: extensionDirectory)
        guard extensionObject.errors.isEmpty else {
            throw TimingSmokeError("Extension parse errors: \(extensionObject.errors.map(\.localizedDescription))")
        }

        let controller = WKWebExtensionController(configuration: .nonPersistent())
        self.controller = controller
        controller.delegate = self

        let context = WKWebExtensionContext(for: extensionObject)
        self.context = context
        context.hasAccessToPrivateData = true
        context.setPermissionStatus(.grantedExplicitly, for: .scripting)
        context.setPermissionStatus(.grantedExplicitly, for: .webNavigation)
        try controller.load(context)
        guard context.isLoaded else {
            throw TimingSmokeError("Extension context did not become loaded")
        }

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.webExtensionController = controller
        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600),
            configuration: configuration
        )
        self.webView = webView
        webView.navigationDelegate = self

        let hostWindow = NSWindow(
            contentRect: NSRect(x: -3000, y: -3000, width: 800, height: 600),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        hostWindow.contentView = webView
        hostWindow.orderFront(nil)
        self.hostWindow = hostWindow

        exposesTab = true
        controller.didOpenWindow(self)
        controller.didOpenTab(self)
        let localhost = try WKWebExtension.MatchPattern(string: "http://127.0.0.1/*")
        context.setPermissionStatus(.grantedExplicitly, for: localhost)
        guard context.hasInjectedContent(for: pageURL), context.hasAccess(to: pageURL, in: self) else {
            throw TimingSmokeError("Loaded context did not expose the localhost timing tab")
        }

        DispatchQueue.main.async {
            webView.load(URLRequest(url: self.pageURL))
            controller.didChangeTabProperties([.loading, .URL], for: self)
        }
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        openWindowsFor extensionContext: WKWebExtensionContext
    ) -> [any WKWebExtensionWindow] {
        exposesTab ? [self] : []
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        focusedWindowFor extensionContext: WKWebExtensionContext
    ) -> (any WKWebExtensionWindow)? {
        exposesTab ? self : nil
    }

    func tabs(for context: WKWebExtensionContext) -> [any WKWebExtensionTab] {
        exposesTab ? [self] : []
    }

    func activeTab(for context: WKWebExtensionContext) -> (any WKWebExtensionTab)? {
        exposesTab ? self : nil
    }

    func isPrivate(for context: WKWebExtensionContext) -> Bool { true }

    func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? { self }

    func webView(for context: WKWebExtensionContext) -> WKWebView? { webView }

    func url(for context: WKWebExtensionContext) -> URL? { webView?.url }

    func title(for context: WKWebExtensionContext) -> String? { webView?.title }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        controller?.didChangeTabProperties([.loading, .URL], for: self)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        controller?.didChangeTabProperties([.loading, .URL], for: self)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        controller?.didChangeTabProperties([.loading, .URL], for: self)
        probeWhenReady()
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        fail("Page provisional navigation failed: \(error)")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        fail("Page navigation failed: \(error)")
    }

    func probeWhenReady() {
        guard let webView else { fail("Missing WKWebView") }
        probeAttempts += 1
        let probe = """
        (() => JSON.stringify({
          pageURL: location.href,
          parserContent: document.getElementById('parser-content')?.textContent ?? null,
          manifestStart: globalThis.__timingManifestStart ?? null,
          parserSnapshot: globalThis.__timingParserSnapshot ?? null,
          lateSnapshot: globalThis.__timingLateSnapshot ?? null,
          backgroundReply: document.documentElement.dataset.timingBackgroundReply ?? null
        }))()
        """
        webView.evaluateJavaScript(probe) { value, error in
            guard error == nil, let text = value as? String, let result = self.decodeObject(text) else {
                self.fail("Probe evaluation failed: \(String(describing: error))")
            }
            if result["backgroundReply"] is NSNull, self.probeAttempts < 100 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.probeWhenReady() }
                return
            }
            self.check(result)
        }
    }

    func check(_ result: [String: Any]) {
        guard result["pageURL"] as? String == pageURL.absoluteString,
              result["parserContent"] as? String == "Parser content survived delayed injection",
              let manifest = result["manifestStart"] as? [String: Any],
              manifest["bodyExisted"] as? Bool == false,
              manifest["readyState"] as? String == "loading",
              let manifestTimestamp = (manifest["timestamp"] as? NSNumber)?.doubleValue,
              let early = result["parserSnapshot"] as? [String: Any],
              early["manifestStartSeen"] as? Bool == true,
              early["googleAdStatus"] as? String == "undefined",
              let earlyTimestamp = (early["timestamp"] as? NSNumber)?.doubleValue,
              earlyTimestamp >= manifestTimestamp,
              let late = result["lateSnapshot"] as? [String: Any],
              late["googleAdStatus"] as? Int == 1,
              let lateTimestamp = (late["timestamp"] as? NSNumber)?.doubleValue,
              lateTimestamp > earlyTimestamp,
              let replyText = result["backgroundReply"] as? String,
              let reply = decodeObject(replyText) else {
            fail("Timing snapshots were unexpected: \(result)")
        }
        if let error = reply["error"] as? String {
            fail("Delayed background operation failed: \(error)")
        }
        guard reply["modeledNativeDelayMs"] as? Int == 1500,
              let observedDelay = reply["observedDelayMs"] as? Int,
              observedDelay >= 1400,
              let senderDocumentId = reply["senderDocumentId"] as? String,
              !senderDocumentId.isEmpty,
              reply["frameDocumentId"] as? String == senderDocumentId,
              reply["injectionDocumentId"] as? String == senderDocumentId,
              let replyLate = reply["lateSnapshot"] as? [String: Any],
              replyLate["googleAdStatus"] as? Int == 1,
              let runtimeRevision = reply["runtimeRevision"] as? String,
              !runtimeRevision.isEmpty else {
            fail("Delayed document-bound injection result was unexpected: \(reply)")
        }

        print("PASS: manifest MAIN/document_start ran before the parser inline snapshot")
        print("REPRODUCED: modeled 1500 ms background delay (observed \(observedDelay) ms) left google_ad_status undefined for parser code, then set-constant changed it to 1")
        print("PASS: delayed runtime \(runtimeRevision) still targeted sender document \(senderDocumentId)")
        exit(0)
    }

    func decodeObject(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    func fail(_ message: String) -> Never {
        fputs("FAIL: \(message)\n", stderr)
        let errors = context?.errors.map(\.localizedDescription) ?? []
        if !errors.isEmpty { fputs("Extension context errors: \(errors)\n", stderr) }
        exit(1)
    }
}

struct TimingSmokeError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

guard CommandLine.arguments.count == 3 else {
    fputs("usage: WebExtensionEarlyTimingSmoke <extension-directory> <page-url>\n", stderr)
    exit(2)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
Task { @MainActor in
    let smoke = WebExtensionEarlyTimingSmoke(
        extensionDirectory: URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true),
        pageURL: URL(string: CommandLine.arguments[2])!
    )
    DispatchQueue.main.asyncAfter(deadline: .now() + 30) { smoke.fail("Timed out") }
    do {
        try await smoke.start()
    } catch {
        smoke.fail("Setup failed: \(error.localizedDescription)")
    }
}
app.run()
