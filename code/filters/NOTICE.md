# Szűrőlista-bemenetek

- Kiadott lista: AdGuard Base filter 2.4.89.22
- Frissítési idő a fájlfejléc szerint: 2026-09-09T12:20:56+00:00
- Forrás URL: https://filters.adtidy.org/extension/safari/filters/2.txt
- SHA-256: `f55c87d2a6c08149f306fe62a8a3f42b5edc0663c897a3ae25a8d7c6a794fb4e`
- Licenc URL a fájlfejléc szerint:
  https://github.com/AdguardTeam/AdguardFilters/blob/master/LICENSE

A lista fejléce szerint az AdGuard Base az EasyList és az AdGuard English filter
összeállítása. Az AdGuardFilters által megadott GPLv3 licenc teljes szövege a
`LICENSE-AdGuardFilters-GPL-3.0.txt` fájlban van. Az EasyList szerzőit az
https://easylist.to/ oldal jelöli; az EasyList hivatalos licencoldala GPL-3.0-or-later
vagy CC-BY-SA-3.0-or-later választást ad. Ebben a GPL-alapú projektben a GPL utat
használjuk.

## Hufilter for AdGuard

- Rögzített kiadás: `1832f017a963e4b96183e7865670a5cdd91ce263` (`gh-pages`)
- Forrás commit: `9a62d00504244bcbab1051e49acd5240997332a6`
- Lista-verzió: `202609081912`
- Frissítési idő a fájlfejléc szerint: 2026-09-08T19:12:00+00:00
- Rögzített lista SHA-256: `211b63f31366a3e70bca1cb764356628eefa62be08a896ee4165f856c652df1b`
- Forrás URL: https://raw.githubusercontent.com/hufilter/hufilter/1832f017a963e4b96183e7865670a5cdd91ce263/hufilter-adguard.txt
- Licenc: CC BY 4.0; teljes szöveg: `LICENSE-Hufilter-CC-BY-4.0.txt`

Az `adguard-base.txt` és a `hufilter-adguard.txt` változatlan, külön rögzített
bemenet. A `local-rules.txt` egy saját, rövid kiegészítés; jelenleg a 24.hu
megfigyelt reklámsorára tartalmaz szabályt. A generáló előbb a Base, majd a
Hufilter és a saját szabályok tartalmát adja át a konverternek, köztük pontosan
egy elválasztó újsorral. A `blockerList.json` és a
`generated/` alatti fájlok ebből készített, módosított kimenetek. A
`blockerList.json` végén két saját sentinel szabály található.

A helyi kiegészítés a Base media.net szabályának Safari által támogatott
script/XHR third-party részét is megőrzi. Az eredeti object módosító nem
támogatott; annak konverziós hibája a naplóban megmarad. A Base meglévő
kivételszabályai továbbra is a natív blokk után érvényesülnek.
