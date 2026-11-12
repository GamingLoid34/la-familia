# Inmatning: text först, gemensamt utkast — 2026-10-23

Android 1.16.0 (59), Flutter/PWA 1.2.0+33. Fortsättning på kalenderpilot enligt Oscars godkända plan.

## Beteende

- Lägg till öppnar snabbtext först. Android har mikrofon; webb/PWA hänvisar till tangentbordets diktering. Fyll i själv finns direkt.
- Tolkningen fyller det vanliga redigerbara formuläret, utan separat bekräftelsedialog. Ursprungstexten behålls. Datum och start/slut finns samlade under När, följt av personval. Symbol/mall, upprepning och packlista ligger under Fler val.
- Ingen angiven tid börjar som Tid inte bestämd. Klockslag och Heldag är uttryckliga val. På webben öppnar valet Klockslag tidväljaren.
- Text som inte anger datum/tid/person/upprepning ersätter inte tidigare val. Kalenderinmatningen gör ingen omdirigering till middag/inköp/specialistverktyg och gissar inte personer genom ungefärlig namnmatchning eller dubbla förnamn.
- En smal regel för exempelvis ”tandläkare torsdag 15” stöds i båda klienterna. Detta är regelbaserad tolkning, inte fri AI-tolkning. Användaren granskar utkastet före Spara.
- Flutter använder samma sparväg och kvittensjournal som manuell inmatning. Mallfrågan begränsas till aktuell familj och gemensamma mallar enligt befintliga regler.

## Verifiering

- Android: 985 enhetstester, noll fel; assembleDevDebug godkänd. Samma signeringscertifikat som 1.15.0, applicationId com.lafamilia.app.dev.
- Flutter: 442 tester godkända; flutter analyze utan anmärkningar; releasewebb byggd med APP_VERSION=1.2.0+33.
- Befintliga funktionstester: 132 godkända. Ingen backend-/regeländring ingår.
- Lokal Chrome, 430×932, svensk tidszon, riktiga Auth/Firestore-emulatorer: snabbtext först, utkast i samma dialog, sparande med bevarade datum/tid/person efter ny text samt manuell heldag verifierade mot lagrade dokument. Syntetiska testkonton; inga familjedata ändrade i testerna.
- Endast Firebase Hosting publicerad. Liveversion 33 och main.dart.js verifierade mot fryst release. HTTP-kontroller utförda även för privacy, besok, bootstrap och ladda-ner. /app-release.apk är sedan tidigare HTML-fallback; native APK levereras privat på Drive.
- Fysiska telefoner, taligenkänning och iPhone-tangentbordets diktering är inte verifierade i denna miljö. Ingen garanti om godtyckliga talfraser. Tidigare separata pilotbegränsningar gäller fortsatt.

## Leverans och underlag

Webb: https://la-familia-5d9f5.web.app

Android: https://drive.google.com/file/d/124inVPtKwglfImcfdCCC1vBYpXhZSFSh/view

Privat Drive-leverans verifierad med storlek och MD5; lokal APK SHA-256: 57fc03717c0110c14437487fc0e0693b567ce80c51e7214a84bfdf50dc6eb2ae.

Fryst webb: /home/oscar/utveckling/vardag-pwa-leveranser/1.2.0-33

Testloggar, skärmbilder, leveranskvitto och browserprotokoll: /home/oscar/utveckling/vardag-driftunderlag/inmatning-20261023
