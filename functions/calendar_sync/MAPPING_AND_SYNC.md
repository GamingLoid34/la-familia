# Säker synkdelmängd och synkflöde

`event_mapping.js` tolkar Google-, Microsoft Graph- och iCloud-händelser till
Vardags gemensamma fält. `toCanonical(provider,raw)` och
`fromCanonical(provider,event,{originalRaw,operationId})` returnerar antingen
`supported:true` med `event`/`payload` eller `supported:false,reason`.
`fingerprint` jämför det normaliserade innehållet, inte ID, tidsstämplar eller
checklistor. Originalleverantörens hela svar ligger separat i serverns cache.

Stöd: tidsatta aktiviteter med start och slut samma svenska kalenderdygn;
en heldag; Vardags dagliga, veckovisa, varannan vecka och månatliga upprepning
med slutdatum. Google/iCloud har även undantagsdatum. Vid månadens slut används
explicit BYMONTHDAY för att undvika att parserbibliotekets dag 31 driver till 30.

Det som inte kan representeras säkert ger konflikt och skrivs inte över:
nattpass/flerdagars, sekundprecision, avancerade upprepningsvillkor som inte
ingår i delmängden (vanliga obegränsade dag-/vecko- och månadsserier stöds), COUNT, RDATE/EXRULE, flera veckodagar, flyttade förekomster,
serier med flyttade tillfällen, Outlook-undantag, mötesinbjudningar och
konferens-/onlinemöten. UTC/annan tidszon fungerar för engångshändelser när
ett entydigt UTC-instant finns. Återkommande händelser måste följa svensk/CET-tid
för att inte byta klockslag när sommartiden ändras. Google/Outlook kan ange en
själv som organizer även på vanliga aktiviteter; dessa accepteras när inga
attendees finns, men organizer skickas aldrig i en skrivning.

Google/Graph använder endast PATCH av hanterade fält; okända leverantörsfält
lämnas kvar. En oförändrad beskrivning i HTML och oförändrad rå upprepningsregel
återanvänds. iCloud kräver PUT: där bevaras VCALENDAR-egenskaper, UID, VALARM och
okända VEVENT-egenskaper, medan ändrade kända fält ersätts. UID vid skapande beror
på operationId och blir samma vid återförsök. Originalet visas aldrig i loggar.

API-källor: [Google Events](https://developers.google.com/workspace/calendar/api/v3/reference/events),
[Graph recurrencePattern](https://learn.microsoft.com/en-us/graph/api/resources/recurrencepattern?view=graph-rest-1.0),
[Graph recurrenceRange](https://learn.microsoft.com/en-us/graph/api/resources/recurrencerange?view=graph-rest-1.0).

`sync_service.js` kopplar provider-adaptrar och `reconcile.js` till Firestore.
Alla länkar, original, konflikter, tombstones och outbox är server-only under
`calendar_sync_connections/{id}`. Inkommande aktiviteter skapas atomiskt som
familjesynlig markör `Privat` och ägarens text i `private_activities/{uid}/events`.
Markören innehåller bara befintliga privata aktivitetsfält. Serverdata för en
koppling hamnar aldrig på den familjesynliga markören.

Synk till leverantören tar endast egna manuellt skapade aktiviteter som gäller
användaren själv eller alla. Importer och andras privata poster ingår inte.
Inkommande poster som skapats av en annan synkkoppling exporteras inte vidare
automatiskt. Listor/preparationer bevaras vid uppdatering och ingår inte i
ändringsjämförelsen. Privata detaljdokument får aldrig skugga markörens datum,
tider, behörighet eller upprepningsregel.

Inkommande synk behåller extern integritetsinställning men visar alltid importen
privat lokalt. Länken sparar därför separata localHash/remoteHash och
privacyPolicy=local-private. Utgående redigeringar på dessa poster bevarar
leverantörens integritetsinställning; väntat remote-innehåll jämförs separat.

En fullständig leverantörsläsning måste lyckas innan någon plan körs. Fulla
cachesnapshots får ny generation; connection.remoteCacheGeneration byts först
efter hela körningen. Delta läser bara aktiv generation, så en gammal cachepost
inte kan återuppstå efter borttagning. Googles instansundantag markeras även
på seriemastern; markeringen bevaras över senare fulla läsningar.

Extern skrivning föregås av persisterad outbox. Aktuellt ETag kontrolleras och
If-Match används. Bekräftelsen sparar revisionen som faktiskt skickades och
lämnar en senare lokal ändring osynkad till nästa pass. Inkommande skrivningar
kontrollerar lokal revision, användarens familj/roll, privatkontrakt, lease och
generation inom samma transaktion som markör/detalj/länk. Saknad lokal rad är
konflikt, aldrig automatiskt en radering. En faktisk Firestore-delete skapar
tombstone; systemets redan kvitterade inkommande delete blir inte en ny utgående
radering.

`functions.js` exponerar selectCalendarSyncCalendar, syncCalendarNow,
getCalendarSyncConflicts, resolveCalendarSyncConflict, syncConnectedCalendars
(var 15:e minut) och onSyncedCalendarEventDeleted. Kalenderbyte på befintlig
anslutning kräver frånkoppling. Aktivering gör först en läsprobe; klienten
startar sedan första synken inom samma bekräftade flöde. Konfliktvalen använder
aktuella revisioner och ETags. skip betyder att stoppa synk för just aktiviteten
på kopplingen och behålla båda kopiorna.

Verifiering använder fiktiva konton och in-memory Firestore/provider-adaptrar.
Verklig OAuth, CalDAV, mobilbakgrund och provideracceptans måste fortfarande
provas mot riktiga konton efter serverkonfiguration. Ingen av dessa tester
ansluter till familjens eller en leverantörs riktiga kalender.

## Oklart utfall efter avbruten create

Om leverantören hann skapa en aktivitet men processen dog före kvittens kan
lokalposten hinna raderas innan återförsöket. Då saknas ännu länk och vanlig
tombstone. En sådan redan påbörjad create får beständig outbox-status
`quarantined`; arbetaren stoppar före nästa leverantörslista och kan därför
inte återimportera den externa kopian som en ny privat aktivitet. Konflikten
visas som `ambiguous-create-outcome`, och spärren överlever nya arbetarkörningar.

Användarens uttryckliga val att stoppa synk för aktiviteten sparar en permanent
ignored-post för både lokal-ID och säkert identifierat remote-ID. Google och
iCloud har deterministiskt create-ID från samma `createdEventIdentity` som
adaptern använder. Outlook kräver en fullständig läsning och exakt en träff på
operationens oföränderliga transactionId. Ingen träff, flera träffar eller
ofullständig läsning lämnar spärren kvar; frånvaro bevisar inte att en tidigare
begäran aldrig kommer att bli synlig. Detta återställningsflöde skriver eller
raderar ingenting hos leverantören. Ägaren kan även koppla från kalendern.

Regressionsprov simulerar remote commit → processdöd → lokal radering → flera
återförsök för alla tre leverantörer och verifierar att ingen aktivitet
återuppstår. De provar också explicit skip och Outlooks uteblivna/tvetydiga
transactionId-träff. Se [Graph event.transactionId](https://learn.microsoft.com/en-us/graph/api/resources/event?view=graph-rest-1.0#properties).
