# Uppdrag till Claude: Vardag i Flutter

## Mål och mandat

Uppdatera Flutter-appen så att den får samma aktuella funktioner, arbetssätt, namn och visuella identitet som Android-appen Vardag. Användaren har uttryckligen bett att båda apparna ska heta **Vardag**, med samma logga och så likt utseende som möjligt.

Claude ska implementera koden. Detta dokument är ett gransknings- och implementationsunderlag; inga kodändringar har gjorts av den som skrev planen.

- Flutter-projekt: `C:\mina_appar\vardag-projektet\la familia`
- Android-referens: `C:\mina_appar\vardag-projektet\vardag-android`
- Granskad baslinje 2026-09-24: Android **1.11.1**, commit `382a96a`; Flutter commit `7898a57`.
- Kontrollera tillkommande ändringar före start. Sidogrenar, exempelvis klockprojektet, ingår inte automatiskt.
- Uppgiften gäller funktionerna i Flutter-appen. Uppgradering av Flutter SDK eller paket är inget eget mål.

Implementera etapperna, verifiera dem och håll en checklista över befintligt, delvis befintligt, saknat och färdigt. Återanvänd fungerande Flutter-kod. Behåll webb/PWA och storskärmsfunktioner. Publicering är ett separat leveranssteg.

## 1. Namn, logga och visuell identitet

### Appnamn

Allt användarsynligt produktnamn ska vara **Vardag**. Androids produktionsapp heter redan Vardag; Flutter har fortfarande bland annat `android:label="La Familia"` och webbmanifestets namn `La Familia`.

Inventera och uppdatera:

- Installerat appnamn, appens titel, inloggning, onboarding, startskärm och inställningar.
- Webbens sidtitel, metadata, PWA-manifestets `name`, `short_name` och beskrivning.
- Installationshjälp, delningstexter, notisrubriker där produktnamnet används och användarsynliga hjälpsidor.
- Widget och relevanta nedladdnings-/informationssidor.
- Storskärmens användarsynliga produktnamn där det förekommer.

Byt inte tekniska identifierare bara för namnbytets skull: Firebase-projekt, `applicationId`, paketnamn, autentisering, databasvägar, hostingmål, URL:er och signeringsidentitet ska bevaras. Mappen `la familia` behöver inte döpas om. Utvecklingsversionen får fortsatt heta Vardag DEV.

### Logga och ikoner

Använd Androids befintliga Vardag-original, inte Flutter-appens äldre familjesiluett och inte en nytolkning av loggan.

Källor under Android-projektets `app/src/main/res/`:

- `drawable/vardag_logo.xml`: hela loggan, V-symbol och ordmärke. Vektorns färg är `#1E5155` och dess viewport är 755 × 473.
- `drawable/ic_launcher_foreground.xml`: appikonens förgrund.
- `drawable/ic_launcher_background.xml`: appikonens bakgrund.
- `drawable/ic_launcher_monochrome.xml`: monokrom ikon.
- `drawable/ic_splash_logo.xml`: startskärmens variant.
- `mipmap-anydpi-v26/ic_launcher.xml` och `ic_launcher_round.xml`: adaptiv ikonsammansättning.

Överför originalgeometrin till lämpliga Flutter-/webbformat, med bibehållna proportioner, färger och frizoner. Konvertera vektorn eller rendera den deterministiskt; återskapa den inte med generativ bildframställning. Hel logga används inne i appen, medan hemskärmsikonen använder symbolen utan oläsligt ordmärke, som Android.

Berörda befintliga Flutter-resurser omfattar `assets/images/logo.png`, `assets/images/icon_foreground.png`, `web/favicon.png`, `web/icons/`, `web/manifest.json` och ikon-/splashkonfiguration i `pubspec.yaml`. Kontrollera vilka filer som faktiskt används innan de ersätts. Uppdatera vanliga och maskbara PWA-ikoner samt Apple touch-ikon där den används.

### Likhet mellan apparna

Jämför Androids aktuella tema och skärmar mot Flutter. Matcha färger, Nunito-typografi, dagsfärger, låg stimulans, rubriker, kort, ikoner, knappar, avstånd och svenska benämningar. Behåll tillgänglighet och respektive plattforms fungerande navigation. Webbens manifestfärger ska följa den valda Vardag-identiteten, inte ligga kvar som gamla Flutter-standardfärger.

Verifiera sida vid sida: startskärm, inloggning, Hem, Kalender, Min dag, Sysslor, Mer och formulär. Kontrollera normal och stor text, liten mobil och bred skärm samt installerad PWA-ikon. Redovisa att redan installerade PWA:er kan behöva uppdateras för att visa nytt namn/ikon; lova inte att cache uppdateras omedelbart.

## 2. Skydda gemensamma data först

Båda apparna använder samma Firebase-backend. Behåll befintliga samlingar, fält, roller och serverkontrakt. Fokusläge är ett visningsläge, inte en behörighetsroll.

Flutter bevarar redan aktiviteter utan klockslag vid redigering. Behåll denna rättning. Däremot bygger `lib/widgets/add_event_sheet.dart` om packlistan vid sparning och hämtar klarstatus från dokumentet som öppnades. Detta kan tappa radmetadata och återställa andra användares avbockningar.

- Skicka inte packlistan om bara titel, datum eller tid har ändrats.
- Bevara metadata på oförändrade rader och hantera samtidig redigering av listan.
- Bevara upprepningsundantag, avbockningar, källkopplingar och `lessonPrep`.
- Ändra inte importerade posters ursprung oavsiktligt vid vanlig redigering.
- Avsluta gamla prenumerationer vid konto-/familjebyte. Kassera sena svar för fel användare eller datum.

Referenser: Androids `AktivitetPayload`, `ChecklistUpdates`, `LessonPrep` och `docs/assistent-steg3-kontrakt.md`.

**Godkänt:** titeländring i Flutter återställer inte Androids avbockning; överhoppade förekomster förblir överhoppade efter redigering.

## 3. Mer och gemensam navigation

Huvudflikar: **Hem · Kalender · Sysslor · Mer**.

Mer ska innehålla:

- Överst: Återkommande, Uppgifter, Inkorg.
- VARDAG: Timer, Inköpslista, Mat & matsedel, Lathund.
- PLANERING: Arbetsschema, Vardagsplan.
- IMPORT & DATA: Skanna schema, Importer.
- INSTÄLLNINGAR: befintliga inställningar inklusive rutiner.

Uppgifter, Inkorg, PLANERING och IMPORT & DATA är för förälder/admin enligt gällande regler. Städdag och Sysslostatistik hör till Sysslor. Rutiner hör till inställningarna i Mer.

Genvägar ska gå till rätt huvudflik och undersida, inte skapa konkurrerande kopior av huvudvyer. Tillbaka ska fungera. Ta bort verktygsknappen från vanliga Hem och vuxnas separata Min dag, men behåll en fungerande väg till Mer, utloggning och att lämna fokusläge för barn-/fokusvyer utan flikfält.

Referenser: Androids navigation, `ToolsRoutes`, `SettingsScreen` och `docs/hem-och-mer.md`. Lokalisera aktuell implementation; filnamn kan skilja sig från tänkta skärmnamn.

## 4. Fria Uppgifter

Bygg klientstöd för `tasks`, separat från sysslor: lista, skapa, öppna, ändra, slutföra, återöppna och ta bort.

Stöd titel, deadline med valfri tid, visningsdatum, ansvarig vuxen eller vem som helst, berörda familjemedlemmar, källanteckning, koppling till aktivitetsförekomst och öppen/klar status.

Håll `dueDate`, `showFromDate` och `occurrenceDate` åtskilda. Följ `TaskModel`, `TaskRepository` och de faktiska Firestore-reglernas fältformat och validering. Barn och ungdomar ska inte prenumerera på vuxenuppgifter, men kan vara personer som uppgiften handlar om.

**Godkänt:** uppgifter skapade i respektive app går att läsa och hantera i den andra med rätt behörighet.

## 5. Inkorg och anteckningar

Flutter-projektet har serverstödet, men saknar motsvarande klientgränssnitt. Återanvänd `onNoteWritten` och `confirmNoteActions`; bygg ingen separat AI-tolkning.

Inför:

- Ny anteckning med originaltext, gemensam som standard och möjlighet till privat.
- ”Vem gäller det?” med hela familjen, inklusive vuxna.
- Status för sparad, tolkning pågår, behöver granskas, bekräftad, avfärdad och misslyckad.
- Förslagskort och val av vilka åtgärder som ska bekräftas.
- Omtolkning, återförsök och dubblettvarning enligt Android.
- Resultat per åtgärd, inklusive överhoppade åtgärder och anledning.

Tryck på kort öppnar fullständig markerbar originaltext, datum, berörda personer och vad som hänt. **Ändra** och **Ta bort** ska synas direkt.

Ändring skapar först en ny anteckning och mjukraderar sedan den gamla. Originaltexten får inte skrivas över. Befintligt skapat innehåll behålls och detta ska framgå. Oförändrad anteckning ska inte skapa en ny kopia. Hantera delvis misslyckad ändring sanningsenligt.

När något skapats ska borttagningen kunna erbjuda bara anteckningen eller anteckningen med det som skapades. Följ `InboxViewModel.deleteWithCreated` och dess skydd; källkoppling ger inte generell rätt att radera en aktivitet som anteckningen bara kompletterat.

Privata anteckningar får inte läcka genom frågor, dubblettkontroll, överblick eller källänkar. Anpassa frågor efter reglerna, inte genom efterfiltrering av otillåten data. Bekräfta med `noteId`, `revision` och `actionIds` enligt serverkontraktet. Hantera gamla förslag och dubbla tryck.

Lägg anteckningsknappen bredvid vädret på Hem för vuxna. Öppna Ny anteckning med tangentbordet uppe. Visa ”Sparad i Inkorgen.” med **Öppna** när sparningen lyckats. Androids snabbväg från Hem har ingen dubblettfråga.

Referenser: `NoteModel`, `NoteRepositoryImpl`, `InboxViewModel`, `InboxScreen`, `NoteEdit`, `functions/note_inbox.js`, `functions/note_confirm.js` och `docs/assistent-steg3-kontrakt.md`.

## 6. Personligt Hem och Inför i morgon

Flutter har en enklare morgondagslista. Porta Androids nuvarande `TomorrowOverviewEngine` och anslutning till Hem, inte äldre produktplaners avsikter.

Överblicken ska omfatta konflikter/lämning/hämtning, brådskande uppgifter, packlistor, lektionsförberedelser, anteckningar för granskning, relevanta aktiviteter och särskilda skolhändelser, arbetspass över midnatt, relevanta sysslor, uppgifter som nått visningsdatum och giltig bekräftad information.

- Följ motorns urval, sortering och dubblettregler. Fönstret slutar vid imorgon.
- Vanliga lektioner ska inte fylla överblicken; prov, läxor och uttryckliga förberedelser kan visas.
- Valet egna/otilldelade uppgifter får inte samtidigt filtrera bort familjens aktiviteter eller konflikter.
- Datum och dag ska vara begripliga på varje rad.
- Informationsrader visar förslagets titel och giltighet, inte brevets första rad.
- Informationsdetaljen erbjuder Dölj, Visa brevet och Stäng. Dölj avslutar familjens visning genom befintligt giltighetskontrakt, utan att radera originalet.
- Matcha aktuellt personligt Hem och vägen till Min dag.

Följ senaste bortvalen: ingen Upptagen-knapp eller gammal familjelappsremsa på Hem, ingen ”Jag tar det” i konfliktdialogen, ingen ”Välj middag”-rad i morgondagsöverblicken. Dölj sjukhusmatval och Besök enligt Androids aktuella flöden.

`family_notes` och `notes` är olika funktioner. Blanda inte ihop dem och radera inte äldre data som del av portningen.

## 7. Gemensamt aktivitetsformulär

Använd samma formulär från Hem, Kalender och Min dag. Ordning: **titel, datum, vem, tid**. Inget obligatoriskt symbolsteg.

Tre tidslägen: **Klockslag**, **Heldag**, **Tid inte bestämd**. Använd exakt Androids `timeMode`-värden och representation. Tidlöst innebär tom `time` och ingen `endTime`; valt klockslag tar bort tidlöst läge. Importerad heldag ska förväljas korrekt.

Förvalt datum: idag från Hem, vald dag från Kalender, aktivitetens datum vid redigering. Bevara seriens startdag enligt Androids datumlås och redigeringsregler.

**Fler val**: upprepning/slutdatum, förberedelse dagen innan, packlista, symbol och mall. Sammanfatta ifyllda val och visa befintliga val vid redigering.

**Skriv eller säg** fyller formuläret för aktiviteter och sparar inte direkt. Behåll fält som meningen inte nämner. Behåll befintliga bekräftelseflöden för sysslor, middag och inköp. Okänd mening kan bli titel enligt Androids logik.

Skydda mot oavsiktlig stängning genom svep/tryck utanför och behåll tydliga stängningsvägar. Skilj lokalt köad sparning från serverbekräftad. Påstå inte lokal beständighet om webbplattformen inte garanterar den. Hantera sena nekanden, utkast och dubbeltryck utan dubbletter.

Efter sparning ska **Visa** öppna rätt datum och detalj i den riktiga Kalender-fliken.

Referenser: `AktivitetFormularLogik`, `AktivitetPayload`, `FormularTolkning`, `AktivitetSparning`, `SparBekraftelse` och `docs/bygge-1.md`. Dokumentet innehåller äldre lägen; aktuell kod och senare tidslägesbeslut gäller.

## 8. Ändring, borttagning och Återkommande

- Gemensam aktivitetsdetalj från Hem, Kalender och Min dag.
- Redigera öppnar alltid förifyllt formulär.
- Dagens aktiviteter i Min dag erbjuder ”Ändra eller ta bort” utan att förlora transportvalet.
- Synlig Ta bort i aktivitetsdetalj och Ta bort syssla i sysseldetalj.
- Återkommande: fråga om rätt enskilt datum eller alla gånger.
- Använd radens förekomstdatum, inte veckans måndag eller seriens startdatum.
- Avboka relevanta påminnelser och hantera misslyckad skrivning tydligt.

Återkommande under Mer visar aktiviteter och sysslor tillsammans med titel, vem, när och typ. Alla får se listan; borttagning följer rättigheter. Kalenderns genväg går till samma lista i Mer.

Flutters `lib/utils/event_actions.dart` innehåller redan delar av aktivitetsborttagningen: komplettera och återanvänd.

## 9. Kalender, Min dag och tillförlitlighet

För över kompakt kontrollrad, ett tydligt personfilter, aktiv filtertext och Visa alla, familjemedlemmar med profilbilder och medlemsdag för valt datum, väder endast för vald dag med underlag, lättåtkomlig Lägg till och bevarad scroll/datum/filter/läge efter detaljer.

Flutter har även Agenda: behåll fungerande lägen och tillämpa förbättringarna där. Matcha aktuella Android-beteenden utan att ta bort användbar Flutter-funktion av misstag.

Min dag ska skilja laddning, verkligt tom dag, delvis läsfel och fullständigt läsfel. Visa fungerande data och erbjud återförsök. Visa inte ”Inget planerat” under hämtning eller efter ett dolt fel. Källor, person och datum ska hållas isär.

Verifiera korta tidsblocks läsbarhet, dagsfärger, låg stimulans, stor text och knappar ovanför navigationen. Prova snabbt datumbyte, kontobyte, familjebyte och midnatt/resume.

Referenser: `DataTillstand`, `MinDagTillforlitlighet`, `CalendarWeatherSelection`, `docs/fas-ux-01.md` och `docs/fas-ux-02.md`. Historiska statusrader i rapporterna är inte aktuellt grenläge.

## 10. Skola, import och påminnelser

Jämför befintligt Flutter-stöd och komplettera:

- Förberedelse dagen innan lektion och avbockning per lektionsdatum via `lessonPrep`.
- En återkommande förberedelse får inte bli permanent klar efter första tillfället.
- Skollunch i Min dag när relevant matsedel finns.
- Egen matsedel: återanvänd befintligt stöd, komplettera luckor.
- Flera ICS-filer i samma importflöde och begripliga namn från innehållet.
- Hitta/ta bort skannade importer och ångra där Android erbjuder det.
- Vanliga skollektioner följer Androids regler för uteblivna lektionsnotiser.

Kontrollera både lokala notiser och webbens serverpåminnelser. Klientändringar förändrar inte automatiskt serverutskick. Identifiera backendluckor separat, särskilt heldag vid import och informationsförslagens datumtolkning. Anta inte att en dokumenterad idé är implementerad eller driftsatt.

## 11. Test och leverans

Kör analys, relevanta befintliga tester och nya beteendetester för ändringarna. Bygg webb och andra faktiskt stödda mål. Testa mot testdata, inte genom att ändra familjens riktiga innehåll.

Slutchecklista (uppdaterad 2026-09-25 av Claude, gren `vardag-flutter` — se `docs/vardag-flutter.md`):

- [ ] Vardag visas som namn i app, webb och installerat läge. *Kod klar (label, titel, manifest, widget); installerat läge ej provat på enhet.*
- [x] Originalets logga/symbol används och är visuellt verifierad. *Vektorerna kopierade oförändrade, PNG renderade deterministiskt, granskade som bild. Hemskärmsikonen på riktig telefon ej provad.*
- [ ] Tema och centrala skärmar har jämförts sida vid sida. *Färgroller portade och Mer, Uppgifter, Inkorg, formulär, Inför i morgon och inloggning granskade som skärmdumpar; Hem, Kalender och Min dag kräver enhet.*
- [ ] Mer, Uppgifter, Inkorg och Återkommande fungerar med rätt roller. *Byggt och rollstyrt; ej provat mot riktiga regler.*
- [ ] Skapa i Android och ändra i Flutter samt omvänt fungerar. *Samma fältformat och portade Android-test; korsprov på enheter kvarstår.*
- [x] Heldag och tid inte bestämd behåller sitt läge. *Automatiskt testat (`test/plan_godkant_test.dart`).*
- [x] Samtidig titeländring/avbockning tappar inte data. *Automatiskt testat; ej provat mellan två enheter.*
- [x] Borttagning av en förekomst påverkar rätt datum. *Radens förekomstdatum används överallt; undantag via `arrayUnion`.*
- [x] Lektionsförberedelse bockas av för rätt dag. *`lessonPrep.doneDates` per lektionsdatum; automatiskt testat.*
- [ ] Anteckning kan skapas, granskas, ändras och tas bort. *Hela flödet byggt; kräver driftsatta `onNoteWritten`/`confirmNoteActions` och prov på enhet.*
- [ ] Privat anteckning och vuxenuppgifter visas endast för rätt användare. *Frågorna är avgränsade enligt reglerna; ej provat mot riktiga regler.*
- [x] Hem visar rätt dag och relevanta uppgifter utan dubbletter. *Androids motor och 93 Android-test portade.*
- [ ] Nätavbrott och nekade skrivningar ger sanningsenliga besked. *Byggt (lokalt köat/serverbekräftat, sena nekanden); ej provat utan nät.*
- [ ] Barn-/fokusläge når Mer och kan lämnas. *Flikfältet finns kvar och 🧰 öppnar Mer i helskärm; ej provat på enhet.*
- [ ] Storskärm och övriga befintliga Flutter-flöden fungerar. *Storskärmen använder egna teman och rörs inte; hela testsviten grön; ej provat på skärmen.*
- [ ] Riktig iPhone/PWA har provats: tangentbord, tillbaka, formulär, ikon, namn och notiser. *Kvarstår — ingen enhet i passet.*

Saknas enhet eller åtkomst ska motsvarande kontroll redovisas som kvarstående, inte godkänd.

Leverera implementation, uppdaterad checklista, testresultat, eventuella backendbehov, begränsningar och publiceringsinstruktioner. Skilj kodgranskat, automatiskt testat, enhetstestat och publicerat. Gör inte namnbytet genom att ändra appens tekniska identitet eller signering: Android-projekten delar produktionsidentitet, så versionering och uppdateringsväg måste kontrolleras före eventuell APK-leverans.

## Underlagets begränsningar

Planen bygger på lokal kod, git-historik och projektrapporter. Appar och driftsatt backend har inte körts eller verifierats i denna granskning. Äldre planer är bakgrund; dagens kod och de senaste användarbesluten har företräde.

## Status per etapp (2026-09-25)

Inventering av befintligt, delvis befintligt, saknat och färdigt finns i
`docs/vardag-flutter.md` (tabellen "Sammanfattning per etapp"). Kort:

| Etapp | Före | Nu |
|---|---|---|
| 1 Namn, logga, identitet | Saknat | Färdigt i kod; enhetskontroll kvarstår |
| 2 Gemensamma data | Delvis (bara tidlöst) | Färdigt, automatiskt testat |
| 3 Mer och navigation | Delvis (Verktyg-sida) | Färdigt |
| 4 Uppgifter | Saknat | Färdigt i kod |
| 5 Inkorg | Saknat (bara server) | Färdigt i kod |
| 6 Inför i morgon | Delvis (enkel lista) | Färdigt, motorn automatiskt testad |
| 7 Formulär | Delvis | Färdigt, logiken automatiskt testad |
| 8 Ändring/borttagning/Återkommande | Delvis | Färdigt |
| 9 Kalender, Min dag | Delvis | Färdigt i kod |
| 10 Skola, import, påminnelser | Delvis | Färdigt i klient; backendluckor listade |
| 11 Test och leverans | — | Analys och tester gröna, webbygge; enhetsprov och publicering kvarstår |
