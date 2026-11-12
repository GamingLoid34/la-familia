# iPhone/PWA 1.0.1+28 – färdig för publiceringsbeslut

Förberedd 2026-10-22. Inte publicerad. Källversion: 2869f17c1dfd4bff49ebb58bfbbd35e7bba7fbba på kalenderpilot. Befintlig webbversion är 1.0.0+27.

## Paket och innehåll

Färdigt releasepaket: `/home/oscar/utveckling/vardag-pwa-leveranser/1.0.1-28/`. `public/` innehåller 50 filer; `sha256.json` låser deras innehåll. firebase.json är begränsad till Hosting-sajten la-familia-5d9f5 och har samma wildcard-rewrite som aktuell drift. Inga functions-, rules-, storage- eller indexsektioner finns i denna leveranskonfiguration.

Versionen innehåller tidigare implementerad journal för kalenderändringar, flytt/ångra med serielänkar, säkrare upprepningsredigering, klientrapportering och flaggstyrd avgränsning/arkiv. Detta är samma kandidat som redan enhetstestats, nu byggd och kontrollerad för leverans. Ingen ny produktfunktion eller serverändring har lagts till under förberedelsen.

Version 1.0.1 och byggnummer 28 verifierades i paketets version.json. APP_VERSION=1.0.1+28 användes vid releasebygget. Den befintliga Firebase-konfigurationen anger rätt projekt. Inga inloggningsuppgifter eller familjedata behövs i paketet.

Android hanteras av den separata Vardag-appen. Nedladdningssidan pekar fortsatt på https://vardag-nedladdning.web.app och är innehållsmässigt oförändrad jämfört med drift (endast radslut skiljer). Ingen Flutter-APK byggs eller distribueras i denna PWA-leverans. README:s äldre krav på Flutter-APK är därmed inte tillämpligt på detta iPhone-uppdrag. /app-release.apk på nuvarande sajt returnerar HTML via fallback, inte en APK: HTTP 200 ensamt är inget giltigt APK-prov.

## Utförda kontroller

- flutter analyze --no-pub: inga anmärkningar.
- flutter test --no-pub: 421 passerade, 0 fel.
- flutter build web --release --no-pub --dart-define=APP_VERSION=1.0.1+28: lyckades.
- Chrome i 390×844 mobilformat: startsidan renderar inloggningsformuläret, korrekt versionsfil, inga pageerror och inga misslyckade nätanrop. Skärmbild: releasepaketets mobile-login.png. Ingen inloggning med familjekonto gjordes i detta prov.
- Integritetssidan och besökssidans HTML matchar drift byte för byte; nedladdningssidans text och länk matchar efter normalisering av radslut. Besöksfiler, manifest, ikoner, bootstrap, push-worker och huvudprogram finns i paketet.
- Filerna i det kopierade releasepaketet verifierades mot sha256.json.

Loggar: /tmp/vardag-pwa-analyze.log, /tmp/vardag-pwa-test.log, /tmp/vardag-pwa-build.log. Webbläsarresultat finns även i releasepaketet.

## Offline: faktisk begränsning

Den genererade flutter_service_worker.js avregistrerar sin egen gamla worker. Detta är exakt samma beteende/källtext som den nu publicerade webbappens worker, inte en nytillkommen försämring. Koden för FCM-push ligger i en separat firebase-messaging-sw.js och har inte ändrats.

Lokalt prov: öppna appen online, slå av nät i Chrome, ladda om. Omladdning misslyckas med ERR_INTERNET_DISCONNECTED. Ingen fungerande offline-start eller offline-omladdning utlovas för denna kandidat. Resultatet gäller lokalt Chrome-prov, inte ett komplett Safari/PWA-prov. Att en redan öppnad app kan köa en dataskrivning är en annan egenskap än att hela webbappen kan starta utan nät.

Efter publicering måste iPhone-proven omfatta den nya versionen, journalen vid omladdning, synk och push. Full offline-start är en kvarvarande produktbegränsning och piloten får inte godkännas som fullt offlineverifierad. Inga readiness-fält har markerats och kalenderpiloten förblir avstängd.

## Återställning och publicering efter godkännande

Nuvarande Hosting-release: sites/la-familia-5d9f5/releases/1790193142862000.
Återställningsversion: sites/la-familia-5d9f5/versions/3bea2b1451b41b85 (2026-09-23T19:52:22.862Z).
Metadata och fillista är sparade i `/home/oscar/utveckling/vardag-driftunderlag/20261022-pwa/`. Kontrollera direkt före publicering att live-versionen fortfarande är denna; utred annars förändringen. Den gamla versionen kan återställas via Firebase Hostings releasehistorik. Denna förberedelse har inte skapat en ny Hosting-version eller testkanal i Firebase.

Efter uttryckligt godkännande, kontrollera filhasharna och kör från releasekatalogen:

```sh
npm exec --offline --package=firebase-tools -- firebase deploy --project la-familia-5d9f5 --only hosting --non-interactive
```

Verifiera sedan aktiv release, version.json=1.0.1/28, startsida, integritetssida, besöksvy, bootstrap med JavaScript-MIME, nedladdningssidans externa Android-länk och push-worker. Kontrollera även att pilotflaggan är oförändrad. Sätt build-28-taggen först efter lyckade efterkontroller. Denna publicering ersätter webbappen även för datoranvändare, inte enbart iPhone. Den aktiverar inte kalenderläget.

## Publicerad efter godkännande

Version 1.0.1+28 publicerades 2026-10-22 efter Oscars uttryckliga JA. Aktiv Hosting-version: `sites/la-familia-5d9f5/versions/bcf81c938d6ee0ed`. Åtta HTTP-kontroller passerade: versionsfil, startsida, integritetssida, besöksvy, bootstrap, nedladdningssida, push-worker och huvudprogram. Samtliga hämtade filer matchade releasepaketet byte för byte; JavaScript-MIME kontrollerades. Kalenderpiloten är fortsatt avstängd. Verifieringsunderlag: `/home/oscar/utveckling/vardag-driftunderlag/20261022-pwa/verification-after.json`.

Det lokala webbläsarprovet är godkänt sedan tidigare. Ett separat webbläsarprov mot publicerad sajt hann inte köras före avbrottet; faktisk iPhone-kontroll återstår. Begränsningen för omladdning utan nät kvarstår. Inga serverfunktioner eller regler ändrades av Hosting-publiceringen.
