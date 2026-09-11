#if os(macOS)
import AppKit
import SafariServices
import OSLog

// Safari owns the extensions. This host has no window and is only needed for
// discovery, the user's first setup, and activation of a new bundled rule list.
@MainActor
final class MacBackgroundApp: NSObject, NSApplicationDelegate {
    private static let logger = Logger(subsystem: "org.local.adblocker", category: "Setup")
    private var setupTask: Task<Void, Never>?
    private var needsSettings = true

    static func run() {
        let app = NSApplication.shared
        let delegate = MacBackgroundApp()
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupTask = Task {
            // Installer uses a new process so an older running build cannot
            // consume the launch request. Let that older host exit first.
            let instances = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
                .filter { $0.bundleURL == Bundle.main.bundleURL }
            let newest = instances.max {
                if $0.launchDate == $1.launchDate { return $0.processIdentifier < $1.processIdentifier }
                return ($0.launchDate ?? .distantPast) < ($1.launchDate ?? .distantPast)
            }
            guard newest?.processIdentifier == ProcessInfo.processInfo.processIdentifier else {
                NSApplication.shared.terminate(nil)
                return
            }
            let previous = instances.filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            for app in previous { app.terminate() }
            for _ in 0..<25 where previous.contains(where: { !$0.isTerminated }) {
                try? await Task.sleep(for: .milliseconds(200))
            }
            guard previous.allSatisfy(\.isTerminated) else {
                Self.logger.error("Previous host is still running; setup deferred until it exits.")
                NSApplication.shared.terminate(nil)
                return
            }
            await setup()
            NSApplication.shared.terminate(nil)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        needsSettings = true
        return false
    }

    private func record(_ phase: String, native: SafariSetupState, web: SafariSetupState) {
        let result: [String: Any] = [
            "phase": phase,
            "date": Date().timeIntervalSince1970,
            "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            "native": native.dictionary,
            "web": web.dictionary,
            "ownWindowCount": NSApplication.shared.windows.count,
        ]
        UserDefaults.standard.set(result, forKey: "lastBackgroundSetup")
        Self.logger.info("Setup: \(phase, privacy: .public)")
    }

    private func setup() async {
        guard let identifier = Bundle.main.bundleIdentifier,
              let plugins = Bundle.main.builtInPlugInsURL,
              ["AdBlockerContentBlocker.appex", "AdBlockerWebExtension.appex"].allSatisfy({
                  FileManager.default.fileExists(atPath: plugins.appendingPathComponent($0).path)
              }) else {
            Self.logger.error("The installed application is missing its bundled extensions.")
            return
        }
        let nativeID = identifier + ".ContentBlocker"
        let webID = identifier + ".WebExtension"

        // Launch Services discovers extensions when the containing app starts.
        // Give that asynchronous discovery a bounded opportunity to finish.
        var native = await SafariSetupState.native(nativeID)
        var web = await SafariSetupState.web(webID)
        for _ in 0..<2 where !native.known || !web.known {
            try? await Task.sleep(for: .seconds(1))
            native = await SafariSetupState.native(nativeID)
            web = await SafariSetupState.web(webID)
        }

        let deadline = ContinuousClock.now.advanced(by: .seconds(120))
        while !Task.isCancelled {
            if native.enabled {
                let outcome = await NativeRuleBundle.activate(enabled: true)
                switch outcome {
                case .current, .reloaded:
                    if web.enabled {
                        // Website permissions remain a separate Safari decision.
                        record("extensions-enabled-site-permissions-managed-by-safari", native: native, web: web)
                        return
                    }
                default:
                    record("native-rule-activation-not-confirmed", native: native, web: web)
                    return
                }
            }

            if needsSettings {
                needsSettings = false
                let target = !native.enabled ? nativeID : webID
                let error: String? = await safariRequest(timeout: .seconds(15)) { done in
                    SFSafariApplication.showPreferencesForExtension(withIdentifier: target) { error in
                        done(error?.localizedDescription ?? "")
                    }
                }
                if error != "" {
                    Self.logger.error("Safari settings could not select the extension: \(error ?? "timeout", privacy: .public)")
                }
            }

            if !native.known || !web.known {
                // Missing registration and an unsigned extension rejected by
                // Safari can produce the same API error. Never invent a cause
                // or change Safari's developer/security preferences here.
                record("extension-unavailable-check-signing-and-safari", native: native, web: web)
                return
            }
            record("waiting-for-user-in-safari", native: native, web: web)
            guard ContinuousClock.now < deadline else { return }
            try? await Task.sleep(for: .seconds(2))
            native = await SafariSetupState.native(nativeID)
            web = await SafariSetupState.web(webID)
        }
    }
}

struct SafariSetupState {
    let enabled: Bool
    let known: Bool
    let error: String?

    var dictionary: [String: Any] {
        ["enabled": enabled, "known": known, "error": error ?? ""]
    }

    static func native(_ identifier: String) async -> Self {
        let reply: (Bool?, String?)? = await safariRequest(timeout: .seconds(15)) { done in
            SFContentBlockerManager.getStateOfContentBlocker(withIdentifier: identifier) { state, error in
                done((state?.isEnabled, error?.localizedDescription))
            }
        }
        return state(reply)
    }

    static func web(_ identifier: String) async -> Self {
        let reply: (Bool?, String?)? = await safariRequest(timeout: .seconds(15)) { done in
            SFSafariExtensionManager.getStateOfSafariExtension(withIdentifier: identifier) { state, error in
                done((state?.isEnabled, error?.localizedDescription))
            }
        }
        return state(reply)
    }

    private static func state(_ reply: (Bool?, String?)?) -> Self {
        Self(enabled: reply?.0 == true && reply?.1 == nil,
             known: reply?.0 != nil && reply?.1 == nil,
             error: reply == nil ? "Safari state request timed out" : reply?.1)
    }
}
#endif
