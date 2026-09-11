# v0.0.1 ellenőrzések

A verzió kiadási jelölése 0.0.1; a korábbi helyi prototípus 0.1.0 jelölését
egységesítettük. A natív szabálylista változatlan: 97 505 szabály, SHA-256
`508b0900171a9eb4a0e6b4367d33d4566851a6cdeea16fdb46cac00c020961a8`.

- Saját JavaScript-regressziók: 38/38 sikeres a 0.0.1 verzióval.
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

A helyi fixture saját tesztadatokat használ. Más blokkoló, Premium-előfizetés
vagy csak a reklám hiánya nem bizonyítja önmagában ennek az appnak a hatását.

## Nyitott korlátok

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
