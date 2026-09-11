# Beállítás

A kiadott macOS csomag telepítését az [INSTALLER.md](INSTALLER.md) írja le.

Forrásból helyi tesztbuildhez:

```sh
bash code/scripts/build.sh macOS
bash code/scripts/install-macos.sh
python3 code/scripts/serve_fixture.py
```

A fejlesztői install script `~/Applications/Ad Blocker.app` alá telepít.
A publikus pkg `/Applications` alá telepít; egy gépen egy aktív példányt használj.
A Safari két bővítményét és webhelyengedélyeit kézzel kell bekapcsolni.
A helyi fixture címe `http://127.0.0.1:8765/`. A natív hálózati tiltás, az
elrejtés, a content-script jel és a hasznos gomb külön ellenőrzés.

A Safari aláíratlan fejlesztői bővítmények engedélyét újraindítás után ismét
kérheti. A helyi próba nem helyettesíti a Developer ID-aláírt kiadást.

## iPhone/iPad fejlesztés

`bash code/scripts/build.sh iOS` aláírás nélküli fordítási ellenőrzés.
Eszköztelepítéshez saját megfelelő Apple-aláírás/provisioning kell; a
generált projekt az iPhone és iPad eszközcsaládot is tartalmazza.
A generátor a manuálisan átírt Xcode-beállításokat új buildnél felülírja,
ezért a tartós változtatásokat a `scripts/generate_project.py` fájlban végezd.
