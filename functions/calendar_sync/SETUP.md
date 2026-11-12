# Aktivering av Google-, Outlook- och iCloud-synk

Serverexporterna styrs av `calendar_sync/deployment.js` (standard `enabled:false`).
Aktivera den i samma granskade release som synkfunktionerna driftsätts, efter att
hemligheter och leverantörsprov är klara. Enbart en namngiven deldriftsättning
räcker inte för att undvika oanvända Secret-parametrar: de avstängda modulerna
ska inte laddas under Functions-discovery. Den fasta källkodsflaggan säkerställer
att discovery och det driftsatta serverpaketet använder samma exportlista.

Kodens adapter- och OAuth-tester använder endast påhittade testvärden. Ingen
appregistrering, hemlighet eller skarp anslutning skapas av dessa moduler.
Registrering, driftsättning och riktiga kontotester återstår. Visa leverantören
som ej konfigurerad tills dess; en knapp får inte hävda att synk fungerar bara
för att koden finns.

## Callback och konfiguration

Rekommenderad exakt callback för båda OAuth-registreringarna:

```
https://us-central1-la-familia-5d9f5.cloudfunctions.net/calendarOAuthCallback
```

Backend måste driftsättas med detta namn och region innan kontoanslutning
provas. Ändras URL:en ska både registreringarna och serverkonfigurationen
ändras. Använd serverbaserad Web-callback även när anslutningen börjar från
Android, iPhone eller Flutter-webben; klienten ska aldrig få klienthemligheten.

Föreslagna namn i Google Secret Manager/Firebase Functions secrets:

| Namn | Innehåll |
| --- | --- |
| `CALENDAR_PROVIDER_CONFIG` | JSON med konfiguration för aktiverade Google-/Outlook-klienter |
| `CALENDAR_TOKEN_ENCRYPTION_KEY` | Slumpmässig 32-byte AES-nyckel kodad i base64 |

Providerkonfigurationen kan börja med endast Google. Lägg senare till Outlook
utan att ändra användarnas befintliga anslutningar:

```json
{"google":{"clientId":"<Google client ID>","clientSecret":"<Google client secret>"}}
```

Outlook har samma struktur under nyckeln `outlook`. Fälten som accepteras är
endast `clientId` och `clientSecret`; Microsoft använder klienthemlighetens
**värde**, inte secret ID. Tomt objekt `{}` betyder att inga OAuth-leverantörer
är konfigurerade; iCloud kan ändå aktiveras med bara AES-nyckeln. Lagra JSON:en
i Secret Manager, aldrig i Git, klientbyggen eller chatten. Parsingfel innehåller
aldrig JSON-innehållet i felmeddelanden.

Dekoda AES-nyckeln till exakt 32 byte innan `createOAuthService`/`createSecretBox`
anropas. Nyckelbyte utan kontrollerad omkryptering gör befintliga kopplingar
oläsbara. Tilldela endast synkfunktionernas tjänstekonto åtkomst till hemligheterna.

Övriga serverparametrar: callback-URL ovan och Microsoft tenant `common` för
både privata och organisationskonton. Ingen användarstyrd token-endpoint eller
callback-URL accepteras av modulen.

## Google

1. Öppna [Google Cloud Console, APIs & Services](https://console.cloud.google.com/apis/dashboard)
   i rätt projekt och aktivera **Google Calendar API**.
2. Konfigurera OAuth consent screen med appnamn, supportkontakt och rätt
   målgrupp. För externa familjer behövs External och tillåtna testanvändare
   medan appen ligger i testläge.
3. Skapa OAuth Client ID av typen **Web application**. Lägg in callback-URL:en
   ovan under Authorized redirect URIs, exakt inklusive sökväg.
4. Konfigurera scopes `https://www.googleapis.com/auth/calendar.events` och
   `https://www.googleapis.com/auth/calendar.calendarlist.readonly`.
5. Förvara klientuppgifterna enligt tabellen. Servern begär offline access,
   uttryckligt samtycke och S256 PKCE. Delvis beviljade scopes eller uteblivet
   refresh-token gör att anslutningen stoppas med tydlig felkod.

Extern produktion behöver tillämplig OAuth-granskning. Testlägets tidsgränser
för refresh-token måste beaktas när familjepiloten planeras. Räkna inte en
lyckad Firebase/Google-inloggning som godkännande till Calendar API.
[Googles serverflöde och registreringskrav](https://developers.google.com/identity/protocols/oauth2/web-server)

## Microsoft/Outlook

1. Öppna [Microsoft Entra admin center](https://entra.microsoft.com/),
   App registrations → New registration.
2. Välj kontoalternativet för konton i alla organisationer **och personliga
   Microsoft-konton** om både arbets-Outlook och privat Outlook ska stödjas.
3. Registrera callback-URL:en som **Web**, inte Single-page application.
4. Lägg till delegerad Microsoft Graph-behörighet `Calendars.ReadWrite`.
   OAuth-flödet begär även `offline_access`. Application permissions behövs inte.
5. Skapa klienthemlighet och lagra dess värde i rätt secret. Anteckna utgångs-
   datum i driftansvaret och rotera innan den löper ut.

En arbetsorganisation kan kräva administratörens samtycke även om privat
Outlook fungerar. Servern använder authorization code + PKCE och roterar
refresh-token inom ett distribuerat anslutningslås.
[Microsofts code flow](https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-auth-code-flow),
[refresh-token och rotation](https://learn.microsoft.com/en-us/entra/identity-platform/refresh-tokens)

## iCloud

Användaren behöver tvåfaktorsautentisering på sitt Apple Account samt ett
appspecifikt lösenord från kontots säkerhetsinställningar. Det fylls i endast i
en säker anslutningsvy och skickas till autentiserad backend. Lagra användarnamn
plus app-lösenord krypterat med `createSecretBox` och AAD som binder användare,
familj och anslutnings-id. Kräv lyckad `listCalendars()` och vald kalenderprobe
före status connected. Avslutad koppling ska radera den serverlagrade
inloggningsuppgiften enligt den användarbeställda frånkopplingen.

Adaptern använder CalDAV och tillåter bara Apples CalDAV-hostar. Apple har
även kontoauktorisering för vissa stödda tredjepartsappar, men någon tillgänglig
utvecklarregistrering för denna app är inte verifierad. Lovar därför inte
"Logga in med Apple" för iCloud-kalendersynken.
[Apples appspecifika lösenord](https://support.apple.com/en-us/102654),
[åtkomst för tredjepartsappar](https://support.apple.com/en-us/121539)

## Krav på HTTP- och Firestore-kopplingen

`oauth.js` är en factory med injicerade beroenden:

```js
const service = createOAuthService({
  providers: {
    google: {clientId, clientSecret, redirectUri},
    outlook: {clientId, clientSecret, redirectUri, tenant: 'common'},
  },
  encryptionKey, // Buffer, exakt 32 byte
  store, authorize, fetchImpl, now,
});
```

- `authorize(uid, familyId)` returnerar uttryckligen `true` endast för aktuell
  medlem som får koppla kalender. Kontrollera behörighet på nytt i callback
  och vid varje synkomgång; återkallat medlemskap ska stoppa tokenanvändning.
- `store.createState(hash, record)` använder create-if-absent. Endast statehash
  lagras; PKCE-verifier är AES-GCM-krypterad. TTL är tio minuter.
- `store.consumeState(hash)` läser och förbrukar posten atomärt i en Firestore-
  transaktion. Två samtidiga callbacks får inte få samma post. TTL-städning i
  Firestore är kompletterande; koden kontrollerar utgångstid synkront.
- `store.putConnection(id, record)` och `getConnection(id)` använder en helt
  klientspärrad samling. `record.secret` är krypterat, men dess åtkomst ska ändå
  vara begränsad till backend. Separata minimala statusdokument kan visas i UI.
- `store.withConnectionLock(id, fn)` måste vara ett distribuerat exklusivt lås
  över hela `fn`, inte ett processlokalt mutex. Låt nätverksanrop ligga utanför
  Firestores automatiskt återförsökta transaktionsfunktion. Lease ska täcka
  tokenanropets 25-sekunderstimeout, med ägarskapskontroll/renewal vid behov.
  Frånkoppling ska använda samma lås så att en pågående refresh inte återskapar
  borttagna hemligheter.

HTTP-starten verifierar Firebase ID-token och anropar
`begin({uid,familyId,provider})`. Resultatets `browserBinding` sätts som
`__Host-vardag_calendar_oauth`-cookie med **Secure; HttpOnly; SameSite=Lax;
Path=/; Max-Age=600** på samma origin som callbacken. Returnera därefter eller
redirecta till `authorizationUrl`; browserBinding ska inte exponeras i URL,
UI eller logg. En callable från annan origin sätter inte automatiskt den rätta
cookien: använd en autentiserad HTTP-start eller engångsbindningsrutt på
callback-hostens origin. Visa ett fast appmeddelande och navigera till appens
fasta återgångs-URL; ingen godtycklig returnUrl från query.

Callbacken läser cookien och anropar
`complete({state,code,error,browserBinding})`, rensar sedan cookien och skickar
aldrig tokens till webbläsaren. UID/family är bundna till startens state.
Runtime-store sparar resultatet som **awaiting_confirmation**, även om det
lägre OAuth-protokollet har slutförts. Browsercookien och den separata
Firebase-autentiserade slutbekräftelsen nedan behövs tillsammans för att stoppa
kontolänknings-CSRF via den delbara handoff-länken. Först efter slutbekräftelse
blir status **authorized**, och efter kalenderprobe och uttryckligt kalenderval
blir den **connected**.

Sätt `Cache-Control: no-store`, `Referrer-Policy: no-referrer` och en strikt CSP
på start/callback. Logga aldrig query, request-body, cookies, tokenresponser,
råa SDK-fel eller anslutningsdokument. Kontrollera även plattformens automatiska
HTTP-requestloggar: callback-URL kan innehålla engångskod och state; redigera
eller exkludera sådan querydata från driftloggningen före pilot.

`getAccessToken({connectionId,uid,familyId,forceRefresh?})` är endast för servern.
Den återanvänder giltig token, förnyar nära utgången, sparar eventuell rotation
innan den returnerar och avvisar fel familj/användare. Återkallat samtycke ger
`reauthorization-required`. Anropa aldrig med klientangiven UID utan verifierad
Firebase-identitet eller en betrodd schemalagd synk som kontrollerar medlemskap.

## Prov före extern familj

Kör först mocktesterna i `functions/test/calendar_oauth.test.js` och
`functions/test/calendar_providers.test.js`. Kör därefter riktiga testkonton:
anslut/avbryt/återkalla, flera parallella callbacks, uppdatera samma aktivitet på
båda sidor, ETag-konflikt, offline-återförsök utan dublett, raderad aktivitet,
serie med flytt/inställt tillfälle, privat aktivitet, sommartidsbyte,
refresh-token efter minst en timme samt frånkoppling under pågående synk.
Gör testskrivningar i tydligt vald testkalender, aldrig i en obekräftad familjs
ordinarie kalender. iCloud behöver ett särskilt verifierat kontotest eftersom
nätverksadaptern ännu bara är provad mot protokollmockar.

## Implementerad start, bekräftelse och städning

`runtime.js` använder den extra bekräftelse som behövs när en anslutning börjar
med en delbar engångslänk:

1. `startCalendarConnection({provider})` är en autentiserad callable och ger
   endast `{url,expiresAt}`. URL:en går till `calendarOAuthStart?ticket=...`;
   Firebase ID-token finns aldrig i URL:en.
2. HTTP-starten förbrukar ticket, sätter browsercookien och går till
   leverantörens samtycke.
3. OAuth-callback sparar krypterade tokens med status `awaiting_confirmation`.
   Dessa anslutningar kan varken listas av användaren eller användas av synk.
4. Callbacken går till den fasta adressen
   `https://la-familia-5d9f5.web.app/#/calendar-connect?ticket=...`.
   Ticket ligger i fragmentet och skickas inte till webbserverns accesslogg.
   Flutter fångar ticket endast i minnet och tar bort det från adressfältet.
5. Efter vanlig Firebase-inloggning anropar klienten
   `finishCalendarConnection({ticket})`. Matchande UID/familj och ett nytt
   medlemskapstest krävs. Först därefter görs kalenderprobe och status blir
   `authorized`. Kalender väljs separat innan `connected` och synk aktiveras.

Detta stoppar att en angripare delar sin handoff-länk och får offrets externa
kalender kopplad till angriparens konto: offrets Firebase-identitet matchar inte
startens identitet vid slutlig bekräftelse. Ett misslyckat försök förbrukar
bekräftelsen; användaren får starta om anslutningen.

`FirestoreOAuthStore` finns implementerad i `firestore_store.js`. Den använder
`calendar_sync_connections` och `calendar_sync_states`, ett återinträdesbart
AsyncLocalStorage-sammanhang över distribuerat 90-sekunderslease, förnyat var
30:e sekund. Alla credentialuppdateringar verifierar leaseägare och generation
inne i transaktion. Disconnect använder samma lås, ökar generation, stänger av
synk och ersätter `secret` med null. Externa kalenderdata ändras inte.

`expirePendingCalendarConnections` är en separat schemalagd funktion utan
hemlighetsbindning som kör var 15:e minut. Awaiting-confirmation får 15 minuters
frist; därefter nollas credentials och anslutningen markeras disconnected.
Aktiva anslutningar berörs inte. Konfigurera dessutom Firestore TTL på
`calendar_sync_states.ttlAt` för att städa förbrukade/utgångna engångsposter.

## Offentlig tillgänglighet och funktionsbindningar

`getCalendarConnections` och `disconnectCalendarConnection` kräver inga
hemlighetsbindningar. Listningen visar endast granskade metadata, aldrig raw,
secret, scope-token, providerresponse eller privata kalenderposter. Tillgängliga
anslutningsknappar styrs av vanliga **servermiljöparametrar**:

```
CALENDAR_GOOGLE_READY=false
CALENDAR_MICROSOFT_READY=false
CALENDAR_ICLOUD_READY=false
```

Saknat värde är false. Sätt respektive flagga till `true` först efter korrekt
registrering, hemlighetsbindning, driftsatta handlers och verkligt kontotest.
En true-flagga är inte ett substitut för hemligheter; starten kontrollerar också
att verklig serverkonfiguration finns och avvisar annars anropet.

`connectICloudCalendar` binder endast `CALENDAR_TOKEN_ENCRYPTION_KEY`.
Gemensam OAuth-start/callback/slutbekräftelse och synkworker binder
`CALENDAR_PROVIDER_CONFIG` plus AES-nyckeln. Konfigurations-JSON får innehålla
endast Google först, endast Outlook eller båda. Därmed blockerar en ännu inte
registrerad leverantör inte den andra. Inga skenbara klienthemligheter behövs.
För iCloud-only worker kan providerkonfigurationen vara `{}`. De bundna secret-
namnen måste finnas innan motsvarande handlers driftsätts.

En tom mall med exakta callback-/scopevärden kan skapas utan att läsa eller
skapa en enda verklig hemlighet:

```sh
node functions/scripts/prepare-calendar-sync-config.js /tmp/calendar-sync.env.template
```

Skriptet vägrar skriva över en befintlig fil, använder filrättighet 0600 och
aktiverar eller driftsätter ingenting. Namnen `CALENDAR_OAUTH_REDIRECT_URI` och
`CALENDAR_MICROSOFT_TENANT` i mallen dokumenterar de fasta värdena i runtime;
callback kan inte styras via användarinput.
