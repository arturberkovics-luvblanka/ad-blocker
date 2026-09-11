#if os(macOS)
import AppKit
import SwiftUI
import SafariServices

// Safari owns the filtering. The host is used for setup, diagnostics and updates.
@MainActor
final class MacBackgroundApp: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var startup: Task<Void, Never>?
    private var model: MacOnboardingModel?
    private var window: NSWindow?
    private var reopening = false

    static func run() {
        let app = NSApplication.shared
        let delegate = MacBackgroundApp()
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        startup = Task { [weak self] in
            guard let self else { return }
            // A package update must run its new host, not an older process.
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
                do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            }
            guard previous.allSatisfy(\.isTerminated), !Task.isCancelled else {
                NSApplication.shared.terminate(nil)
                return
            }
            let model = MacOnboardingModel()
            self.model = model
            let automatic = CommandLine.arguments.contains("--setup")
            if automatic && model.previouslyCompleted && !reopening {
                // Repeated setup of this already-tested build stays quiet when
                // switches are still on. This does not prove current site access.
                await model.refresh()
                if model.readiness.canTest && model.verifiedThisBuild && !reopening && !Task.isCancelled {
                    NSApplication.shared.terminate(nil)
                    return
                }
            }
            showWindow()
            model.beginDiscovery()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        reopening = true
        if model != nil { showWindow() }
        return false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard window?.isVisible == true, let model else { return }
        Task { await model.refresh() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        startup?.cancel()
        model?.stop()
    }

    func windowWillClose(_ notification: Notification) {
        model?.stop()
        NSApplication.shared.terminate(nil)
    }

    private func showWindow() {
        guard let model else { return }
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 700),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = "Ad Blocker"
            window.contentMinSize = NSSize(width: 740, height: 620)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = NSHostingView(rootView: MacOnboardingView(model: model) { [weak self] in
                self?.window?.close()
            })
            window.center()
            self.window = window
            installMenu()
        }
        NSApplication.shared.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func installMenu() {
        let menu = NSMenu()
        let item = NSMenuItem()
        menu.addItem(item)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Ad Blocker bezárása", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = appMenu
        NSApplication.shared.mainMenu = menu
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
