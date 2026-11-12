# Kalenderleverantörer

`providers.js` innehåller nätverksadaptrar, inte OAuth, lagring eller konfliktpolicy.
Varje metod kräver ett riktigt lyckat leverantörssvar. Mocktesterna innebär inte
att ett verkligt konto är anslutet eller att iCloud har verifierats mot en enhet.

## Kontrakt

```js
const {GoogleCalendarProvider, OutlookCalendarProvider, ICloudCalendarProvider} = require('./providers');
const google = new GoogleCalendarProvider({accessToken, fetchImpl});
const outlook = new OutlookCalendarProvider({accessToken, fetchImpl});
const icloud = new ICloudCalendarProvider({username, appPassword, fetchImpl});

await google.listCalendars(); // [{id,name,writable,timeZone?,raw}]
await google.listEvents(calendarId, {syncToken});
// {items:[{id,etag,deleted,raw}], syncToken:string|null, full:boolean}
await google.getEvent(calendarId, eventId); // {id,etag,deleted,raw}
await google.createEvent(calendarId, {operationId, event});
await google.updateEvent(calendarId, eventId, event, {etag});
await google.deleteEvent(calendarId, eventId, {etag});
```

Alla tre följer samma metodkontrakt. `event` är ett Google Event-body,
Microsoft Graph Event-body respektive `{ics: 'BEGIN:VCALENDAR...'}`. `raw`
bevarar leverantörsdata. Adapterlagret gör ingen översättning till Vardags
aktivitetsmodell. Läsresultat kan innehålla personliga detaljer; lagra dem bara i
användarens serverprivata anslutningsyta och exportera dem inte som familjefält.

Synkmotorn måste spara operationId före skrivningen och återanvända samma id
vid återförsök. Google väljer deterministiskt event-id och markerar operationen
i private extendedProperties. Outlook använder transactionId. iCloud väljer en
deterministisk `.ics`-resurs och använder `If-None-Match: *`. Vid identifierad
Google-/iCloud-dublett returneras befintlig post med `alreadyExists: true`;
returnerat innehåll kan redan vara redigerat på leverantörssidan. Återförsök får
inte skriva över det utan vanlig konfliktkontroll.

`createdEventIdentity(provider, calendarId, operationId)` exporterar exakt samma
identitet som create använder: `{id}` för Google/iCloud och `{transactionId}`
för Outlook. Återställning efter okänt skrivresultat får använda den identiteten,
inte gissa utifrån titel eller tid. Om den lokala aktiviteten hunnit raderas
ska synkmotorn sätta den okända operationen i karantän före inkommande import,
annars kan en redan skapad extern post återskapa den raderade aktiviteten.

Uppdatering och borttagning kräver ETag. `conflict` (409/412) ska visas eller
lösas av synkmotorn; återförsök får aldrig ta bort If-Match. `deleted: true` är
en borttagning hos källan, inte ett tillstånd som automatiskt tillåter att en
annan familjemedlems aktivitet tas bort.

För `full:true` får saknade fjärr-id:n jämföras först när hela läsningen lyckats.
För `full:false` gäller bara returnerade ändringar. Spara ny syncToken först
efter att alla ändringar lagrats. `sync-reset-required` kräver en komplett ny
läsning; radera inte befintlig spegling före den lyckats. Alla HTTP-fel,
pagineringsfel, för stora svar och inkompletta data avbryter omgången.

## Återkommande aktiviteter

Google hämtar oexpanderade serier med `singleEvents=false`, RRULE/EXDATE,
inställda undantag samt `recurringEventId`/`originalStartTime` för flyttade
förekomster. Inkrementella anrop använder samma parametrar som första läsningen.
Tidsfönster filtreras inte i adaptern eftersom Google förbjuder dem med syncToken.
En separat master-GET före skrivning kompletteras med en sökning på iCalUID för
att hitta undantag som inte finns på masterdokumentet. Resultatet markeras med
`raw.vardagSeriesHasExceptions`; normaliseringen måste avvisa sådana serier.
Detta gäller också återspelning av en redan sparad utgående operation.

Outlook gör paginerad komplett läsning för vald kalender och returnerar alltid
`syncToken:null, full:true`. Microsofts stabila delta-API gäller primära
kalenderns expanderade calendarView i ett tidsfönster; beta-API används inte.
Varje seriesMaster kompletteras med `exceptionOccurrences` och
`cancelledOccurrences` genom ett separat GET med `$select` och `$expand`, både
vid listning och enskild läsning före skrivning.
Ändrad ETag mellan läsningarna ger `provider-changed-during-sync` och en
senare komplett omläsning. Paginerade undantagsrelationer avvisas uttryckligen
tills de har en testad implementering; de trunkeras aldrig.

CalDAV överför hela VCALENDAR-resursen inklusive VTIMEZONE, RRULE, EXDATE och
RECURRENCE-ID. Skrivningen måste innehålla en serie/ett UID med alla dess
undantag. Att ersätta resursen med endast ett enskilt tillfälle skulle annars
förstöra serien. `sync-collection` används när servern stöder det. Annars görs
komplett `calendar-query`. En återkallad behörighet förväxlas inte med ett
utgånget synktoken.

Synkmotorn måste uttryckligen stoppa regler och undantag som dess egen
normalisering inte stöder före en skrivning. Adapterns stöd för råa serier
betyder inte att Vardags begränsade recurrence-format kan representera alla
leverantörsregler. Google-/Outlook-PATCH bevarar utelämnade fält. PUT i CalDAV
ersätter hela resursen, vilket kräver en sammanslagning av ursprungsinnehållet.

Mötesinbjudningar ingår inte: payload med attendees eller organizer, samt
CalDAV med ATTENDEE/ORGANIZER/METHOD, avvisas innan nätverksanrop. Kalenderkopior
ska inte oavsiktligt skicka mötesmail. Synk av befintliga möten kräver dessutom
en separat policy i synkmotorn så att en titeländring/borttagning av ett redan
inbjudet möte aldrig automatiskt blir en uppdatering till alla deltagare.

## Säkerhet och gränser

Google anropas endast på `www.googleapis.com/calendar/v3/`, Graph endast på
`graph.microsoft.com/v1.0/`. Bearer-token följer inte redirect. Graphs nextLink
måste peka till samma resurssökväg. iCloud tillåter bara HTTPS på
`caldav.icloud.com` och `p<nummer>-caldav.icloud.com`, normal port, utan userinfo,
query eller fragment. Redirect valideras före nästa Basic-auth-anrop. Kalender-
resurser får inte peka till en annan kalender. XML-DTD/entitetsdefinitioner är
förbjudna. Svar begränsas till 8 MiB, 100 sidor och 10 000 poster. Ett enskilt
HTTP-anrop avbryts efter 25 sekunder. Inga HTTP-feltexter eller token loggas.

Råa token och iClouds appspecifika lösenord hör hemma i krypterad serverlagring
med användarbindning, aldrig i familjedokument, loggar, exporter eller klientens
synkstatus. Google/Outlook-token måste förnyas av OAuth-lagret; adaptern tar emot
en aktuell accessToken. `unauthenticated` leder till förnyelse/återanslutning,
`rate-limited` till backoff enligt retryAfter. Även andra fel kan behöva backoff.

## Registrering och kontotest som återstår

- **Google:** aktiverad Calendar API, OAuth-webbklient med exakt HTTPS callback
  och samtyckesskärm. Begär
  `https://www.googleapis.com/auth/calendar.events` och
  `https://www.googleapis.com/auth/calendar.calendarlist.readonly` samt offline
  access för refresh-token. Testläge behöver tillåtna testanvändare; en bred
  extern produkt kräver Googles granskning av tillämpliga känsliga scopes.
- **Microsoft:** Entra app registration som tillåter både personliga Microsoft-
  konton och organisationskonton om båda ska stödjas. Registrera exakt server-
  callback som Web-redirect, använd authorization code med PKCE, delegerad
  `Calendars.ReadWrite` och `offline_access`. Organisationens administratör kan
  blockera användarsamtycke. Ingen application-wide kalenderbehörighet behövs.
- **iCloud:** Apple Account med tvåfaktorsautentisering och appspecifikt lösenord
  för den anslutna användaren. Lösenordet ska lämnas i säker anslutningsvy, aldrig
  i chatten. Apple beskriver ny kontoauktorisering för stödda tredjepartsappar,
  men vi har ingen verifierad publik utvecklarregistrering för den vägen.
  CalDAV-discovery och app-lösenord används här; ett verkligt konto behövs för
  att verifiera Apples serverbeteende och slutlig användarupplevelse.

Ingen av dessa registreringar eller verkliga konton har ändrats av
adapterarbetet. Anslutningar får inte markeras aktiva innan vald kalender har
lästs och användarens godkända synkriktning har sparats.

## Verifiering

```sh
/home/oscar/utvecklingsverktyg/node24/bin/node functions/test/calendar_providers.test.js
```

Mocktester täcker paginering, serier, undantag, tombstones, token-reset,
idempotens, ETag-konflikter, privata felmeddelanden, blockerade redirects,
CalDAV-discovery och fallback. De ersätter inte kontotest med Google, Outlook
(personligt och organisationskonto) och iCloud före användarutskick.

## Primärkällor kontrollerade 2026-10-30

- [Google events.list och synktoken](https://developers.google.com/workspace/calendar/api/v3/reference/events/list)
- [Google eget event-id vid insert](https://developers.google.com/workspace/calendar/api/v3/reference/events/insert)
- [Google villkorade anrop med ETag](https://developers.google.com/workspace/calendar/api/guides/version-resources)
- [Google OAuth-scopes](https://developers.google.com/workspace/calendar/api/auth)
- [Graph event, serier och undantag](https://learn.microsoft.com/en-us/graph/api/resources/event?view=graph-rest-1.0)
- [Graph GET av serie inklusive undantag](https://learn.microsoft.com/en-us/graph/api/event-get?view=graph-rest-1.0)
- [Graph transactionId vid skapande](https://learn.microsoft.com/en-us/graph/api/user-post-events?view=graph-rest-1.0)
- [Graph stabilt delta-API](https://learn.microsoft.com/en-us/graph/api/event-delta?view=graph-rest-1.0)
- [Apple appspecifika lösenord](https://support.apple.com/en-us/102654)
- [Apple åtkomst från tredjepartsappar](https://support.apple.com/en-us/121539)
- [CalDAV RFC 4791](https://www.rfc-editor.org/rfc/rfc4791)
- [WebDAV-synk RFC 6578](https://www.rfc-editor.org/rfc/rfc6578)
