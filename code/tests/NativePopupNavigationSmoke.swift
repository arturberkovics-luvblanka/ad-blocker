import AppKit
import WebKit

// Uses only the shared local fixture server. Unlike navigation-policy probes,
// this retains target=_blank web views and reads their loaded document markers.
final class NativePopupNavigationSmoke: NSObject, WKNavigationDelegate, WKUIDelegate {
    enum Phase: CaseIterable { case off, popupOnly, documentAndPopup, exception }

    private let store = WKContentRuleListStore(url: URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true))!
    private var popupOnlyRules: WKContentRuleList!
    private var documentRules: WKContentRuleList!
    private var phase = Phase.off
    private var mainWebView: WKWebView!
    private var popups: [WKWebView] = []
    private var popupMarkers: [String] = []
    private var popupFailures: [String] = []
    private var popupURLs: [ObjectIdentifier: String] = [:]
    private var expectedPopupURLs: Set<String> = []
    private var terminalPopupURLs: Set<String> = []

    private let targetURL = "http://127.0.0.1:8765/native-popup-target.html"
    private let exceptionURL = "http://127.0.0.1:8765/native-popup-exception.html"

    func start() {
        let targetFilter = #"^http://127\.0\.0\.1:8765/native-popup-target\.html$"#
        let exceptionFilter = #"^http://127\.0\.0\.1:8765/native-popup-exception\.html$"#
        let popupOnly = [[
            "trigger": ["url-filter": targetFilter, "resource-type": ["popup"]],
            "action": ["type": "block"],
        ]]
        let documentAndPopup = [
            ["trigger": ["url-filter": targetFilter, "resource-type": ["document", "popup"]], "action": ["type": "block"]],
            ["trigger": ["url-filter": exceptionFilter, "resource-type": ["document", "popup"]], "action": ["type": "block"]],
            [
                "trigger": ["url-filter": exceptionFilter, "if-domain": ["127.0.0.1"]],
                "action": ["type": "ignore-previous-rules"],
            ],
        ]
        compile(identifier: "NativePopupOnly", rules: popupOnly) { self.popupOnlyRules = $0
            self.compile(identifier: "NativePopupDocument", rules: documentAndPopup) { self.documentRules = $0
                self.loadPhase()
            }
        }
    }

    private func compile(identifier: String, rules: [[String: Any]], completion: @escaping (WKContentRuleList) -> Void) {
        do {
            let json = try String(decoding: JSONSerialization.data(withJSONObject: rules), as: UTF8.self)
            store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: json) { list, error in
                guard let list else { self.fail("\(identifier) compilation: \(error?.localizedDescription ?? "unknown error")") }
                completion(list)
            }
        } catch { fail(error.localizedDescription) }
    }

    private func loadPhase() {
        popupMarkers = []
        popupFailures = []
        popups = []
        popupURLs = [:]
        expectedPopupURLs = []
        terminalPopupURLs = []
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        if phase == .popupOnly { configuration.userContentController.add(popupOnlyRules) }
        if phase == .documentAndPopup || phase == .exception { configuration.userContentController.add(documentRules) }
        mainWebView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        mainWebView.navigationDelegate = self
        mainWebView.uiDelegate = self
        mainWebView.load(URLRequest(url: URL(string: "http://127.0.0.1:8765/native-popup-navigation.html")!))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === mainWebView else {
            let url = popupURLs[ObjectIdentifier(webView)]
            webView.evaluateJavaScript("document.documentElement.dataset.popupTarget || ''") { value, _ in
                if let marker = value as? String, !marker.isEmpty { self.popupMarkers.append(marker) }
                if let url { self.completePopup(url) }
            }
            return
        }
        let exception = phase == .exception
        expectedPopupURLs = exception ? [targetURL, exceptionURL] : [targetURL]
        let script = """
        (() => {
          const frame = document.getElementById('document-frame');
          frame.src = '\(exception ? exceptionURL : targetURL)';
          document.getElementById('useful').click();
          document.getElementById('target-link').click();
        })()
        """
        webView.evaluateJavaScript(script) { _, error in
            guard error == nil else { self.fail("Fixture action: \(error!.localizedDescription)") }
            if exception {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    webView.evaluateJavaScript("document.getElementById('exception-link').click()") { _, error in
                        guard error == nil else { self.fail("Exception link: \(error!.localizedDescription)") }
                        self.waitForPopupTerminals()
                    }
                }
            } else {
                self.waitForPopupTerminals()
            }
        }
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        let popup = WKWebView(frame: NSRect(x: 0, y: 0, width: 600, height: 400), configuration: configuration)
        popup.navigationDelegate = self
        popup.uiDelegate = self
        popups.append(popup)
        if let url = navigationAction.request.url?.absoluteString {
            popupURLs[ObjectIdentifier(popup)] = url
        }
        return popup
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard webView !== mainWebView, let url = popupURLs[ObjectIdentifier(webView)] else { return }
        let details = error as NSError
        // Observed WebKit content-blocker error; unrelated network failures
        // must not count as successful protection.
        guard details.domain == "WebKitErrorDomain", details.code == 104 else {
            fail("Unexpected navigation error: \(details.domain) \(details.code) \(details.localizedDescription)")
        }
        popupFailures.append("url=\(url) domain=\(details.domain) code=\(details.code) description=\(details.localizedDescription)")
        completePopup(url)
    }

    private func completePopup(_ url: String) {
        guard expectedPopupURLs.contains(url), terminalPopupURLs.insert(url).inserted else { return }
        if terminalPopupURLs.isSuperset(of: expectedPopupURLs) {
            checkPhase()
        }
    }

    private func waitForPopupTerminals() {
        let waitingPhase = phase
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            guard self.phase == waitingPhase else { return }
            guard !self.terminalPopupURLs.isSuperset(of: self.expectedPopupURLs) else { return }
            self.fail("Timed out awaiting popup terminal event: expected=\(self.expectedPopupURLs), terminal=\(self.terminalPopupURLs)")
        }
    }

    private func checkPhase(attempt: Int = 0) {
        let frameScript = """
        JSON.stringify({
          useful: document.getElementById('useful').textContent === '1',
          frame: document.getElementById('document-frame').contentDocument?.documentElement.dataset.popupTarget || ''
        })
        """
        mainWebView.evaluateJavaScript(frameScript) { value, error in
            guard error == nil, let text = value as? String,
                  let data = text.data(using: .utf8),
                  let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  result["useful"] as? Bool == true else {
                self.fail("Useful-page check: \(String(describing: error))")
            }
            let frame = result["frame"] as? String ?? ""
            let expectedMarker = self.phase == .exception ? "exception" : "target"
            if self.phase != .documentAndPopup, frame != expectedMarker, attempt < 20 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.checkPhase(attempt: attempt + 1) }
                return
            }
            switch self.phase {
            case .off, .popupOnly:
                guard frame == "target", self.popupMarkers.contains("target") else {
                    self.fail("Expected real target loads in \(self.phase): frame=\(frame), popups=\(self.popupMarkers)")
                }
                print("PASS: \(self.phase) loaded target=_blank and iframe documents while useful page stayed interactive")
            case .documentAndPopup:
                guard frame.isEmpty, !self.popupMarkers.contains("target"),
                      self.popupFailures.contains(where: { $0.contains("url=\(self.targetURL) ") }) else {
                    self.fail("Document fallback did not block actual target documents: frame=\(frame), popups=\(self.popupMarkers)")
                }
                print("PASS: document fallback popup navigation error: \(self.popupFailures.joined(separator: " | "))")
                print("OBSERVED: iframe had no target marker when the popup blocker error arrived")
            case .exception:
                guard frame == expectedMarker, self.popupMarkers.contains(expectedMarker),
                      !self.popupMarkers.contains("target"),
                      self.popupFailures.contains(where: { $0.contains("url=\(self.targetURL) ") }) else {
                    self.fail("ignore-previous-rules did not preserve only its exception: frame=\(frame), popups=\(self.popupMarkers), failures=\(self.popupFailures)")
                }
                print("PASS: ignore-previous-rules restored only the exception target=_blank and iframe documents")
            }
            if let next = Phase.allCases.drop(while: { $0 != self.phase }).dropFirst().first {
                self.phase = next
                self.loadPhase()
            } else {
                exit(0)
            }
        }
    }

    func fail(_ message: String) -> Never {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: NativePopupNavigationSmoke temporary-rule-store\n", stderr)
    exit(2)
}
_ = NSApplication.shared
let test = NativePopupNavigationSmoke()
test.start()
DispatchQueue.main.asyncAfter(deadline: .now() + 60) { test.fail("Timed out") }
RunLoop.main.run()
