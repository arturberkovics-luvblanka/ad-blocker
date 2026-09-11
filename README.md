# Ad Blocker

Nyílt forrású Safari reklámblokkoló macOS-re, közös iOS/iPadOS forrással.
A **v0.0.2 build 7** ad-hoc aláírású macOS teszt-előkiadás. A telepítés,
csomagegyezés, beépített Safari-önteszt, duplikátummentes regisztráció, három
célzott hibadomain és kontrollos YouTube-minta élő ellenőrzése sikeres.

[**macOS telepítő letöltése**](https://github.com/arturberkovics-luvblanka/ad-blocker/releases/download/v0.0.2/AdBlocker-0.0.2-build7-macOS-arm64.pkg) · [Kiadások](https://github.com/arturberkovics-luvblanka/ad-blocker/releases)

> Az első indítás vezetett beállítóablakot, a későbbi kézi megnyitás
> állapotképernyőt, az app pedig beépített helyi működéspróbát ad. A telepített
> build 7 mindkét Safari-réteggel teljesítette az öt ellenőrzést.

## Mit tartalmaz?

- Natív Safari-szűrés: 97 507 szabály, AdGuard Base, Hufilter és célzott kiegészítések.
- Külön Safari Web Extension a fejlett CSS- és scriptlet-szabályokhoz.
- YouTube-szabályok és korai videóreklám-adatvédelem.
- Popupblokkolás, működő oldalkivételek és a csomagolt lista automatikus betöltése.
- Valódi rétegállapotok és helyi ellenőrző oldal.

A build 7 élő mátrixa tíz webhelyet, öt célzott szűrőjavítást és három
YouTube-videót vizsgált. A pontos eredmények és a nem tesztelt esetek:
[élő validáció](code/docs/LIVE-VALIDATION.md). Az önteszt nem jelent minden
weboldalra vagy YouTube-hirdetésre szóló garanciát.
Automatikus sütielutasítás és internetes listafrissítés még nincs benne.
iPhone/iPad forrás és buildcél van; készülékes kiadás még nincs.

## Telepítés macOS-en

1. Töltsd le a `.pkg` fájlt a kiadásból, és nyisd meg a macOS Installerrel.
2. A telepítő az `/Applications/Ad Blocker.app` helyre másolja az appot.
3. Az ad-hoc tesztkiadáshoz engedélyezd kézzel a Safari **Developer → Allow
   unsigned extensions** kapcsolóját. Teljes Safari-kilépés után ezt újra meg
   kellhet tenni.
4. Nyisd meg az appot, majd engedélyezd mindkét Ad Blocker-bővítményt a Safari
   beállításaiban. A webes bővítménynek külön oldalengedély is kell.

**Aláírás:** ez a kiadás ad-hoc aláírású, nincs Developer ID-aláírás vagy
Apple-notarizáció. A macOS és a Safari kézi jóváhagyást, illetve a Safari
helyi, aláíratlan bővítményekhez tartozó fejlesztői engedélyét kéri.
A telepítő nem módosít biztonsági vagy böngészőengedélyeket.
Részletes lépések: [Telepítés](code/docs/INSTALLER.md).

## Fordítás forrásból

Apple Silicon Mac, teljes Xcode (Swift 6 vagy újabb) és Python 3 szükséges.
A kiadás macOS 27 / Xcode 27 környezetben készült. A projekt minimuma
macOS 14, de régebbi rendszereken nincs kiadási teszteredmény.

```sh
git clone https://github.com/arturberkovics-luvblanka/ad-blocker.git
cd ad-blocker
bash code/scripts/build.sh macOS Release
```

A normál appbuild a mellékelt forrásokat és generált szabályokat használja,
nem igényel Node-csomagletöltést. [Fejlesztési leírás](code/README.md),
[újragenerálás](code/docs/BUILDING.md), [tesztelés](code/docs/TESTING.md).

## Források és licencek

A saját kód **GPL-3.0-or-later**: [LICENSE](LICENSE), [NOTICE](NOTICE.md).
A külső motorok és szűrőlisták saját licencei megmaradnak; a kombinált
kiadás GPLv3 feltételeivel terjeszthető. [Függőségjegyzék](code/docs/DEPENDENCIES.md).

A repo tartalmazza a módosított Swift-függőségeket, a runtime generátorát,
a rögzített bemeneteket, az upstream JS-forrásarchívumokat és a csomagolt
Public Suffix List eredeti forrását. [Upstream forrásjegyzék](code/vendor/upstream-sources/README.md).
