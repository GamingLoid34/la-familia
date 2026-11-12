# Vardag 1.21.0 — kalenderfiler och kommande kontosynk

## Publicerad 1.21.0+71

Android och Flutter/webb har export under **Ta med kalendern**. Personlig export
innehåller egna och familjegemensamma aktiviteter samt ägarens privata innehåll.
Familjeexport är för föräldrar och innehåller inga privata aktiviteter.
Importerade källkalendrar utelämnas som standard för att undvika dubletter.
Serier, undantag, flyttar, heldagar, arbetspass över midnatt och packlistor följer
med i ICS-format. Filen är en fristående kopia, ingen automatisk synk.

Filimporten använder samma serverparser i båda klienterna. Användaren väljer
period, granskar antal och varningar och bekräftar innan skrivning. Maxgränser
ger besked, inte tyst avklippning. Identiska filer för samma mål skapar inte nya
poster. Originalfilen sparas serverprivat och tas bort med importen.

Importförhandsgranskning använder det nya, alltid skrivfria anropet
`previewIcsText`; en äldre server kan därför inte oavsiktligt importera innan
bekräftelsen. Första driftsättningen måste omfatta:

```
functions:exportCalendar,functions:previewIcsText,functions:importIcsText,functions:onCalendarImportDeleted
```

Filimportens begränsningar visas före skrivning: bland annat tidsatta nattpass,
privata/konfidentiella källposter och vissa avancerade upprepningsregler.
Privata källposter får inte omvandlas till familjesynliga aktiviteter.
Detaljer: [kalenderimport-export-kontrakt.md](kalenderimport-export-kontrakt.md).

## Kontosynk — kod för senare aktivering

Google, Outlook och iCloud har separata adaptrar, OAuth/CalDAV-anslutning,
krypterad serverlagring av behörigheter, beständig skrivkö och konflikthantering.
Inkommande aktiviteter läggs i ägarens privata lagring. Kontot synkar egna
manuellt skapade aktiviteter som gäller ägaren eller hela familjen; andra
medlemmars egna aktiviteter och gamla kalenderimporter skickas inte vidare.
Frånkoppling behåller aktiviteterna hos båda parter och tar bort serverns
anslutningshemligheter.

Funktionen är avstängd i 1.21-byggena: Android `calendarAccountSync` och Flutter
`CALENDAR_ACCOUNT_SYNC` har standardvärde false. Ingen synkfunktion ska
driftsättas eller visas som klar innan leverantörsregistrering och riktiga
kontotester är genomförda. Mocktester visar kodens beteende, inte att ett
riktigt Google-, Outlook- eller iCloud-konto fungerar.

V1 stoppar bland annat mötesinbjudningar, nattpass och serier med flyttade
förekomster som inte kan representeras säkert. De visas som konflikter och
skrivs inte över. Samtidiga ändringar kräver uttryckligt val. Ett oklart
överföringsresultat efter processdöd pausar synkningen tills identiteten är
säkert fastställd; saknade lokala data räknas aldrig som en radering.

Aktivering: [SETUP.md](../functions/calendar_sync/SETUP.md).
Datamodell och gränser: [MAPPING_AND_SYNC.md](../functions/calendar_sync/MAPPING_AND_SYNC.md).

## Publicering och verifiering

Version 1.21.0+71 publicerades 2026-10-31 efter användarens uttryckliga
publiceringsgodkännande. De fyra namngivna serverfunktionerna ovan driftsattes
först, sedan APK-nedladdningen och webbappen. Inga Firestore-regler eller andra
serverfunktioner ingick. Kontosynkens servermoduler laddas inte medan
`calendar_sync/deployment.js` har `enabled:false`; detta skyddas av ett test.

Verifierat före publicering: 876 Android-tester, 438 Flutter-tester och
23 servertestfiler godkända; Flutter-analysering utan anmärkningar. Den signerade
Android-produktionsappen och Flutter-webben är byggda. APK:n finns på den
befintliga nedladdningssidan och är även verifierat uppladdad till privat Drive.

Alla 14 livekontroller passerade: version 1.21.0+71, integritetssida, besöksvy,
JavaScript/MIME, nedladdningssidor, APK-omdirigering och filhash, webbpaket,
oförändrad Hem 0.2.1+3 samt nekade oinloggade export-/importanrop. Dessa
kontroller provar inte export/import med en verklig familjs inloggning.

Driftunderlag, testloggar, signerad APK och separata Hosting-kandidater ligger i
`/home/oscar/utveckling/vardag-driftunderlag/kalenderportabilitet-20261030/`.
Hems 34 kandidatfiler är byteidentiska med föregående release; dess publicerade
version och webbpaket är också hashverifierade. Livebevis finns i
`live-verification.json` och samlad status i `verification.json`.
Fysisk Android/iPhone och riktiga leverantörskonton har inte kunnat provas i
denna miljö. Google-/Microsoft-registrering, säker serverkonfiguration och
riktiga leverantörsprov återstår före en separat aktivering av kontosynken.
