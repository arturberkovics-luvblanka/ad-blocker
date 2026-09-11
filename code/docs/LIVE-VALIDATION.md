# v0.0.2 build 7 — élő validáció

Aktuális állapot: 2026-09-11, macOS 27 beta `26A5425a`, Safari 27. A vizsgált
app `0.0.2 (7)`, helyi ad-hoc aláírással; Developer ID-aláírás és notarizálás
nincs.

Az élő mátrix tíz webhelyet, öt célzott szűrőjavítást és három YouTube-videót
vizsgált. Az alábbi állítások kizárólag ezekre a konkrét próbákra vonatkoznak.

## Igazolt

- A `AdBlocker-0.0.2-build7-macOS-arm64.pkg` SHA-256 értéke
  `6e64fc25d88a87e3459e2074a749505c86aecbba76d4bfff858fb90c1323ea21`.
- A macOS Installerrel végzett build 5 → build 7 frissítés sikeres. A receipt
  verziója `0.0.2.7`; a telepített app `verify_macos.py` ellenőrzése sikeres,
  és bájtszinten egyezik a végleges Release appal.
- Az app mindkét Safari-réteget bekapcsoltként látja. A build 5 régi
  öntesztjét helyesen elavultnak minősítette, majd az új build 7 önteszt mind
  az öt ellenőrzése sikeres lett, és az onboarding befejezhetővé vált.
- A végleges app `--setup` indítása 0-s kilépési kóddal, 0,65 másodperc alatt,
  saját ablak nélkül fejeződött be. A friss diagnosztika mindkét réteget ON
  állapotúnak és az új natív listát visszaigazoltnak mutatja.
- Az élő diagnosztika a build 7-hez köti a
  `1b150ecfd69c3af111042b0f229589ea5d01aa395a87164bc53f9fb863917554`
  natív generációt, a
  `6e45fc354371732ec243cb4b5b205b31a9fc8d219e1970bf021047c1f57b9b02`
  fejlett generációt és a
  `660fc08c71affaaa6ff789001f018ce3c406b3de8c45aa00feffb3127f77e743`
  runtime revisiont.
- A Safari-regisztráció auditja mindkét extensionazonosítóhoz pontosan egy,
  az `/Applications/Ad Blocker.app` alatti plugint talált; fejlesztői
  duplikátum nincs.
- A hvg.hu friss újratöltésében hét új kampány reklámkártyája egyaránt
  `display:none`, nulla magasságú lett, miközben öt normál ajánlókártya
  `display:block` és 152,953125 pontos magasságú maradt. A vizuális rácsban
  csak az öt rendes kártya látszott, reklámhelyek nélkül; a BrandLab is rejtett.
  Ez a telepített build 7 célzott regressziós eredménye, nem teljes webes
  garancia.
- Az Allrecipes friss újratöltésében a sárga MyRecipes-promóció eltűnt, a
  normál „Get the MyRecipes app” navigáció és a „Save Recipe” megmaradt. A
  2× adagolás ismét helyes értékeket adott, és a receptvideó működött.
- A 24.hu friss újratöltésében a kétszer renderelt OkAuchan sidebar-linkek
  teljes `li` konténere és a FELIX-link teljes `article` konténere egyaránt
  `display:none`, nulla magasságú lett. Kontrollként 14 másik
  `.m-nonstopWidget__item` és 155 másik `article.m-articleWidget__wrap`
  magassága nulla fölött maradt. A címlap normál képei és címei rendben
  megjelentek, és a fejlécjelölős előfizetői cikkek megmaradtak.
- A YouTube kontrollos mintavideója a telepített build 7-tel sikeres. Azonos,
  bejelentkezett Safari-környezetben, a felhasználó szerint Premium nélkül, a
  youtube.com natív szűrőjét kikapcsolva és a webes bővítményt megtagadva a
  `VTLnDqjfRZQ` videó friss lapján 6 másodperces Old Spice/P&G „Szponzorált”
  reklám jelent meg `2/2` jelzéssel, továbbá P&G companion és külön MotoGP
  szponzorált oldalsáv. A két réteg visszakapcsolása és ugyanazon videó teljes
  újratöltése után a készítői tartalom és reklámmentes oldalsáv látszott. A
  videó 389,8975-ről 516,7553 másodpercre haladt, lejátszás közben; a saját
  runtime-revízió négy guardja jelen volt a `Window.prototype.toString` alatt,
  az `adSlots`, `playerAds` és `adPlacements` mező pedig `undefined`. Ez egy
  kontrollos mintavideó eredménye, nem teljes YouTube-garancia. A korábbi
  F1-videó 0:08-ról 2:23-ra haladása igazolt, teljes végignézése nem.
- Ugyanezen YouTube-lapon egy normál ajánlókártyára kattintva, teljes
  újratöltés nélkül megnyílt az `mfmdXPT7nAM&t=77s` MKBHD-videó. A készítői
  tartalom működött, platformhirdetés és companion nem jelent meg; az Inspector
  pontos URL-t, `paused:false`, `ad-showing:false` állapotot és 800,88496
  másodperces lejátszási pozíciót mutatott. A 77 másodperces kezdéstől 899
  másodpercig tartó előrehaladás és a következő oldal működése bizonyított. A
  videót nem néztük végig; a végén kézzel szüneteltetve 14:59/30:50 és működő
  Play gomb látszott.

Helyi bizonyítékok: `builds/releases/v0.0.2/build7/verification.json`,
`builds/logs/v002-build7-live-onboarding-diagnostics.json` és a végleges
`builds/logs/v002-live-safari-matrix.json`; a csendes indítás külön állapota a
`builds/logs/v002-build7-after-quiet-setup.json` fájlban van.

## Nem tesztelt ebben a kiadási körben

- Azonos build újratelepítési/helyreállítási próba.
- A nyilvános v0.0.1-ről induló tiszta frissítési út; a ténylegesen elvégzett
  frissítés build 5 → build 7 volt.
- Developer ID-val aláírt és notarizált kiadás teljes Safari-kilépési,
  gépújraindítási, profil- és privát böngészési életciklusmátrixa.
- Videóba szerkesztett szponzoráció felismerése vagy eltávolítása. A YouTube-
  eredmények a platform által kiszolgált hirdetésekre vonatkoznak.

A kiadás pontos forrását a `v0.0.2` git tag rögzíti; a kiadáshoz mellékelt
`verification.json` a teljes commitazonosítót is tartalmazza.

A korábbi webes mátrix megfigyelései részben a build 5 alatt készültek. Ezek a
hibák feltárására alkalmasak, de a build 7 javításainak sikerét csak az új élő
visszateszt igazolja. A részletes történeti eredmények és korlátok:
[TESTING.md](TESTING.md).
