#if os(macOS)
import SwiftUI

struct MacOnboardingView: View {
    @ObservedObject var model: MacOnboardingModel
    let close: () -> Void
    private let accent = Color(red: 0.08, green: 0.48, blue: 0.39)

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if model.walkthrough { walkthroughContent }
                        else { dashboard }
                        if let message = model.message {
                            Label(message, systemImage: "info.circle")
                                .font(.callout).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if model.localBuild { developmentNotice }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(32)
                }
                Divider()
                footer.padding(.horizontal, 32).padding(.vertical, 18)
            }
        }
        .frame(minWidth: 740, minHeight: 620)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(accent)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(spacing: 10) {
                Image(systemName: "shield.lefthalf.filled").font(.title2).foregroundStyle(accent)
                Text("Ad Blocker").font(.headline)
            }
            Text(model.walkthrough ? "NÉHÁNY LÉPÉS, ÉS INDULHAT" : "SAFARI-VÉDELEM")
                .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            if model.walkthrough {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(OnboardingStep.allCases, id: \.rawValue) { item in
                        HStack(spacing: 10) {
                            Text("\(item.rawValue + 1)")
                                .font(.caption.weight(.semibold))
                                .frame(width: 24, height: 24)
                                .background(item == model.step ? accent : Color.secondary.opacity(0.12), in: Circle())
                                .foregroundStyle(item == model.step ? .white : .secondary)
                            Text(item.title).font(.callout.weight(item == model.step ? .semibold : .regular))
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 8)
                        .foregroundStyle(item == model.step ? .primary : .secondary)
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(item == model.step ? [.isSelected] : [])
                    }
                }
            } else {
                Label("Állapot", systemImage: "checkmark.shield").font(.callout.weight(.semibold))
            }
            Spacer()
            Text("A védelem a Safariban fut.\nAz appot beállítás után bezárhatod.")
                .font(.caption).foregroundStyle(.secondary).lineSpacing(4)
            Text("\(model.version) · \(model.build)").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(width: 220)
        .frame(maxHeight: .infinity)
        .background(accent.opacity(0.045))
    }

    @ViewBuilder private var walkthroughContent: some View {
        switch model.step {
        case .welcome:
            heading("Kevesebb reklám.\nNyugodtabb böngészés.", subtitle: "Állítsuk be együtt az Ad Blockert. Megmutatjuk, mi működik automatikusan, és mit kell egyszer engedélyezned a Safariban.")
            feature("Szűrőlista", symbol: "line.3.horizontal.decrease", text: "Már betöltéskor kiszűri az ismert reklámkéréseket és elrejti a reklámelemeket.")
            feature("Fejlett védelem", symbol: "sparkles", text: "A webes bővítmény a dinamikus oldalakon is dolgozik, és a YouTube-reklámok szűrésében is részt vesz.")
            Text("A Safari beállításaiban a két réteg neve: „Ad Blocker – Szűrőlista” és „Ad Blocker – Oldalellenőrzés”.")
                .font(.callout).foregroundStyle(.secondary)
            Text("A sütik automatikus elutasítása még nem része ennek a verziónak. A működéspróba az alapvédelmet ellenőrzi; nem ígér minden oldalon teljes reklámmentességet.")
                .font(.caption).foregroundStyle(.secondary)
        case .extensions:
            heading("Kapcsold be a két réteget", subtitle: "A Safari jóváhagyását neked kell megadnod. Az app megnyitja a megfelelő beállítást, majd ellenőrzi az eredményt.")
            extensionCard("Szűrőlista", detail: model.nativeDetail,
                          known: model.readiness.nativeKnown, enabled: model.readiness.nativeEnabled, native: true)
            extensionCard("Oldalellenőrzés", detail: model.webDetail,
                          known: model.readiness.webKnown, enabled: model.readiness.webEnabled, native: false)
            if model.readiness.nativeEnabled && !model.readiness.rulesAcknowledged {
                Button("Szabálybetöltés újrapróbálása") { Task { await model.refresh(forceRules: true) } }
                    .disabled(model.busy)
            }
            Text("Ha visszatérsz ide, újra ellenőrizzük a kapcsolókat. Ha közben bezárod az appot, innen folytathatod a beállítást.")
                .font(.callout).foregroundStyle(.secondary)
        case .websites:
            heading("Engedd dolgozni az oldalakon", subtitle: "A fejlett védelemnek hozzáférésre van szüksége azokhoz a weboldalakhoz, ahol szeretnéd használni.")
            feature("1. Nyisd meg a webhelyengedélyeket", symbol: "safari", text: "Safari → Beállítások → Bővítmények → Ad Blocker – Oldalellenőrzés → Webhelyek szerkesztése.")
            feature("2. Válassz tartós hozzáférést", symbol: "hand.raised", text: "A széles körű védelemhez válaszd az Engedélyezés lehetőséget az összes webhelyre. Az egyszeri vagy egynapos engedély később lejárhat.")
            feature("3. Nézd meg a kivételeket", symbol: "list.bullet", text: "Ha egy oldalon tiltod a hozzáférést, ott a fejlett réteg nem működik. Másik Safari-profilban és privát böngészésben külön bekapcsolás is szükséges lehet.")
            Button("Webhelyengedélyek megnyitása") { model.openSettings(native: false) }
                .buttonStyle(.bordered)
            Text("A webes bővítmény a megnyitott oldalak tartalmát olvashatja és módosíthatja a szűréshez. Az app nem küld böngészési előzményt vagy oldaltartalmat külső szolgáltatásnak.")
                .font(.caption).foregroundStyle(.secondary)
        case .test:
            heading("Próbáljuk ki a védelmet", subtitle: "Egy saját tesztoldalt nyitunk a Safariban. Ellenőrizzük a szűrést, a bővítmény futását és azt is, hogy a hasznos tartalom működik-e.")
            feature("Önálló, helyi ellenőrzés", symbol: "checkmark.shield", text: "A próba ezen a Macen fut. Nem kell hozzá terminál vagy külön tesztszerver; személyes oldalaidat nem vizsgálja.")
            Text(model.selfTest.userMessage).font(.callout).foregroundStyle(.secondary)
                .accessibilityLabel("Működéspróba: \(model.selfTest.userMessage)")
            if model.selfTest.isRunning || model.completing {
                HStack { ProgressView().controlSize(.small); Text(model.completing ? "Safari-állapot visszaellenőrzése…" : "Várjuk a Safari tesztoldalát…").font(.callout) }
                Button("Próba megszakítása") { model.selfTest.cancel() }
            }
            Text("Ha a Safari hozzáférést kér a tesztoldalhoz, engedélyezd, majd töltsd újra az oldalt. Ha másik reklámblokkoló is fut, annak hatását is figyelembe kell venni az eredménynél.")
                .font(.caption).foregroundStyle(.secondary)
        case .complete:
            Image(systemName: "checkmark.shield.fill").font(.system(size: 52)).foregroundStyle(accent)
            heading("A beállítás kész", subtitle: "A két réteg bekapcsolva, és a helyi működéspróba sikeres. A tesztelt Safari-környezetben az alapvédelem működik.")
            feature("Az appot most bezárhatod", symbol: "macwindow", text: "A szűrést a Safari végzi. A már megnyitott oldalakat frissítsd, hogy az új védelem életbe lépjen.")
            feature("Később is segítünk", symbol: "arrow.clockwise", text: "Ha változtatsz az engedélyeken, másik profilt használsz vagy hibát látsz, nyisd meg az Ad Blockert egy új ellenőrzéshez.")
        }
    }

    private var dashboard: some View {
        VStack(alignment: .leading, spacing: 24) {
            heading(model.readiness.canTest ? "A Safari-rétegek bekapcsolva" : "Nézzük meg a védelmet", subtitle: "Az aktuális kapcsolókat és a szabálybetöltést ellenőrizzük. A webhelyengedély és az oldalon működő védelem külön próbával igazolható.")
            extensionCard("Szűrőlista", detail: model.nativeDetail, known: model.readiness.nativeKnown,
                          enabled: model.readiness.nativeEnabled, native: true)
            extensionCard("Oldalellenőrzés", detail: model.webDetail, known: model.readiness.webKnown,
                          enabled: model.readiness.webEnabled, native: false)
            if let evidence = model.evidence {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Legutóbbi sikeres helyi próba").font(.callout.weight(.semibold))
                    Text(evidence.date.formatted(date: .abbreviated, time: .shortened)).font(.callout).foregroundStyle(.secondary)
                    if !model.verifiedThisBuild {
                        Text("Azóta frissült az app vagy a lista. Ehhez a verzióhoz új működéspróba ajánlott.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Button("Beállítási útmutató megnyitása") { model.showWalkthrough() }
                .buttonStyle(.bordered)
        }
    }

    private var developmentNotice: some View {
        Group {
            if model.step == .extensions && (!model.readiness.nativeKnown || !model.readiness.webKnown) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Helyi fejlesztői tesztverzió").font(.caption.weight(.semibold))
                    developmentDetails
                }
            } else {
                DisclosureGroup("Helyi fejlesztői tesztverzió") {
                    developmentDetails.padding(.top, 6)
                }
            }
        }
        .font(.caption.weight(.medium))
        .padding(14)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private var developmentDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ez a csomag még nem Developer ID-aláírt. A Safari az „Allow unsigned extensions” fejlesztői engedélyt kilépéskor visszaállítja. A tartós kiadáshoz rendes Apple-aláírás kell; a sikeres működéspróba ezt nem helyettesíti.")
            Text("Helyi kipróbáláshoz: Safari → Beállítások → Speciális → webfejlesztői funkciók megjelenítése, majd Fejlesztő → Allow unsigned extensions. A kapcsolót és az esetleges rendszerhitelesítést neked kell kezelni. Utána válaszd az Új ellenőrzés gombot.")
        }
        .font(.caption).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var footer: some View {
        HStack {
            if model.walkthrough && model.step != .welcome && model.step != .complete {
                Button("Vissza") { model.go(to: OnboardingStep(rawValue: model.step.rawValue - 1) ?? .welcome) }
                    .disabled(model.selfTest.isRunning || model.completing)
            } else if model.busy {
                ProgressView().controlSize(.small)
                Text("Ellenőrzés…").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !model.walkthrough {
                Button("Állapot frissítése") { Task { await model.refresh() } }.disabled(model.busy)
                Button("Működéspróba") { model.walkthrough = true; model.go(to: .test) }
                    .buttonStyle(.borderedProminent)
            } else {
                switch model.step {
                case .welcome:
                    Button("Kezdjük") { model.go(to: .extensions); model.beginDiscovery() }
                        .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                case .extensions:
                    Button("Új ellenőrzés") { model.beginDiscovery() }.disabled(model.busy)
                    Button("Tovább") { model.go(to: .websites) }.disabled(!model.readiness.canTest || model.busy)
                        .buttonStyle(.borderedProminent)
                case .websites:
                    Button("Tovább a működéspróbához") { model.go(to: .test) }.buttonStyle(.borderedProminent)
                case .test:
                    Button("Teszt megnyitása Safariban") { Task { await model.runTest() } }
                        .disabled(model.busy || model.selfTest.isRunning || model.completing)
                        .buttonStyle(.borderedProminent)
                case .complete:
                    Button("Befejezés") { close() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    private func heading(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 29, weight: .semibold, design: .rounded)).fixedSize(horizontal: false, vertical: true)
            Text(subtitle).font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).lineSpacing(3)
        }
    }

    private func feature(_ title: String, symbol: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.title3).foregroundStyle(accent).frame(width: 28)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func extensionCard(_ title: String, detail: String, known: Bool, enabled: Bool, native: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: known && enabled ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.headline).foregroundStyle(known && enabled ? accent : Color.primary)
                Spacer()
                if !known || !enabled {
                    Button("Beállítás") { model.openSettings(native: native) }.buttonStyle(.bordered)
                }
            }
            Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.07)))
    }
}
#endif
