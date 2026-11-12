# Vardag 1.19.0: klientparitet och Hem

Ordinarie Android bygger på samma kalenderomfattning som den testade Dev-appen. Webbappen fungerar även som en webbaserad app på iPhone. Båda använder samma familjedata. Den separata webbappen Hem publiceras under `/hem/` i den version som redan provats; den är inte en komplett nativeapp och funktionerna där utvecklas vidare separat.

## Vardag

- Privata aktiviteter kan skapas av vuxna och ungdomar. Andra i familjen ser tid, person och en neutral markering. Titel, symbol, packlista och förberedelse lagras i ett ägardokument som familjens andra konton inte kan läsa. Det är inte ändpunktkryptering mot databasadministratören.
- Privata återkommande aktiviteter kan ändras som serie, ställas in en gång eller flyttas en gång och återställas. Flytt och återställning kräver internet. Fler än åtta flyttade privata tillfällen raderas i begränsade transaktioner; vid avbrott kan man försöka igen.
- Flutter har ljust, mörkt och följ enheten; Android har motsvarande temaval. Veckorubrikernas kontrast har ett separat test. Båda klienterna har skanning av schema, andra kalendrar, återkommande, inkorg och uppgifter kopplade till planering. Den gamla vägledningen bevaras i källkoden, medan kalenderappen visar en aktuell lathund.
- Snabbinmatning erbjuder text och tal där webbläsaren stöder det. Diktering, skanning och notiser kan skilja sig mellan enheter.
- Vardag för Android har samma paketnamn och signeringscertifikat som föregående ordinarie version. APK:n har version 1.19.0, kod 68. Webbbygget och Hem levereras från samma Hosting-site, med Hem under `/hem/`.

## Verifiering och kvarstående enhetsprov

Flutter analys samt 426 tester, Androids 858 enhetstester och ett signerat produktionsbygge passerade. Reglerna kompilerades och provades i lokala Firebase-emulatorer: 54 behörighetsprov och sju SDK-scenarier för privat flytt, återställning och radering. Browserprov med syntetiska konton visade att en ungdom kan skapa en privat aktivitet, att andra ser en neutral markering samt att en privat förekomst går att flytta. Ett utloggat browserprov öppnade både Vardag och Hem. Säkerhetsreglerna jämfördes med den senast verifierade versionen före publicering och med den testade källan efteråt.

Ingen fysisk telefon var ansluten vid detta bygge. Installering av den nya ordinarie APK:n, senaste flyttflödet, skanning, röst och notiser på riktiga Android- och iPhone-enheter samt 48-timmarsprovet för gamla påminnelser är inte verifierade här. Gammal Androidkod kan ge en neutral påminnelse om en privat markering även till annan familjemedlem tills enheten uppdaterats. Flutter har ingen separat native-iOS-build i detta projekt; iPhone-versionen är webbappen. Hem har fortsatt begränsningar, bland annat ljudlösa webbtimers och ingen fullständig växthantering.
