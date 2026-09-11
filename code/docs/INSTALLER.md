# macOS telepítő

## Csomag készítése

A `package-macos.sh` egy már elkészült és érvényes `Ad Blocker.app` csomagból
szabványos macOS component package fájlt készít. A verziót a
`extension/manifest.json` fájlból olvassa, és megköveteli, hogy az megegyezzen
az alkalmazás `CFBundleShortVersionString` értékével.

```bash
bash code/scripts/package-macos.sh \
  "/teljes/útvonal/Ad Blocker.app"
```

Az alapértelmezett kimenet:

```text
builds/macOS/AdBlocker-0.0.1-macOS-arm64.pkg
```

Második argumentummal külön kimeneti mappa adható meg. A script:

- ellenőrzi az app és a beágyazott extensionök kódaláírását;
- csak tiszta `arm64` bundle-öket fogad el;
- staging payload root alatt pontosan az `Applications/Ad Blocker.app`
  útvonalat készíti elő;
- a natív `pkgbuild --root` és `--component-plist` útvonalat használja;
- a staging másolatból kihagyja a Finder/resource-fork extended metadata
  adatait, és elutasítja az AppleDouble vagy `.DS_Store` payloadot;
- minden felismert bundle-nél kikapcsolja a relocation- és verzióellenőrzést,
  bekapcsolja a szigorú bundle identifier ellenőrzést, és teljes bundle-cserét
  kér;
- nem ad a csomaghoz preinstall vagy postinstall scriptet;
- `pkgutil --expand-full` segítségével ellenőrzi a metadata- és payload-adatokat;
- ellenőrzi a kibontott app aláírását és összeveti a fájljait az eredeti appal;
- kiírja az elkészült `.pkg` SHA-256 értékét.

Meglévő, azonos nevű csomagot a script nem ír felül.

Az explicit component beállítások miatt az Installer nem keresi meg és nem
írja felül a korábbi `~/Applications/Ad Blocker.app` fejlesztői példányt. A
payload mindig az `/Applications/Ad Blocker.app` útvonalra kerül. A
verzióellenőrzés az első `0.0.1` nyilvános kiadásnál ki van kapcsolva, ezért
egy ugyanazon a célútvonalon lévő korábbi tesztverzió nem teszi
kiszámíthatatlanná a telepítést. A bundle identifiernek ugyanakkor pontosan
egyeznie kell.

## Jelenlegi aláírási korlát

A jelenlegi fejlesztői gépen a `security find-identity -v -p basic` eredménye
`0 valid identities found`. A fejlesztői alkalmazás ad-hoc aláírású, a
`package-macos.sh` pedig nem választ ki és nem talál ki tanúsítványt. Az így
elkészült `.pkg` ezért nincs Developer ID Installer tanúsítvánnyal aláírva és
nincs Apple által notarizálva.

Ez első nyilvános tesztcsomagként használható, de a macOS azonosítatlan
fejlesztőre figyelmeztethet vagy blokkolhatja a megnyitását. Ha a rendszer
felajánlja, a felhasználó a **Rendszerbeállítások → Adatvédelem és biztonság**
oldalon kézzel engedélyezheti az adott telepítő megnyitását. A Gatekeepert és
a SIP-et nem kell és nem szabad kikapcsolni; a csomag nem törli a quarantine
jelzőt és nem módosít rendszerbiztonsági beállítást.

A figyelmeztetés nélküli nyilvános terjesztéshez később valódi Developer ID
Application és Developer ID Installer aláírás, majd Apple notarizálás és
stapling szükséges. Ez a folyamat nincs kész, és a jelenlegi csomagról nem
állítható, hogy notarizált.

## Telepítés és Safari

1. Nyisd meg az `AdBlocker-0.0.1-macOS-arm64.pkg` fájlt, és telepítsd az
   alkalmazást az `/Applications` mappába.
2. Indítsd el az **Ad Blocker** alkalmazást.
3. Nyisd meg a Safari **Beállítások → Bővítmények** oldalát.
4. Kézzel kapcsold be az **Ad Blocker – Szűrőlista** és az
   **Ad Blocker – Oldalellenőrzés** bővítményt.
5. A webes bővítménynek kézzel add meg a szükséges webhely-hozzáférést, majd
   töltsd újra a már nyitott oldalakat.

A `.pkg` csak az alkalmazást másolja az `/Applications` mappába. Nem kapcsolja
be a Safari-bővítményeket, nem ad nekik webhelyengedélyt, nem nyitja meg
automatikusan a felhasználó alkalmazását, és nem módosít Safari- vagy macOS-
védelmi beállítást.
