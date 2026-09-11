# Fordítás és újragenerálás

## Alkalmazás

Apple Silicon Mac, teljes Xcode/Swift6+ és Python3:

```sh
bash code/scripts/build.sh macOS Release
```

A build kiírja a ZIP helyét; a köztes app a rendszer ideiglenes
`adblocker-$(id -u)/DerivedData-macOS/Build/Products/Release/Ad Blocker.app`
könyvtárában van. A `.pkg` készítése:

```sh
bash code/scripts/package-macos.sh --local "/pontos/út/Ad Blocker.app"
```

A fenti útvonal csak helyi, ad-hoc tesztcsomagot készít. A v0.0.2 build 5
alapértelmezett neve `builds/macOS/AdBlocker-0.0.2-build5-macOS-arm64.pkg`.
A csomagoló a két engedélyezett installer scriptet is kibontja és ellenőrzi.
A regressziók külön futnak:

```sh
python3 code/tests/installer_postinstall_test.py
```

A kiadás forrása tiszta checkoutból, általános `/private/tmp` buildútvonalon
fordult. A publikus binárisokban nincs a fejlesztő saját home-mappájára
mutató forrásútvonal. Developer ID hiányában a macOS app ad-hoc aláírású.

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

A v0.0.2 Release build, a package strukturális ellenőrzése és a korábbi
postinstall 4/4 unit tesztje sikeres. A build 2 valódi `.pkg` telepítése és a postinstall
felhasználói háttérindítása sikeres. A build 3 a késleltetett Safari-felismerést
javítja; a build 4 pozitív helyi Safari-próbája kézi engedélyek után sikeres.

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
