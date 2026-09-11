import AppKit
import WebKit

@MainActor
final class SmokeTab: NSObject, WKWebExtensionTab {
    weak var owner: SmokeWindow?
    var pageWebView: WKWebView?

    func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        owner
    }

    func indexInWindow(for context: WKWebExtensionContext) -> Int {
        0
    }

    func webView(for context: WKWebExtensionContext) -> WKWebView? {
        pageWebView
    }

    func url(for context: WKWebExtensionContext) -> URL? {
        pageWebView?.url
    }

    func title(for context: WKWebExtensionContext) -> String? {
        pageWebView?.title
    }
}

@MainActor
final class SmokeWindow: NSObject, WKWebExtensionWindow {
    let tab: SmokeTab

    init(tab: SmokeTab) {
        self.tab = tab
    }

    func tabs(for context: WKWebExtensionContext) -> [any WKWebExtensionTab] {
        [tab]
    }

    func activeTab(for context: WKWebExtensionContext) -> (any WKWebExtensionTab)? {
        tab
    }

    func isPrivate(for context: WKWebExtensionContext) -> Bool {
        true
    }
}

@MainActor
final class WebExtensionIntegrationSmoke: NSObject, WKWebExtensionControllerDelegate, WKNavigationDelegate {
    let extensionDirectory: URL
    let pageURL: URL
    let tab = SmokeTab()
    lazy var window = SmokeWindow(tab: tab)
    var controller: WKWebExtensionController?
    var context: WKWebExtensionContext?
    var webView: WKWebView?
    var hostWindow: NSWindow?
    var exposesWindow = false
    var probeAttempts = 0

    init(extensionDirectory: URL, pageURL: URL) {
        self.extensionDirectory = extensionDirectory
        self.pageURL = pageURL
    }

    func start() async throws {
        let extensionObject = try await WKWebExtension(resourceBaseURL: extensionDirectory)
        guard extensionObject.errors.isEmpty else {
            let details = extensionObject.errors.map {
                let error = $0 as NSError
                return "\(error.domain)#\(error.code): \(error.localizedDescription); \(error.userInfo)"
            }
            throw SmokeError("Extension parse errors: \(details)")
        }

        let controller = WKWebExtensionController(configuration: .nonPersistent())
        self.controller = controller
        controller.delegate = self

        let context = WKWebExtensionContext(for: extensionObject)
        self.context = context
        context.hasAccessToPrivateData = true
        let localhost = try WKWebExtension.MatchPattern(string: "http://127.0.0.1/*")
        context.setPermissionStatus(.grantedExplicitly, for: .scripting)
        context.setPermissionStatus(.grantedExplicitly, for: .webNavigation)

        try controller.load(context)
        guard context.isLoaded else {
            throw SmokeError("Extension context did not become loaded")
        }

        let pageConfiguration = WKWebViewConfiguration()
        pageConfiguration.websiteDataStore = .nonPersistent()
        pageConfiguration.webExtensionController = controller
        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600),
            configuration: pageConfiguration
        )
        self.webView = webView
        tab.pageWebView = webView
        tab.owner = window
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

        exposesWindow = true
        controller.didOpenWindow(window)
        controller.didOpenTab(tab)
        context.setPermissionStatus(.grantedExplicitly, for: localhost)
        guard context.hasInjectedContent,
              context.hasInjectedContent(for: pageURL),
              context.hasAccess(to: pageURL, in: tab),
              context.openWindows.count == 1,
              context.openTabs.count == 1 else {
            throw SmokeError("Loaded context did not expose the localhost test tab")
        }
        DispatchQueue.main.async {
            webView.load(URLRequest(url: self.pageURL))
            controller.didChangeTabProperties([.loading, .URL], for: self.tab)
        }
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        openWindowsFor extensionContext: WKWebExtensionContext
    ) -> [any WKWebExtensionWindow] {
        return exposesWindow ? [window] : []
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        focusedWindowFor extensionContext: WKWebExtensionContext
    ) -> (any WKWebExtensionWindow)? {
        return exposesWindow ? window : nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        controller?.didChangeTabProperties([.loading, .URL], for: tab)
        probeWhenReady()
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        controller?.didChangeTabProperties([.loading, .URL], for: tab)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        controller?.didChangeTabProperties([.loading, .URL], for: tab)
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
        guard let webView else {
            fail("Missing WKWebView")
        }
        probeAttempts += 1
        let probe = """
        (() => {
          const snapshot = win => ({
            pageURL: win.location.href,
            windowName: win.name,
            parserContent: win.document.getElementById('parser-content')?.textContent ?? null,
            inlineScriptRan: win.__fixtureInlineScriptRan === true,
            isolatedReached: win.document.documentElement.dataset.documentIsolatedReached === 'true',
            daiAbsentNow: typeof win.google?.ima?.dai?.api?.StreamManager !== 'function',
            mainStart: win.__webExtensionMainStart ?? null,
            backgroundReply: win.document.documentElement.dataset.webExtensionReply ?? null
          });
          const httpChild = document.getElementById('child-frame')?.contentWindow;
          const blankChild = document.getElementById('blank-frame')?.contentWindow;
          const srcdocChild = document.getElementById('srcdoc-frame')?.contentWindow;
          return JSON.stringify({
            main: snapshot(window),
            httpChild: httpChild && httpChild.document.readyState === 'complete' ? snapshot(httpChild) : null,
            blankChild: blankChild && blankChild.document.readyState === 'complete' ? snapshot(blankChild) : null,
            srcdocChild: srcdocChild && srcdocChild.document.readyState === 'complete' ? snapshot(srcdocChild) : null
          });
        })()
        """
        webView.evaluateJavaScript(probe) { value, error in
            guard error == nil, let text = value as? String else {
                self.fail("Probe evaluation failed: \(String(describing: error))")
            }
            guard let result = self.decodeObject(text) else {
                self.fail("Probe returned invalid JSON: \(text)")
            }
            let documents = ["main", "httpChild", "blankChild", "srcdocChild"]
                .map { result[$0] as? [String: Any] }
            let waitingForReply = documents.contains { document in
                document == nil || document?["backgroundReply"] is NSNull
            }
            if waitingForReply, self.probeAttempts < 350 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.probeWhenReady()
                }
                return
            }
            self.check(result)
        }
    }

    func check(_ result: [String: Any]) {
        guard let main = result["main"] as? [String: Any],
              let httpChild = result["httpChild"] as? [String: Any],
              let blankChild = result["blankChild"] as? [String: Any],
              let srcdocChild = result["srcdocChild"] as? [String: Any] else {
            fail("One or more document snapshots were missing: \(result)")
        }
        let childURL = URL(string: "/child.html", relativeTo: pageURL)!.absoluteString
        let mainIdentity = checkDocument(
            main, expectedURL: pageURL.absoluteString, expectedContent: "Parser content survived",
            expectedWindowName: "", expectedParentFrameId: -1, requiresCommittedEvent: true,
            supportExpectation: true
        )
        let httpIdentity = checkDocument(
            httpChild, expectedURL: childURL, expectedContent: "Child parser content survived",
            expectedWindowName: "", expectedParentFrameId: 0, requiresCommittedEvent: true,
            supportExpectation: true
        )
        let blankIdentity = checkDocument(
            blankChild, expectedURL: "about:blank", expectedContent: nil,
            expectedWindowName: "useful-blank-frame", expectedParentFrameId: 0,
            requiresCommittedEvent: false, supportExpectation: nil
        )
        let srcdocIdentity = checkDocument(
            srcdocChild, expectedURL: "about:srcdoc", expectedContent: "Srcdoc parser content survived",
            expectedWindowName: "useful-srcdoc-frame", expectedParentFrameId: 0,
            requiresCommittedEvent: false, supportExpectation: nil
        )
        let identities = [mainIdentity, httpIdentity, blankIdentity, srcdocIdentity]
        guard mainIdentity.frameId == 0,
              identities.dropFirst().allSatisfy({ $0.frameId > 0 }),
              Set(identities.map(\.documentId)).count == identities.count,
              Set(identities.map(\.runtimeRevision)).count == 1 else {
            fail("Main/child identities were not distinct and consistent: \(result)")
        }

        print("PASS: manifest MAIN content scripts reached HTTP, about:blank, and about:srcdoc documents under strict CSP")
        print("PASS: HTTP documents accepted MAIN, ISOLATED, and DocumentBackgroundScript documentId injection without changing useful content")
        reportSpecialFrame(blankIdentity, label: "about:blank")
        reportSpecialFrame(srcdocIdentity, label: "about:srcdoc")
        exit(0)
    }

    func reportSpecialFrame(
        _ identity: (documentId: String, frameId: Int64, parentFrameId: Int64, runtimeRevision: String, frameURL: String, supported: Bool, error: String?),
        label: String
    ) {
        if identity.supported {
            print("PASS: \(label) accepted MAIN, ISOLATED, and DocumentBackgroundScript documentId injection")
        } else {
            print("CONFIRMED LIMITATION: sender.url=\(label), documentId=\(identity.documentId), frameId=\(identity.frameId), parentFrameId=\(identity.parentFrameId), getFrame.url='\(identity.frameURL)'; manifest injection and useful content survived, but MAIN/ISOLATED documentId injection failed and DAI stayed absent: \(identity.error ?? "unknown error")")
        }
    }

    func checkDocument(
        _ result: [String: Any],
        expectedURL: String,
        expectedContent: String?,
        expectedWindowName: String,
        expectedParentFrameId: Int64,
        requiresCommittedEvent: Bool,
        supportExpectation: Bool?
    ) -> (documentId: String, frameId: Int64, parentFrameId: Int64, runtimeRevision: String, frameURL: String, supported: Bool, error: String?) {
        guard result["pageURL"] as? String == expectedURL,
              result["windowName"] as? String == expectedWindowName,
              (result["parserContent"] as? String) == expectedContent,
              result["inlineScriptRan"] as? Bool == false,
              let mainStart = result["mainStart"] as? [String: Any],
              mainStart["bodyExisted"] as? Bool == false,
              mainStart["readyState"] as? String == "loading",
              mainStart["locationHref"] as? String == expectedURL,
              mainStart["windowName"] as? String == expectedWindowName,
              mainStart["daiAbsentBefore"] as? Bool == true,
              let events = mainStart["events"] as? [String],
              events.first == "manifest-main-document-start",
              events.contains("dom-content-loaded"),
              let replyText = result["backgroundReply"] as? String,
              let reply = decodeObject(replyText) else {
            fail("Manifest MAIN/document_start/CSP result was unexpected for \(expectedURL): \(result)")
        }

        if let error = reply["error"] as? String {
            fail("Extension background operation failed: \(error)")
        }
        guard let senderDocumentId = reply["senderDocumentId"] as? String,
              !senderDocumentId.isEmpty,
              let frameId = (reply["frameId"] as? NSNumber)?.int64Value,
              let parentFrameId = (reply["parentFrameId"] as? NSNumber)?.int64Value,
              parentFrameId == expectedParentFrameId,
              reply["senderUrl"] as? String == expectedURL,
              reply["frameDocumentId"] as? String == senderDocumentId,
              let frameURL = reply["frameUrl"] as? String,
              (frameURL == expectedURL || (!requiresCommittedEvent && frameURL.isEmpty)),
              (!requiresCommittedEvent
                  || (reply["committedDocumentId"] as? String == senderDocumentId
                      && reply["committedUrl"] as? String == expectedURL)),
              let runtimeRevision = reply["runtimeRevision"] as? String,
              !runtimeRevision.isEmpty,
              let isolated = reply["isolated"] as? [String: Any],
              let mainBefore = reply["mainBefore"] as? [String: Any],
              let mainAfter = reply["mainAfter"] as? [String: Any] else {
            fail("Document identity targeting result was unexpected for \(expectedURL): \(reply)")
        }

        let isolatedError = isolated["error"] as? String
        let mainBeforeError = mainBefore["error"] as? String
        let runtimeError = reply["runtimeError"] as? String
        let mainAfterError = mainAfter["error"] as? String
        let errors = [isolatedError, mainBeforeError, runtimeError, mainAfterError]
        let allSucceeded = errors.allSatisfy { $0 == nil }
        let allFailed = errors.allSatisfy { $0 != nil }
        guard isolated["documentId"] as? String == senderDocumentId,
              mainBefore["documentId"] as? String == senderDocumentId,
              mainAfter["documentId"] as? String == senderDocumentId,
              allSucceeded || allFailed else {
            fail("Programmatic injection paths disagreed for \(expectedURL): \(reply)")
        }
        if let supportExpectation, supportExpectation != allSucceeded {
            fail("Programmatic injection support changed unexpectedly for \(expectedURL): \(reply)")
        }

        if allSucceeded {
            guard result["isolatedReached"] as? Bool == true,
                  result["daiAbsentNow"] as? Bool == false,
                  mainStart["executeScriptRuns"] as? Int == 1,
                  events.contains("document-id-main-before-runtime"),
                  isolated["documentId"] as? String == senderDocumentId,
                  mainBefore["documentId"] as? String == senderDocumentId,
                  mainAfter["documentId"] as? String == senderDocumentId,
                  let isolatedResult = isolated["result"] as? [String: Any],
              isolatedResult["locationHref"] as? String == expectedURL,
              isolatedResult["windowName"] as? String == expectedWindowName,
              (isolatedResult["parserContent"] as? String) == expectedContent,
                  let beforeResult = mainBefore["result"] as? [String: Any],
                  beforeResult["stateMissing"] as? Bool == false,
                  beforeResult["daiAbsentBefore"] as? Bool == true,
                  beforeResult["locationHref"] as? String == expectedURL,
                  beforeResult["windowName"] as? String == expectedWindowName,
                  (beforeResult["parserContent"] as? String) == expectedContent,
                  let afterResult = mainAfter["result"] as? [String: Any],
                  afterResult["daiStreamManager"] as? Bool == true,
                  afterResult["daiInstanceWorks"] as? Bool == true,
                  afterResult["locationHref"] as? String == expectedURL,
                  afterResult["windowName"] as? String == expectedWindowName,
                  (afterResult["parserContent"] as? String) == expectedContent else {
                fail("Successful programmatic injection did not preserve expected state for \(expectedURL): \(reply)")
            }
        } else {
            guard [isolatedError, mainBeforeError, mainAfterError].allSatisfy({
                      $0?.contains("Extension does not have access to this frame") == true
                  }),
                  runtimeError?.contains("Script injection failed") == true,
                  result["isolatedReached"] as? Bool == false,
                  result["daiAbsentNow"] as? Bool == true,
                  mainStart["executeScriptRuns"] as? Int == 0,
                  !events.contains("document-id-main-before-runtime") else {
                fail("Failed programmatic injection still changed \(expectedURL): \(result)")
            }
        }
        return (senderDocumentId, frameId, parentFrameId, runtimeRevision, frameURL, allSucceeded, errors.compactMap { $0 }.joined(separator: " | "))
    }

    func decodeObject(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    func fail(_ message: String) -> Never {
        let runtimeErrors = context?.errors.map(\.localizedDescription) ?? []
        fputs("FAIL: \(message)\n", stderr)
        if !runtimeErrors.isEmpty {
            fputs("Extension context errors: \(runtimeErrors)\n", stderr)
        }
        exit(1)
    }
}

struct SmokeError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

guard CommandLine.arguments.count == 3 else {
    fputs("usage: WebExtensionIntegrationSmoke <extension-directory> <page-url>\n", stderr)
    exit(2)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
Task { @MainActor in
    let smoke = WebExtensionIntegrationSmoke(
        extensionDirectory: URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true),
        pageURL: URL(string: CommandLine.arguments[2])!
    )
    DispatchQueue.main.asyncAfter(deadline: .now() + 45) {
        smoke.fail("Timed out")
    }
    do {
        try await smoke.start()
    } catch {
        smoke.fail("Setup failed: \(error.localizedDescription)")
    }
}
app.run()
