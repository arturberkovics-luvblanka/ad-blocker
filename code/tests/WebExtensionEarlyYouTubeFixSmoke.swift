import AppKit
import WebKit

@MainActor
final class WebExtensionEarlyYouTubeFixSmoke: NSObject, WKWebExtensionControllerDelegate,
    WKWebExtensionWindow, WKWebExtensionTab, WKNavigationDelegate {
    let extensionDirectory: URL
    let pageURL = URL(string: "https://www.youtube.com/watch?v=static-fixture")!
    var controller: WKWebExtensionController?
    var context: WKWebExtensionContext?
    var webView: WKWebView?
    var hostWindow: NSWindow?
    var exposesTab = false
    var probeAttempts = 0

    init(extensionDirectory: URL) {
        self.extensionDirectory = extensionDirectory
    }

    func start() async throws {
        let extensionObject = try await WKWebExtension(resourceBaseURL: extensionDirectory)
        guard extensionObject.errors.isEmpty else {
            throw EarlyFixSmokeError("Extension parse errors: \(extensionObject.errors.map(\.localizedDescription))")
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
            throw EarlyFixSmokeError("Extension context did not become loaded")
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
        let youtube = try WKWebExtension.MatchPattern(string: "https://www.youtube.com/*")
        context.setPermissionStatus(.grantedExplicitly, for: youtube)
        guard context.hasInjectedContent(for: pageURL), context.hasAccess(to: pageURL, in: self) else {
            throw EarlyFixSmokeError("Loaded context did not expose the static YouTube test document")
        }

        let html = """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta http-equiv="Content-Security-Policy"
                content="default-src 'none'; script-src 'unsafe-inline'; style-src 'none'; frame-src 'none'; connect-src 'none'">
          <title>Static early YouTube fixture</title>
          <script>
            globalThis.ytInitialPlayerResponse = {
              adPlacements: ['parser-ad-placement'],
              adSlots: ['parser-ad-slot'],
              playerAds: ['parser-player-ad'],
              videoDetails: {videoId: 'parser-video'},
              streamingData: {formats: ['parser-format']}
            };
            globalThis.playerResponse = {
              adPlacements: ['parser-player-response-ad'],
              videoDetails: {videoId: 'parser-player-response-video'},
              streamingData: {serverAbrStreamingUrl: 'https://media.invalid/parser'}
            };
            globalThis.__earlyYoutubeDescriptors = {
              ytInitialPlayerResponse: Object.getOwnPropertyDescriptor(globalThis, 'ytInitialPlayerResponse'),
              playerResponse: Object.getOwnPropertyDescriptor(globalThis, 'playerResponse')
            };
            globalThis.__earlyYoutubeParserSnapshot = JSON.parse(JSON.stringify({
              ytInitialPlayerResponse: globalThis.ytInitialPlayerResponse,
              playerResponse: globalThis.playerResponse
            }));
          </script>
        </head>
        <body><main id="content">Useful parser content</main></body>
        </html>
        """
        DispatchQueue.main.async {
            webView.loadHTMLString(html, baseURL: self.pageURL)
            controller.didChangeTabProperties([.loading, .URL], for: self)
        }
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        openWindowsFor extensionContext: WKWebExtensionContext
    ) -> [any WKWebExtensionWindow] { exposesTab ? [self] : [] }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        focusedWindowFor extensionContext: WKWebExtensionContext
    ) -> (any WKWebExtensionWindow)? { exposesTab ? self : nil }

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
          usefulContent: document.getElementById('content')?.textContent ?? null,
          parserSnapshot: globalThis.__earlyYoutubeParserSnapshot ?? null,
          backgroundReply: document.documentElement.dataset.earlyYoutubeFixReply ?? null
        }))()
        """
        webView.evaluateJavaScript(probe) { value, error in
            guard error == nil, let text = value as? String, let result = self.decodeObject(text) else {
                self.fail("Probe evaluation failed: \(String(describing: error))")
            }
            if result["backgroundReply"] is NSNull {
                if self.probeAttempts < 250 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.probeWhenReady() }
                    return
                }
                self.fail("Delayed runtime reply did not arrive within the 25-second completion bound; early snapshot: \(result)")
            }
            self.check(result)
        }
    }

    func check(_ result: [String: Any]) {
        guard result["pageURL"] as? String == pageURL.absoluteString,
              result["usefulContent"] as? String == "Useful parser content",
              let parser = result["parserSnapshot"] as? [String: Any],
              protectedSnapshot(parser,
                  expectedYtVideo: "parser-video",
                  expectedYtFormat: "parser-format",
                  expectedPlayerVideo: "parser-player-response-video",
                  expectedPlayerStream: "https://media.invalid/parser"),
              let replyText = result["backgroundReply"] as? String,
              let reply = decodeObject(replyText) else {
            fail("Early parser snapshot was not protected: \(result)")
        }
        if let error = reply["error"] as? String {
            fail("Delayed runtime operation failed: \(error)")
        }
        guard reply["modeledNativeDelayMs"] as? Int == 1500,
              let observedDelay = reply["observedModeledDelayMs"] as? Int,
              observedDelay >= 1400,
              let totalBackgroundMs = reply["totalBackgroundMs"] as? Int,
              totalBackgroundMs >= observedDelay,
              let senderDocumentId = reply["senderDocumentId"] as? String,
              !senderDocumentId.isEmpty,
              reply["frameDocumentId"] as? String == senderDocumentId,
              reply["injectionDocumentId"] as? String == senderDocumentId,
              let lateResult = reply["lateResult"] as? [String: Any],
              lateResult["descriptorsStable"] as? Bool == true,
              let reassignment = lateResult["reassignmentSnapshot"] as? [String: Any],
              protectedSnapshot(reassignment,
                  expectedYtVideo: "late-video",
                  expectedYtFormat: "late-format",
                  expectedPlayerVideo: "late-player-response-video",
                  expectedPlayerStream: "https://media.invalid/late"),
              let runtimeRevision = reply["runtimeRevision"] as? String,
              !runtimeRevision.isEmpty else {
            fail("Delayed deduplication or reassignment result was unexpected: \(reply)")
        }

        print("PASS: unchanged early-youtube.js protected all four core ad fields before parser snapshots")
        print("PASS: videoDetails and streamingData survived early and post-delay object assignments")
        print("PASS: modeled 1500 ms delay observed \(observedDelay) ms; delayed runtime \(runtimeRevision) reused both top-level accessor descriptors for document \(senderDocumentId) (total background \(totalBackgroundMs) ms)")
        exit(0)
    }

    func protectedSnapshot(
        _ snapshot: [String: Any],
        expectedYtVideo: String,
        expectedYtFormat: String,
        expectedPlayerVideo: String,
        expectedPlayerStream: String
    ) -> Bool {
        guard let yt = snapshot["ytInitialPlayerResponse"] as? [String: Any],
              yt["adPlacements"] == nil,
              yt["adSlots"] == nil,
              yt["playerAds"] == nil,
              (yt["videoDetails"] as? [String: Any])?["videoId"] as? String == expectedYtVideo,
              ((yt["streamingData"] as? [String: Any])?["formats"] as? [String]) == [expectedYtFormat],
              let player = snapshot["playerResponse"] as? [String: Any],
              player["adPlacements"] == nil,
              (player["videoDetails"] as? [String: Any])?["videoId"] as? String == expectedPlayerVideo,
              (player["streamingData"] as? [String: Any])?["serverAbrStreamingUrl"] as? String == expectedPlayerStream else {
            return false
        }
        return true
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

struct EarlyFixSmokeError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

guard CommandLine.arguments.count == 2 else {
    fputs("usage: WebExtensionEarlyYouTubeFixSmoke <extension-directory>\n", stderr)
    exit(2)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
Task { @MainActor in
    let smoke = WebExtensionEarlyYouTubeFixSmoke(
        extensionDirectory: URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    )
    DispatchQueue.main.asyncAfter(deadline: .now() + 35) { smoke.fail("Timed out") }
    do {
        try await smoke.start()
    } catch {
        smoke.fail("Setup failed: \(error.localizedDescription)")
    }
}
app.run()
