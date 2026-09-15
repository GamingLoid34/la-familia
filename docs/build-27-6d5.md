# Build 27 — Korrigering 6d.5

## Bakgrund

Build 26:s slutrapport (`docs/build-26-6d4.md`, Avvikelser #5) dokumenterade
att den generella höjningen av all text under 18 px till >= 18 px av misstag
träffade två avsiktliga undantag (Trafiklab-attribution, synkstämpel) och att
`SingleChildScrollView`/vågrät rullning fortfarande fanns kvar i
`DisplayRamPlate` och `DisplayActivityCard`. 6d.5 rättar båda delarna.

## Steg 1: kodändringar

### 1. Inget scrollbart på väggen

`grep -rn "SingleChildScrollView" lib/screens/display/` gav tidigare träffar
i `display_chips.dart` (DisplayRamPlate gren a/b, DisplayActivityCard
tidraden) — samtliga borttagna:

- **DisplayRamPlate gren a** ("piktogram · etikett · tid" får plats): ingen
  omslutning. Innehållet är mätt att rymmas.
- **DisplayRamPlate gren b** ("piktogram · tid" får plats): ingen omslutning.
- **DisplayRamPlate gren c** (varken a eller b ryms): `FittedBox(fit:
  BoxFit.scaleDown, alignment: Alignment.centerLeft)` — det enda beslutade
  undantaget från FAS 5.6.
- **DisplayActivityCard, tidraden**: samma `FittedBox(scaleDown)`-undantag
  när tidraden i full storlek inte ryms; titelraden rullas eller kortas
  aldrig (oförändrat, `maxLines: 1` + ellipsis).

`grep -rn "SingleChildScrollView" lib/screens/display/` ger nu inga träffar.
README har fått regeln "Ingen SingleChildScrollView, ListView eller annan
scroll på väggen" i en ny sektion.

**Känd kvarstående avvikelse** (utanför uppdragets omfattning, se Avvikelser
nedan): `ListView.separated` används fortfarande i `avgangar_module.dart`,
`idag_nu_module.dart`, `nedrakning_module.dart` och `skolmat_module.dart` för
listor som är begränsade av `Expanded`. Dessa rördes inte i 6d.5 eftersom
uppdraget specifikt pekade ut `DisplayRamPlate`/`DisplayActivityCard`.

### 2. Typografiundantagen återställda

| Text/element | Storlek | Kategori |
|---|---:|---|
| Attribution "data från Trafiklab.se" (kompakt kort) | 10 px | Undantag |
| Attribution "data från Trafiklab.se" (bred rubrikrad) | 11 px | Undantag |
| Synkstämpel "Synk HH:MM · La Familia" | 12 px | Undantag |
| Chip-badge (PÅGÅR m.fl., `_buildChipBadge`, mätstilen) | 12 px w800 | Undantag |
| Chip-badge i persondagsschemat (`isLarge`) | 18 px | Innehåll (plats finns) |
| Avgångskortets linjepill | 12 px | Undantag |
| Avgångskortets bytesbricka ("byte i Mjölby") | 10 px | Undantag |
| Avgångskortets tid/status (försenad, inställd, GA-tid) | 13 px | Undantag |
| Footerkickers ("Avgångar" m.fl., samma i alla footerkort) | 14 px | Undantag |
| Nedräkningsetikett minuter (idag_nu-chip) | 13 px | Undantag |
| Varningsikon ⚠ bredvid footerkicker | 13 px | Undantag |
| Varningsikon ⚠ bredvid bred rubrikrad | 16 px | Undantag |
| Tågemoji 🚆 bredvid footerkicker | 16 px | Undantag |
| Lunchrätter, skolmat, "Inga …"-tomtillstånd | 18 px | Innehåll |
| Hero-text och nedräkningstitlar (idag_nu) | 18 px | Innehåll |
| Middagsveckan, persondag (namn, sysslor, imorgon-text) | 18 px | Innehåll |
| Rubriker (IDAG, "Avgångar & Kollektivtrafik", hållplatsnamn) | 18 px | Innehåll |

Fastställt genom `diff` mot checkpoint `1667532` (senaste rena tillstånd
före build 26:s typografihöjning) för samtliga sex ändrade filer. Ett par
ytterligare avvikelser (varningsikon, tågemoji) hittades vid granskningen
och återställdes till sina ursprungliga, ej-innehållsrelaterade storlekar
(13/16 px) eftersom de sitter i samma rad som en redan dokumenterad
undantags-text och aldrig var avsedda att räknas som innehållstext.

Chip-badgens `isLarge`-gren (schemat i persondagsvyn) hade av misstag satts
till 15 px i det tidigare, oincheckade arbetet — rättad till 18 px enligt
uppdraget ("badge i schemat behåller 18 px — där finns plats").

## Steg 2: visuell verifiering

`flutter test test/correction_6d5_test.dart` — 7 nya tester, alla gröna:

- **(a) Avgångskortet med tre tåg och bytesbricka:** `_buildDepartureRow` i
  `avgangar_module.dart` hämtar data via ett Cloud Functions-anrop i
  `initState`; det finns ingen Firebase-mockningsinfrastruktur i testsviten
  för att pumpa hela `AvgangarModule`-widgeten med fasta avgångar. Verifierat
  genom kodgranskning i stället för automatiskt widgettest: raden bygger en
  fast `Row` med `Expanded` + `TextOverflow.ellipsis` på målorienterad text,
  utan `SingleChildScrollView`/`FittedBox`, och samtliga tid/status-texter
  ligger nu på 13 px (se tabell) — god marginal mot kortets bredd.
  **Avvikelse:** inget automatiskt bevis för denna deluppgift (se Avvikelser).
- **(b) idag_nu-chip med PÅGÅR-badge i 330 px och 200 px:** `DisplayActivityCard`
  (samma widget som `IdagNuModule` renderar per händelse) med `isOngoing:
  true` och `badgeText: 'PÅGÅR'` testas vid båda bredderna. Badge-texten är
  12 px, inget overflow, ingen `SingleChildScrollView`.
- **(c) Kvällsscenens smala kolumner:** scenen `kvall` (layout `sidebar`)
  visar `veckotavla` i huvudytan, som bygger sina dagskolumner av
  `DisplayRamPlate`/`DisplayActivityCard`. Dessa täcks redan av
  `test/display_chip_density_test.dart` vid 330/200/135 px (gren a/b/c) och
  av de nya scroll-fria testerna i `correction_6d5_test.dart` ned till 90 px.
  Sidopanelen `middag_vecka` är ren innehållstext på 18 px utan
  scroll-omslutning (kodgranskad, kräver Firestore-ström för widgettest).
- **(d) Footerkorten:** `DisplayFooterCard` (delad av alla tre footerkort)
  testad vid 260 px och 220 px, ljust och mörkt tema. Kickern är 14 px,
  inget overflow.

Ingen overflow, ingen klippning i något av de körda testerna.
`flutter analyze` och `flutter test` (389 tester) samt `node --test
functions/test/*.test.js` (23 tester) är gröna.

## Steg 3: publicering

1. **Byggen:**
   - Android APK: `flutter build apk --release --dart-define=APP_VERSION=1.0.0+27` (77.7 MB).
   - Webbklient: `flutter build web --release --dart-define=APP_VERSION=1.0.0+27`.
2. **Distribution:** APK kopierad till `build/web/app-release.apk`,
   `build/web/la-familia.apk` och `web/app-release.apk`. Nedladdningssidans
   badge/filnamn uppdaterat till Build 27 i både `web/ladda-ner/index.html`
   och den byggda `build/web/ladda-ner/index.html`.
3. **Hosting:** distribuerad till `https://la-familia-5d9f5.web.app/`.
4. **De 6 efterkontrollerna med `curl.exe`:**
   - `version.json`: `build_number":"27"` (HTTP 200).
   - `privacy.html`: HTTP 200.
   - `/besok/`: HTTP 200.
   - `flutter_bootstrap.js`: `Content-Type: text/javascript; charset=utf-8`.
   - `/ladda-ner/`: HTTP 200.
   - `/app-release.apk`: HTTP 200.
5. **Git:**
   - Release-commit: `cf7791d` ("Build 27: Korrigering 6d.5").
   - Release-tagg: `git tag build-27` (pekar på `cf7791d`).
   - Bekräftat: `build-26` pekar på `58ca08f` ("Build 26: Korrigering 6d.4"),
     inte på den efterföljande dokumentationscommiten `a8a5fb4`.

## Avvikelser från spec

1. **Kvarstående `ListView` på väggen:** `avgangar_module.dart`,
   `idag_nu_module.dart`, `nedrakning_module.dart` och `skolmat_module.dart`
   använder fortsatt `ListView.separated` inom `Expanded`-ytor. Uppdraget för
   6d.5 pekade specifikt ut `DisplayRamPlate`/`DisplayActivityCard`, så
   dessa lämnades orörda. Om regeln "ingen ListView på väggen" ska gälla
   fullt ut krävs en separat korrigering som hanterar överflödigt innehåll
   i dessa listor (t.ex. hård gräns på antal poster i stället för scroll).
2. **Avgångskortet med tre tåg saknar automatiskt widgettest:**
   `AvgangarModule` hämtar avgångar via ett Cloud Functions-anrop i
   `initState`, och testsviten har ingen Firebase-mockningsinfrastruktur.
   Verifierat genom kodgranskning i stället (se Steg 2).
3. **`middag_vecka`-modulen (kvällsscenens sidopanel) saknar automatiskt
   widgettest** av samma skäl: den läser en Firestore-ström via
   `Provider`/`context.watch<FamilyProvider>()`. Innehållet är ren
   18 px-text utan scroll-omslutning, verifierat genom kodgranskning.
4. **Debug-signeringen** kvarstår oförändrad sedan build 26 (APK signeras
   med debug-certifikat för direktinstallation via `/ladda-ner/`, inte
   Google Play-produktionsnyckel) — inte en del av 6d.5:s omfattning.
