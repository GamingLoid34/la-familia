# Vardag i Flutter — rapport

Gren: `vardag-flutter` (från `master` @ `7898a57`). Ingenting är sammanslaget till
`master`, publicerat eller driftsatt. Baslinje för jämförelse: Android `vardag-android`
1.11.1 @ `382a96a`.

Rapporten skiljer på fyra nivåer av verifiering:

| Nivå | Betyder |
|---|---|
| **Kodgranskat** | Läst och jämfört mot Android-koden och specifikationen. |
| **Automatiskt testat** | Täckt av `flutter test` (enhets-/widgettest) och `flutter analyze`. |
| **Visuellt kontrollerat** | Ritat med skärmdumpsverktyget `test_screens/` (riktig Nunito och Material-ikoner, testdata, ingen Firebase) och granskat som bild. |
| **Enhetstestat / publicerat** | Provat på riktig telefon/PWA mot riktig backend. **Inget av detta är gjort.** |

## Sammanfattning per etapp

| Etapp | Före (Flutter `7898a57`) | Nu | Verifiering |
|---|---|---|---|
| 1 Namn, logga, identitet | La Familia, familjesiluett, gradientheaders | Vardag överallt användarsynligt; Androids originalvektorer (konverterade deterministiskt); Androids färgroller (veckodagsfärg/neutral/lågstimuli); Mer-flik; startskärm/inloggning som Android | Kodgranskat, automatiskt testat, visuellt kontrollerat (Mer mån/tor/fre, lågstimuli, neutral, inloggning, ikon) |
| 2 Skydda gemensamma data | Packlistan byggdes om vid varje sparning; hela `recurrence` (inkl. undantag) skrevs över; `source` sattes till `manual` | Redigering skriver bara ändrade fält; packlistan slås ihop i transaktion; undantag, `lessonPrep`, källkopplingar och ursprung bevaras; prenumerationer låsta till användare/familj | Kodgranskat, automatiskt testat (`plan_godkant_test.dart` m.fl.) |
| 3 Mer och navigation | Inställningar + separat Verktyg-sida via 🧰 | Hem · Kalender · Sysslor · Mer; Mer med Androids sektioner och rollstyrning; genvägar byter flik; 🧰 bara i fokus-/barnlägets Min dag (öppnar Mer i helskärm) | Kodgranskat, visuellt kontrollerat |
| 4 Fria Uppgifter | Saknades | Lista, skapa, öppna, ändra, slutföra, återöppna, ta bort; samma fält och regler som Android | Kodgranskat, automatiskt testat (modell/validering), visuellt kontrollerat |
| 5 Inkorg | Saknades (bara server) | Ny anteckning, Vem gäller det?, privat/gemensam, granskning med val, Tolka om/Försök igen, dubblettvarning, resultat per åtgärd, detalj med Ändra/Ta bort, ta bort med det som skapades, 📝 på Hem | Kodgranskat, automatiskt testat (hash-paritet, statustexter, bekräftelsesvar), visuellt kontrollerat |
| 6 Inför i morgon | Enkel morgondagslista efter 18 | Androids motor portad (93 Android-test + egna); vuxna ser INFÖR I MORGON hela dagen med Klart/Skjut upp/Klar, informationsrad med Dölj/Visa brevet/Stäng, datum på varje rad | Kodgranskat, automatiskt testat, visuellt kontrollerat |
| 7 Aktivitetsformulär | Obligatoriskt symbolsteg, ingen datumrad, ett tidsläge | Titel, datum, vem, tid (Klockslag/Heldag/Tid inte bestämd), Fler val, Skriv eller säg, stängningsskydd, lokal/serverbekräftad sparning, Visa → Kalender | Kodgranskat, automatiskt testat (204 test för logiken), visuellt kontrollerat |
| 8 Ändring, borttagning, Återkommande | Borttagning i meny, "Bara denna dag" | Detaljen läser live och har Ta bort/Redigera; Bara <dag>/Alla gånger på radens datum; Ta bort syssla; Återkommande under Mer | Kodgranskat, automatiskt testat (logik) |
| 9 Kalender, Min dag | Snabbfält, familjelappar, Upptagen, Jag tar det; Min dag visade tom dag under hämtning | Se avsnittet Kalender och Min dag | Kodgranskat, logiken automatiskt testad |
| 10 Skola, import, påminnelser | En .ics åt gången, klientparser | Flera .ics via `importIcsText`, namn ur innehållet, skanningar hittas/tas bort/ångras, lektionsförberedelse, inga lektionsnotiser för vanliga skollektioner | Kodgranskat, automatiskt testat |
| 11 Test och leverans | — | Se Testresultat och Publicering | — |

## Kalender och Min dag

**Kalender:** snabbfältet (flyttat in i formulärets "Skriv eller säg"), familjelapparna,
Upptagen-knapparna och "Jag tar det" i konfliktdialogerna är borta. ⋮ Fler val har
Familjemedlemmar (profilbilder, medlemsdag för vald dag) och Återkommande. Personfiltret
visar profilbild och förnamn, med "Visar bara X" och "Visa alla". Väder visas bara för
vald dag och bara när prognosen har underlag, med "Kan vara inaktuell" för gammal cache.
"Lägg till" finns i alla lägen utom fokus. Rubriken är 28 Bold som övriga flikar.
Dag/Vecka/Månad, helskärm och tillstånd efter detaljer är kvar.

**Min dag:** egna källor nycklade på dag, användare och familj; sena svar kasseras.
"Hämtar dagen…", riktigt tom dag, delvis fel och allt fallerat skiljs åt, med "Försök
igen" som bara startar om trasiga källor. "Inget låg på schemat denna dag". Sjukhusmatvalet
är dolt bakom en konstant. Transportarket har "Ändra eller ta bort". Skollunch 11:00–11:45
per barn när skolan har uppladdad matsedel.

## Slutchecklista (planens avsnitt 11)

Status: ✅ klart och verifierat så långt det går utan enhet · 🟡 kodgranskat/automattestat men **inte** provat på enhet · ⏳ kvarstår (kräver enhet eller åtkomst)

| Punkt | Status | Kommentar |
|---|---|---|
| Vardag visas som namn i app, webb och installerat läge | 🟡 | App-label, webbtitel, manifest, apple-mobile-web-app-title, widget. Installerade PWA:er kan visa gammalt namn/ikon tills webbläsaren uppdaterar manifestet — det går inte att tvinga. |
| Originalets logga/symbol används och är visuellt verifierad | ✅ | Vektorerna kopierade oförändrade; PNG renderade ur dem (`tool/vardag_ikoner`); logga och ikon granskade som bild. Installerad ikon på telefon ⏳. |
| Tema och centrala skärmar jämförda sida vid sida | 🟡 | Jämfört mot Android-koden (färgroller, typografi, radier) och som skärmdumpar av Mer, Uppgifter, Inkorg, formulär, Inför i morgon, inloggning. Hem, Kalender och Min dag kräver Firebase och kunde inte ritas utan enhet ⏳. |
| Mer, Uppgifter, Inkorg och Återkommande fungerar med rätt roller | 🟡 | Rollstyrning i UI och frågor; barn/ungdom prenumererar aldrig på tasks/notes. Mot riktiga regler ⏳. |
| Skapa i Android och ändra i Flutter samt omvänt | 🟡 | Samma fältformat, samma regler, portade Android-test. Korsprov på enheter ⏳. |
| Heldag och tid inte bestämd behåller sitt läge | ✅ (automatiskt) | `plan_godkant_test.dart`, `aktivitet_payload_test.dart`. |
| Samtidig titeländring/avbockning tappar inte data | ✅ (automatiskt) | Titeländring skickar ingen packlista; ändrad packlista slås ihop mot senaste versionen i transaktion. |
| Borttagning av en förekomst påverkar rätt datum | ✅ (automatiskt/kod) | Radens förekomstdatum skickas från Hem, Kalender, Min dag och detaljen; undantaget läggs med `arrayUnion`. |
| Lektionsförberedelse bockas av för rätt dag | ✅ (automatiskt) | `lessonPrep.doneDates` per lektionsdatum med `arrayUnion`/`arrayRemove`. |
| Anteckning kan skapas, granskas, ändras och tas bort | 🟡 | Hela flödet byggt; `confirmNoteActions` och `onNoteWritten` måste vara driftsatta ⏳. |
| Privat anteckning och vuxenuppgifter visas bara för rätt användare | 🟡 | Två avgränsade frågor för notes; tasks/notes bara för vuxna. Mot riktiga regler ⏳. |
| Hem visar rätt dag och relevanta uppgifter utan dubbletter | ✅ (automatiskt) | Motorns dubblettregler och sortering portade med Androids test. |
| Nätavbrott och nekade skrivningar ger sanningsenliga besked | 🟡 | Formuläret skiljer lokalt köat/serverbekräftat, sena nekanden visas som dialog; på webben lovas ingen lokal beständighet. Provat utan nät ⏳. |
| Barn-/fokusläge når Mer och kan lämnas | 🟡 | Flutter behåller flikfältet i fokusläge; dessutom 🧰 → Mer i helskärm → VIS-LÄGE/Logga ut. Barnrollens "Allt" skriver `child` (som Android). |
| Storskärm och övriga Flutter-flöden fungerar | 🟡 | Storskärmen använder egna teman och rörs inte; hela testsviten grön. `?display=1` på riktig skärm ⏳. |
| Riktig iPhone/PWA provad | ⏳ | Ingen enhet i det här passet. |

## Testresultat

Körda på grenens sista commit (2026-09-25):

| Kontroll | Resultat |
|---|---|
| `flutter analyze` | No issues found! |
| `flutter test` | 933 test, alla gröna (baslinje före arbetet: 416) |
| `node --test` (functions, oförändrade) | 83 test, alla gröna |
| `flutter build web --release` | Lyckas |
| `flutter build apk --debug` | Lyckas — bara kompileringskontroll av ikon-/startskärmsresurserna; ska **inte** publiceras |

Nya testfiler i urval: `tasks_notes_model_test.dart` (uppgifter, hash-paritet med
Android, anteckningar), `tomorrow_overview_engine_test.dart` (93 portade Android-test
+ 8), `aktivitet_*_test.dart`, `checklist_updates_test.dart`, `lesson_prep_test.dart`,
`aterkommande_lista_test.dart`, `data_tillstand_test.dart`,
`calendar_weather_selection_test.dart`, `school_notifications_test.dart`,
`ics_summary_test.dart`, `min_dag_*_test.dart` och `plan_godkant_test.dart`
(planens godkännandekrav i avsnitt 2).

### Visuell kontroll

`flutter test test_screens/vardag_screens_test.dart` ritar till `build/screens/`:
Mer (måndag, torsdag, fredag, lågstimuli, neutral), Uppgifter (även stor text),
Inkorg (även bred skärm), aktivitetsformuläret, Inför i morgon, Återkommande,
inloggning och onboarding. Granskat: dagsfärg på sidan, tonade kort, svart text
enligt WCAG-valet, loggan på inloggningen, datum på varje rad i Inför i morgon.

### Andra granskningen (Oscar, 2026-09-25)

Fyra fel som kvarstod efter första rättelseomgången, nu åtgärdade:

1. **Packlista utan nät kunde skriva över Androids avbockningar.** Rättelsen i `0197ae3`
   köade hela listan från telefonens kopia — fel. Nu skrivs en packlisteändring aldrig
   som hel lista: den läggs först i en lokal kö (`PendingChecklistEdits`, ursprung +
   formulärets lista) och sparas bara med transaktionen som slår ihop mot serverns
   senaste version — direkt, när nätet kommer tillbaka, vid återkomst till appen eller
   vid nästa start. Test: `pending_checklist_edits_test.dart` återskapar scenariot med
   en avbockning från Android medan Flutter saknade nät.
   *Begränsning:* finns redan en väntande packlisteändring för samma aktivitet och
   telefonen fortfarande saknar nät, nekar formuläret en ny packlisteändring med en
   förklaring i stället för att gissa. På webben ligger kön i webbläsarens lagring, som
   inte är garanterad (privat läge, rensad data).
2. **Inför i morgon kunde ge ett falskt lugnande besked.** Providern håller nu
   laddning och fel per källa; översikten väntar på familjemedlemmar, sysslor,
   återkommande och morgondagens aktiviteter (utöver uppgifter, anteckningar och
   arbetspass) och visar felraden om någon felar. "Försök igen" startar om familjens
   prenumerationer och arbetspassens fråga. Test: `tomorrow_overview_section_test.dart`.
3. **Anteckningens text försvann vid nekad sparning.** Formuläret öppnas nu igen med
   utkastet och felet överst tills sparningen lyckas eller användaren stänger — för
   snabbanteckningen, ny anteckning i Inkorgen och ändring. Test:
   `compose_note_retry_test.dart`.
4. **Sena sparfel återställde inte påminnelserna.** Återställningen (påminnelser och
   ev. mall) körs nu både vid omedelbart och sent nekande. Test:
   `aktivitet_sparning_test.dart`.

### Tredje granskningen (Oscar, 2026-09-25): packlistekön

1. **Kön var inte bunden till konto/familj.** Varje post bär nu `uid` och `familyId`;
   `flush` kör bara den inloggades poster i den aktiva familjen. En annan användares
   poster rörs inte och kan inte raderas av någon annans behörighetsfel.
2. **Misslyckad lokal lagring kunde döljas.** `save` skiljer nu på *bekräftad*
   (servern tog emot) och *köad* (servern nåddes inte men posten ligger säkert i kön).
   Nås varken servern eller kön kastas `PacklistaEjSparad`. En köad packlista redovisas
   som lokal sparning (`PacklistaKoad` → "sparat på telefonen"), aldrig som bekräftad.
3. **Samtidiga köoperationer.** Alla läsningar/skrivningar av kön går genom ett lås,
   och varje post har ett eget operations-id; bara den genomförda operationen tas bort.
4. **Återställning före påminnelsearbetet.** Återställningen väntar nu in
   påminnelsearbetet, både vid omedelbart och sent nekande.

Testerna kör `save` och `flush` på riktigt med ersättningar för lagring och server:
kontobyte, annan familj, lagringsfel (med och utan serverkontakt), permanenta fel,
samtidiga köläggningar, en pågående flush som inte får radera en nyare operation, och
ordningen. Samtidighetstestet faller om låset tas bort (kontrollerat).

### Oberoende kodgranskning

En separat granskning av hela ändringen mot `firestore.rules` och Android-koden
hittade sju fel som är rättade i commit `0197ae3`: fel förekomstdatum från vissa
vyer, Visa-frågan utan familjefilter (nekas av reglerna), ändrad anteckning med fel
ägare, uppgiftstitel med radbrytning, packlisteändring utan nät, uppgiftsredigering
som kunde ångra någon annans Klart, och sidoeffekter kvar efter nekad sparning.

## Backendbehov (inte ändrat — separat beslut och driftsättning)

1. **Webbens serverpåminnelser** (`functions/web_reminders.js`) hoppar inte över vanliga skollektioner. Appen gör det nu lokalt; webbpush gör det inte.
2. **`confirmNoteActions` sätter aldrig åtgärdernas `status`**, så informationsradens rubrik väljs i klienten (första `info`-förslaget oavsett status). Samma avvikelse behövs i Android om rubriken ska bli rätt där.
3. **Heldag utan DTEND** från `importIcsText` får ingen `endTime` och känns då inte igen som heldag av formuläret.
4. **`importIcsText` jämför datum mot "idag" i servertid (UTC).**
5. Flutter-klienten importerar nu .ics via `importIcsText` — callablen måste vara driftsatt (Android använder den redan).

## Begränsningar och avvikelser från Android

- **Uppgiftsformuläret har en GÄLLER-rad** för berörda familjemedlemmar (`aboutUids`). Android saknar UI för fältet men bevarar det; planen bad om stöd.
- **Resultat per åtgärd** efter bekräftelse visas som en dialog när något hoppades över (Android visar bara första skälet i en snackbar).
- **Ta bort med det som skapades** hittar aktiviteter via `sourceNoteId` utan Androids ±60-dagarsfönster; skyddet är detsamma (bara exakt det anteckningen skapade).
- **Posttypen (`type`)** skrivs vid redigering bara om den saknas.
- **Inför i morgon** visar dag och datum på varje rad och byter råa datum mot "tor 24 sep".
- **Flikfältet finns kvar i fokus-/barnläge** (Android döljer det). Planen säger att respektive plattforms fungerande navigation ska behållas.
- **Ångra efter skanning** finns i Flutter men inte i Android.
- **Inkorgens statustext `dismissed`** skrivs aldrig av servern och visas därför aldrig.
- **Min dag visar ingen egen förberedelserad** för morgondagens lektion — som Android;
  förberedelsen bockas i detaljen för rätt tillfälle och syns i Inför i morgon.
- **Skollunch i Min dag** gäller bara skolor med uppladdad matsedel ("Egen matsedel"), inte
  Mateo-listan — samma begränsning som Android.
- Emojier ritas inte i skärmdumpsverktyget (testmiljön saknar emojitypsnitt); skuggor ritas som svarta konturer där.

## Publicering

**Publicera inte en Flutter-APK.** Android-appen Vardag har samma `applicationId`
(`com.lafamilia.app`) med versionCode 48; Flutter har 27. En Flutter-APK kan därför
inte installeras som uppdatering, och ladda-ner-sidan pekar redan Android-familjen
till Vardag. Flutter-leveransen är webben/PWA:n (iPhone och dator) samt storskärmen.

När grenen är granskad och sammanslagen enligt README:s ritual:

1. `flutter test`, `flutter analyze`, `node --test` (functions).
2. `flutter build web --release --dart-define=APP_VERSION=<version>`.
3. Förkontroll och `firebase deploy --only hosting` (inga regler eller functions behöver
   ändras för klientdelen).
4. Efterkontroller med `curl.exe` enligt ritualen, bland annat att `manifest.json`
   innehåller `"name": "Vardag"` och att `icons/apple-touch-icon.png` svarar 200.
5. Installerade PWA:er: be familjen öppna appen en gång med nät; ikon och namn på
   hemskärmen kan kräva att genvägen läggs till på nytt (iOS uppdaterar sällan
   hemskärmsikonen för en redan installerad webbapp).
