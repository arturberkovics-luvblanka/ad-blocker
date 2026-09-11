# Beállítás

A GitHubon jelenleg közzétett macOS csomag a v0.0.1. A fejlesztői ág v0.0.2
forrásában már elkészült az ablak nélküli háttérbeállítás, de ez a verzió még
nincs kiadva. A valódi `.pkg` telepítés és automatikus háttérindítás már
sikeres; a pozitív Safari-beállítás kézi rendszerengedélyek után igazolt.

A kiadott macOS csomag részletes leírása: [INSTALLER.md](INSTALLER.md).

## v0.0.2 macOS onboarding

A v0.0.2 host `LSUIElement` agent appként, saját ablak nélkül fut. Telepítés
után a postinstall megkísérli egyszer elindítani az aktív felhasználó
környezetében. Ha ez nem lehetséges, nyisd meg egyszer kézzel az
`/Applications/Ad Blocker.app` alkalmazást.

A host lekéri mindkét Safari-bővítmény állapotát. Szükség esetén egyszer
megnyitja a Safari **Beállítások → Bővítmények** oldalát, majd legfeljebb
120 másodpercig vár a késleltetett felismerésre és a felhasználói döntésre. Ezután:

1. kézzel kapcsold be az **Ad Blocker – Szűrőlista** és az
   **Ad Blocker – Oldalellenőrzés** bővítményt;
2. a webes bővítménynek add meg a kívánt webhely-hozzáférést;
3. töltsd újra a már nyitott oldalakat.

A host nem kapcsolhatja be automatikusan a Safari-bővítményeket, és nem adhat
webhelyengedélyt. Az aláíratlan fejlesztői buildhez a Safari külön fejlesztői
**Allow unsigned extensions** engedélye is szükséges lehet; ezt a csomag nem
módosítja, és a Safari újraindítása után ismét kérheti.

Ha a háttérfolyamat eredménye nem világos:

```bash
"/Applications/Ad Blocker.app/Contents/MacOS/Ad Blocker" --diagnose
```

Az eredmény tartalmazza a natív és webes réteg állapotát, valamint a legutóbbi
háttérbeállítás fázisát. Ismeretlen állapotot a host nem tekint sikernek.

## Forrásból helyi tesztbuild

```sh
bash code/scripts/build.sh macOS
bash code/scripts/install-macos.sh
python3 code/scripts/serve_fixture.py
```

A fejlesztői install script `~/Applications/Ad Blocker.app` alá telepít. A
publikus pkg `/Applications` alá telepít; egy gépen egy aktív példányt
használj. A helyi fixture címe `http://127.0.0.1:8765/`. A natív hálózati
tiltás, az elrejtés, a content-script jel és a hasznos gomb külön ellenőrzés.

A helyi próba nem helyettesíti a Developer ID-aláírt és notarizált kiadást.

## iPhone/iPad fejlesztés

`bash code/scripts/build.sh iOS` aláírás nélküli fordítási ellenőrzés.
Eszköztelepítéshez saját megfelelő Apple-aláírás/provisioning kell; a
generált projekt az iPhone és iPad eszközcsaládot is tartalmazza.
A generátor a manuálisan átírt Xcode-beállításokat új buildnél felülírja,
ezért a tartós változtatásokat a `scripts/generate_project.py` fájlban végezd.
