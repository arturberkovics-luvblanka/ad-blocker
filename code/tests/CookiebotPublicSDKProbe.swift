import AppKit
import Foundation
import WebKit

final class CookiebotPublicSDKProbe: NSObject, WKNavigationDelegate {
    private enum Phase {
        case initialNavigation
        case initialReadback
        case submittedReadback
        case reloadNavigation
        case reloadReadback
        case finished
    }

    private let targetURL = URL(string: "https://www.cookiebot.com/en/")!
    private var webView: WKWebView!
    private var phase: Phase = .initialNavigation
    private var initialReadyEvents = 0
    private var initialDeclineEvents = 0
    private var pollDeadline = Date()
    private var finished = false
    private var loggedInitialMarker = false

    func start() {
        let controller = WKUserContentController()
        controller.addUserScript(WKUserScript(
            source: Self.earlyEventProbe,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
            in: .page
        ))

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController = controller

        webView = WKWebView(
            frame: NSRect(x: -3000, y: -3000, width: 1024, height: 768),
            configuration: configuration
        )
        webView.navigationDelegate = self

        DispatchQueue.main.asyncAfter(deadline: .now() + 75) { [weak self] in
            guard let self, !self.finished else { return }
            self.fail("global timeout after 75 seconds")
        }

        print("INFO: loading Cookiebot public site in a nonPersistent WKWebView")
        webView.load(URLRequest(
            url: targetURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 30
        ))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        switch phase {
        case .initialNavigation:
            phase = .initialReadback
            beginPolling(seconds: 20)
        case .reloadNavigation:
            phase = .reloadReadback
            beginPolling(seconds: 20)
        case .initialReadback, .submittedReadback, .reloadReadback, .finished:
            break
        }
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        fail("TLS/network navigation failed without bypass: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        fail("page navigation failed: \(error.localizedDescription)")
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        fail("web content process terminated")
    }

    private func beginPolling(seconds: TimeInterval) {
        pollDeadline = Date().addingTimeInterval(seconds)
        poll()
    }

    private func poll() {
        guard !finished else { return }
        webView.evaluateJavaScript(Self.snapshotScript) { value, error in
            if let error {
                self.retryOrFail("snapshot evaluation failed: \(error.localizedDescription)")
                return
            }
            guard let text = value as? String,
                  let data = text.data(using: .utf8),
                  let snapshot = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                self.retryOrFail("snapshot returned invalid JSON")
                return
            }
            self.handle(snapshot)
        }
    }

    private func handle(_ snapshot: [String: Any]) {
        switch phase {
        case .initialReadback:
            if !loggedInitialMarker,
               let marker = snapshot["marker"] as? [String: Any],
               integer(marker, "count") > 0 {
                loggedInitialMarker = true
                print("INFO: detected marker \(sanitizedMarker(snapshot))")
            }
            rejectKnownUnsupportedConfiguration(snapshot)
            guard isReady(snapshot) else {
                retryOrFail("Cookiebot did not become ready", snapshot: snapshot)
                return
            }
            validateSupportedConfiguration(snapshot)
            print("INFO: initial marker \(sanitizedMarker(snapshot))")
            print("INFO: initial state \(sanitizedState(snapshot))")
            initialReadyEvents = integer(snapshot, "readyEvents")
            initialDeclineEvents = integer(snapshot, "declineEvents")
            submitDecline()

        case .submittedReadback:
            validateSupportedConfiguration(snapshot)
            let observedSubmissionEvent = integer(snapshot, "readyEvents") > initialReadyEvents
                || integer(snapshot, "declineEvents") > initialDeclineEvents
            guard observedSubmissionEvent, isRejectedState(snapshot) else {
                retryOrFail("submitted state was not observable", snapshot: snapshot)
                return
            }
            guard integer(snapshot, "submitCalls") == 1 else {
                fail("submitCustomConsent was not called exactly once")
            }
            print("PASS: submitCustomConsent(false,false,false) produced a documented decline state")
            print("INFO: submitted state \(sanitizedState(snapshot))")
            phase = .reloadNavigation
            webView.reload()

        case .reloadReadback:
            rejectKnownUnsupportedConfiguration(snapshot)
            guard isReady(snapshot) else {
                retryOrFail("Cookiebot did not become ready after reload", snapshot: snapshot)
                return
            }
            validateSupportedConfiguration(snapshot)
            guard isRejectedState(snapshot) else {
                fail("decline state did not persist across the probe reload; state=\(sanitizedState(snapshot))")
            }
            guard integer(snapshot, "submitCalls") == 0 else {
                fail("reload document unexpectedly submitted consent again")
            }
            print("PASS: normalized decline state persisted after a same-session reload")
            print("INFO: reload state \(sanitizedState(snapshot))")
            finish(code: 0)

        case .initialNavigation, .reloadNavigation, .finished:
            fail("received a snapshot in an invalid phase")
        }
    }

    private func validateSupportedConfiguration(_ snapshot: [String: Any]) {
        rejectKnownUnsupportedConfiguration(snapshot)
        guard let marker = snapshot["marker"] as? [String: Any] else {
            unsupported("Cookiebot script marker was unavailable")
        }
        guard integer(marker, "count") == 1,
              marker["source"] as? String == "https://consent.cookiebot.com/uc.js",
              marker["cbidShapeValid"] as? Bool == true else {
            unsupported("public page did not expose one exact official Cookiebot marker")
        }
        if let framework = marker["framework"] as? String, !framework.isEmpty {
            unsupported("Cookiebot data-framework is set (\(framework)); category-only probe stopped")
        }
        guard let conflictingMarkers = snapshot["conflictingMarkers"] as? [String],
              conflictingMarkers.isEmpty else {
            unsupported("IAB/GPP or another CMP marker is present: \(snapshot["conflictingMarkers"] ?? [])")
        }
        guard snapshot["apiPresent"] as? Bool == true,
              snapshot["submitPresent"] as? Bool == true else {
            unsupported("documented Cookiebot public API was unavailable")
        }
    }

    private func rejectKnownUnsupportedConfiguration(_ snapshot: [String: Any]) {
        guard snapshot["officialPage"] as? Bool == true else {
            unsupported("navigation left the exact HTTPS Cookiebot public host")
        }
        guard let marker = snapshot["marker"] as? [String: Any] else { return }
        let count = integer(marker, "count")
        if count > 1 {
            unsupported("multiple Cookiebot script markers were present")
        }
        if count == 1 {
            if marker["source"] as? String != "https://consent.cookiebot.com/uc.js" {
                unsupported("Cookiebot marker used an unrecognized script source")
            }
            if marker["cbidShapeValid"] as? Bool != true {
                unsupported("Cookiebot marker had no recognized domain-group ID shape")
            }
            if let framework = marker["framework"] as? String, !framework.isEmpty {
                unsupported("Cookiebot data-framework is set (\(framework)); category-only probe stopped")
            }
        }
        if let conflictingMarkers = snapshot["conflictingMarkers"] as? [String],
           !conflictingMarkers.isEmpty {
            unsupported("IAB/GPP or another CMP marker is present: \(conflictingMarkers)")
        }
    }

    private func submitDecline() {
        phase = .submittedReadback
        pollDeadline = Date().addingTimeInterval(20)
        let script = """
        (() => {
          const probe = window.__cookiebotPublicProbe;
          if (location.protocol !== 'https:' || location.hostname !== 'www.cookiebot.com') return 'wrong-location';
          if (!probe || probe.submitCalls !== 0) return 'duplicate';
          if (typeof window.Cookiebot?.submitCustomConsent !== 'function') return 'missing';
          probe.submitCalls += 1;
          window.Cookiebot.submitCustomConsent(false, false, false);
          return 'submitted';
        })()
        """
        webView.evaluateJavaScript(script) { value, error in
            guard error == nil, value as? String == "submitted" else {
                self.fail("submitCustomConsent call failed: \(error?.localizedDescription ?? String(describing: value))")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.poll() }
        }
    }

    private func isReady(_ snapshot: [String: Any]) -> Bool {
        integer(snapshot, "readyEvents") > 0
            && snapshot["apiPresent"] as? Bool == true
            && snapshot["state"] is [String: Any]
    }

    private func isRejectedState(_ snapshot: [String: Any]) -> Bool {
        guard let state = snapshot["state"] as? [String: Any] else { return false }
        return state["necessary"] as? Bool == true
            && state["preferences"] as? Bool == false
            && state["statistics"] as? Bool == false
            && state["marketing"] as? Bool == false
            && state["hasResponse"] as? Bool == true
            && state["declined"] as? Bool == true
            && state["method"] as? String == "explicit"
    }

    private func retryOrFail(_ reason: String, snapshot: [String: Any]? = nil) {
        guard Date() < pollDeadline else {
            if let snapshot {
                print("INFO: timeout marker \(sanitizedMarker(snapshot))")
                print("INFO: timeout API present=\(snapshot["apiPresent"] ?? false), submitPresent=\(snapshot["submitPresent"] ?? false)")
                print("INFO: timeout events ready=\(integer(snapshot, "readyEvents")), decline=\(integer(snapshot, "declineEvents")), accept=\(integer(snapshot, "acceptEvents"))")
                print("INFO: timeout state \(sanitizedState(snapshot))")
            }
            fail("\(reason) before bounded timeout")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.poll() }
    }

    private func integer(_ object: [String: Any], _ key: String) -> Int {
        (object[key] as? NSNumber)?.intValue ?? -1
    }

    private func sanitizedMarker(_ snapshot: [String: Any]) -> String {
        guard let marker = snapshot["marker"] as? [String: Any] else { return "missing" }
        let source = marker["source"] as? String ?? "missing"
        let framework = marker["framework"] as? String ?? "none"
        let validID = marker["cbidShapeValid"] as? Bool ?? false
        return "source=\(source), framework=\(framework), cbidShapeValid=\(validID)"
    }

    private func sanitizedState(_ snapshot: [String: Any]) -> String {
        guard let state = snapshot["state"] as? [String: Any],
              let data = try? JSONSerialization.data(withJSONObject: state, options: [.sortedKeys]) else {
            return "unavailable"
        }
        return String(decoding: data, as: UTF8.self)
    }

    private func unsupported(_ reason: String) -> Never {
        print("UNSUPPORTED: \(reason)")
        finish(code: 2)
    }

    private func fail(_ reason: String) -> Never {
        fputs("FAIL: \(reason)\n", stderr)
        finish(code: 1)
    }

    private func finish(code: Int32) -> Never {
        finished = true
        phase = .finished
        fflush(stdout)
        fflush(stderr)
        exit(code)
    }

    private static let earlyEventProbe = """
    (() => {
      window.__cookiebotPublicProbe = {
        readyEvents: 0,
        declineEvents: 0,
        acceptEvents: 0,
        submitCalls: 0
      };
      window.addEventListener('CookiebotOnConsentReady', () => {
        window.__cookiebotPublicProbe.readyEvents += 1;
      });
      window.addEventListener('CookiebotOnDecline', () => {
        window.__cookiebotPublicProbe.declineEvents += 1;
      });
      window.addEventListener('CookiebotOnAccept', () => {
        window.__cookiebotPublicProbe.acceptEvents += 1;
      });
    })();
    """

    private static let snapshotScript = """
    (() => {
      const probe = window.__cookiebotPublicProbe || {};
      const markers = [...document.querySelectorAll('script#Cookiebot')];
      const marker = markers.length === 1 ? markers[0] : null;
      let source = null;
      let cbid = null;
      if (marker) {
        try {
          const url = new URL(marker.src, location.href);
          source = `${url.protocol}//${url.host}${url.pathname}`;
          cbid = marker.dataset.cbid || url.searchParams.get('cbid');
        } catch (_) {}
      }
      const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
      const conflictingMarkers = [];
      if (typeof window.__tcfapi === 'function' || document.querySelector('iframe[name="__tcfapiLocator"]')) conflictingMarkers.push('IAB-TCF');
      if (typeof window.__gpp === 'function' || document.querySelector('iframe[name="__gppLocator"]')) conflictingMarkers.push('IAB-GPP');
      if (typeof window.__uspapi === 'function' || document.querySelector('iframe[name="__uspapiLocator"]')) conflictingMarkers.push('IAB-USP');
      if (window.OneTrust || document.querySelector('#onetrust-consent-sdk,script[src*="cookielaw.org/scripttemplates/"]')) conflictingMarkers.push('OneTrust');
      if (window.Didomi || document.querySelector('script[src*="sdk.privacy-center.org"],script[src*="sdk.didomi.io"]')) conflictingMarkers.push('Didomi');
      if (window.UC_UI || document.querySelector('script[src*="usercentrics.eu"],script[src*="usercentrics.com"]')) conflictingMarkers.push('Usercentrics');
      const api = window.Cookiebot;
      const consent = api?.consent;
      const bool = value => typeof value === 'boolean' ? value : null;
      const method = consent?.method === null || consent?.method === 'explicit' || consent?.method === 'implied'
        ? consent.method : 'unknown';
      return JSON.stringify({
        officialPage: location.protocol === 'https:' && location.hostname === 'www.cookiebot.com',
        marker: {
          count: markers.length,
          source,
          framework: marker?.getAttribute('data-framework') || '',
          cbidShapeValid: typeof cbid === 'string' && uuid.test(cbid)
        },
        conflictingMarkers,
        apiPresent: typeof api === 'object' && api !== null,
        submitPresent: typeof api?.submitCustomConsent === 'function',
        readyEvents: Number.isSafeInteger(probe.readyEvents) ? probe.readyEvents : -1,
        declineEvents: Number.isSafeInteger(probe.declineEvents) ? probe.declineEvents : -1,
        acceptEvents: Number.isSafeInteger(probe.acceptEvents) ? probe.acceptEvents : -1,
        submitCalls: Number.isSafeInteger(probe.submitCalls) ? probe.submitCalls : -1,
        state: consent ? {
          necessary: bool(consent.necessary),
          preferences: bool(consent.preferences),
          statistics: bool(consent.statistics),
          marketing: bool(consent.marketing),
          method,
          consented: bool(api.consented),
          declined: bool(api.declined),
          hasResponse: bool(api.hasResponse)
        } : null
      });
    })()
    """
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let probe = CookiebotPublicSDKProbe()
probe.start()
RunLoop.main.run()
