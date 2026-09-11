# macOS első beállítás — v0.0.2 build 5 fejlesztés

Az új beállítási felület fejlesztés alatt van. Ez a leírás a forrásban készülő
viselkedést rögzíti; a telepített build 4 korábbi Safari-próbái nem igazolják
az új build végponttól végpontig tartó működését.

## Felhasználói út

1. **Így működik:** a natív szűrőlista és a fejlett webes védelem bemutatása;
   a Safari tényleges bővítménynevei, a hozzáférés oka és a verzió korlátai.
2. **Bekapcsolás:** két külön állapotkártya, a megfelelő Safari-beállítást
   megnyitó gombok, a natív lista visszaigazolt aktiválása. Ismeretlen vagy
   kikapcsolt rétegnél nem lehet sikeres beállítást állítani.
3. **Webhelyek:** tartós vagy korlátozott hozzáférés, webhelykivételek,
   Safari-profilok és privát böngészés magyarázata. A felhasználó adja meg az
   engedélyt. A továbblépés nem bizonyít minden webhelyre adott hozzáférést.
4. **Működéspróba:** az app saját, rövid életű loopback tesztoldalt indít és
   azt Safariban nyitja meg. Külön ellenőrizendő a hálózati szűrés, a natív
   elrejtés, az aktuális webes réteg, a fejlett próba és a hasznos kontroll.
5. **Kész:** csak sikeres működéspróba és újra lekérdezett, megfelelő Safari-
   állapot után menthető. A kész felirat a tesztelt környezet alapműködését
   jelenti, nem minden weboldal reklámmentességét.

Az onboarding lépése mentett, ezért az app bezárása után folytatható.
A beállítás befejezése külön, verzióhoz és natív listához kötött korábbi
tesztadat. Ez nem írhatja felül az aktuális Safari-állapotot.

## Indítási viselkedés

- Első kézi indítás és első telepítés utáni `--setup`: látható beállítás.
- Már befejezett beállítás után kézi megnyitás: rövid állapotképernyő,
  működéspróba és újranyitható útmutató.
- Már befejezett beállítás utáni automatikus `--setup`: friss Safari-
  állapotlekérdezés és szükség szerinti natív listaaktiválás. Jó állapotnál
  saját ablak nélkül kilép; ellenkező esetben az állapotképernyő segít.
- Ablakbezárás vagy kilépés: a helyi teszt és a várakozás leáll, a host kilép.
- Nem települ állandó figyelőfolyamat. Ha az app nem fut és a bővítményt
  kikapcsolják, nincs azonnali háttérértesítésre vonatkozó ígéret.

## Aláírás

A helyi ad-hoc build külön jelzi, hogy a Safari fejlesztői engedélye teljes
Safari-kilépéskor visszaállhat. Ezt a sikeres önteszt nem oldja meg.
A normál Developer ID-kiadás és a telepítési életciklus végső tesztje külön
követelmény. A fejlesztői béta letöltési jogosultság nem bizonyít fizetős
Apple Developer Program-tagságot.

## Elfogadási vizsgálatok

| Követelmény | Szükséges bizonyíték |
| --- | --- |
| Első telepítésből végigjárható beállítás | Valódi pkg, új felhasználói környezet, Safari és app UI |
| Megszakítás után folytatás | Bezárás/újranyitás több lépésből, beállításvesztés nélkül |
| Ismeretlen vagy visszavont engedély | Negatív állapotpróba; nincs hamis kész állapot |
| Önálló működéspróba | Beépített kiszolgáló; nincs Python, külső szolgáltatás vagy fejlesztői szerver |
| Önteszt hitelessége | Pozitív kontrollok, generációegyezés, sikertelen/hiányzó probe kezelése |
| Csendes későbbi működés | Host bezárása, kézi megnyitás és automatikus frissítési indítás |
| Frissítés | Azonos Team és bundle ID-k, valódi A→B pkg, új lista és régi beállítások |
| Tartós Safari-működés | Developer ID build, legalább 5 Safari-kilépés/újraindítás |
| Tartós gépújraindítási működés | Developer ID build, legalább 3 újraindítás/bejelentkezés |
| Profil és privát böngészés | Külön kapcsoló- és funkcionális próbák |
| Hibás telepítés és helyreállítás | Megszakított/hibás csomag negatív teszt és ellenőrzött visszaállítás |

Minden végpontpróba mellé appverzió, build, OS/Safari-verzió, a ténylegesen
telepített csomag és az ellenőrzés időpontja tartozzon. Fordítás, egységteszt,
külön UI-előnézet és WebKit-harness nem helyettesíti a valódi Safari-próbát.
