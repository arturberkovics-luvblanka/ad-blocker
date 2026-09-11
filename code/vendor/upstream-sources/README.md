# Rögzített upstream források

A `SOURCE_MANIFEST.json` tartalmazza a hivatalos letöltési URL-eket, tageket,
commitokat, fájlhash-eket, licenceket és az elvégzett ellenőrzéseket.
A két `.tar.gz` fájl változatlan GitHub-forrásarchívum: a fejlesztési forrást,
teszteket, saját lockfile-t és buildeszközöket is tartalmazza. Az archívumok
letöltése commit szerint történt; a verziótagek ugyanarra a commitra mutattak.

- Scriptlets 2.4.2: `Scriptlets-2.4.2.tar.gz`, GPL-3.0.
- ExtendedCss 2.1.1: `ExtendedCss-2.1.1.tar.gz`, GPL-3.0.
- Public Suffix List: `public_suffix_list-2025-07-09.dat`, MPL-2.0.

A licencszövegek külön is megtalálhatók ebben a mappában. A JavaScript-források
upstream buildje itt nem futott le; a kiadott npm-csomagokkal való bájtonkénti
azonosságukat ez az ellenőrzés nem állítja. Az alkalmazás bundle-generátora a
`SafariConverterLib/Extension/pnpm-lock.yaml` által rögzített npm-csomagokat
használja. A jelen archívumok ezek módosítható fejlesztési forrását egészítik ki.

## Upstream build belépési pontjai

Mindkét archívumot külön munkamappába bontsd ki. Az archívum saját README-jét,
package.json fájlját és lockfile-ját használd. A Scriptlets build belépési pontja
`pnpm build`; az ExtendedCssé `yarn build`. Az upstream prebuild/postbuild
lépések és a szükséges fejlesztői függőségek az archívumokban szerepelnek.
A pontos scripts mezőket a forrásjegyzék is rögzíti. A függőségek első
telepítése hálózati hozzáférést igényelhet.

## A csomagolt PSL-adatok reprodukciója

A mellékelt lista a `publicsuffix/list` rögzített commitjából származik.
A projektben mellékelt swift-psl 1.1.43 ResourceBuilderével újragenerált
`common.bin`, `negated.bin` és `asterisk.bin` mindegyike **bájtonként egyezik**
a termékben csomagolt megfelelő fájllal. A hash-ek a forrásjegyzékben vannak.
Ez a szabályadatok megfelelő forrását igazolja; a 2025-ös HTTP-válasz esetleges
generált kommentfejléceinek azonosságát nem állítja.

A projekt gyökeréből, új ideiglenes mappával:

```sh
PSL_CHECK_DIR="$(mktemp -d)"
swift run --package-path code/vendor/swift-dependencies/swift-psl \
  --scratch-path "$PSL_CHECK_DIR/build" ResourceBuilder \
  "$PWD/code/vendor/upstream-sources/public_suffix_list-2025-07-09.dat" \
  "$PSL_CHECK_DIR/common.bin" "$PSL_CHECK_DIR/negated.bin" "$PSL_CHECK_DIR/asterisk.bin"
for part in common negated asterisk; do
  cmp "$PSL_CHECK_DIR/$part.bin" \
    "code/vendor/swift-dependencies/swift-psl/Sources/PublicSuffixList/Resources/$part.bin"
done
```

A parancsok csak ideiglenes kimeneteket készítenek; nem írják felül a termék
csomagolt erőforrásait. Sikeres `cmp` esetén nincs külön kimenet.
