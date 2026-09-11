# Ad Blocker 0.0.2 — források és licencek

A saját alkalmazáskód GPL-3.0-or-later. Copyright (C) 2026 Ad Blocker contributors. Teljes licenc: az alkalmazás Resources/LICENSE fájlja.

A csomagolt szabálylista az AdGuard Base filter 2.4.89.22 (2026-09-09 12:20:56 UTC) és a Hufilter for AdGuard 202609081912 (2026-09-08 19:12 UTC) átalakított része. Az AdGuard Base forrása: https://filters.adtidy.org/extension/safari/filters/2.txt . Az AdGuard Base EasyList és AdGuard English szabályokat tartalmaz. AdGuardFilters: GPL-3.0-only; EasyList esetében a GPL-3.0-or-later licencutat használjuk. Az eredeti szerzői és licencfejlécek a projekt `code/filters/adguard-base.txt` fájljában megmaradtak.

A Hufilter for AdGuard rögzített kiadása: https://raw.githubusercontent.com/hufilter/hufilter/1832f017a963e4b96183e7865670a5cdd91ce263/hufilter-adguard.txt . A kiadást a `9a62d00504244bcbab1051e49acd5240997332a6` forrás commit állította elő. Copyright Hufilter Contributors. Licenc: Creative Commons Attribution 4.0 International (CC BY 4.0); teljes szöveg: Resources/LICENSE-Hufilter-CC-BY-4.0.txt.

Konverter és futásidejű fejlett motor: AdGuard SafariConverterLib 4.3.0, commit 7a2e93f0afa70479cc59985f332025236c3f0c39, GPL-3.0-only. https://github.com/AdguardTeam/SafariConverterLib

A Web Extension futásidejű Swift-függőségei: PunycodeSwift 3.0.0 (MIT), swift-psl 1.1.43 (MIT), Public Suffix List adatok (MPL-2.0). A swift-argument-parser 1.5.0 (Apache-2.0) csak a CLI buildfüggősége. A SafariConverterLib és swift-psl csomagmanifestje 2026-09-10-én a mellékelt helyi forrásokra lett átállítva.

A webes runtime az upstream Extension forrásból készül: @adguard/extended-css 2.1.1 és @adguard/scriptlets 2.4.2, GPL-3.0. A Scriptlets 2.4.2 célzott vendor-frissítés a `google-ima3-dai` IMA DAI mock támogatásához. Források: https://github.com/AdguardTeam/ExtendedCss és https://github.com/AdguardTeam/Scriptlets . A build a rögzített lockfile-t használja; a nyers JS-szabályokból előre regisztrált függvények készülnek. A böngésző saját `browser` API-ját használjuk, webextension-polyfill kód nem kerül a bundle-ba. A teljes licencszövegek a Resources/licenses mappában vannak.

A kiadás teljes forrása, a módosított függőségek és buildeszközök: https://github.com/arturberkovics-luvblanka/ad-blocker/tree/v0.0.2 . A webes motorok eredeti forrásarchívumai és a Public Suffix List forrásadata a code/vendor/upstream-sources mappában található.

Konverziós korlát: a 12 077 fejlett szabály a külön webes motort és webhelyengedélyt igényli; 223 konverziós hibát a forrásprojekt külön naplóban tart nyilván. A Hufilter 17 hibája közül a 24.hu `$$script[tag-content="a2blckLayer"]` szabály is kiesik, ezért ez a speciális anti-adblock beavatkozás nem tekinthető működőnek. A végleges natív lista 97 507 szabályt tartalmaz, köztük három projekt-sentinel szabályt. A szabályok kézbesítése nem igazolja minden beavatkozás sikerét vagy a teljes reklámmentességet. Gépi jelentés: Resources/conversion-report.json.
