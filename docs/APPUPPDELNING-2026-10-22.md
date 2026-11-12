# Vardag: bevara arbetet och dela upp apparna

Beslut och första implementation 2026-10-22. Detta är en stegvis utbrytning,
inte ett påstående att alla extrafunktioner redan har egna färdiga appar.

## Mål och gränser

| Produkt | Innehåll | Status |
|---|---|---|
| Vardag | Familjekalender, personer, återkommande aktiviteter, veckobrev/inkorg, uppgifter, packlista, förberedelser, kalenderpåminnelser, storskärm | Behåll |
| Hem (arbetsnamn) | Sysslor, städzoner/städläge, inköpslista, matplanering och recept | Separat webbpreview skapad; sex Flutter-vyer utflyttade, native återstår |
| Växtfunktioner | Växter, bevattning och befintlig Växtkoll-koppling | Inventerad koppling; separat målapp inte verifierad lokalt |
| Fokustimer Preview | Fristående lokal Android-timer | Byggd från befintlig UI och domänmodell; förhandsversion |

Uppgifter från veckobrev är kalenderstöd och ska inte flyttas tillsammans med
hushållssysslor. Inget konverteras automatiskt till kalenderaktiviteter.

## Bevarande

Verifierade Git-bundles för Android, Flutter och vardag-contract finns i
`/home/oscar/utveckling/vardag-uppdelning/20261022/`, med commit och SHA-256 i
`manifest.json`. De innehåller versionshanterad kod och historik, inte en backup
av Firestore eller lokala hemligheter. Familjens data har inte ändrats.

`source-inventory.json` i samma katalog är en sökbar kandidatlista över källfiler
med kontrollsummor, grupperad efter filnamn. Den är ett arbetsunderlag och inte
bevis för att alla beroenden är fristående.

## Första verkliga utbrytningen: timer

Eget projekt: `/home/oscar/utveckling/vardag-timer`. Eget app-id och ingen
nätverksbehörighet eller Firebase. TimerScreen, TimerState och ursprungliga tester
återanvänds. Ny tidsberäkning använder sluttid och återställer lokal nedräkning.

Vardags timerskärm, vymodell, tillstånd och gamla oanvända Android-larmmotor har
flyttats ur byggets källmappar. Timer-valen har tagits bort oavsett pilotflagga.
Flutter-sidan, tjänsten och schemaläggningsfunktionerna har också flyttats ut.
Originalen finns i det nya projektets `reference/` samt i historiken.

Bara kompatibilitetskoden för gamla larm/rutter finns kvar i Vardag: Android
avbokar det tidigare timer-id:t vid start och ignorerar timerlarm i mottagaren;
Flutter avbokar timer-id:t vid notisinitiering och tar bort timerkanalerna.
Gamla Android-rutten visar arkivet. Kalenderns övriga påminnelser behålls.

Preview kräver öppen app för slutsignal. Bakgrundslarm och fysisk enhet återstår.
Flutter-originalet hade bakgrundsnotiser och är bevarat, men någon fristående
Flutter/iPhone-timer levereras ännu inte. Därför publiceras ingen ny kalender-
release automatiskt i denna utbrytning; installerad app och webb fortsätter som
förut tills ersättarna är redo för användning.

## Beroenden att flytta tillsammans

- Städ/sysslor: `ChoreRepository`, mallar, städzoner, avbockning via Cloud Function,
  rotation, poäng, historik och notiser. `chores`, `chore_templates` och `chore_log`
  är separata datadelar. Historiken får inte tappas vid flytt.
- Inköp: `ShoppingRepository`, `shopping_items` och matplaneringens inköpsgenerering.
- Mat: `MealRepository`, `MealChoiceRepository`, `meals`, `dishes`, `meal_choices`,
  AI-menyer och familjens matpreferenser. Storskärmens matvisning är en konsument
  som måste få ett uttryckligt läsgränssnitt innan modellen flyttas.
- Växter: `VaxterScreen`, `VaxtPayloads`, `VaxtMatcher`, växtrelaterade sysslor och
  `VaxtkollKoppling`. Växter ligger delvis som sysslor, så hela `chores` får inte
  godtyckligt flyttas till en växtapp. Utgå från befintlig koppling först.

## Fortsatt ordning och kriterier

1. Gör timer-preview redo för vanlig användning: bakgrundssignal, återstart,
   behörigheter och fysisk telefon. Bestäm inte att iPhone stöds innan den byggts.
2. Skapa Hem med återanvända funktioner och bevarad historik. Samma familjeidentitet
   måste kontrolleras av serverregler; duplicera aldrig administratörsbehörighet.
3. Kontrollera befintlig Växtkoll-app och koppling innan ännu en växtapp skapas.
4. Ta bort respektive funktion ur kalenderbygget när ersättaren är verifierad.
   Håll arkiv/export tillgängliga under övergången och avboka gamla arbeten/larm.
5. Arbeta därefter med storskärmens förenkling med samma kalenderdata.

Kopplingar ska vara frivilliga. En extraapp kan senare erbjuda att skicka en vald
post till Vardag med käll-id och dubblettskydd. Inget sådant API är infört här.
Svensk datalagring är ett separat arkitekturbeslut; denna kodflytt flyttar ingen
backend och ger inga nya löften om var autentisering, loggar eller push lagras.

## Verifiering och leverans

- Android Vardag: `:app:testDevDebugUnitTest :app:assembleDevDebug` godkänt,
  982 tester utan fel. Åtta timer-tester har flyttats till den fristående appen.
- Fokustimer: `:app:testDebugUnitTest :app:assembleDebug` godkänt, 12 tester.
- Flutter: 431 tester godkända och `flutter analyze --no-pub` utan anmärkningar.
- Flutter webb: `flutter build web --no-pub` godkänt (196,9 sekunder).
- Åtta flyttade originalfiler jämförda med tidigare Git-versioner: identiska
  efter normalisering av radslut. Kvitto: `preservation-check.json` i arkivmappen.
- APK-manifestet har kontrollerats: eget app-id och ingen internetbehörighet.
- Fysisk telefon, bakgrundslarm och iPhone har inte verifierats.

Timer-APK: `/home/oscar/utveckling/apk-leveranser/fokustimer/fokustimer-preview-0.1.0.apk`.
Privat Drive-leverans verifierad med storlek och checksumma:
https://drive.google.com/file/d/1uYuEfiCO-x2zw3MCAl7qEH9lklZSA0nC/view
Kvitto: `../vardag-uppdelning/20261022/timer-delivery.json` från projektroten.

Rutiner, AI-planerare, lathund och besöksfunktioner behöver också bedömas vid
nästa inventeringspass; de har inte flyttats i detta steg. Kalendervyer och
storskärm som använder information från extraappar måste få sina läskopplingar
säkrade innan resterande källkod tas bort.


## Uppdatering: Hem

Nästa steg har genomförts som ett separat Flutter-webbprojekt i
`/home/oscar/utveckling/vardag-hem`. Sex huvudvyer har flyttats ur Vardags
Flutter-implementation med originalen bevarade. Native-Android, publicering
och delar av integrationstestningen återstår. Full rapport finns i
`/home/oscar/utveckling/vardag-hem/docs/UTBRYTNING.md`.
