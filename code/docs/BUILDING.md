# Fordítás és újragenerálás

## Alkalmazás

Apple Silicon Mac, teljes Xcode/Swift6+ és Python3:

```sh
bash code/scripts/build.sh macOS Release
```

A build kiírja a ZIP helyét; a köztes app a rendszer ideiglenes
`adblocker-$(id -u)/DerivedData-macOS-local/Build/Products/Release/Ad Blocker.app`
könyvtárában van. A `.pkg` készítése:

```sh
bash code/scripts/package-macos.sh --local "/pontos/út/Ad Blocker.app"
```

A DerivedData app és a benne levő Safari extensionök csak fordítási termékek,
nem telepítési példányok. A sikeres helyi macOS build ezért kizárólag a saját
két DerivedData extensionjének PlugInKit-regisztrációját távolítja el; az
`/Applications/Ad Blocker.app` példányhoz nem nyúl.

A fenti útvonal csak helyi, ad-hoc tesztcsomagot készít. A jelenlegi v0.0.2
build 7 neve `builds/macOS/AdBlocker-0.0.2-build7-macOS-arm64.pkg`.
A csomagoló a két engedélyezett installer scriptet is kibontja és ellenőrzi.
A regressziók külön futnak:

```sh
python3 code/tests/installer_postinstall_test.py
```

A kiadási jelöltet tiszta checkoutból, általános `/private/tmp`
buildútvonalon kell fordítani. A publikus binárisokban nem maradhat a
fejlesztő saját home-mappájára mutató forrásútvonal. Developer ID hiányában a
macOS app ad-hoc aláírású, és csak teszt-előkiadásként jelölhető.

## Közvetlen terjesztési build

Ezt csak fizetős Apple Developer Program-tagsághoz tartozó Developer ID
Application és Developer ID Installer identitykkel szabad futtatni. A sima,
ingyenes Apple Accounttal elérhető beta/Xcode-letöltés nem hoz létre ilyen
identityt. A script előbb ellenőrzi a Keychaint és sikertelen előfeltételnél
nem készít félrevezetően kiadhatónak jelölt artefaktumot.

```sh
export ADBLOCKER_DEVELOPMENT_TEAM=ABCDEFGHIJ
export 'ADBLOCKER_DEVELOPER_ID_APPLICATION=Developer ID Application: Your Name (ABCDEFGHIJ)'
bash code/scripts/build.sh macOS Release --distribution
```

Ezután a [INSTALLER.md](INSTALLER.md) szerinti `package-macos.sh --distribution`
Developer ID Installer-aláírást, notarizálást, staplinget és a kész csomag
független ellenőrzését végzi. A kiadási útvonal nem esik vissza helyi/ad-hoc
aláírásra.

A build 7 Release fordítása, csomagellenőrzése és valódi build 5 → build 7
Installer-frissítése sikeres. A telepített app bájtszinten egyezik a Release
termékkel, és az ötellenőrzéses onboarding-önteszt sikeres. A még nyitott élő
mátrix: [LIVE-VALIDATION.md](LIVE-VALIDATION.md).

## Natív konverter

Az újrageneráláshoz a Swift mellett `jq` és `ripgrep` (`rg`) is szükséges.

A repo a konverter módosított teljes Swift-forrását és helyi függőségeit
tartalmazza; kész konverterbináris nincs a Gitben.

```sh
bash code/tools/build_converters.sh
bash code/tools/generate_blocker_list.sh --local-converter
```

A más gépen/Xcode-verzióval készült bináris hash-e eltérhet. A
`--local-converter` kifejezett választás a saját fordítás használatára,
amelynek valódi hash-e a riportba kerül. A rögzített forráslisták és az
elvárt szabálymultiset hash-ellenőrzése továbbra is kötelező. A szabályok
vagy konverterszemantika szándékos változásakor a pineket csak a teljes
delta és a kivételek sorrendjének áttekintése után frissítsd.

A konverzió után indítsd a helyi fixture-szervert, majd futtasd a
`bash code/scripts/test-webkit.sh` ellenőrzést. A normál appbuildhez a
konverter újrafuttatása nem szükséges.

## JavaScript runtime

Node.js és pnpm szükséges:

```sh
pnpm --dir code/vendor/SafariConverterLib/Extension install --frozen-lockfile --ignore-scripts
node code/scripts/build-extension-runtime.mjs
python3 code/scripts/verify_runtime.py
node --test code/tests/*.test.mjs
```

A preferred upstream source archívumok és buildparancsaik a
`code/vendor/upstream-sources` alatt vannak. A saját runtime-generátor a
lockfile által rögzített npm kiadásokból dolgozik; ezeket ne cseréld le
ellenőrizetlen verziókra. Az alap alkalmazásbuild a mellékelt, hash-ellenőrzött
runtime-ot használja és nem telepít hálózatról csomagot.
