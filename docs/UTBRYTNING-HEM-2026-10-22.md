# Hem-utbrytning – andra steget, 2026-10-22

## Leverans

Eget projekt: `/home/oscar/utveckling/vardag-hem` (Flutter, webb).
Eget leveransbygge: `/home/oscar/utveckling/vardag-hem-leveranser/0.1.0`.
Ingen publicering eller backend-migrering har utförts.

Hem innehåller återanvända vyer för sysslor, städdag/städläge, inköp,
matplanering och sysslohistorik. En egen liten startsida och inloggning binder
samman dem. Kalender, veckobrev och planeringsuppgifter ingår inte i Hem.

## Verklig kodflytt

Vardags sex huvudvyer för dessa funktioner har ersatts med små vägar till
arkivet: ShoppingListPage, MealPlannerPage, SysslorPage, StaddagPage,
StadlagePage och ChoreStatsPage. 4 190 gamla rader har ersatts av 26 nya enligt
Git-diffen. Det är implementationerna som flyttats, inte ytterligare flaggor.

Alla sex originalfiler är byte-identiskt bevarade i Hem-projektets
`reference/vardag-screens/`, verifierat mot `docs/removed-from-vardag.json`.
27 källfiler eller avgränsade delar återanvänds; ursprungliga kontrollsummor
finns i `docs/source-manifest.json`. Full tidigare historik finns även i de
redan verifierade Git-bundles från första utbrytningen.

Delade hjälpklasser, formulär och läskopplingar används ännu på andra ställen i
Vardag. Dessa har inte tagits bort blint. Androids nativeimplementationer är
inte utbrutna i detta steg. Detta är alltså inte färdig förenkling av hela appen.

## Datagräns

Samma konton, familje-id:n, dokument och serverregler används. Inga gamla poster
kopieras till nya samlingar. Historik läses fortfarande från `chore_log` och
avbockning går genom befintlig `completeChore` för serverns kontroll och poäng.
Växtsysslor finns kvar i sysslolistan tills deras särskilda utbrytning är gjord.

Hem har en egen familjebevakning utan kalenderlyssnare, pilotrapportering,
pushregistrering eller widgetskrivning. Vid familjebyte töms listor, gamla
callbacks ignoreras och öppna formulär/rutter stängs. Administratör, förälder,
barn och ungdom stöds; okänd/saknad roll ger stopp tills profilen är giltig.
Matstatistik räknas transaktionellt i Hem, vilket förhindrar dubbelräkning
mellan samtidiga Hem-klienter. Gamla Vardag-versioners batchlogik är oförändrad.

## Verifiering

- Hem: 30 tester passerar och Flutter-analyzen hittar inga problem.
- Vardag Flutter: samtliga 431 tester passerar och analysen är utan anmärkningar.
- Vardags webbbygge och Hems leveransbygge är godkända.
- Sex originalvyer är jämförda mot sina kontrollsummor och bevarade oförändrade.
- Regelprov med syntetiska familjer: egen familjs inköp tillåts; annan familjs
  inköp, byte av en inköpsposts familj och egen skrivning till poänghistorik nekas.
- Testprojektet heter `demo-vardag-hem`; ingen produktionsdata har använts i proven.

Beständiga testloggar och webbläsarbilder finns i
`/home/oscar/utveckling/vardag-driftunderlag/hem-verifiering/`.

## Kvar före vanlig användning

Webbversionen är en förhandsversion utan bakgrundspåminnelser. En webbadapter
ersätter de gamla native-larmanropen. Nativebyggen av Hem stoppas i startflödet
tills en riktig plattformsadapter finns. Fysisk iPhone/Android, Cloud Functions
för avbockning/AI-menyer och publicering återstår att integrationsverifiera.

Ingen ny kalenderrelease med dessa borttagna vyer ska publiceras till användare
som behöver funktionerna förrän Hem är verifierad och tillgänglig. Installerad
Vardag och den publicerade webben är oförändrade.

Två widgettester låser att även root-dialoger försvinner vid familjebyte och
utloggning. Hela appens navigator byts med sessionen. Dagsskiftet uppdateras
vid midnatt och återgång till appen, utan kalenderprenumerationer.

## Slutfört webbläsarprov

`browser-final.json` redovisar åtta godkända kontroller: administratörsinloggning,
familjeavgränsade inköp, skapa/avbocka inköp med sparning, befintlig historik och
poäng, familjebyte med öppet formulär, barninloggning efter utloggad förälder,
barnets läsning av en befintlig syssla samt oförändrad kalenderpilotflagga.
Inga webbläsarfel och inga försök att använda blockerade externa API:er.

Desktop- och mobilbred webbläsarvy är granskade via `hem-home.png` och
`hem-mobile.png`. Dessa är emulatorbilder med syntetisk data, inte telefonprov.
