# v0.0.2 forrásellenőrzések

A GitHubon jelenleg közzétett kiadás a v0.0.1. A helyi munkapéldány v0.0.2
onboardingja helyben elkészült, de még nincs publikálva. A natív szabálylista
változatlan: 97 505 szabály, SHA-256
`508b0900171a9eb4a0e6b4367d33d4566851a6cdeea16fdb46cac00c020961a8`.

- Saját JavaScript-regressziók: 39/39 sikeres a v0.0.2 forrásával.
- A macOS Release és a közös iOS Release build sikeres; az iOS build
  aláíratlan, készülékes teszt nem történt.
- Az ablak nélküli macOS host Release buildje sikeres. A host saját ablak
  nélkül indult a helyi buildpróbában, és a diagnosztika strukturált
  állapotot adott.
- A postinstall unit tesztjei 4/4 sikeresek: aktív user, hiányzó/nem megfelelő
  user, indítási hiba és a csomagolt script pontos szerkezete.
- A v0.0.2 `.pkg` strukturális kibontási, payload-, aláírás- és scriptellenőrzése
  sikeres.

## Build 4 — tényleges Safari-próba

A verziócsere véletlenül megváltoztatta a helyi diagnosztikai origin és két
WK-tesztmanifest címét. A build 4 visszaállítja a szerver tényleges címét.
A regresszióteszt most a szerver bind címéből képezi a pozitív tesztorigint,
és összeveti a manifestekkel és a natív tesztszabályokkal.

Safari alatt a webes réteg bekapcsolva, a natív kikapcsolva volt. A valódi
oldal és helyi napló igazolta a content scriptet, a csomagolt runtime pontos
revisionjét és a natív lookup `no_matching_rules` válaszát. A hasznos gomb
0-ról 1-re lépett. Külön valódi Safari-próbában a statikus MAIN script az
első oldalscript előtt és szigorú CSP alatt is lefutott. Az izolált WebKit
integrációs és időzítési próbák szintén sikeresek, a korábban dokumentált
blank/srcdoc programozott injektálási korlát megmaradt.

A natív szűrőlista bekapcsolását Safari az automatizált kattintás miatt
elutasította. A teljes ON/ON beállítás és annak pozitív végpontpróbája még
nincs igazolva. A működő webes réteg önmagában nem bizonyít natív blokkolást.

## Korábbi ellenőrzések a változatlan blokkolómotoron

- A mellékelt konverterforrásból mindkét eszköz újrafordult; a helyi
  újragenerálás 97 505 natív / 12 076 fejlett szabállyal és az elvárt
  szabálymultiset-egyezéssel sikeres.
- Mac build, beágyazott extensionök, erőforrások és ad-hoc aláírás ellenőrzése.
- A teljes natív lista WebKitben lefordult; hálózati/kozmetikai OFF/ON és
  hasznos tartalom kontrollja sikeres.
- Izolált WKWebExtension-próbák: dokumentumcélzás, MAIN/CSP, korai
  YouTube-adatmezők, deduplikáció; popup/first-party/kivétel és dokumentumtiltás.
- Élő Safari-próbákban több oldalon igazolt reklámos kontroll és elrejtés.
  A felhasználó további saját próbáiban jól működőnek találta a verziót.

## Futtatás

```sh
node --test code/tests/*.test.mjs
python3 -m unittest code/tests/installer_postinstall_test.py
bash code/scripts/test-native-rule-activation.sh
bash code/scripts/test-advanced-native.sh
# Külön terminálban:
python3 code/scripts/serve_fixture.py
# A helyi szerver mellett:
bash code/scripts/test-webkit.sh
bash code/scripts/test-native-popup-projection-webkit.sh
bash code/scripts/test-native-popup-navigation-webkit.sh
bash code/scripts/test-webextension-early-youtube-fix.sh
```

A telepített v0.0.2 host onboarding-állapota saját ablak megnyitása nélkül
olvasható ki:

```sh
"/Applications/Ad Blocker.app/Contents/MacOS/Ad Blocker" --diagnose
```

Az ismeretlen Safari-állapot nem számít sikeres aktiválásnak.

A helyi fixture saját tesztadatokat használ. Más blokkoló, Premium-előfizetés
vagy csak a reklám hiánya nem bizonyítja önmagában ennek az appnak a hatását.

## Nyitott korlátok

- A v0.0.2 build 2 valódi `.pkg` telepítése és postinstall háttérindítása
  sikeres; a telepített app mindkét extensionje és erőforrásai ellenőrizve.
  A késleltetett felismerés javítását a build 3 külön ellenőrzi.
- A v0.0.2 élő negatív próbája sikeres: Safari unsigned OFF mellett a
  háttér-host nulla saját ablakkal futott, SFErrorDomain 1 hibát rögzített,
  és nem állított sikeres aktiválást. Dupla indítás után is kilépett.
  A pozitív, telepítés utáni végponttól végpontig tartó próba még hiányzik.
  A csomag nem Developer ID-aláírt és nem notarizált.
- A v0.0.2 még nem GitHub-kiadás; a nyilvános letöltési link továbbra is a
  v0.0.1-re mutat.
- Nincs teljes webre vagy minden YouTube-variánsra vonatkozó garancia.
- Nincs valódi iPhone/iPad teszt; az aláírás nélküli iOS build nem telepíthető IPA.
- 223 konverziós hiba a `filters/generated/adguard-base-unsupported.log` fájlban.
- Egyes blank/srcdoc programozott injektálásokat WebKit elutasít; egyes CSS
  beavatkozások prioritása korlátozott.
- A vendor teljes Swift-köre 328 tesztet teljesített egy app-group entitlementet
  igénylő singleton-teszt kihagyásával. A teljes `make test` emiatt nem zöld.
  Hiányzó linteszközök és az Xcode 27 xctrace/bundle útvonala miatt a teljes
  lint/performance folyamat sem minősített; tíz beépített measure teszt sikeres.
- Az automatikus valódi sütielutasítás és a hálózati listafrissítés későbbi munka.

A CookiebotPublicSDKProbe külön kísérlet: az ismert eltérő CMP/privacy
konfigurációknál művelet nélkül `UNSUPPORTED` állapotot ad; nem termékfunkció.
