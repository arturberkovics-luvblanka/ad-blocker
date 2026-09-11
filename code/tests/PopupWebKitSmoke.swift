import AppKit
import WebKit

// Verifies one pinned, site-specific popup rule against real WKWebView window.open behavior.
final class PopupWebKitSmoke: NSObject, WKNavigationDelegate, WKUIDelegate {
    enum Phase: String {
        case control
        case protected
    }

    let runtime: String
    var phase: Phase = .control
    var openedURLs: [String] = []
    var webView: WKWebView!

    init(runtime: String) {
        self.runtime = runtime
    }

    func loadCurrentPhase() {
        openedURLs = []

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        if phase == .protected {
            let installRule = runtime + """
            new AdBlockerAdvancedRuntime.ContentScript().applyConfiguration({
              css: [], extendedCss: [], js: [],
              scriptlets: [{name: 'prevent-window-open', args: ['bbelements.com']}],
              engineTimestamp: 1
            });
            """
            configuration.userContentController.addUserScript(WKUserScript(
                source: installRule,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true,
                in: WKContentWorld.world(name: "PopupRuntimeTest")
            ))
        }

        webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600),
            configuration: configuration
        )
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.loadHTMLString("""
        <!doctype html><html><body>
        <button id="advert" onclick="window.open('https://bbelements.com/ad', '_blank')">Advert</button>
        <button id="useful" onclick="window.open('https://example.com/useful', '_blank')">Useful link</button>
        <div id="content">Useful page content</div>
        </body></html>
        """, baseURL: URL(string: "https://sg.hu/"))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let triggerBothButtons = """
        (() => {
          document.getElementById('advert').click();
          document.getElementById('useful').click();
          return document.getElementById('content').textContent;
        })()
        """
        webView.evaluateJavaScript(triggerBothButtons) { value, error in
            guard error == nil, value as? String == "Useful page content" else {
                self.fail("Page action failed in \(self.phase.rawValue): \(String(describing: error))")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.checkCurrentPhase()
            }
        }
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url?.absoluteString {
            openedURLs.append(url)
        }
        return nil
    }

    func checkCurrentPhase() {
        let advertURL = "https://bbelements.com/ad"
        let usefulURL = "https://example.com/useful"

        switch phase {
        case .control:
            guard openedURLs == [advertURL, usefulURL] else {
                fail("Negative control did not attempt both windows: \(openedURLs)")
                return
            }
            print("PASS: negative control attempted advert and useful windows: \(openedURLs)")
            phase = .protected
            loadCurrentPhase()

        case .protected:
            guard openedURLs == [usefulURL] else {
                fail("Targeted rule result was unexpected: \(openedURLs)")
                return
            }
            print("PASS: sg.hu prevent-window-open blocked bbelements.com and forwarded the useful window request: \(openedURLs)")
            exit(0)
        }
    }

    func fail(_ message: String) {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

guard CommandLine.arguments.count == 2 else {
    fputs("usage: PopupWebKitSmoke <advanced-content-runtime.js>\n", stderr)
    exit(2)
}

_ = NSApplication.shared
let smoke = PopupWebKitSmoke(
    runtime: try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
)
smoke.loadCurrentPhase()
DispatchQueue.main.asyncAfter(deadline: .now() + 30) { smoke.fail("Timed out") }
RunLoop.main.run()
