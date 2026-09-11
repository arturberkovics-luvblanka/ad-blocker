import AppKit
import WebKit

// Real WebKit semantics for the bundled runtime, not Safari extension permissions.
final class AdvancedSmoke: NSObject, WKNavigationDelegate {
    var webView: WKWebView!
    var strictCSP = false
    let runtime: String
    let expectedRevision: String

    init(runtime: String, expectedRevision: String) {
        self.runtime = runtime
        self.expectedRevision = expectedRevision
    }

    func load() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let script = runtime + """
        document.documentElement.dataset.runtimeRevision = AdBlockerAdvancedRuntime.revision;
        new AdBlockerAdvancedRuntime.ContentScript().applyConfiguration({
          css: ['.plain-ad'], extendedCss: ['.advanced-ad:contains(Sponsored)'], js: [],
          scriptlets: [
            {name: 'set-constant', args: ['google_ad_status', '1']},
            {name: 'json-prune', args: ['playerResponse.adPlacements playerResponse.adSlots', 'playerResponse.streamingData.serverAbrStreamingUrl']},
            {name: 'google-ima3-dai', args: []}
          ], engineTimestamp: 1
        });
        """
        configuration.userContentController.addUserScript(WKUserScript(
            source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true,
            in: WKContentWorld.world(name: "AdBlockerRuntimeTest")
        ))
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        webView.navigationDelegate = self
        let csp = strictCSP ? "<meta http-equiv=\"Content-Security-Policy\" content=\"script-src 'none'; style-src 'unsafe-inline'\">" : ""
        webView.loadHTMLString("""
        <!doctype html><html><head>\(csp)</head><body>
        <div class="plain-ad">Advertisement</div>
        <div class="advanced-ad">Sponsored</div>
        <div id="content">Useful content</div>
        </body></html>
        """, baseURL: URL(string: "https://www.youtube.com/"))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let probe = """
        (() => {
          const parsed = JSON.parse('{"playerResponse":{"adPlacements":[1],"adSlots":[2],"streamingData":{"serverAbrStreamingUrl":"https://example.invalid/media"},"videoDetails":{"videoId":"test"}}}');
          const StreamManager = window.google?.ima?.dai?.api?.StreamManager;
          const streamManager = typeof StreamManager === 'function'
            ? new StreamManager(document.createElement('video'), document.createElement('div')) : null;
          return JSON.stringify({
            runtimeRevision: document.documentElement.dataset.runtimeRevision === '\(expectedRevision)',
            daiInitialized: !!streamManager && streamManager.contentTimeForStreamTime(37) === 37,
            constant: window.google_ad_status === 1,
            adsPruned: !('adPlacements' in parsed.playerResponse) && !('adSlots' in parsed.playerResponse),
            contentPreserved: parsed.playerResponse.videoDetails.videoId === 'test' && parsed.playerResponse.streamingData.serverAbrStreamingUrl === 'https://example.invalid/media',
            cssHidden: getComputedStyle(document.querySelector('.plain-ad')).display === 'none',
            extendedHidden: getComputedStyle(document.querySelector('.advanced-ad')).display === 'none',
            usefulVisible: getComputedStyle(document.getElementById('content')).display !== 'none'
          });
        })()
        """
        webView.evaluateJavaScript(probe) { value, error in
            guard error == nil, let text = value as? String, let data = text.data(using: .utf8),
                  let result = try? JSONSerialization.jsonObject(with: data) as? [String: Bool] else {
                self.fail("Probe failed: \(String(describing: error))"); return
            }
            guard result["contentPreserved"] == true, result["cssHidden"] == true,
                  result["runtimeRevision"] == true,
                  result["daiInitialized"] == !self.strictCSP,
                  result["extendedHidden"] == true, result["usefulVisible"] == true,
                  result["constant"] == !self.strictCSP, result["adsPruned"] == !self.strictCSP else {
                self.fail("Unexpected strictCSP=\(self.strictCSP): \(text)"); return
            }
            print("PASS: real isolated-world content runtime, strictCSP=\(self.strictCSP): \(text)")
            if self.strictCSP {
                print("CONFIRMED LIMITATION: content-script fallback cannot apply these scriptlets under script-src 'none'; requires the Safari MAIN scripting path.")
                exit(0)
            }
            self.strictCSP = true
            self.load()
        }
    }

    func fail(_ message: String) {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

guard CommandLine.arguments.count == 3 else { exit(2) }
_ = NSApplication.shared
let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))) as! [String: Any]
guard let revision = manifest["runtimeRevision"] as? String,
      revision.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { exit(2) }
let test = AdvancedSmoke(
    runtime: try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8),
    expectedRevision: revision
)
test.load()
DispatchQueue.main.asyncAfter(deadline: .now() + 30) { test.fail("Timed out") }
RunLoop.main.run()
