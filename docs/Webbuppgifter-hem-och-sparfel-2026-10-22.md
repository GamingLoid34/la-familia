# Webbens uppgifter på Hem och rapporterat sparfel

Användaren bekräftade Android-vyn men rapporterade många uppgifter överst på webbens Hem och meddelandet ”Kunde inte spara uppgiften. Försök igen.” vid användning av webbappen.

## Ändring i 1.0.3+30

Hem visar högst tre uppgifter med begränsad radlängd och en knapp till hela listan, inklusive antal aktuella. På smal skärm ligger kortet efter kalenderns nu/nästa-kort; på bred skärm i högerkolumnen, så kalendern/familjen syns högst upp. Alla uppgifter behåller hela listan och alla sparade poster.

Sparfel skiljer nu på åtkomst nekad, utgången inloggning, borttagen post och nätfel. Övriga fel får en felkod; teknisk logg innehåller kod, undantagstyp och stack men inga uppgiftstitlar eller dokumentdata. Själva statuspatchen ändras inte eftersom den fungerar i reproduktionsproven. Inga data ändras automatiskt och inga säkerhetsregler lättas.

## Utredning och verifiering

- Publicerade Firestore-regler hämtades och var identiska med projektets regler.
- 430 Flutter-tester passerade. Nya widgetprov visar högst tre rader på 320 px bred Hem-vy med 25 uppgifter, öppning av hela listan, bibehållna 25 poster i fullvyn och spärr mot dubbelklick under pågående skrivning. Felmeddelandenas skillnader verifieras också.
- flutter analyze utan anmärkningar.
- Ett riktigt Chrome-test med Firebase-webbplugin mot separat Firestore-emulator genomförde avbockning, serverläsning och återöppning. Källanteckning och barnkoppling bevarades. Provet finns i test/browser/task_web_sdk.dart och körs uttryckligen med --platform chrome --dart-define=TASK_EMULATOR_TEST=true. Det kräver en lokal emulator med öppna testregler på 127.0.0.1:8197 och det fasta demo-projektet demo-vardag-task-sdk; ingen produktionskonfiguration används.
- Familjens 29 dokument lästes för diagnos. Kopior provades i separat demo-projekt i emulatorn med de verkliga säkerhetsreglerna och en lokal testförälder. Alla 29 statusuppdateringar godkändes. Originaldata i produktion ändrades inte. Kopior och operatörsdiagnostik ligger privat utanför Git.

## Kvarstående

Det rapporterade sparfelet har INTE återskapats och får inte beskrivas som löst. Den tidigare felhanteringen dolde felkoden, så orsaken i användarens webbsession går inte att avgöra från skärmbilden. Efter uppdatering behöver samma åtgärd provas igen; den nya felkoden avgör fortsatt åtgärd om felet kvarstår. Ingen ny Android-APK krävs.

## Leverans

Webb 1.0.3+30 byggd och publicerad på https://la-familia-5d9f5.web.app från det frysta Hosting-paketet /home/oscar/utveckling/vardag-pwa-leveranser/1.0.3-30. Åtta HTTP-resurser verifierades med HTTP 200 och byteidentiskt innehåll mot paketet. Endast Hosting publicerades, inga regler eller funktioner ändrades. Föregående frysta paket 1.0.2-29 finns kvar för återställning.
