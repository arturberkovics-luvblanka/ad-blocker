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
bash code/scripts/package-macos.sh "/pontos/út/Ad Blocker.app"
```

A kiadás forrása tiszta checkoutból, általános `/private/tmp` buildútvonalon
fordult. A publikus binárisokban nincs a fejlesztő saját home-mappájára
mutató forrásútvonal. Developer ID hiányában a macOS app ad-hoc aláírású.

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
