# Safari-bővítmény regisztrációja és Apple-terjesztési terv

Dátum: 2026-09-11

Ez a dokumentum külön kezeli a v0.0.2-ben már elkészült háttérbeállítást és a
későbbi Developer ID-s terjesztési tervet. Nem történt Apple Developer
regisztráció, vásárlás, tanúsítványkérés, Developer ID-aláírás vagy
notarizálás.

## Miért nem jelenhet meg az aláíratlan bővítmény?

A jelenlegi Release app és a két beágyazott extension ad-hoc aláírású. Az app
aláírásában nincs Team ID, a `.pkg` pedig nincs Developer ID Installer
identityvel aláírva vagy notarizálva.

Az Apple dokumentációja két külön feltételt ír le:

1. a containing macOS appot legalább egyszer futtatni kell, hogy a Safari
   telepítettként felismerje a beágyazott web extensiont;
2. a Safari biztonsági okból figyelmen kívül hagyja az aláíratlan extensiont,
   ezért az nem jelenik meg az Extensions beállításokban, amíg a fejlesztői
   **Allow unsigned extensions** kapcsoló nincs bekapcsolva. Ez a kapcsoló a
   Safari bezárásakor visszaállhat.

Az egyszeri Gatekeeper-jóváhagyás legfeljebb a telepítő vagy az app
megnyitását engedi. Nem alakítja az ad-hoc aláírást terjesztési aláírássá, és
nem helyettesíti a Safari külön unsigned-extension kapuját.

## A publikus Safari API határa

A macOS 27 SDK-ban:

- `SFSafariExtensionManager` a Safari extension állapotát olvassa vissza;
- `SFContentBlockerManager` az állapotot olvassa és egy már engedélyezett
  content blocker szabályait töltheti újra;
- `SFSafariApplication.showPreferencesForExtension` megnyitja a Safari
  Extensions beállítását;
- egyik publikus API sem kapcsolhat be extensiont vagy adhat
  webhelyengedélyt.

A két extension kapcsolója, a profilonkénti állapot és a webhely-hozzáférés
felhasználói döntés marad. Az alkalmazás csak visszaolvashatja az eredményt,
aktiválhatja a már engedélyezett natív szabályokat, és szükség esetén egyszer
megnyithatja a megfelelő Safari-beállítást.

## Elkészült v0.0.2 háttérbeállítás

A macOS host `LSUIElement=true` agent appként, saját ablak és Dock-ikon nélkül
fut. A macOS belépési pont AppKit run loopot használ; az iOS/iPadOS belépési
pont továbbra is SwiftUI.

Induláskor a host:

1. legfeljebb 120 másodpercig lekéri mindkét extension állapotát;
   ismeretlen eredménynél is két másodpercenként újrapróbálkozik;
2. már engedélyezett natív extensionnél betölti a csomagolt szabályokat;
3. kikapcsolt állapotnál legfeljebb egyszer megnyitja a Safari Extensions
   beállítását, majd két másodpercenként, legfeljebb 120 másodpercig figyeli a
   felhasználói döntést;
4. ismeretlen állapotnál diagnosztikai eredményt ment, és a határidőig
   tovább vár a felismerésre; ez nem számít sikeres aktiválásnak;
5. nem ír Safari- vagy macOS-biztonsági beállítást, nem ad webhelyengedélyt,
   és nem telepít login itemet vagy LaunchAgentet.

A `--diagnose` mód kiírja a legutóbbi háttérbeállítás normalizált JSON
eredményét, a natív és webes extension aktuális állapotát, az app helyét és
verzióját. A diagnosztika nem kapcsolja be a bővítményeket.

Az Apple troubleshooting útmutatója szerint maga a containing app futása a
Safari-felismerés szükséges lépése. Az explicit `LSRegisterURL` csak az app és
document/URL claimjeinek LaunchServices-regisztrációját ígéri; nem
dokumentált helyettesítője a host futtatásának, és nem engedélyez Safari
extensiont.

## Elkészült best-effort háttérindítás a `.pkg` után

A modern Installer Distribution XML dokumentált befejezési műveletei:
`None`, `RequireLogout`, `RequireRestart` és `RequireShutdown`. Nincs
dokumentált „launch installed app” befejezési művelet. A v0.0.2 csomag ezért
egyetlen, szűken korlátozott postinstall scripttel kér egyszeri,
felhasználói környezetű háttérindítást.

A script:

1. kizárólag gyökérkötetre telepítéskor fut tovább;
2. az `/dev/console` tulajdonosából olvassa ki az aktív GUI-felhasználót;
3. csak legalább 501-es UID és valódi felhasználónév esetén folytatódik;
   `root`, `loginwindow`, `_mbsetupuser`, hiányzó session vagy hibás UID
   esetén kézi megnyitást kér;
4. csak az `/Applications/Ad Blocker.app` példányt indítja az adott
   felhasználó bootstrap- és Unix-környezetében:
   `launchctl asuser UID sudo -u USER open -n -g ... --args --setup`;
5. nem próbál rootként appot indítani, és hiba esetén a telepítési naplóban
   kézi megnyitást kér;
6. nem használ `pluginkit` parancsot, nem telepít tartós segédet, nem töröl
   quarantine jelzőt, és nem módosít biztonsági vagy Safari-beállítást.

Ez kényelmi indítás, nem Apple által garantált Safari-regisztrációs API, és
nem jelent automatikus extension-engedélyezést. Fast User Switching esetén
csak a `/dev/console` aktuális felhasználója célozható. Az Installer
postinstall unit tesztjei 4/4 sikeresek, de a valódi `.pkg` telepítési és
hitelesítési próba és a postinstall felhasználói háttérindítása sikeres;
a pozitív helyi Safari-beállítás kézi engedélyek után igazolt.

Az `SMAppService` ehhez az egyszeri művelethez tartós és aránytalan
megoldás lenne: kódaláírást és felhasználói jóváhagyást igényel, a user
LaunchAgentet pedig felhasználónként, futó appból kell regisztrálni. A
`pluginkit -a` helyi man oldala fejlesztési és karbantartási beavatkozásként
írja le az explicit hozzáadást; nem használjuk telepítési kerülőútként.

## Második lépés: Developer ID és notarizálás

A normál Safari-beállítások mellett működő közvetlen terjesztéshez Apple
Developer Program tagság szükséges. Az Apple által jelenleg közölt ár évi
**99 USD**, vagy ahol elérhető, helyi pénznemben megjelenő összeg; a
regionális ár eltérhet.

Ez még terv, nem végrehajtott kiadási folyamat:

1. A felhasználó saját Apple Accounttal belép a programba, elvégzi az
   azonosítást, elfogadja a szerződéseket és kifizeti a tagságot.
2. A host apphoz és az extension targetekhez tartós, egyedi bundle
   identifiereket kell választani. Az `org.local.*` technikailag nem
   érvénytelen, de a publikus azonosítókról kiadás előtt tudatosan kell
   dönteni.
3. A host appot és minden beágyazott extensiont belülről kifelé Developer ID
   Application identityvel, Hardened Runtime mellett és biztonságos
   időbélyeggel kell aláírni. Minden target a saját feladatához szükséges
   entitlementeket kapja; az entitlementlistáknak nem kell azonosnak lenniük.
   A beágyazott targeteknek ugyanahhoz a fejlesztői csapathoz kell tartozniuk.
4. A `.pkg` Developer ID Installer identityvel kap aláírást.
5. A kész flat `.pkg` az Apple notary service-hez kerül `notarytool`
   használatával. Siker után a ticketet a csomaghoz kell staple-elni és
   visszaellenőrizni.
6. Kiadási kapuk: `codesign --verify --deep --strict`,
   `pkgutil --check-signature`, `spctl --type install`, elfogadott
   `notarytool` eredmény, `stapler validate`, majd tiszta felhasználói profilú
   telepítés és háttér-host indítás.

Az Apple szerint a Developer ID-s, 2019. június 1. után készült közvetlenül
terjesztett szoftvert notarizálni kell. Ad-hoc, Apple Development vagy Mac App
Distribution identity nem megfelelő ehhez a közvetlen terjesztési
folyamathoz.

## Felhasználói és későbbi kiadási lépések

Felhasználói feladat marad:

- az Apple Developer Program belépés és fizetés, ha Developer ID-s közvetlen
  terjesztés mellett dönt;
- a tanúsítványok és szerződések fiókszintű jóváhagyása;
- a két Safari extension kézi bekapcsolása;
- a webes extension webhely-hozzáférésének kézi engedélyezése.

A v0.0.2 host és postinstall elkészült, a Release build és a helyi strukturális
csomagtesztek sikeresek. Még szükséges:

- a felhasználó saját Team ID-jával Developer ID build és Installer-aláírás;
- notarizálás, staple-ellenőrzés és tiszta profilú telepítési próba;
- ezek után a hash-ellenőrzött, Developer ID-aláírt nyilvános kiadás publikálása.

Jelszót, Apple Account tokent vagy notarizációs titkot nem szabad forrásba,
parancssori argumentumba vagy naplóba írni. A későbbi automatizálás
Keychainben tárolt `notarytool` profilt használjon.

## Elsődleges Apple-források

- [Running your Safari web extension](https://developer.apple.com/documentation/safariservices/running-your-safari-web-extension)
- [Troubleshooting your Safari web extension](https://developer.apple.com/documentation/safariservices/troubleshooting-your-safari-web-extension)
- [Distributing your Safari web extension](https://developer.apple.com/documentation/safariservices/distributing-your-safari-web-extension)
- [Managing Safari web extension permissions](https://developer.apple.com/documentation/safariservices/managing-safari-web-extension-permissions)
- [SFSafariExtensionManager](https://developer.apple.com/documentation/safariservices/sfsafariextensionmanager)
- [SFContentBlockerManager](https://developer.apple.com/documentation/safariservices/sfcontentblockermanager)
- [LSUIElement](https://developer.apple.com/documentation/bundleresources/information-property-list/lsuielement)
- [LSRegisterURL](https://developer.apple.com/documentation/coreservices/1446350-lsregisterurl)
- [SMAppService.register](https://developer.apple.com/documentation/servicemanagement/smappservice/register%28%29)
- [Packaging Mac software for distribution](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution)
- [Certificates overview](https://developer.apple.com/help/account/create-certificates/certificates-overview)
- [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Apple Developer Program enrollment](https://developer.apple.com/help/account/membership/program-enrollment)
- [Distribution XML Reference](https://developer.apple.com/library/archive/documentation/DeveloperTools/Reference/DistributionDefinitionRef/Chapters/Distribution_XML_Ref.html)
- [Security Development Checklists](https://developer.apple.com/library/archive/documentation/Security/Conceptual/SecureCodingGuide/SecurityDevelopmentChecklists/SecurityDevelopmentChecklists.html)

Helyi elsődleges SDK-források:

- macOS 27 SDK `SafariServices.framework/Headers/SFSafariExtensionManager.h`
- macOS 27 SDK `SafariServices.framework/Headers/SFContentBlockerManager.h`
- macOS 27 SDK `SafariServices.framework/Headers/SFSafariApplication.h`
- macOS 27 SDK `ServiceManagement.framework/Headers/SMAppService.h`
- `open(1)`, `launchctl(1)`, `pluginkit(8)`, `pkgbuild(1)` és
  `productbuild(1)` helyi man oldalak
