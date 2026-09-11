# Ad Blocker v0.0.2 forrás

Natív Safari content blocker + Safari Web Extension. A macOS host AppKit
app: az első indításkor érthető beállítóablakot, később kézzel megnyitható
állapotablakot mutat; az adott buildhez korábban sikeresen ellenőrzött
beállítás automatikus `--setup` indítása csendes lehet.
Az iPhone/iPad host SwiftUI. A v0.0.2 build 7 ad-hoc aláírású macOS
teszt-előkiadás. A rendes telepítési cél mindig `/Applications/Ad Blocker.app`;
külön helyi tesztpéldányt csak explicit
`install-macos.sh --local-test-path` argumentum hozhat létre. Az iCloud
Desktop mappából közvetlenül ne futtasd.

## Mappák

| Mappa | Tartalom |
|---|---|
| `Sources/App/` | macOS onboarding és állapotablak, iOS/iPadOS app, működéspróba és állapotkezelés |
| `Sources/ContentBlocker/` | A csomagolt Safari-szabálylista betöltése |
| `Sources/WebExtension/` | A Safari webes extension natív belépési pontja |
| `extension/` | Manifest, fejlett szabálymotor, oldaldiagnosztika, bővítménypopup |
| `extension-runtime/` | A csomagolt JS-runtime belépési pontja és bemeneti hash-jegyzéke |
| `filters/` | Rögzített forráslista, natív JSON és konverziós jelentés |
| `vendor/` | A szabálykonverter rögzített forrása és licence |
| `scripts/` | Projektgenerálás, build, csomagolás és helyi tesztszerver |
| `installer/` | A pkg ellenőrzött frissítésvédő preinstall és első indítást kérő postinstall scriptje |
| `tools/` | A függőségi és szabálykonverziós eszközök |
| `tests/` | Kontrollos tesztoldal, JS-tesztek és natív WebKit-próba |
| `docs/` | Telepítés, licencek, tényleges ellenőrzési eredmények |
| `Configuration/` | A generátor által előállított Info.plist és entitlement fájlok |
| `AdBlocker.xcodeproj/` | Megnyitható Xcode-projekt, Mac és iOS app scheme-mel |

## Fordítás

Előfeltétel: teljes Xcode aktív fejlesztői útvonallal, Python 3. A JS-tesztekhez Node.js szükséges. A normál appbuild offline, csomagolt listából működik; a konverter újrafuttatása külön lépés.

```sh
bash code/scripts/build.sh macOS
bash code/scripts/install-macos.sh
bash code/scripts/build.sh iOS
node --test code/tests/*.test.mjs
python3 code/tests/installer_postinstall_test.py
bash code/scripts/test-advanced-native.sh
bash code/scripts/test-advanced-webkit.sh
# Külön terminálban futó serve_fixture.py mellett:
bash code/scripts/test-webkit.sh
```

A parancsokat a projekt gyökeréből futtasd. Az iOS parancs aláírás nélküli
fordítási ellenőrzés, nem telepíthető IPA. A Mac parancs helyi ad-hoc
aláírással készít tesztappot. A build 7 valódi frissítő telepítése, a telepített
app és a Release termék egyezése, valamint az új, öt ellenőrzéses onboarding-
önteszt sikeres. A tiszta extensionregisztráció, az öt célzott javítás és a
három YouTube-videós mátrix is élő Safari-próbát kapott. Pontos állapot és nem
tesztelt esetek: [LIVE-VALIDATION.md](docs/LIVE-VALIDATION.md). Naplók:
`../builds/logs/`.
Az Xcode köztes fájljai a rendszer ideiglenes mappájába kerülnek: az iCloud
Desktop által hozzáadott Finder-metaadatok különben megakaszthatják a
codesigningot.

A `generate_project.py` a hat target egyszerű, külső projektgenerátor nélküli leírása. Tartós buildbeállítás-módosítást ebben végezz; a build újragenerálja az Xcode-projektet és a Configuration fájlokat. A Signing & Capabilities alatt kézzel megadott iOS Team csak a következő generálásig marad meg; eszközös tesztnél ezt később külön fejlesztői konfigurációba kell kivezetni.

## Első kipróbálás

Részletesen: [SETUP.md](docs/SETUP.md). Az első megnyitás az onboarding
ablakban megmutatja a két Safari-réteget, a kézi engedélyezési lépéseket és a
helyi működéspróbát. A sikeres beállítás után az app kézzel megnyitva az
állapotot és az újraellenőrzést mutatja; egy egészséges frissítés miatti
háttérindítás csendes lehet. Az állapota a telepített bináris `--diagnose`
kapcsolójával is olvasható ki.

## Valós korlátok

- A natív lista és a külön advanced/scriptlet motor be van építve. A konverziós hibák külön jelentésben szerepelnek.
- A webes motor a rögzített AdGuard-szabályokat futtatja; a YouTube lookup,
  JS-regisztráció, egy reklámos OFF/ON mintavideó és egy oldalon belüli
  videóváltás ellenőrzött. Ez nem minden videóra vagy videóba szerkesztett
  szponzorációra vonatkozó garancia.
- Teljes popupvédelem, automatikus sütielutasítás és internetes listafrissítés még hiányzik. A content-fallback scriptinjektálása szigorú CSP mellett meghiúsulhat.
- A build-minimum macOS 14 / iOS 17, de csak a ténylegesen tesztelt rendszerekhez tartozhat működési állítás.
- Készülék- és Safari-igazolás: [LIVE-VALIDATION.md](docs/LIVE-VALIDATION.md)
  és [TESTING.md](docs/TESTING.md). Egy WebKit-próba önmagában nem
  Safari-extension teszt.

A Safari-válaszok időkorlátjának regressziós tesztje:

```sh
xcrun swiftc code/Sources/App/SafariRequest.swift code/tests/SafariRequestTests.swift -o /tmp/AdBlockerRequestTests
/tmp/AdBlockerRequestTests
```

Az állapotlekérdezés 15, a szabálybetöltés 60 másodperces időkorlátot kap. Időtúllépéskor a művelet eredménye ismeretlen, nem tekinthető sikeresnek.

## A csomagolt webes motor újragenerálása

A rendes Mac/iOS build offline használja a mellékelt JS-fájlokat, és Pythonból
ellenőrzi, hogy a bemeneteik nem változtak. Fejlesztői újragenerálás:

```sh
pnpm --dir code/vendor/SafariConverterLib/Extension install --frozen-lockfile --ignore-scripts
node code/scripts/build-extension-runtime.mjs
python3 code/scripts/verify_runtime.py
```

Az újragenerálás után JS-regresszió, natív kulcsegyezés, WebKit- és Safari-próba
kell. A sikeres bundle-build önmagában nem igazolja a reklámblokkolást.

A csomagolt natív lista változását az app felismeri, és bekapcsolt natív
bővítménynél megnyitáskor automatikusan újratölti. Csak sikeres Safari-callback
után őriz visszaigazolást; a már nyitott oldalakat továbbra is frissíteni kell.
A koordinátor regressziói: `bash code/scripts/test-native-rule-activation.sh`.

A nyilvános kiadás build/újragenerálási útja: [BUILDING.md](docs/BUILDING.md).
