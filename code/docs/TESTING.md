# v0.0.2 forrásellenőrzések

## Build 7 — telepített jelölt és új célzott szűrők, 2026-09-11

A `AdBlocker-0.0.2-build7-macOS-arm64.pkg` valódi build 5 → build 7
Installer-frissítése sikeres. A receipt verziója `0.0.2.7`; a telepített app
`verify_macos.py` ellenőrzése sikeres, és bájtszinten egyezik a Release appal.
Az app mindkét Safari-réteget ON állapotúnak látta, a build 5 régi öntesztjét
helyesen elavultnak minősítette, majd az új önteszt mind az öt ellenőrzése
sikeres lett. Az aktuális élő állapot: [LIVE-VALIDATION.md](LIVE-VALIDATION.md).

Az ezt megelőző élő Safari-próba a 24.hu kezdőlapján két jelöletlen
reklámkártyát talált:
a FELIX-kampányt a fő rácsban és az OkAuchan-kampányt az aktuális hírek között.
A szabályok a két megfigyelt kampány pontos URL-jét és saját kártyakonténerét
célozzák; nem általánosítjuk őket más `/egyeb/` vagy `/tech/` cikkekre. A
fixture megőrzi a normál NG-cikket, a hasonló, de nem egyező URL-t, az
előfizetői cikket és az aktuális hírek szerkesztői szomszédját.

A hvg.hu élő cikkoldalának „Ez is érdekelhet” rácsában a reklámok és a rendes
cikkek közös listában érkeztek. A widget DOM-ja és nyilvános forrása szerint az
explicit reklám külön `.rltd_tag` elemet kap; a külső cikk címkéje ezen felül
`.rltd_article_tag`, a rendes HVG-cikk pedig címke nélküli. A célzott szelektor
csak az első eset teljes `.rltd_item_container` elemét rejti. A külön
`.sidebar-brandlab` konténerű BrandLab reklámblokk is rejtett. A fixture a
szerkesztői és a partnercímkés ajánlót, valamint egy normál oldalsávot láthatón
hagy.

Az Allrecipes élő receptoldalán megfigyelt sárga MyRecipes app-promóció saját
`.mntl-site-wide-notification` bannergyökérben és pontos
`myrecipesapp.onelink.me/Wc8m` CTA-val jelent meg. A szabály ennek együttállását
célozza. A fixture egy más tartalmú site-wide értesítést, a fejléc normál „Get
the app” linkjét és a recept „Save” gombját láthatón hagy.

- Az öt új szelektor a forrásszabályok számát 138 529-ről 138 534-re, a
  Safari-kompatibilis forrásszabályokét 128 440-ről 128 445-re emelte.
- A konverter a szelektorokat a 24.hu, hvg.hu és Allrecipes már létező natív
  kozmetikai objektumába vonta össze. A végleges lista ezért továbbra is
  97 507 JSON-szabályobjektum, a fejlett lista pedig változatlanul 12 077
  szabály.
- A három kibővített domainobjektum minden korábbi szelektora megmaradt; a
  többi 97 504 szabályobjektum bájtszinten változatlan, és a fejlett
  szabályfájl is bájtszinten azonos.
- A teljes 97 507-es lista az új pozitív/negatív fixture-rel WebKitben
  lefordult és sikeresen lefutott. A 44/44 JavaScript-teszt és a runtime-
  ellenőrzés is sikeres.
- Natív lista SHA-256:
  `1b150ecfd69c3af111042b0f229589ea5d01aa395a87164bc53f9fb863917554`.
  Szabálykészlet SHA-256:
  `9fb31e9bd9b25831bd6413c38fb2b8ca723ba7e32019d8d038e2c77ecc0a91ed`.
  A fejlett lista SHA-256 értéke változatlan:
  `6e45fc354371732ec243cb4b5b205b31a9fc8d219e1970bf021047c1f57b9b02`.
  Runtime revision:
  `660fc08c71affaaa6ff789001f018ce3c406b3de8c45aa00feffb3127f77e743`.

A build 7 app-, pkg-, telepítési és onboarding-ellenőrzése megtörtént. A három
javított webhely élő visszatesztje, a duplikátummentes regisztráció és a
kontrollos YouTube-minta is sikeres; az oldalon belüli YouTube-videóváltás
működött. A dinamikusan szerkesztett fizetett kártyák jövőbeli URL-, osztály-
vagy jelölésváltozata kikerülheti ezeket a szabályokat, és ugyanez igaz az
Allrecipes app-banner kampányazonosítójának változására. A mostani bizonyíték
nem terjed ki ismeretlen kampányokra vagy videóba szerkesztett szponzorációra.
Pontos élő eredmények: [LIVE-VALIDATION.md](LIVE-VALIDATION.md).

## Build 5 — onboarding és helyi önellenőrzés, 2026-09-11

Az új forrásból a macOS Release build sikeres (0.0.2/build 5, arm64), a
csomagolt erőforrások és a két bővítmény ellenőrzése sikeres. A személyes
forrásútvonalakat mindhárom executable-ből ellenőrizetten eltávolítja a
Swift prefix mapping. Az iOS Release regressziós build is sikeres, aláírás
nélkül; nem készülékteszt.

- 44/44 JavaScript-teszt, köztük az időtúllépésből hamis blokkolási sikert
  kizáró két oldalteszt.
- OnboardingState: 5 célzott teszteset. Megszakítás/folytatás, kapcsolóállapot
  önmagában nem kész, hiányzó/visszavont engedély, korábbi és hibás mentés.
- NativeRuleActivation: 4 tesztcsoport; párhuzamos kérés, generációcsere,
  sikertelen/időtúllépő reload és explicit újrapróbálás.
- ProtectionSelfTestHarness: korai megszakítás, kéréskorlát, fix útvonal,
  pozitív kontrollok, hibás jelentés, késői blokkolandó kérés, elavult runtime,
  egyező generáció és szabályos befejezés/leállítás.
- 97 507 szabály teljes WebKit-fordítása és kontrollos natív működése;
  a helyi szabályok deltaként +2 natív és +1 fejlett szabályt adtak, korábbi
  szabály eltávolítása nélkül.
- A fejlett localhost-szabály tényleges FilterEngine-lekérése és a pontos
  `:has-text` hatás WebKitben, normál és szigorú CSP mellett sikeres.
- Telepítő regresszió: 5/5. A csomagolás a két installer scriptet, a pontos
  telepítési útvonalat és a kibontott payloadot ellenőrzi.
- `PYTHONOPTIMIZE=1` mellett is elutasítja a verifier az eltérő csomagtartalmat.
- Az első két képernyő külön UI-előnézetben vizuálisan és CUA-val ellenőrizve.
  Ez nem a telepített új app vagy a Safari végponttól végpontig tartó próbája.

Ebben a build 5 fázisban a kiadás előtti élő validáció még függőben volt. A
beágyazott licencjegyzéket és a célzott szűrőket tartalmazó későbbi build 7
telepítési és onboarding-próbája ezt a részt felváltotta. Az azonos build
újratelepítése, a nyilvános v0.0.1→v0.0.2 frissítés, a profil-, privát- és
engedély-visszavonási mátrix továbbra is nyitott. Nincs Developer ID vagy
notarizálás.

A build 5 elkülönítetten ellenőrzött, de a licencjegyzék javítása előtti
csomagjának neve `AdBlocker-0.0.2-build5-macOS-arm64.pkg` volt; a régi helyi
telepítők takarításakor ezt a példányt is eltávolítottuk.
SHA-256: `aa5824a47fa076a1c23bac6b03d64d1647d096fc0fe281a3b384361b35ad925a`.
A build 7 aktuális artefaktuma és élő eredménye a dokumentum elején szerepel.
Az alábbi build 4 bejegyzések történetiek.

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

A Safari az automatizált natív bekapcsolást elutasította; a felhasználó
kézzel engedélyezte. Ezután a telepített build 4 mindkét rétege ON állapotot
adott, a háttér-host nulla saját ablakkal sikeres állapotot rögzített és kilépett.
A helyi Safari-oldal mind a négy ellenőrzése sikeres volt: hasznos script,
natív hálózati blokkolás, natív reklámdoboz-elrejtés, webes content script.
A natív csomagolt SHA megegyezett a visszaigazolt generációval.

A következő gombkattintást a Computer Use az aktuális böngésző-URL korlátozása
miatt leállította; ezt nem próbáltuk más eszközzel megkerülni. A hasznos gomb
korábbi web-only próbája sikeres volt; új ON/ON gombkattintást nem állítunk.
Ez ezen a Macen elvégzett fejlesztői telepítési próba, nem más gépekre vagy
notarizált, felügyelet nélküli telepítésre vonatkozó igazolás.

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
python3 code/tests/installer_postinstall_test.py
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
  A késleltetett felismerést a későbbi build 3 javította; a végső helyi
  Safari-próba a build 4-gyel sikeres.
- A v0.0.2 élő negatív próbája sikeres: Safari unsigned OFF mellett a
  háttér-host nulla saját ablakkal futott, SFErrorDomain 1 hibát rögzített,
  és nem állított sikeres aktiválást. Dupla indítás után is kilépett.
  A pozitív, telepítés utáni helyi próba később a build 4-gyel sikeres lett.
  A csomag nem Developer ID-aláírt és nem notarizált.
- A v0.0.2 build 7 ad-hoc macOS teszt-előkiadás; Developer ID-aláírás és
  notarizálás nincs.
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
