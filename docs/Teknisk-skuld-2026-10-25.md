# Teknisk skuld och kodrensning i Vardag — 2026-10-25

Granskade arbetskopior: vardag-kalenderpilot (Android), vardag-flutter-kalenderpilot (webb/iPhone), samt Vardag Hem som referens för återanvändning. Utgångspunkter: Android 1cf3c5b, webb 273797f. Båda arbetskopiorna var rena före arbetet. Ingen slutsats dras om vilken AI eller person som orsakat enskilda problem; resterna kommer från flera generationer, även de senaste ombyggnaderna.

## Bedömning

Det finns tydlig teknisk skuld, men koden behöver inte skrivas om från noll. Android har användbara repository-gränser, gemensam FamilySession, kontraktsmodeller, en sparningsjournal och omfattande regressionstester. I båda klienterna finns bevarande av okänd upprepning och tester för flytt/återkommande händelser. Dessa skydd har behållits.

Den största säkra rensningen var kod som redan hade ersatts i gränssnittet men fortfarande låg kvar i produktionskällträdet. Orphan-kod identifierades genom referenser/importgraf och därefter manuellt kontrollerade startvägar. Android-manifest, Hilt-registreringar och andra implicita anrop får inte behandlas som vanliga textreferenser. För Dart räknades även villkorliga importer; web_reload_web.dart behölls därför.

## Genomförda förändringar

- Arkiverade oanropade äldre TV-inställningar, deras ViewModels och stöd för TV-editorer. Den nuvarande storskärmslänken och webbens FamilyWall behålls. Webbens klassiska DisplayShell är fortfarande åtkomlig med classic=1 och har inte raderats.
- Androids DisplayConfigRepository har blivit ett läsgränssnitt för de två funktioner Min dag faktiskt använder: familjens skolmatskonfiguration och veckans matsedel. Deras läsbeteende är oförändrat. Oanvända foto-, hållplats-, uppladdnings- och redigeringsmetoder har arkiverats, och onödiga Functions/Storage-beroenden har tagits ur den klassen.
- Tog bort den oanropade gamla AI-planerarens UI, ViewModel, repository och modeller. Den separata aktiva Vardagsplan-funktionen är kvar.
- Tog bort överblivna specialistvyer och hjälpklasser efter tidigare Hem-utbrytning. Arkivet och historikdatan finns kvar. Växtpayload-generatorn som fortfarande behövs av en översiktstest ligger nu i testkällträdet, inte i APK:n. Motsvarande Dart-fixtures för städdata/trasor ligger i test/fixtures.
- Androids snabbtext har nu en obligatorisk utkastcallback till det vanliga formuläret. Det alternativa bekräftelsearket och dess separata skrivvägar är borta. Oanvända formulärparametrar och callbacks har tagits bort.
- Tog bort den gamla veckodagsfärgens beräkningar och utvecklaröverstyrning. Fyra onödiga Flow-prenumerationer i Home/Settings togs bort, samt Home-wrapperns dubbla UI-state-prenumeration. Ljust/Mörkt/Följ enheten och deras kontrasttester behålls.
- Tog bort dubblerad Room/KSP-konfiguration i Gradle. JVM-mål och spärren mot instrumenterade tester på fysisk telefon är kvar.
- Webbens oanvända shimmer-bibliotek har tagits ur pubspec och låsfil. Inga andra beroendeversioner ändrades.
- Androids obligatoriska regexgrupper läses nu med uttrycklig requireNotNull efter lyckad matchning; de tidigare Kotlin-varningarna för dessa läsningar är åtgärdade utan ändrad datumtolkning.

## Vad som finns kvar och varför

1. **Två klientimplementationer.** Android och Flutter har fortfarande separata parser-, kalender- och presentationslösningar. Att radera den ena skulle ta bort en plattform. Fortsatt arbete bör prioritera gemensamma scenarier/testdata och datakontrakt så att klienterna ger samma resultat.
2. **Stora skärmfiler.** Kalender, agenda, Min dag och inkorg blandar fortfarande mycket presentation och flödeslogik. Exempelvis är Flutter-kalendern cirka 1 800 rader och Android-kalendern cirka 1 760. En uppdelning kan förbättra underhållbarheten men är inte automatiskt färre kodrader. En bred omskrivning utan beteendeprov vore riskabel.
3. **Delad specialistsemantik.** Sysslor, rutiner, skolmat och växtdata används fortfarande av vissa översikter, äldre familjelägen och integrationskontrakt. Den koden är inte bevisat oanvänd och har därför inte raderats för att förbättra siffran. Hem är fortfarande en separat förhandsversion.
4. **Backendgränser och datalagring.** Backend delas med andra appar, bland annat MyMirai. Ingen serverfunktion, Firestore-regel, familjedata, autentisering eller datalagringsregion har ändrats. En inventering av svensk datalagring är fortfarande ett separat produktarbete.
5. **Prestanda saknar telefonmätning.** Färre oanvända prenumerationer och mindre bygginnehåll är verifierbara förändringar, men det bevisar inte att rapporterat lagg är löst. APK-jämförelsen görs med samma DevDebug-variant. Nästa prestandaarbete behöver mäta start, scroll och vybyte på telefon och skilja debugkostnad från appens egna omritningar/dataflöden.

## Bevarande och mätmetod

Original finns utanför båda aktiva källträden i /home/oscar/utveckling/vardag-uppdelning/20261025-teknisk-skuld. Där finns Git-bundles från före ändringen samt filmanifest med SHA-256 för arkiverade filer. Kopiorna har verifierats mot manifesten. Äldre arbete är återställbart och kan återanvändas i andra appar. Vardag Hem har inte skrivits över.

Källkodsmåtten omfattar Android app/src/main/java (*.kt) respektive Flutter lib (*.dart). Testkod, dokumentation, genererade filer, byggcache och backupkopior räknas inte. Rader är fysiska källrader inklusive kommentarer och tomrader; även icke-tomma rader och byte redovisas i JSON-underlaget. Det är inte minifiering eller borttagning av kommentarer för att få en bättre siffra. Arkivering minskar den aktiva appkoden, inte all historik på hårddisken.

Tester som enbart avsåg utplockade funktioner har arkiverats med koden. Tester för fortsatt aktiv logik behålls, även de som tidigare låg i en blandad TV-studiosvit. Lägre antal aktiva tester efter rensningen redovisas öppet och ska inte tolkas som att samma testantal körts igen.

Loggar och före/efter-mått: /home/oscar/utveckling/vardag-driftunderlag/skuld-20261025.

## Slutresultat

| Produktionskällträd | Filer före → efter | Rader före → efter | Minskning |
|---|---:|---:|---:|
| Android | 365 → 330 | 54 177 → 48 441 | −5 736 (10.6 %) |
| Flutter/webb | 156 → 137 | 57 403 → 49 514 | −7 889 (13.7 %) |

Totalt 13 625 färre källrader (12,2 %) och 54 färre filer i produktionskällträden. Icke-tomma rader minskade från 103 850 till 91 071.

APK, samma DevDebug-variant och signeringscertifikat: 30,479,419 → 29,399,489 byte, en minskning med 1,079,930 byte (3,54 %). Detta är 1,08 MB med decimal MB. Webbens main.dart.js är exakt lika stor före/efter: 4 794 248 byte. Dart-kompilatorn uteslöt redan den oanvända koden.

Verifierat: 843 Android-enhetstester, APK-bygge samt kompilering av Androids instrumenterade tester; 409 Fluttertester, flutter analyze utan anmärkningar och releasewebb; 132 befintliga funktionstester. Instrumentation och fysiskt telefonprov har inte körts. Före rensningen fanns 987 respektive 442 aktiva tester; tester enbart för arkiverade funktioner har följt med till arkivet. Aktiva tester för kalender/sparande, skolmatskonfiguration, temakontrast, widget/integration och storskärmens kvarvarande styrning är kvar.

Webb 1.2.1+34 är publicerad, med sju HTTP-kontroller och bytejämförelse av JavaScript mot fryst release. Chrome verifierade att både vanliga ingången och storskärmsingången når inloggningen utan JavaScript-fel. Inga produktionsdata ändrades av testerna.

Androidleverans: Vardag Dev 1.17.1 (61). Samma paket och signering som 1.17.0.

Privat APK-uppladdning verifierad mot Drive: https://drive.google.com/file/d/1Z4jKPKZyQnhsVd0DH88PI1OijOuJTQ_r/view
