# Harmadik fél buildeszközei

A `bin/ConverterTool` és `bin/ConverterTool-debug` a SafariConverterLib 4.3.0
változatából készült arm64 macOS buildeszköz. A mellettük lévő
`swift-psl_PublicSuffixList.bundle` a futásukhoz szükséges adatcsomag. Ezek nem
kerülnek az alkalmazás futásidejű csomagjába; kizárólag a blokkolólista
előállítására szolgálnak.

A mellékelt SafariConverterLib-forrás helyi javítása a `$popup` szabályokhoz a
Safari `popup` erőforrástípusát is hozzáadja. A linkből nyíló lapokhoz szükséges
korábbi `document` ág megmarad. A popup mellett megadott explicit
tartalomtípusok is megmaradnak; a `subdocument` külön gyermekkeret-ággá alakul.

A pontos forrásverziókat a `PINNED_VERSIONS.json`, a teljes licencszövegeket a
`licenses/` könyvtár tartalmazza. A hozzájuk tartozó forrás a
`SafariConverterLib/` és `swift-dependencies/` könyvtárban található.

A `swift-psl` bináris erőforrásai a Public Suffix Listből készültek. A csomag
saját LICENSE fájlja csak a Swift kód MIT-licencét tartalmazta, ezért a beágyazott
adat MPL-2.0 licencét külön is mellékeljük.
