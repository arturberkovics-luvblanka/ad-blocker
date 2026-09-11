# Ad Blocker beállítása Macen

A v0.0.2 build 5 forrásában új, látható első beállítás készül. A GitHubon
korábban közzétett v0.0.1 csomag ettől eltér. A build és a helyi tesztek nem
helyettesítik a Developer ID-kiadás és a Safari-újraindítás ellenőrzését.

## Első telepítés és megnyitás

1. Telepítsd a macOS `.pkg` csomagot. Az app helye az Alkalmazások mappa,
   pontosan `/Applications/Ad Blocker.app`.
2. A telepítő megkísérli elindítani az első beállítást. Ha az ablak nem
   jelenik meg, nyisd meg az **Ad Blocker** appot az Alkalmazásokból.
3. Az **Így működik** lépés bemutatja a két védelmi réteget és a korlátokat.
4. A **Bekapcsolás** lépésből nyisd meg a Safari beállításait, és kapcsold be
   az **Ad Blocker – Szűrőlista**, majd az **Ad Blocker – Oldalellenőrzés**
   bővítményt. A kapcsolókat a Safari engedélyezi; az app nem állítja át őket.
5. A **Webhelyek** lépés szerint add meg az Oldalellenőrzés tartós
   hozzáférését. Ha csak egyes oldalakat engedélyezel, a fejlett védelem
   hatóköre ezekre korlátozódik. A profilokat és a privát böngészést külön
   ellenőrizd.
6. A **Működéspróba** saját tesztoldalt nyit a Safariban. Az app csak friss,
   a csomagolt motorhoz tartozó eredményt fogad el. A sikertelen próba vagy
   időtúllépés nem kész beállítás.
7. Siker után a **Befejezés** bezárja az appot. A szűrés a Safariban fut;
   a korábban megnyitott oldalakat frissítsd.

Az appból indított próba helyben fut, külön terminál és Python-szerver nélkül.
A tesztoldal csak a működéspróba idején érhető el. A siker a tesztelt Safari-
környezet alapműködését igazolja, nem minden weboldal reklámmentességét.

## Helyi, még aláíratlan tesztcsomag

Ha a felület **Helyi fejlesztői tesztverzió** jelzést mutat, a Safari külön
fejlesztői engedélye szükséges lehet. Safari → Beállítások → Speciális:
webfejlesztői funkciók megjelenítése, majd Fejlesztő → **Allow unsigned
extensions**. A kapcsolót és az esetleges rendszerhitelesítést kézzel kell
kezelni. Ezután az appban válaszd az **Új ellenőrzés** gombot.

Ez a fejlesztői engedély Safari-kilépéskor visszaáll. A rendes terjesztési
aláírás hiányát az onboarding nem oldhatja meg. Az Apple fejlesztői béták
letöltése ingyenes regisztrációval is elérhető; a Developer ID és notarizálás
külön, fizetős programhoz tartozik.

## Későbbi használat és frissítés

Az app kézi megnyitásakor rövid állapotképernyő jelenik meg. Látható a két
réteg aktuális kapcsolója és a legutóbbi sikeres próba időpontja. Új buildhez
vagy új motorhoz új próba ajánlott. Az útmutató bármikor újranyitható.

A már ellenőrzött, azonos build automatikus beállítása jó kapcsolóállapotnál
csendben kilép. Másik build vagy javítandó állapot esetén az állapotképernyő
jelenik meg; a teljes bevezetőt nem kell automatikusan újrakezdeni.
A puszta kapcsolóállapot nem igazolja az aktuális webhelyengedélyt.

Ha az appot a beállítás közben bezárod, megőrzi a lépést. Nincs állandó
háttérfigyelő, így a teljesen kikapcsolt bővítmény nem tud azonnal jelzést
küldeni. Hiba esetén nyisd meg az appot vagy a Safari bővítménymenüjét.

## Fejlesztői ellenőrzés

A telepítő és a kiadási aláírás részletei: [INSTALLER.md](INSTALLER.md).
Az onboarding állapotkezelése és elfogadási kapui: [ONBOARDING.md](ONBOARDING.md).
A tényleges teszteredmények: [TESTING.md](TESTING.md).

A telepített app `--diagnose` módja nem nyit ablakot és nem indít működéspróbát;
a két réteget, a buildet és a legutóbbi igazolt onboardingot olvassa vissza.
A korábbi fejlesztői fixture továbbra is elérhető a `serve_fixture.py`
scripttel a `127.0.0.1:8765` címen; ez nem az új felhasználói próba előfeltétele.

## iPhone/iPad

Az iOS build jelenleg fordítási ellenőrzés. A Mac onboardingjának elkészítése
nem jelenti kész, készüléken igazolt mobilváltozat meglétét.
