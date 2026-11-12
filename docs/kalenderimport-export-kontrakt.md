# Kalenderfilimport, format 2

`importIcsText` och `previewIcsText`, callables i `us-central1`, används av Android och Flutter (iOS/web).
URL-prenumerationerna är oförändrade och använder en annan väg.

Klienterna använder den separata, alltid skrivfria `previewIcsText` för granskning.
En äldre server som saknar endpointen ger därför ett säkert fel och kan inte
ignorera preview-parametern och importera innan användaren bekräftar.

Request: `icsText`, `calendarName`, `memberUid` (krävs för schema),
`kind: activity|schedule`, `fromDate: YYYY-MM-DD`, `toDate: YYYY-MM-DD`,
`preview: true|false`. Valfritt `familyId` måste stämma med inloggad användare.
Endast parent/admin med giltig familj; vald medlem måste finnas i samma familj.
Behörigheter kontrolleras igen i skrivtransaktionen.

Datumintervallet är inklusivt, högst 366 dagar. Utan datum används idag i
Europe/Stockholm till idag + 365 dagar. Användaren kan uttryckligen välja historik.
`preview:true` skriver ingenting och returnerar:

- `count`: antal faktiska kalenderposter (flerdagars heldag kan ge flera poster).
- `fromDate`, `toDate`, `timeZone: Europe/Stockholm`.
- `alreadyImported`, `importId`, `warnings`, `maxEvents:400`, `sourcePreserved`.

Klienterna visar period, antal, familjesynlighet och att upprepningar blir separata
tillfällen inom perioden före bekräftelsen. Samma payload skickas med `preview:false`
vid bekräftelse. Max 400 poster och 5 MiB UTF-8-källa. Överskridna gränser avvisar
hela importen; aldrig tyst avklippning eller partiell batch.

Parsern använder node-ical och hanterar UTC, IANA/igenkända Windows-tidszoner,
flytande svensk tid, RRULE, EXDATE, RECURRENCE-ID/flytt och STATUS:CANCELLED.
Serier som började före perioden expanderas ändå. Flyttade tillfällen vars
ursprungsdatum ligger utanför perioden inkluderas när den nya tiden hamnar i den.
Heldag är VALUE=DATE; tidsatt 00:00 är inte heldag. Heldag DTEND är exklusivt.

Nuvarande uttryckliga begränsningar: RDATE/EXRULE, RANGE=THISANDFUTURE,
upprepning oftare än dagligen/BYHOUR/BYMINUTE/BYSECOND och okända tidszoner
avvisas före skrivning. Tidsatta nattpass/flerdagars avvisas också tills båda
klienternas gemensamma modell stöder slutdatum. Vi skriver inte `24:00`, som
Androids LocalTime inte kan läsa. Tidsatta sekundvärden visas med minutprecision,
med originalvärden bevarade i originalkällan och icsOriginalStart/End.

`CLASS:PRIVATE`, `CLASS:CONFIDENTIAL` och okända sekretessklasser inom vald
period avvisas före skrivning. Filimporten är familjedelad och får inte göra
privata uppgifter offentliga för familjen. Exportera enbart de delade posterna
från källan för denna importväg. Den separata kommande kontosynken lägger i
stället nya inkommande aktiviteter i ägarens privata lagring.

Poster har vanliga planner_events-fält plus `icsKey` (instans + dag),
`icsInstanceKey` (ursprunglig UID + RECURRENCE-ID eller start), `icsOriginalStart`,
`icsOriginalEnd` (ISO), `icsAllDay` och `calendarImportId`. Flerdagars heldag delas
för visning; alla delar behåller gemensam instansnyckel och originalintervall.
Långa textfält kortas med synlig varning; originaltexten bevaras.

Import-id är SHA256 över familj, vald person, typ och filens innehåll (normaliserade
radslut/BOM). Namn och datumintervall ingår inte. En identisk fil för samma mål
returnerar `alreadyImported:true` och den ursprungliga perioden, även om nya datum
valts. Klienten ska tydligt meddela detta. Samma fil utökar aldrig importen tyst.
Ändrade exporter är nya filer, inte en synkstrategi; de kan innehålla överlappande
händelser. Riktig synk måste använda provider-ID och revisionskontroll.

Alla poster, importmetadata och originalkälla sparas atomiskt i en Firestore-
transaktion. `calendar_import_sources/{importId}` innehåller familj, antal chunks,
originalstorlek, SHA256 och encoding=gzip-base64. Under `chunks/000`, `001`, ...
finns originalfilen i base64-chunks. Samlingen är server-only med befintlig default
deny; inga klientregler har öppnats. När användaren tar bort kalenderimporten
rensar `onCalendarImportDeleted` även originalkällan och dess chunks. Triggern
kontrollerar familj och att importen inte hunnit skapas igen, så att en fördröjd
leverans inte raderar en ny originalkälla. Fullständig familjeradering måste också
omfatta samlingen.

Tester: `node functions/test/ics_text_import.test.js` med Node 24. De omfattar
DST, gamla serier, flytt över intervallgräns, undantag, annullering, heldag/midnatt,
uttalade begränsningar, maxgräns, medlemsbehörighet, familjebyte, preview utan writes,
atomisk lagring, bevarad originalfil och dedup.
