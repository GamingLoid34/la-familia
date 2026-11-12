# Vardag: avskalad testversion, andra kalendrar och TV

Android 1.15.0 (58), paket `com.lafamilia.app.dev`. Webb 1.1.0+32.
Installerad Vardag DEV kan uppdateras direkt: signeringscertifikatet har jämförts
med APK:n för 1.14.4. Inga familjedokument har raderats eller migrerats.

## Kalenderappen

Tre huvudval ersätter navigationen med en separat syssloflik. Kalender, personer,
veckobrev/inkorg, vuxnas uppgifter, förberedelser och packlistor behålls.
Specialistfunktionernas avgränsning gäller i den nya klienten oavsett den gamla
serverflaggan. Äldre klienter följer fortfarande sin flagga; serverns befintliga
pilotgrind och notisspärrar är därför fortfarande relevanta under övergången.

16 Androidfiler (vyer, vymodeller, matformulär och gamla TV-inställningar) är bevarade i
`vardag-hem/reference/android`. Kontrollerade SHA-256 finns i dess manifest.
Sju gamla skärmrutter visar nu arkivet i stället för att bygga specialverktygen.
Delade modeller, läsning/export av historik och viss kompatibilitetskod är kvar;
allt gammalt domänstöd är alltså inte borttaget ur källträdet.
Flutter läser inte längre sysslor, rutiner, måltider eller familjeanteckningar
som bakgrundsdata i kalenderns FamilyProvider. Uppgifter i `tasks` är en separat,
bevarad funktion. Hem och Fokustimer utvecklas separat; detta publicerar inte Hem.

Ett fel i webben har rättats: rapportering av klientversion uppdaterade användarens
dokument, som startade om familjeprenumerationerna och rapporterade igen. Oförändrad
familj återanvänder nu prenumerationerna. Sena svar avvisas efter familjebyte.
Webben laddas om vid ett verkligt familjebyte för att återstarta behörighetsbundna
Firestore-strömmar med ett rent tillstånd. Hem och Kalender återanvänder också samma strömmar vid omritning.
Hem läser arbetspass från den gemensamma rotsamlingen `work_shifts`, inte den
äldre obehöriga undersamlingen. Detta minskar upprepade prenumerationsbyten i
Firebase JS:s felande ca9/b815-kö; se även upstream-rapporten:
https://github.com/firebase/firebase-js-sdk/issues/9491

## Andra kalendrar

Befintlig kalenderprenumeration återanvänds. Välj **Andra kalendrar**, ange ett namn
och klistra in en HTTPS- eller webcal-länk i iCalendar/ICS-format. En person kan
väljas; annars är kalendern familjegemensam. Vardag skriver inte tillbaka till
källan. Länken kan vara privat och ska inte delas i skärmbilder eller loggar.

De nya serverändringarna stöder upprepningar, inställda/flyttade tillfällen,
svensk sommar-/vintertid, flytande svenska tider och flerdagars heldagshändelser.
De hämtar högst 500 tillfällen inom cirka sex månader. Mycket täta upprepningar,
för stora svar, icke-HTTPS-länkar och interna nätadresser avvisas. DNS-resultatet
låses till anslutningen och omdirigeringar kontrolleras separat.

Fälten är kompatibla med båda klienterna. Källans ändrade eller borttagna plats,
beskrivning och sluttid uppdateras; familjens packlista bevaras vid merge.
Lokal redigering av importerade källfält kan ersättas vid nästa synk. ICS-filimport
är en separat engångsväg och har inte fått denna nya prenumerationsparser.
Tidsatta tillfällen över midnatt har fortfarande kalenderns tidigare begränsning.

**Serverdelen är blockerad, inte publicerad.** Tre försök på Node 24 (även
isolerad funktionskod) fick Cloud Runs interna startkontrollfel. Ett fjärde försök
på Node 22 accepterades av driftsättningen med noll trafik, men när trafiken
aktiverades fick även den revisionen samma interna startkontrollfel. Lyckad
deploy-CLI betyder alltså inte att kalenderfunktionen fungerar. Trafiken för
båda kalenderfunktionerna är uttryckligen återförd till tidigare revision 00009.
RoutesReady är True, men både funktionsadressen och direktadressen svarade ändå
HTTP 500 i slutprovet. Även Cloud Logging gav internt 500-fel. Nya
kalenderprenumerationer och automatisk synk kan därför inte räknas som fungerande.
Befintliga kalenderposter läses direkt från Firestore och påverkas inte av detta.
Ingen användardata ändrades av serverkontrollerna (obehöriga tomma HTTP-anrop).
Ingen lagringsregion har flyttats; svensk datalagring återstår som eget beslut.

## Storskärm

Öppna `https://la-familia-5d9f5.web.app/?display=1` och logga in med vanligt konto.
Visar klocka, familjemedlemmar, idag och de kommande sex dagarna. Kalenderändringar
kommer via Firestore. Långa listor roterar automatiskt var 20:e sekund, utan scroll.
Offline/cache och läsfel markeras i nederkanten; ett fel ger inte en falsk kvittens.

Inställningar → Storskärm ger länken och valet att visa veckobrevsuppgifter.
`&tasks=1` kräver fortfarande vuxenkonto; barn startar ingen uppgiftsprenumeration.
Rubrikerna blir synliga för alla framför TV:n. Börja med dator ansluten till TV:n,
F11 och avstängt viloläge. Inbyggda TV-webbläsare och faktisk läsbarhet från soffan
måste provas på den avsedda TV:n. Klassiska displaymoduler är bevarade, och den
klassiska webbvyn kan nås med `&classic=1`; den nya TV-vyn behöver inte dess scener.

## Verifiering och begränsningar

- Android: bygge och 982 tester godkända; APK-signering matchar tidigare version.
- Flutter: 436 tester godkända, analys utan anmärkning och release-webb byggd.
- Serverkod: samtliga 132 tester godkända på både Node 24 och Node 22;
  serverns driftstatus är separat enligt ovan.
- Chrome med riktiga emulatorregler: sju flödeskontroller godkända utan JS-fel.
- TV-layout provad i 1920×1080, 1280×720 och 960×540 med överfulla listor.
- Kalenderns serverprover täcker DST, undantag, flytt, heldag/midnatt, flerdag,
  resursgränser, URL-kontroll och bevarande/rensning av källfält.
- Inga fysiska telefoner eller TV-apparater var anslutna. Telefonlarm, iPhone/Safari
  och ett långt driftprov är inte verifierade av denna leverans.

Bevis, skärmbilder, APK-kvitto, versionsmanifest och driftsättningsloggar:
`/home/oscar/utveckling/vardag-driftunderlag/morgonleverans/`.

## Leverans

Webb 1.1.0+32 är publicerad på den vanliga adressen. Ny Android-APK 1.15.0 (58)
är verifierad i användarens privata Drive-mapp:
https://drive.google.com/file/d/1dG0Z1FVZf2IccsIrg625hmGW4MVbm55Q/view

Installeras ovanpå Vardag DEV med samma konto. APK:n har inte lagts på publik
webbhosting. Det gamla webb-URL:et `/app-release.apk` returnerar, liksom föregående
release, SPA-HTML och är ingen APK-leverans. `/ladda-ner/` behåller länken till
Vardags ordinarie Androidsida. Inget Git-repository har pushats.
