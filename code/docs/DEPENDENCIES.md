# Függőségek és az első blokkolólista

Ellenőrzés dátuma: 2026-09-09. Ez mérnöki függőség- és licencleltár, nem jogi
szakvélemény.

## Döntés az első tesztverzióhoz

A host app futásidőben nem linkeli a SafariConverterLibet. A rögzített
`ConverterTool` buildeszköz előre elkészíti a Safari Content Blocker JSON-t.
A 2026-09-10-i fejlett integrációtól a Web Extension viszont linkeli a
FilterEngine és ContentBlockerConverter modulokat, és csomagolja az advanced
szabálylistát. PunycodeSwift, swift-psl és a Public Suffix List adatai így
futásidejű függőségek is. A swift-argument-parser továbbra is csak CLI-függőség.

A SafariConverterLib és a swift-psl `Package.swift` fájlja 2026-09-10-én helyi
csomagútvonalakra módosult. A forrásverziók változatlanok, a normál Xcode-build
ezeket a mellékelt forrásokat használja hálózati feloldás helyett. A módosítás
mindkét manifestben látható; az eredeti commitok alább szerepelnek.

A kiválasztott konverter a legutóbbi ellenőrzött kiadás, **SafariConverterLib
v4.3.0**, commit
[`7a2e93f0afa70479cc59985f332025236c3f0c39`](https://github.com/AdguardTeam/SafariConverterLib/commit/7a2e93f0afa70479cc59985f332025236c3f0c39).
A GitHub release oldal ezt v4.3.0-ként és legfrissebb kiadásként mutatta:
https://github.com/AdguardTeam/SafariConverterLib/releases/tag/v4.3.0.

## ConverterTool és tranzitív függőségei

| Komponens | Rögzítés | Licenc | Szerep |
| --- | --- | --- | --- |
| SafariConverterLib | v4.3.0, `7a2e93f0afa70479cc59985f332025236c3f0c39` | GPL-3.0-only | Konverter és CLI |
| PunycodeSwift | 3.0.0, `30a462bdb4398ea835a3585472229e0d74b36ba5` | MIT | Nemzetközi doménnevek |
| swift-argument-parser | 1.5.0, `41982a3656a71c768319979febd796c6fd111d5c` | Apache-2.0 | Csak a CLI argumentumai |
| swift-psl | 1.1.43, `7ccee9d576d4ca45219440e346f61117f44c816f` | MIT | Public suffix feldolgozás |
| Public Suffix List adat | `2025-07-09_15-23-09_UTC` | MPL-2.0 | A swift-psl bináris erőforrása |

Bizonyíték: a rögzített
[`Package.swift`](https://github.com/AdguardTeam/SafariConverterLib/blob/7a2e93f0afa70479cc59985f332025236c3f0c39/Package.swift)
három közvetlen csomagot nevez meg; a
[`Package.resolved`](https://github.com/AdguardTeam/SafariConverterLib/blob/7a2e93f0afa70479cc59985f332025236c3f0c39/Package.resolved)
a fenti három pontos commitot oldja fel. A swift-psl maga a PunycodeSwiftet
használja, tehát ez nem újabb külön függőség. Más futásidejű Swift-csomag nincs.

A SafariConverterLib gyökér LICENSE fájlja a GPL v3 szövege, de nem ad „vagy
újabb” engedélyt; az Extension `package.json` mezője is `GPL-3.0`. Ezért az
óvatos azonosítás **GPL-3.0-only**, nem GPL-3.0-or-later. A projekt
GPL-3.0-or-later licence a v3 feltételeinek választásával összefér vele. A
ConverterTool vagy kódjának terjesztésekor a forrást, a módosításokat és a teljes
licencszöveget elérhetővé kell tenni. A repository ezeket a `vendor/` alatt
mellékeli.

A swift-psl saját MIT LICENSE fájlja nem említi külön a beágyazott Public Suffix
List adatait. A frissítő script bizonyítja, hogy a bináris erőforrások a
`https://publicsuffix.org/list/public_suffix_list.dat` fájlból készülnek; annak
fejléce és a hivatalos repository LICENSE fájlja MPL-2.0. Emiatt az MPL szöveget
külön mellékeltük. Ez a felső szintű csomag leltárából könnyen kimaradt volna.

## A webes runtime 2026-09-10-i integrációja

Az upstream Extension `pnpm-lock.yaml` fájlja rögzíti az
`@adguard/extended-css` 2.1.1 és `@adguard/scriptlets` 2.4.2 csomagokat.
Mindkettő GPL-3.0 licencű; teljes licencük a `vendor/licenses/` mappába és a
Mac host erőforrásai közé kerül. A buildeszközök szintén a lockfile-ból
érkeznek. A Scriptlets 2.4.2 a `google-ima3-dai` IMA DAI mockot is tartalmazza;
erre a generált Base lista három szabálya támaszkodik. Az upstream SafariConverterLib
4.3.0 eredetileg 2.3.1-et nevez meg, ezért ez célzott vendor-függőségfrissítés.
A függőségek telepítése `pnpm install --frozen-lockfile --ignore-scripts`
paranccsal történt, külső install scriptek futtatása nélkül.

A `scripts/build-extension-runtime.mjs` két helyi runtime-bundle-t és egy
kicsi, négy felülvizsgált szabályra korlátozott `early-youtube.js` fájlt készít; a nyers JS-szabályokból fordításkor függvénytérképet generál a
Safari MAIN-world `scripting` útjához. Nincs futás közben letöltött kód vagy
`eval`-alapú szabályfordítás. A `webextension-polyfill` import külsőként marad,
és a Safari natív `browser` objektumához kapcsolódik; polyfill kód nem kerül
a csomagba. A rendes Xcode-build a már mellékelt bundle-okat másolja, ezért
nem igényel Node-csomagtelepítést vagy hálózatot.

## Szűrőadat

A bemenetek sorrendben a hivatalosan kiszolgált **AdGuard Base filter 2.4.89.22**,
majd a magyar oldalakat kiegészítő **Hufilter for AdGuard 202609081912**, végül a
szűk, helyi kiegészítések. Az AdGuard Base frissítési ideje
2026-09-09 12:20:56 UTC:
https://filters.adtidy.org/extension/safari/filters/2.txt. A befagyasztott fájl
SHA-256 értéke
`f55c87d2a6c08149f306fe62a8a3f42b5edc0663c897a3ae25a8d7c6a794fb4e`.
A fájl fejléce szerint ez „EasyList + AdGuard English filter”, és az
AdGuardFilters GPLv3 licencére hivatkozik.

Az AdGuardFilters `package.json` pontos SPDX mezője `GPL-3.0-only`; a teljes
licenc: https://github.com/AdguardTeam/AdguardFilters/blob/master/LICENSE. Az
EasyList hivatalos licencoldala GPL-3.0-or-later vagy CC-BY-SA-3.0-or-later
választást enged, és EasyList-attribúciót kér, ha szükséges:
https://easylist.to/pages/licence.html. A GPL-alapú termékhez a GPL út illik.

A Hufilter rögzített kiadása a `1832f017a963e4b96183e7865670a5cdd91ce263`
`gh-pages` commitból származik; lista-verziója `202609081912`, frissítési ideje
2026-09-08 19:12 UTC, SHA-256 értéke
`211b63f31366a3e70bca1cb764356628eefa62be08a896ee4165f856c652df1b`.
A kiadást a `9a62d00504244bcbab1051e49acd5240997332a6` forrás commit állította elő.
Forrás: https://raw.githubusercontent.com/hufilter/hufilter/1832f017a963e4b96183e7865670a5cdd91ce263/hufilter-adguard.txt . A Hufilter CC BY 4.0 licencű;
a teljes szöveg a `filters/LICENSE-Hufilter-CC-BY-4.0.txt` fájlban van.

A `filters/local-rules.txt` saját, hash-elt kiegészítés. A 24.hu szabályai a
megfigyelt, `m-articleWidget__tag`-gel jelölt reklámsort, valamint a 2026-09-11-i
FELIX- és OkAuchan-kampány pontos URL-jű kártyáját rejtik. Az utóbbi kettőt nem
általánosítjuk minden hasonló URL-re vagy jövőbeli kampányra. A hvg.hu szabálya
a related-widget külön reklámjelölős kártyáját rejti úgy, hogy a címke nélküli
szerkesztői és az eltérő partnercímkés ajánló megmarad; külön szabály rejti a
saját `.sidebar-brandlab` reklámblokkot. Ezek Safari-natív CSS-szabállyá
alakulnak. Az Allrecipes helyi szabálya kizárólag a megfigyelt, site-wide
MyRecipes app-kampány bannergyökerét rejti; a normál „Get the app” navigációt
és a receptmentés vezérlőit nem célozza.

## Konverziós eredmény

A v0.0.1 csomag 97 505 natív szabályt (két saját sentinellel), 12 076 fejlett
szabályt és 223 nyilvántartott konverziós hibát tartalmaz. A pontos forrás-,
konverter- és kimeneti hash-ek a `filters/generated/conversion-report.json`
fájlban vannak. A fejlett szabályokhoz a Web Extension és oldalengedély kell.

A v0.0.2 teszt-előkiadási jelölt 97 507 natív szabályt, köztük három
projekt-sentinelt, valamint 12 077 fejlett szabályt és ugyanazt a 223
nyilvántartott konverziós hibát tartalmazza. A kiadási taghoz mindig a benne
levő `conversion-report.json` pontos hash-ei tartoznak.

Az öt új 24.hu/hvg.hu/Allrecipes kozmetikai szelektor a forrás- és a
Safari-kompatibilis szabályok számát öttel növeli. A konverter ezeket a három
domain már létező kozmetikai JSON-objektumába vonja össze, ezért a végleges
97 507-es JSON-objektumszám és a 12 077-es fejlett darabszám nem változik.

A konverter helyi popup-javítása megtartja a dokumentumtiltást, és hozzáadja
a Safari popup erőforrástípust; kevert típusoknál külön kezeli a child-frame
ágaikat. A saját listában célzott 24.hu, hvg.hu és Allrecipes kozmetikai
javítások, a media.net támogatott script/XHR-része és három ekvivalens
IP-popup regexprojekció is szerepel.

A bináris konvertereket forrásból kell újraépíteni. A build és az explicit
helyi binárisokat használó konverzió: [BUILDING.md](BUILDING.md). A lista
input- és multiset-hash ellenőrzése megmarad; a multiset önmagában nem
bizonyít sorrendi egyezést. Új listát teljes WebKit-próbával is ellenőrizni kell.

## Nyilvános terjesztés

A közvetlen GitHub-forrás és nyilvános letöltés a GPL-kötelezettségek teljesítésére
átlátható út, ha a kiadott build mellett a teljes megfelelő forrás, buildscript,
licencek és módosítási dátumok is elérhetők. Az app GPL-3.0-or-later jelölése
összefér a GPL-3.0-only konverterrel a GPL v3 választásakor.

Az Apple App Store feltételeinek és a GPL terjesztési feltételeinek együttélése
nem tekinthető ezzel lezártnak. App Store kiadás előtt külön jogi ellenőrzés kell;
ez nem akadálya a helyi tesztnek vagy a nyilvános forrású, közvetlenül letölthető
Mac buildnek.

A korai YouTube-szabályok policy-je generációhoz kötött: listafrissítéskor a
`extension-runtime/early-youtube-policy.mjs` review-zárját csak a szabályok
és kivételek újraellenőrzése után szabad frissíteni. A fájl hash-elt bemenet,
mindhárom generált JS hash-ellenőrzött kimenet. A scope kizárólag a felső
`www.youtube.com` dokumentum pontos `/watch` útvonala. A Scriptlets saját
`source.uniqueId` mechanizmusa akadályozza a korai/késői dupla alkalmazást.

## Mellékelt preferred source

A `vendor/upstream-sources` két pontos commithoz kötött JS-forrásarchívumot,
licenceket, hash-jegyzéket és a PSL eredeti forrásadatát tartalmazza.
A mellékelt ResourceBuilderrel újragenerált három PSL-trie bájtonként
egyezik a csomagolt adatokkal. Részletek: `vendor/upstream-sources/README.md`.
