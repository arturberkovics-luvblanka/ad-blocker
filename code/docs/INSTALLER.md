# macOS telepítő

## Csomag készítése

A `package-macos.sh` egy már elkészült és érvényes `Ad Blocker.app` csomagból
szabványos macOS component package fájlt készít. A verziót az
`extension/manifest.json` fájlból olvassa, és megköveteli, hogy az megegyezzen
az alkalmazás `CFBundleShortVersionString` értékével.

```bash
bash code/scripts/package-macos.sh \
  "/teljes/útvonal/Ad Blocker.app"
```

A v0.0.2 alapértelmezett kimenete:

```text
builds/macOS/AdBlocker-0.0.2-macOS-arm64.pkg
```

Második argumentummal külön kimeneti mappa adható meg. A script:

- ellenőrzi az app és a beágyazott extensionök kódaláírását;
- csak tiszta `arm64` bundle-öket fogad el;
- staging payload root alatt pontosan az `Applications/Ad Blocker.app`
  útvonalat készíti elő;
- a natív `pkgbuild --root` és `--component-plist` útvonalat használja;
- minden bundle-nél kikapcsolja a relocation- és verzióellenőrzést,
  bekapcsolja a szigorú bundle identifier ellenőrzést, és teljes
  bundle-cserét kér;
- pontosan egy, végrehajtható `postinstall` scriptet csomagol be;
- `pkgutil --expand-full` segítségével ellenőrzi a metadata-, script- és
  payload-adatokat, köztük a postinstall forrással való bytepontos egyezését;
- elutasítja a kibontás után megmaradó AppleDouble vagy `.DS_Store`
  payloadfájlokat;
- ellenőrzi a kibontott app aláírását és összeveti a fájljait az eredeti
  appal;
- kiírja az elkészült `.pkg` SHA-256 értékét.

Meglévő, azonos nevű csomagot a script nem ír felül. Az Installer mindig az
`/Applications/Ad Blocker.app` útvonalra telepít, és nem helyezi át a korábbi
`~/Applications` fejlesztői példányt.

## Mit végez a postinstall?

A v0.0.2 egy szűk, best-effort háttérindítást használ, hogy a Safari
felismerhesse a containing appot. A script csak gyökérkötetre telepítéskor,
legalább 501-es aktív console user mellett indítja az exact
`/Applications/Ad Blocker.app` példányt a felhasználó saját környezetében:

```text
launchctl asuser UID sudo -u USER open -n -g ... --args --setup
```

Nincs rootként futó app-fallback. Hiányzó vagy nem megfelelő session, illetve
indítási hiba esetén a telepítés kézi appmegnyitást kér. A script nem kapcsol
be Safari-bővítményt, nem ad webhelyengedélyt, nem telepít tartós háttérsegédet,
és nem módosít Safari- vagy macOS-biztonsági beállítást.

## Jelenlegi aláírási korlát

A v0.0.2 helyi Release buildje ad-hoc aláírású. A `package-macos.sh` nem
választ ki és nem talál ki tanúsítványt. Az elkészült `.pkg` nincs Developer
ID Installer tanúsítvánnyal aláírva és nincs Apple által notarizálva.

A macOS azonosítatlan fejlesztőre figyelmeztethet vagy blokkolhatja a
megnyitást. Ha a rendszer felajánlja, a felhasználó a
**Rendszerbeállítások → Adatvédelem és biztonság** oldalon kézzel
engedélyezheti az adott telepítőt. A Gatekeepert és a SIP-et nem kell és nem
szabad kikapcsolni; a csomag nem törli a quarantine jelzőt.

A figyelmeztetés nélküli nyilvános terjesztéshez Developer ID Application és
Developer ID Installer aláírás, Apple-notarizálás és stapling szükséges. Ez a
folyamat még nem készült el.

## Telepítés és Safari

A v0.0.2 még nincs GitHub-kiadásként közzétéve. A kiadási artifact elkészülte
után a lépések:

1. Nyisd meg az `AdBlocker-0.0.2-macOS-arm64.pkg` fájlt, és telepítsd az
   alkalmazást az `/Applications` mappába.
2. A telepítő megkísérli a háttér-host egyszeri indítását. Az appnak nincs
   saját ablaka; szükség esetén megpróbálja megnyitni a Safari Extensions
   beállítást. Ha a Safari még nem ismeri az extensiont, ez is sikertelen lehet.
3. Ennél az ad-hoc tesztbuildnél előbb a Safari **Settings → Developer →
   Allow unsigned extensions** kapcsolóját kell kézzel engedélyezni. Ha a
   Developer lap hiányzik, az Advanced lapon engedélyezd a webfejlesztői
   funkciók megjelenítését. A rendszer hitelesítést kérhet, és a fejlesztői
   engedély Safari-kilépéskor visszaáll. Ezt a későbbi Developer ID-aláírás
   váltja ki; a telepítő nem állítja át helyetted.
4. Kézzel kapcsold be az **Ad Blocker – Szűrőlista** és az
   **Ad Blocker – Oldalellenőrzés** bővítményt.
5. A webes bővítménynek kézzel add meg a szükséges webhely-hozzáférést, majd
   töltsd újra a már nyitott oldalakat.
6. Ha a háttérindítás elmaradt, nyisd meg egyszer kézzel az
   `/Applications/Ad Blocker.app` alkalmazást. Saját ablak helyett ugyanazt a
   háttérbeállítást futtatja.

Az aktuális állapot helyi ellenőrzése:

```bash
"/Applications/Ad Blocker.app/Contents/MacOS/Ad Blocker" --diagnose
```

A diagnosztika kiírja a két Safari-réteg állapotát és a legutóbbi
háttérbeállítás eredményét; nem kapcsol be bővítményt és nem ad
webhelyengedélyt.

A Release build, a csomag szerkezeti ellenőrzése és a postinstall 4/4 unit
tesztje sikeres. Az élő unsigned-OFF próba nulla saját ablakkal és őszinte
hibaállapottal lezárult. A valódi `.pkg` telepítés és a felhasználói háttérindítás sikeres;
a pozitív, telepítés utáni Safari-próba még hátra van.
