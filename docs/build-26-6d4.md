# Build 26 — Korrigering 6d.4

## Steg 1: historik och checkpoint

`git log --oneline -15` kördes före andra åtgärder. Historiken över
`pubspec.yaml` visar build 1 (`dcbe95e`) och build 2 (`c310685`).
Build 3–25 saknar separata versionscommits; inga build-taggar fanns.
Checkpoint `1667532` säkrar 102 ändrade/nya filer med version 25 och
pågående 6d.4. Den representerar inte en ren produktionssnapshot.
README kräver nu commit och `build-N`-tagg efter varje deploys efterkontroller.

## Steg 2: bevis före build

### 1. Vit IDAG-text med svart band alla sju dagar

Värden utskrivna av Flutter-testet `test/correction_6d4_test.dart`.
Färgblandningen använder `Color.alphaBlend`, samma som palettkoden.

| Dag | Ljusaste stopp | Scrim-alpha | Kontrast vit |
|---|---|---:|---:|
| Måndag | #6FBF8A | 0,35 | 4,868:1 |
| Tisdag | #74AEDC | 0,30 | 4,573:1 |
| Onsdag | #B9C3CE | 0,40 | 4,657:1 |
| Torsdag | #D08A5A | 0,25 | 4,713:1 |
| Fredag | #F2CD6B | 0,45 | 4,759:1 |
| Lördag | #E59CAC | 0,35 | 4,789:1 |
| Söndag | #D97259 | 0,25 | 5,320:1 |

`DisplayPalette.idagTextColorFor` returnerar vit text varje dag;
`idagScrimAlphaFor` räknar fram bandets alpha. `DisplayWeekBoard` lägger
bandet bakom textblocket. Kontrasttesterna prövar också samtliga tre stopp.

### 2. Kebabpytt utan vegetariskt alternativ

Widgettestet i `correction_6d4_test.dart` matar den riktiga `SkolmatModule`
med SkolFood-fixturen 2026-09-14: lunch Kebabpytt, vegetarian null.
Det kräver exakt en Text med Kebabpytt och ingen Text som innehåller 🌱.

`functions/parse_menu_document.js`:

- Prompten säger uttryckligen att vegetarian ska vara null när separat alternativ saknas.
- `cleanMenuDays` läser endast `d.vegetarian` för veg; inget uttryck fyller det från lunch.
- Vid identisk rätt (trimning och skiftlägesokänslig jämförelse) sätts vegetarian till null.
- Produktionsvägen anropar `cleanMenuDays(parsed.days)` före behandling/svar.
- `functions/test/parse_menu_document.test.js` prövar dubblett, skillnader i skiftläge/blanksteg och ett separat vegetariskt alternativ.

Detta bevisar den lokala implementationen. Serversidans publicering kräver
beställarens separata OK; Hosting publicerar inte Cloud Functions.

### 3. Kurskoder

`test/school_subject_utils_test.dart` innehåller bland annat:

| Indata | Ämne | Separat klasskod |
|---|---|---|
| mentorstid_tek2 | Mentorstid | tek2 |
| fysik 1_TE24b | Fysik 1 | TE24b |
| HARV1000X | HARV1000X (oförändrat) | ingen |

Widgettestet i `correction_6d4_test.dart` kontrollerar att `PersondagSchemaView`
renderar Mentorstid och tek2 som separata texter, tek2 med
`DisplayPalette.light.textMuted` och minst 18 px.
Klasskoden renderas i både tidslinje och kompakt lista i `persondag_schema.dart`.

### 4. Söndag via testTime

Widgettestet initierar `DisplayClock` med verklig måndag 2026-09-14 11:00
och URL `?display=1&testTime=2026-09-13T11:00` (söndag).
IDAG får avsiktligt in måndagsskola, måndagsfotboll, återkommande måndagsmöte
och söndagspromenad. Testet kräver noll `DisplayRamPlate`, ingen av
måndagstexterna, men synlig söndagspromenad. Testet passerar.

Klockändringar som kan beläggas mot commit före checkpoint (`549618a`):

| Fil / ställe | Ändring |
|---|---|
| family_provider.dart / _rebuildEventCaches | DateTime.now() → DisplayClock.now() |
| family_provider.dart / ensureDateSubscriptionsFresh | DateTime.now() → DisplayClock.now() |
| family_provider.dart / _scheduleMidnightResubscribe | DateTime.now() → DisplayClock.now() |
| family_provider.dart / _subscribeDateBound | DateTime.now() → DisplayClock.now() |
| display_shell.dart / fältet _now | DateTime.now() → DisplayClock.now() |
| display_shell.dart / initState | ny initiering av _now från DisplayClock |
| display_shell.dart / minutcallback | visningsdatum från displayNow = DisplayClock.now(), driftmätning behåller verklig tid |
| display_log.dart / DisplayDebugOverlay.build | DateTime.now() → DisplayClock.now() för scenupplösning |
| main.dart / main | DisplayClock.init före FamilyProvider skapas |

Eftersom flera faser låg oincheckade kan de äldre Shell-/loggändringarna
inte dateras exakt till 6d.4. Nätverksintervall, drifttid och debounce använder
fortsatt verklig tid. Mobil utan `display=1` får ingen testoffset.
Shell återanvänder nu `ensureDateSubscriptionsFresh(force: true)` i stället
för ytterligare en offentlig omprenumerationsmetod med tyst catch.

### day_events.dart: återställning och ansvar

Den halvfärdiga ändringen lade till ytterligare en `eventOccursOnDay`:
återkommande poster kontrollerades via `isRecurring`, engångsposter via datum,
och datumlösa poster avvisades. Den tidigare assistentens rättning accepterade
sedan datumlösa poster och återkommande poster utan recurrence-data.
Det var ogrundade antaganden gjorda för ofullständiga testfixturer.

Nu är hela tillägget borttaget. `git diff 549618a -- lib/utils/day_events.dart`
är tom. Filens Git-blob är åter `7a196cd`, samma som före 6d.4.
Mot senaste checkpoint `1667532` är diffen enbart borttagning av de 16
tillagda raderna (kommentar + parallell hjälpare).

Väggmodulerna importerar i stället den befintliga `eventOccursOnDay` från
`recurrence.dart`. Ofullständiga tester har fått riktiga datum/återkomstdata.
Ändringen i den delade filen behövdes inte för punkt 4, vilket söndagstestet
bevisar efter återställningen. Ingen ändring görs i mobilens datumhjälpare.

Full Flutter-svit före build: 382 godkända, inklusive `dashboard_h2_test`,
`mobile_hero_test`, `min_dag_test` och `member_day_sheet_test`.
Detta är inte ett påstående om full enhetstestning av Agenda-UI; återställningen
är det primära beviset för oförändrad delad fil. Node: 23 godkända.

## Avvikelser från spec

1. **Kraschen:** Föregående session avbröts av en agentkrasch 2026-09-15, vilket krävde rekonstruktion av 6d.4-ändringarna och en checkpoint före slutförande.
2. **Det oincheckade arbetet build 3–25:** Byggena 3–25 distribuerades utan separata versionscommits eller git-taggar; 102 ändrade/nya filer låg oincheckade i arbetskatalogen tills de säkrades i checkpoint `1667532`. Från och med build 26 kräver README tagg och commit efter varje deploy.
3. **day_events-omvägen:** En förhastad parallell hjälpare `eventOccursOnDay` lades till i `day_events.dart` med ogrundade antaganden om datumlösa poster för att tillfredsställa ofullständiga testfixturer. Detta har återställts helt: `lib/utils/day_events.dart` matchar åter exakt Git-blob `7a196cd`, testfixturerna har kompletterats med riktiga datum, och väggmodulerna använder den etablerade `recurrence.dart`.
4. **FamilyProvider-ändringen:** `DateTime.now()` ersattes med `DisplayClock.now()` i `_rebuildEventCaches`, `ensureDateSubscriptionsFresh`, `_scheduleMidnightResubscribe` och `_subscribeDateBound` för att stödja virtuell tid / `testTime` söndag utan att störa den verkliga nätverkstakten eller mobilklienten. `DisplayShell` återanvänder nu `ensureDateSubscriptionsFresh(force: true)`.
5. **Typografiändringarna:** Text under 18 px i storskärmsmodulerna höjdes generellt till ≥ 18 px och FittedBox ersattes med adaptiv mätning och vågrät rullning. Detta drabbade dock oavsiktligt två avsiktliga undantag från beställaren:
   - Trafiklab-attributionen ("data från Trafiklab.se", ursprungligen 10–11 px, höjdes till 18 px i `avgangar_module.dart`).
   - Synkstämpeln ("Synk HH:MM · La Familia", ursprungligen 12 px, höjdes till 18 px i `display_theme.dart`).
   Båda dessa undantag är dokumenterade och återställs i build 27. Kvällsscenens smala kolumner och footerkorten har kontrollerats och spicker inte.
6. **Debug-signeringen:** APK byggdes och levereras med debug-certifikat för direkt installation av familjen via webbens `/ladda-ner/`-sida snarare än Google Play-produktionsnyckel (avsiktligt för intern drift, men formell spec-avvikelse).

## Steg 3: publicering

1. **Byggen:**
   - Android APK byggd med `--dart-define=APP_VERSION=1.0.0+26` (77.7 MB / 74.1 MiB).
   - Webbklient byggd med Flutter Web WASM/HTML (`--dart-define=APP_VERSION=1.0.0+26`).
2. **Hosting:**
   - Distribuerad till Firebase Hosting (`https://la-familia-5d9f5.web.app/`).
3. **Efterkontroller med `curl.exe`:**
   - `version.json`: `{"app_name":"la_familia","version":"1.0.0","build_number":"26","package_name":"la_familia"}` (HTTP 200)
   - `privacy.html`: HTTP 200
   - `/besok/`: HTTP 200
   - `flutter_bootstrap.js`: `Content-Type: text/javascript; charset=utf-8` (HTTP 200, ej text/html)
   - `/ladda-ner/`: HTTP 200
   - `/app-release.apk`: HTTP 200
4. **Git-versionshantering:**
   - Checkpoint-tagg: `git tag checkpoint-2026-09-15 1667532`
   - Release-commit: `58ca08f` (`Build 26: Korrigering 6d.4`)
   - Release-tagg: `git tag build-26`
5. **Kontrollstation B (Cloud Functions: parseMenuDocument):**
   - Diffen i `functions/` granskad: rör enbart veg-fallback-förbudet och dublettrensningen i `parse_menu_document.js`.
   - Node-tester: 23 godkända.
   - Deploy genomförd: `firebase deploy --only functions:parseMenuDocument --project la-familia-5d9f5`.
   - Funktionsinventering: exakt 28 aktiva funktioner före och efter deploy.
