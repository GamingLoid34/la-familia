# Kalenderpilot (2026-10-21)

Lokalt förslag på grenen kalenderpilot; inte driftsatt. Gemensamt datakontrakt finns i vardag-contract, commit 566804d, docs/Kalenderpilot-datakontrakt.md. Androids motsvarande arbetsgren ligger i vardag-kalenderpilot.

- families.calendarPilot (saknat = false) döljer specialistverktyg, filtrerar hemdata och stoppar syssle-/timerpåminnelser. Webbnotisfunktionen måste driftsättas före aktivering. Gamla klienter förstår inte flaggan.
- Arkivet läser och exporterar fem samlingar utan att radera eller skriva. Flaggan är ingen ny säkerhetsgräns i Firestore.
- Oförändrad recurrence utelämnas ur formulärets uppdatering, även för daily och okända typer. Importproveniens och oförändrad packlista bevaras.
- Flytt av ett tillfälle skriver atomiskt ett undantagsdatum och ett fristående planner_events-dokument, markerat med originalSeriesId/originalOccurrenceDate. Serien lagrar detachedOccurrences för idempotenta återförsök. Kräver nätanslutning. Målet påverkas inte av senare serieändring. Importerade serier flyttas i källan.
- Ingen ny navigation, ansvarsfunktion eller backendflytt ingår.

Verifiering: alla 421 tester passerade i slutlig helkörning. flutter analyze utan anmärkningar. Slutligt flutter build web lyckades. Funktionernas 116 befintliga tester samt två nya prov av syssle-/kalendernotiser med pilotflaggan passerade; web_reminders.js passerade ESLint. Firestore-emulatorn verifierade fem transaktions-/behörighetsfall via Android-repots backend-tests.

Före pilot: bygg iOS på macOS, prova två verkliga telefoner, offline och processdöd, familjebyte, omstart/behörigheter, återimport samt 48 timmar utan dolda sysslonotiser. Storskärm/specialpresentationer är inte verifierade för den nya flaggan. Androids nya kvittensjournal har inte införts i Flutter. Ingen garanti om omedelbar larmsynk på en avstängd app lämnas.

## Revision 2, 2026-10-22

Version 1.0.1+28, pilotprotokoll 2. Ersätter ovanstående begränsningar där de skiljer sig: även Flutter/PWA har nu kvittensjournal för kalenderformulär och förekomstoperationer, med writeId, familj/användare, serververifiering och beständiga varningar. Flyttens ursprungsdatum visas, ångra återställer enligt serien, serieradering omfattar flyttade tillfällen och kräver nät. chore_log ingår i arkivet. Oförändrade tidfält hindrar inte titeländring på befintlig övernattning.

Ny callable activateCalendarPilot och lokala regeländringar kräver inventerade enheter med färska protokollrapporter samt dokumenterade telefonprov innan flaggan får aktiveras. Direkt aktivering blockeras; förälder får avaktivera. Helt okänd familjestatus stänger specialistfunktioner, medan saknat fält i känt familjedokument betyder ordinarie läge. Gamla klienter kan fortfarande skriva specialistdata.

Projektplanens iPhone-mål är PWA. Native iOS-bygge är inte ett pilotkrav. Androids kontroll vid lokalt larms utlösning har inte implementerats för native Flutter-notiser. PWA använder serverns webbpåminnelser.

Verifiering revision 2: 421 Fluttertester, 121 funktionstester, 9 Firestore-regel-/transaktionsprov; analys utan anmärkningar. Testerna calendar_pilot_gate.test.js och calendar_pilot_reminders.test.js täcker den nya aktiveringskontrollen respektive faktiskt filtrerade utskick med falsk transport. Journalens omladdning/lagring måste fortfarande provas på iPhone-PWA, liksom 48-timmarsprovet och återimport. Inget är driftsatt.

Gemensamt kontrakt i vardag-contract/docs/Kalenderpilot-datakontrakt.md är omskrivet för revision 2. Full rapport och namngivna Androidprov finns i Androidrepots docs/Kalenderpilot-granskning-2.md.

## Rättelse: veckobrevsuppgifter, 2026-10-22

Version 1.0.2+29 återför tasks till kärnan. Ny vuxenvy på Hem/Alla uppgifter och i Kalenderverktyg; fokusvyn har en ingång till samma lista. Vyn visar barnkoppling, datum och inkorgskälla, och kan markera klar/öppen med en partiell status/doneAt-uppdatering. Ingen inkorgsimport eller fullständig redigerare har portats från Android. Tasks är fortsatt vuxenbegränsade i befintliga serverregler. Barn/utloggade/förälder utan familj startar ingen tasks-prenumeration, verifierat i fyra widgettester. Tasks tas ur arkivets kategorier. Specialistverktygen förblir dolda.

Verifierat: 423 Fluttertester plus 4 nya åtkomst-widgettester, analys utan anmärkningar, releasewebb byggd. 124 funktionstester och 17 tasks-regelprov i Firestore-emulator passerade. Ingen regel-/funktions-/familjedataändring behövs. Androids fulla leveransrapport finns i docs/Veckobrevsuppgifter-kalenderpilot-2026-10-22.md i vardag-kalenderpilot.

Publicerad på https://la-familia-5d9f5.web.app som 1.0.2+29. Åtta HTTP-resurser verifierade byte för byte mot det frysta releasepaketet. Endast Hosting distribuerades; ingen backend-/regeländring.
