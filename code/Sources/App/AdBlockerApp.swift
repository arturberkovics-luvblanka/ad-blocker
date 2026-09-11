import SwiftUI
import SafariServices

@main
enum AdBlockerMain {
    @MainActor static func main() {
        #if os(macOS)
        if CommandLine.arguments.contains("--diagnose") {
            _ = NSApplication.shared
            Task {
                let success = await runSafariDiagnostics(reload: CommandLine.arguments.contains("--reload"))
                exit(success ? 0 : 1)
            }
            RunLoop.main.run()
            return
        }
        #endif
        AdBlockerApp.main()
    }
}

struct AdBlockerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                #if os(macOS)
                .frame(minWidth: 420, idealWidth: 520, minHeight: 580, idealHeight: 660)
                #endif
        }
    }
}

@MainActor
final class ProtectionStatus: ObservableObject {
    @Published var nativeStatus = "Ellenőrzés…"
    @Published var webStatus = "Ellenőrzés…"
    @Published var nativeEnabled = false
    @Published var webEnabled = false
    @Published var busy = false
    @Published var message: String?
    @Published var notice: String?
    @Published var nativeKnown = false
    @Published var webKnown = false
    @Published var reloading = false
    @Published var nativeRulesAcknowledged = false

    private var baseID: String { Bundle.main.bundleIdentifier! }
    var blockerID: String { baseID + ".ContentBlocker" }
    var extensionID: String { baseID + ".WebExtension" }

    nonisolated private static func describe(_ error: Error?) -> String? {
        guard let error = error as NSError? else { return nil }
        if error.domain == SFErrorDomain && error.code == 1 {
            return "A Safari még nem ismeri fel. Ellenőrizd a telepítést és a helyi tesztbővítmények engedélyezését."
        }
        return error.localizedDescription
    }

    func refresh() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        let native: (Bool?, String?)? = await safariRequest(timeout: .seconds(15)) { completion in
            SFContentBlockerManager.getStateOfContentBlocker(withIdentifier: blockerID) { state, error in
                completion((state?.isEnabled, Self.describe(error)))
            }
        }
        let (enabled, error) = native ?? (nil, "A Safari állapotlekérdezése túllépte a 15 másodpercet.")
        nativeKnown = enabled != nil && error == nil
        nativeEnabled = enabled == true
        nativeStatus = error.map { "Nem ellenőrizhető: \($0)" }
            ?? (nativeEnabled ? "Bekapcsolva a Safariban" : "Nincs bekapcsolva")
        #if os(macOS)
        let webReply: (Bool?, String?)? = await safariRequest(timeout: .seconds(15)) { completion in
            SFSafariExtensionManager.getStateOfSafariExtension(withIdentifier: extensionID) { state, error in
                completion((state?.isEnabled, Self.describe(error)))
            }
        }
        let (web, webError) = webReply ?? (nil, "A Safari állapotlekérdezése túllépte a 15 másodpercet.")
        webKnown = web != nil && webError == nil
        webEnabled = web == true
        webStatus = webError.map { "Nem ellenőrizhető: \($0)" }
            ?? (webEnabled ? "Bekapcsolva; az oldalengedély külön ellenőrizendő" : "Nincs bekapcsolva")
        #else
        webStatus = "Az állapot a Safari bővítménymenüjében ellenőrizhető"
        #endif
        if nativeKnown && nativeEnabled {
            await applyBundledRules(force: false)
        } else {
            nativeRulesAcknowledged = false
        }
    }

    func reload() async {
        guard !busy, nativeEnabled else { return }
        busy = true
        await applyBundledRules(force: true)
        busy = false
        await refresh()
    }

    private func applyBundledRules(force: Bool) async {
        reloading = force || NativeRuleBundle.acknowledgedGeneration != NativeRuleBundle.generation
        defer { reloading = false }
        let outcome = await NativeRuleBundle.activate(enabled: nativeEnabled, force: force)
        if outcome == .current {
            nativeRulesAcknowledged = true
            return
        }
        message = nil
        notice = nil
        nativeRulesAcknowledged = outcome == .reloaded
        switch outcome {
        case .current:
            break
        case .reloaded:
            notice = "Szabályok betöltve."
            message = "A Safari visszaigazolta a csomagolt szabályok betöltését. A már nyitott weboldalakat frissítsd."
        case .disabled:
            break
        case .timedOut:
            notice = "A Safari nem igazolta vissza a betöltést."
            message = "A Safari 60 másodpercen belül nem igazolta vissza a szabálybetöltést. A művelet eredménye ismeretlen; a Safari még dolgozhat. Ellenőrizd a tesztoldalt, mielőtt újra próbálod."
        case .failed(let error):
            notice = "A szabályok betöltése sikertelen."
            message = "A szabálybetöltés sikertelen: \(error)"
        }
        if nativeEnabled && !nativeRulesAcknowledged {
            nativeStatus = "Bekapcsolva; az új lista betöltése nincs visszaigazolva"
        }
    }

    func openSettings(forBlocker: Bool = false) {
        #if os(macOS)
        SFSafariApplication.showPreferencesForExtension(withIdentifier: forBlocker ? blockerID : extensionID) { error in
            if let error {
                Task { @MainActor in self.notice = "A Safari beállításai nem nyíltak meg."; self.message = error.localizedDescription }
            }
        }
        #else
        notice = "Beállítások → Appok → Safari → Bővítmények"
        message = "Beállítások → Appok → Safari → Bővítmények: engedélyezd az Ad Blocker két bővítményét."
        #endif
    }

    func openTest() {
        #if os(macOS)
        guard let safari = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari") else {
            notice = "Nem található a Safari."
            message = notice
            return
        }
        NSWorkspace.shared.open([URL(string: "http://127.0.0.1:8765/")!],
            withApplicationAt: safari, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                if let error {
                    Task { @MainActor in self.notice = "A tesztoldal nem nyílt meg."; self.message = error.localizedDescription }
                }
            }
        #endif
    }
}

struct ContentView: View {
    @StateObject private var status = ProtectionStatus()
    @Environment(\.scenePhase) private var scenePhase
    @State private var detailsExpanded = false

    private let accent = Color(red: 0.12, green: 0.55, blue: 0.48)
    private var canvas: Color {
        #if os(macOS)
        Color(nsColor: .underPageBackgroundColor)
        #else
        Color(uiColor: .systemGroupedBackground)
        #endif
    }
    private var surface: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }
    private var headline: String {
        if status.reloading { return "Szabályok betöltése" }
        if status.busy { return "Állapot ellenőrzése" }
        if !status.nativeKnown { return "Ellenőrzés szükséges" }
        if status.nativeEnabled && !status.nativeRulesAcknowledged { return "Szabálybetöltés szükséges" }
        return status.nativeEnabled ? "Szűrőlista bekapcsolva" : "Kapcsold be a szűrést"
    }
    private var subtitle: String {
        if status.busy { return "Kapcsolódás a Safarihoz…" }
        if !status.nativeKnown { return "A Safari állapota nem érhető el." }
        if status.nativeEnabled && !status.nativeRulesAcknowledged {
            return "A csomagolt lista betöltése még nincs visszaigazolva."
        }
        return status.nativeEnabled ? "A blokkolás a tesztoldalon ellenőrizhető." : "Engedélyezd a Safari beállításaiban."
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                header
                VStack(spacing: 16) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 42, weight: .light))
                        .foregroundStyle(status.nativeEnabled ? accent : Color.secondary)
                        .frame(width: 100, height: 100)
                        .background(accent.opacity(0.08), in: Circle())
                        .overlay(Circle().strokeBorder(accent.opacity(0.12), lineWidth: 1))
                    VStack(spacing: 8) {
                        Text(headline)
                            .font(.system(.title2, design: .rounded, weight: .semibold))
                        Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)
                }
                .padding(.top, 8)

                VStack(spacing: 0) {
                    extensionRow("Szűrőlista", icon: "line.3.horizontal.decrease",
                                 enabled: status.nativeEnabled, known: status.nativeKnown) {
                        status.openSettings(forBlocker: true)
                    }
                    Divider().padding(.leading, 60)
                    extensionRow("Oldalellenőrzés", icon: "safari",
                                 enabled: status.webEnabled, known: status.webKnown) {
                        status.openSettings()
                    }
                }
                .background(surface, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.primary.opacity(0.06)))

                VStack(spacing: 12) {
                    Button {
                        if status.nativeEnabled { Task { await status.reload() } }
                        else { status.openSettings(forBlocker: true) }
                    } label: {
                        HStack(spacing: 9) {
                            if status.busy { ProgressView().controlSize(.small).tint(.white) }
                            Text(status.nativeEnabled ? "Szabályok újratöltése" : "Beállítás Safariban")
                                .font(.system(.body, design: .rounded, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .foregroundStyle(.white)
                        .background(accent, in: RoundedRectangle(cornerRadius: 12))
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .disabled(status.busy)
                    .opacity(status.busy ? 0.65 : 1)

                    if let notice = status.notice {
                        Text(notice).font(.callout).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .accessibilityLabel("Művelet eredménye: \(notice)")
                    }
                }

                DisclosureGroup("Részletek", isExpanded: $detailsExpanded) {
                    VStack(alignment: .leading, spacing: 14) {
                        diagnostic("Szűrőlista", value: status.nativeStatus)
                        diagnostic("Oldalellenőrzés", value: status.webStatus)
                        if let message = status.message {
                            Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                        #if os(macOS)
                        Divider()
                        Button { status.openTest() } label: {
                            Label("Tesztoldal megnyitása", systemImage: "arrow.up.right.square")
                        }
                        .buttonStyle(.plain).foregroundStyle(accent)
                        .help("Előbb indítsd el a projekt Teszt indítása.command fájlját.")
                        #endif
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 14)
                }
                .font(.subheadline).tint(.secondary)
                .padding(.horizontal, 4)
            }
            .padding(28)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(canvas)
        .task { await status.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await status.refresh() } }
        }
    }

    private var header: some View {
        HStack {
            Text("Ad Blocker").font(.system(.headline, design: .rounded, weight: .bold))
            Text("0.0.1 · Teszt").font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(.primary.opacity(0.04), in: Capsule())
            Spacer()
            Button { Task { await status.refresh() } } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 34, height: 34)
                    .background(surface, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain).disabled(status.busy)
            .help("Állapot frissítése").accessibilityLabel("Állapot frissítése")
        }
    }

    private func extensionRow(_ title: String, icon: String, enabled: Bool, known: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 17))
                    .foregroundStyle(.secondary).frame(width: 30)
                Text(title).font(.subheadline.weight(.medium))
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    Circle().fill(enabled ? accent : Color.secondary.opacity(0.45))
                        .frame(width: 6, height: 6)
                    Text(status.busy && !status.reloading ? "Ellenőrzés…" : (known ? (enabled ? "Bekapcsolva" : "Kikapcsolva") : "Nem elérhető"))
                        .font(.caption)
                }
                .foregroundStyle(enabled ? accent : Color.secondary)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(18).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Safari beállításainak megnyitása")
    }

    private func diagnostic(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold))
            Text(value).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        }
    }
}
