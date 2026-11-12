import 'lathund_content.dart';

// Hjälp & guider för kalenderappen. Stegen följer respektive klients ingångar.
const kalenderLathund = <LathundKategori>[
  LathundKategori(
    emoji: "👋",
    titel: "Kom igång",
    poster: [
      LathundEntry(
        emoji: "🧭",
        fraga: "Jag är ny – var börjar jag?",
        svar:
            "Vardag samlar familjens kalender, scheman och det ni behöver förbereda. Börja med översikten och lägg sedan in en aktivitet.",
        steg: [
          "Tryck på Hem längst ner för att se dagens översikt. I Fokus visas dagen som en tidslinje.",
          "Tryck på Kalender för att bläddra mellan dagar, veckor och månader. Välj Alla för familjens översikt eller en person för den personens aktiviteter.",
          "Tryck på Lägg till i Kalender när du vill skapa något. Du granskar alltid uppgifterna innan du sparar.",
          "Öppna Mer för inställningar och Kalenderverktyg. Där finns Uppgifter, Inkorg, scheman och Hjälp & guider.",
        ],
        finnsHar: "Hem, Kalender och Mer",
      ),
      LathundEntry(
        emoji: "🔑",
        fraga: "Hur loggar jag in på en ny enhet?",
        svar:
            "Samma konto ger dig samma familj på telefon och webb. Skapa inte en ny familj om du redan tillhör en.",
        steg: [
          "Öppna Vardag och logga in med den e-postadress och det lösenord du redan använder.",
          "Om du är en ny familjemedlem: be en förälder om en inbjudningskod och välj Har du en inbjudningskod? på inloggningssidan. Fyll i koden och de uppgifter som efterfrågas.",
          "Om ingen har skapat familjen ännu: välj Skapa nytt konto (Ny familj), skapa ditt konto och följ steget Skapa familj.",
          "Har du glömt lösenordet? Välj Glömt lösenordet? på inloggningssidan och ange samma e-postadress som till kontot.",
        ],
        finnsHar: "Inloggningssidan",
      ),
      LathundEntry(
        emoji: "👥",
        fraga: "Varför ser vi olika val i familjen?",
        svar:
            "Din roll avgör vad du får göra. Ditt personfilter och din startvy ändrar bara hur du ser appen.",
        steg: [
          "Välj Alla i Kalender om du vill se hela familjens kalender. En vald person begränsar listan.",
          "Föräldrar har dessutom Uppgifter, Inkorg, schemaimport och familjeinställningar. Barn och ungdomar ser därför färre val under Mer.",
          "Vuxna och ungdomar kan skapa privata aktiviteter. Andra ser då en upptagen tid märkt Privat, inte innehållet.",
          "Om ditt konto har fel roll, be en förälder kontrollera den under Mer → Familjen → Hantera familj.",
        ],
        finnsHar: "Kalender → personfilter och Mer",
      ),
    ],
  ),
  LathundKategori(
    emoji: "📅",
    titel: "Aktiviteter och kalender",
    poster: [
      LathundEntry(
        emoji: "➕",
        fraga: "Hur lägger jag till en aktivitet snabbt?",
        svar:
            "Du kan skriva eller säga vad som ska hända. Texten blir ett utkast som du kontrollerar innan något sparas.",
        steg: [
          "Öppna Kalender och tryck på Lägg till.",
          "Skriv till exempel ”Fotboll för Alex på tisdag kl 17–18”. Använd ett namn som finns i er familj. Du kan också trycka på mikrofonen och tillåta mikrofonåtkomst; om det inte fungerar går samma text att skriva.",
          "Låt appen tolka texten och kontrollera titel, datum, klockslag och vem aktiviteten gäller. Rätta det som blev fel eller saknas.",
          "Tryck på Spara. Öppna rätt dag i Kalender och kontrollera att aktiviteten finns där.",
        ],
        finnsHar: "Kalender → Lägg till",
      ),
      LathundEntry(
        emoji: "🕒",
        fraga: "Hur fyller jag i datum och tid själv?",
        svar: "Manuell inmatning finns i samma formulär som snabbtexten.",
        steg: [
          "Öppna Kalender → Lägg till och välj Fyll i själv.",
          "Skriv aktivitetens namn. Tryck på datumet under När och välj dag.",
          "Välj klockslag om aktiviteten har en bestämd tid. Ange start och eventuellt sluttid; lämna den utan klockslag om det bara är dagen som är viktig.",
          "Välj vem aktiviteten gäller. Om ingen väljs gäller en vanlig familjeaktivitet hela familjen. Kontrollera och tryck på Spara.",
        ],
        finnsHar: "Kalender → Lägg till → Fyll i själv",
      ),
      LathundEntry(
        emoji: "🔁",
        fraga: "Hur gör jag en aktivitet återkommande?",
        svar:
            "Upprepning passar till exempel en träning som återkommer samma veckodag.",
        steg: [
          "Öppna Kalender → Lägg till och fyll i det första tillfällets datum och tid.",
          "Öppna Fler val och välj upprepning, till exempel varje vecka eller varannan vecka.",
          "Välj ett slutdatum om serien ska sluta, eller låt den upprepas tills vidare. Kontrollera personer och spara.",
          "Se serierna under Mer → Kalenderverktyg → Återkommande. Välj Redigera i aktivitetens ⋮-meny och därefter Redigera hela serien.",
        ],
        finnsHar: "Kalender → Lägg till → Fler val",
      ),
      LathundEntry(
        emoji: "✏️",
        fraga: "Hur ändrar eller tar jag bort en aktivitet?",
        svar:
            "Du ser bara ändringsval för aktiviteter du har rätt att ändra. Privata aktiviteter kan bara ändras av ägaren.",
        steg: [
          "Öppna Kalender, gå till rätt dag och leta upp aktiviteten.",
          "Tryck på ⋮ vid aktiviteten och välj Redigera. Ändra uppgifterna och spara.",
          "För att ta bort: välj Ta bort i aktivitetens ⋮-meny och läs bekräftelsen innan du fortsätter.",
          "För en upprepad aktivitet får du välja mellan bara den aktuella dagen och alla gånger. Alla gånger tar också bort flyttade tillfällen. Borttagning kräver internet.",
        ],
        finnsHar: "Kalender → aktivitet",
      ),
      LathundEntry(
        emoji: "↪️",
        fraga: "Hur flyttar eller ställer jag in bara ett tillfälle?",
        svar:
            "Välj den aktuella dagen först. Då kan resten av serien fortsätta som vanligt. Flytt och återställning kräver internet och gäller egna kalenderaktiviteter, inte importerade scheman.",
        steg: [
          "Öppna Kalender och gå till den dag då tillfället ursprungligen skulle ha ägt rum.",
          "Öppna aktivitetens ⋮-meny → Redigera → Flytta bara detta tillfälle.",
          "Fyll i nytt datum och nya tider och bekräfta. Det flyttade tillfället blir fristående; senare ändringar i serien ändrar inte det tillfället.",
          "För att ångra en flytt: öppna det flyttade tillfället och välj Ångra flytt – återställ enligt serien.",
          "För att ställa in utan att flytta: välj Ta bort och därefter alternativet för bara den dagen. Välj inte Alla om resten av serien ska finnas kvar.",
        ],
        finnsHar: "Kalender → ett tillfälle i serien",
      ),
      LathundEntry(
        emoji: "🎒",
        fraga: "Hur lägger jag till en packlista?",
        svar:
            "En packlista hör till aktiviteten, till exempel vad ett barn ska ha med till träningen.",
        steg: [
          "Öppna Kalender → Lägg till, eller redigera en befintlig aktivitet.",
          "Öppna Fler val. Lägg till det som ska tas med i packlistan, en sak i taget, och spara aktiviteten.",
          "Öppna aktiviteten på den aktuella dagen. Bocka av sakerna under Att ta med / Förberedelser när de är klara.",
        ],
        finnsHar: "Kalender → aktivitet → Fler val",
      ),
    ],
  ),
  LathundKategori(
    emoji: "🔒",
    titel: "Privata aktiviteter",
    poster: [
      LathundEntry(
        emoji: "🔐",
        fraga: "Hur skapar jag en privat aktivitet?",
        svar:
            "Vuxna och ungdomar kan skapa en aktivitet vars innehåll bara ägaren kan läsa. Tiden är fortfarande synlig för familjen.",
        steg: [
          "Öppna Kalender → Lägg till och skriv eller fyll i aktiviteten.",
          "Under Synlighet väljer du Privat i stället för Familjen. Den privata aktiviteten gäller dig själv.",
          "Kontrollera datum och tid och tryck på Spara. Du ser innehållet när du är inloggad med ditt eget konto.",
          "Familjen ser vem som är upptagen, tiden och texten Privat. De ser inte titel, beskrivning eller packlista.",
        ],
        finnsHar: "Kalender → Lägg till → Synlighet",
      ),
      LathundEntry(
        emoji: "👁️",
        fraga: "Är personfiltret samma sak som privat?",
        svar:
            "Nej. Personfiltret styr bara din egen lista. Synlighet avgör vad andra får läsa.",
        steg: [
          "Välj en person i Kalender för att fokusera på den personens dag. Det ändrar inte vem som får läsa aktiviteterna.",
          "Välj Privat när du skapar en aktivitet om innehållet bara ska kunna läsas av dig.",
          "På den gemensamma storskärmen visas privata aktiviteter som upptagna tider utan innehåll, även om den inloggade vuxna äger aktiviteten.",
        ],
        finnsHar: "Kalender → personfilter eller aktivitetens Synlighet",
      ),
    ],
  ),
  LathundKategori(
    emoji: "📥",
    titel: "Scheman och andra kalendrar",
    poster: [
      LathundEntry(
        emoji: "📷",
        fraga: "Hur skannar jag ett schema?",
        svar:
            "Du behöver en tydlig bild och internetanslutning. Skanningen föreslår händelser; ingenting läggs i kalendern förrän du har granskat och importerat.",
        steg: [
          "Öppna Mer → Kalenderverktyg → Skanna schema.",
          "Välj Ta foto med kameran eller Välj bild från galleriet. Tillåt kamera eller bildåtkomst om enheten frågar. Se till att hela schemat, veckodagar och tider syns skarpt.",
          "Vänta medan schemat läses. På granskningssidan anger du kalendernamn, väljer typ av schema och kontrollerar vilken familjemedlem det gäller.",
          "Kontrollera datum och vecka. Använd veckopilarna om hela schemat hamnat på fel vecka. Tryck på pennan vid en händelse för att rätta uppgifterna.",
          "Avmarkera händelser du inte vill ha med. Kontrollera särskilt start- och sluttider; en bild kan feltolkas.",
          "Tryck på Importera när allt stämmer. Öppna Kalender, välj personen och de aktuella dagarna för att kontrollera resultatet.",
        ],
        finnsHar: "Mer → Kalenderverktyg → Skanna schema",
        endastForaldrar: true,
      ),
      LathundEntry(
        emoji: "🔗",
        fraga: "Hur hämtar jag en annan kalender?",
        svar:
            "Använd en kalenderlänk i ICS-format från exempelvis skolan eller föreningen. En vanlig webbsidelänk är inte samma sak som en kalenderlänk.",
        steg: [
          "Öppna Mer → Kalenderverktyg → Andra kalendrar och välj Lägg till kalender.",
          "Ange ett namn och välj vilken person kalendern gäller, eller lämna personvalet tomt för en gemensam kalender.",
          "Välj om innehållet är schema/skola eller aktiviteter. Klistra in kalenderns https://- eller webcal://-länk och välj Hämta från URL.",
          "Har du en nedladdad fil? Välj datumperiod och .ics-fil. Granska period, antal och eventuella varningar och bekräfta sedan importen. Samma fil till samma person skapar inte dubletter. Upprepningar läggs till som enskilda tillfällen inom perioden, högst 400 poster per fil.",
          "Kontrollera resultatet i Kalender. Ändra helst importerade tider i källkalendern; lokala ändringar kan ersättas vid senare import.",
        ],
        finnsHar: "Mer → Kalenderverktyg → Andra kalendrar",
        endastForaldrar: true,
      ),
      LathundEntry(
        emoji: "📤",
        fraga: "Hur tar jag med min kalender till en annan app?",
        svar:
            "Du kan spara en kalenderfil som fungerar utan Vardag. Den är en kopia och uppdateras inte automatiskt.",
        steg: [
          "Öppna Mer → Kalenderverktyg → Ta med kalendern.",
          "Välj Mina aktiviteter för dina och familjens gemensamma aktiviteter samt dina egna privata. Föräldrar kan också välja Familjens aktiviteter, där alla privata aktiviteter utesluts.",
          "Välj Förbered kalenderfil och läs antalet poster och eventuella varningar. Importerade kalendrar utelämnas eftersom de redan finns hos sin källa.",
          "Välj Spara kalenderfil. På webben hamnar filen i webbläsarens nedladdningar. En personlig export kan innehålla privata uppgifter.",
          "Öppna importfunktionen i Google Kalender, Apple Kalender eller Outlook och välj filen. Skapa gärna en ny kalender som heter Vardag för kopian. Upprepad import i den andra appen kan ge dubletter.",
        ],
        finnsHar: "Mer → Kalenderverktyg → Ta med kalendern",
      ),
      LathundEntry(
        emoji: "🗂️",
        fraga: "Hur tar jag bort en felaktig schemaimport?",
        svar:
            "En skannad bild eller importerad kalender samlas som en egen import. Kontrollera namnet noga innan du tar bort den.",
        steg: [
          "Öppna Mer → Kalenderverktyg → Andra kalendrar.",
          "Leta upp importen under importerade scheman och kalendrar. Kontrollera namn och person så att du väljer rätt omgång.",
          "Tryck på papperskorgen eller Ta bort för just den importen och läs bekräftelsen. Importens händelser tas bort; manuella aktiviteter påverkas inte.",
          "Skanna eller importera därefter den rättade källan om du vill lägga tillbaka schemat.",
        ],
        finnsHar: "Mer → Kalenderverktyg → Andra kalendrar",
        endastForaldrar: true,
      ),
      LathundEntry(
        emoji: "💼",
        fraga: "Hur lägger jag in en arbetsvecka?",
        svar:
            "Markera flera datum när samma arbetstid gäller flera dagar. Lägg olika pass i separata omgångar.",
        steg: [
          "Öppna Mer → Kalenderverktyg → Arbetsschema och tryck på plusknappen för ett nytt arbetspass.",
          "Välj vem som jobbar. Tryck på Start och Slut och ställ in tiderna.",
          "Markera alla datum i datumväljaren som ska ha dessa tider. Använd månadspilarna om datumen ligger i en annan månad.",
          "Tryck på Spara Arbetspass. Kontrollera dagarna i Kalender och upprepa om andra dagar har andra tider.",
        ],
        finnsHar: "Mer → Kalenderverktyg → Arbetsschema",
        endastForaldrar: true,
      ),
    ],
  ),
  LathundKategori(
    emoji: "📌",
    titel: "Uppgifter och veckobrev",
    poster: [
      LathundEntry(
        emoji: "📨",
        fraga: "Hur lägger jag in ett veckobrev?",
        svar:
            "Veckobrev finns i Inkorg. Klistra in brevets text så får du förslag på aktiviteter och uppgifter att granska.",
        steg: [
          "Öppna Mer → Kalenderverktyg → Inkorg och tryck på Klistra in veckobrev eller anteckning.",
          "Klistra in eller skriv hela texten, gärna med datum och veckonummer. Välj vilket barn eller vilka personer brevet gäller.",
          "Välj om själva anteckningens text ska vara privat för dig. Det valet gör inte automatiskt de kommande aktiviteterna eller uppgifterna privata.",
          "Tryck på Spara och tolka. Texten finns kvar i Inkorg även om tolkningen behöver göras om.",
          "Öppna brevet och granska förslagen. Inget förslag blir en aktivitet eller uppgift förrän du väljer att spara det.",
        ],
        finnsHar: "Mer → Kalenderverktyg → Inkorg",
        endastForaldrar: true,
      ),
      LathundEntry(
        emoji: "✅",
        fraga: "Hur granskar jag förslag från veckobrevet?",
        svar:
            "Tolkningen kan missförstå datum eller person. Läs alltid originaltexten och förslagen innan du sparar.",
        steg: [
          "Öppna Mer → Kalenderverktyg → Inkorg och välj brevet som behöver granskas.",
          "Jämför varje förslags titel, datum och person med brevet. Markera bara det som stämmer. Förslag som saknar nödvändiga uppgifter kan inte sparas.",
          "Tryck på Spara valda förslag. Aktiviteter hamnar i Kalender och uppgifter under Mer → Kalenderverktyg → Uppgifter.",
          "Om tolkningen misslyckades finns texten kvar. Kontrollera internetanslutningen och välj Tolka eller Tolka igen. Sparade förslag kan bli synliga för familjen även om originaltexten är privat.",
        ],
        finnsHar: "Mer → Kalenderverktyg → Inkorg → ett veckobrev",
        endastForaldrar: true,
      ),
      LathundEntry(
        emoji: "📌",
        fraga: "Hur skapar och bockar jag av en uppgift?",
        svar:
            "Uppgifter är sådant som ska bli gjort, till exempel att lämna in en blankett. En kalenderaktivitet beskriver i stället något som ska hända en viss tid.",
        steg: [
          "Öppna Mer → Kalenderverktyg → Uppgifter. Tryck på plusknappen eller Lägg till för en ny uppgift.",
          "Skriv vad som ska göras. Ange ett senast-datum om det finns en deadline och ett Visa från-datum om uppgiften ska dyka upp först senare.",
          "Välj vem uppgiften gäller och spara. Du kan även öppna en befintlig uppgift för att ändra den.",
          "Bocka av uppgiften när den är gjord. Den visas bland klara uppgifter; ta bort bocken om du vill öppna den igen.",
        ],
        finnsHar: "Mer → Kalenderverktyg → Uppgifter",
        endastForaldrar: true,
      ),
      LathundEntry(
        emoji: "↕️",
        fraga: "Hur sorterar jag uppgifter efter vecka eller barn?",
        svar:
            "Sorteringen ändrar ordningen och grupperingen i listan. Gäller begränsar vilka personers uppgifter du ser.",
        steg: [
          "Öppna Mer → Kalenderverktyg → Uppgifter.",
          "Öppna Sortera och välj Datum, Vecka eller Person/barn. Datum visar närmaste deadline först. Vecka grupperar efter uppgiftens senast-datum; uppgifter utan datum får en egen grupp.",
          "Öppna Gäller och välj ett barn eller en annan familjemedlem om du bara vill se uppgifter som gäller den personen. Välj alla personer för att återställa filtret.",
          "Öppna och klara uppgifter hålls åtskilda även när du byter sortering. Flera personer på samma uppgift visas tillsammans.",
        ],
        finnsHar: "Mer → Kalenderverktyg → Uppgifter → Sortera / Gäller",
        endastForaldrar: true,
      ),
      LathundEntry(
        emoji: "🗓️",
        fraga: "Hur sorterar jag veckobreven?",
        svar:
            "Veckobrev sorteras i Inkorg. Vecka syftar på publiceringsdatumet för skolnyheter, annars när brevet lades in – inte ett veckonummer som nämns inne i texten.",
        steg: [
          "Öppna Mer → Kalenderverktyg → Inkorg.",
          "Välj Sortera → Datum för nyast först, Vecka för veckogrupper eller Person/barn för grupper efter vem brevet gäller.",
          "Använd Gäller för att välja ett barn. Personkopplingen kommer från valet när brevet lades in, inte från den vuxna som skapade anteckningen.",
          "Öppna brevet för att läsa hela texten eller granska förslagen. Granskningsstatus hålls åtskild även när du sorterar.",
        ],
        finnsHar: "Mer → Kalenderverktyg → Inkorg → Sortera / Gäller",
        endastForaldrar: true,
      ),
    ],
  ),
  LathundKategori(
    emoji: "⚙️",
    titel: "Inställningar och familjen",
    poster: [
      LathundEntry(
        emoji: "🌓",
        fraga: "Hur ändrar jag utseende och startvy?",
        svar:
            "Utseende ändrar färgtemat. Startvy väljer hur din dag presenteras. Inget av valen ändrar dina behörigheter.",
        steg: [
          "Öppna Mer och fäll ut Min vy.",
          "Under Utseende väljer du Följ enheten, Ljust eller Mörkt. Valet gäller denna enhet.",
          "Under Startvy väljer du Vanlig vy för översikten eller Fokus för en enklare tidslinje. Startvyn följer ditt konto.",
        ],
        finnsHar: "Mer → Min vy",
      ),
      LathundEntry(
        emoji: "👨‍👩‍👧",
        fraga: "Hur bjuder jag in eller ändrar familjemedlemmar?",
        svar:
            "En förälder hanterar familjen. Var och en använder sitt eget konto så att personliga val och privata aktiviteter hamnar rätt.",
        steg: [
          "Öppna Mer och fäll ut Familjen.",
          "Välj Bjud in och följ anvisningarna för inbjudningskoden. Låt personen gå med från sin egen enhet.",
          "Öppna Hantera familj om du behöver kontrollera namn eller roll. Ändringarna gäller familjen, inte bara din vy.",
        ],
        finnsHar: "Mer → Familjen",
        endastForaldrar: true,
      ),
      LathundEntry(
        emoji: "🔔",
        fraga: "Hur får jag påminnelser?",
        svar:
            "Du väljer påminnelser i Vardag, men telefonen eller webbläsaren måste också tillåta notiser.",
        steg: [
          "Öppna Mer → Påminnelser och välj vilka påminnelser du vill ha.",
          "På iPhone/iPad: öppna Vardag i Safari, välj Dela → Lägg till på hemskärmen och öppna sedan appen från den ikonen. Under Mer → Påminnelser väljer du Aktivera notiser på den här enheten och tillåter notiser.",
          "Aktivera Kalenderpåminnelser på webben om du vill få dem. Webbnotiser kan vara några minuter sena. Kontrollera också att kalenderaktiviteten har rätt datum och klockslag.",
        ],
        finnsHar: "Mer → Påminnelser",
      ),
      LathundEntry(
        emoji: "📺",
        fraga: "Hur visar jag familjens kalender på en TV?",
        svar:
            "Storskärmen visar kalendern och kommande dagar. Information på TV:n kan läsas av alla som står framför den.",
        steg: [
          "Öppna Mer → Storskärm och välj om uppgifter från veckobrev ska visas. De kräver vuxeninloggning.",
          "Välj Öppna storskärmen. Öppna samma adress på en dator ansluten till TV:n eller i TV:ns webbläsare och logga in med Vardag-kontot.",
          "Välj helskärm, till exempel F11 på dator, och stäng av enhetens viloläge. Långa listor växlar sida automatiskt.",
          "Privata aktiviteter visas utan innehåll. Rutiner och stegvis timer hanteras i Hem-appen.",
        ],
        finnsHar: "Mer → Storskärm",
        endastForaldrar: true,
      ),
      LathundEntry(
        emoji: "🏠",
        fraga: "Var finns städning, timer, blommor och mat?",
        svar:
            "De verktygen har samlats i den separata Hem-appen. Vardag fokuserar på kalender, scheman, veckobrev och uppgifter.",
        steg: [
          "Använd Vardag för det som ska hända och behöver förberedas i familjens planering.",
          "Öppna Hem-appen för sysslor, rutiner, timer, inköp, mat och växter. Fliken Hem inne i Vardag är kalenderappens dagsöversikt, inte den separata appen.",
          "Veckobrevsuppgifter och förberedelser finns kvar i Vardag under Uppgifter.",
        ],
        finnsHar: "Hem-appen och Vardags flik Mer",
      ),
    ],
  ),
  LathundKategori(
    emoji: "💡",
    titel: "När något inte stämmer",
    poster: [
      LathundEntry(
        emoji: "🔍",
        fraga: "Varför hittar jag inte en aktivitet eller uppgift?",
        svar:
            "Börja med datum och filter. Ett dolt resultat behöver inte betyda att uppgiften har tagits bort.",
        steg: [
          "I Kalender: kontrollera vald dag och byt personfiltret till Alla. Prova Dag eller Vecka om posten är svår att hitta i månadsöversikten.",
          "I Uppgifter eller Inkorg: välj alla personer under Gäller och kontrollera även andra statusgrupper. En uppgift med Visa från-datum kan vänta på att bli synlig på Hem.",
          "För en importerad kalender: kontrollera att importen finns under Andra kalendrar och att den gäller rätt person.",
          "Om andra i familjen ser posten men inte du: kontrollera att du är inloggad på rätt konto och i samma familj. Privata aktiviteters innehåll syns bara för ägaren.",
        ],
        finnsHar: "Kalender och Mer → Kalenderverktyg",
      ),
      LathundEntry(
        emoji: "☁️",
        fraga: "Vad betyder ”sparat lokalt” eller ett synkfel?",
        svar:
            "En ändring kan synas på din egen enhet innan den har bekräftats av servern. Andra enheter ser den först när den har synkats.",
        steg: [
          "Kontrollera internetanslutningen om appen visar att den väntar på bekräftelse. Vänta på resultatet innan du lägger in samma sak igen.",
          "Om appen visar ett fel: läs meddelandet och kontrollera om posten faktiskt finns kvar. Rätta eller försök igen när anslutningen fungerar.",
          "Rensa inte appens data eller avinstallera för att lösa en väntande ändring; en ändring som bara finns lokalt kan då gå förlorad.",
          "Skanning, tolkning, flytt och borttagning behöver internet. Om ett fel fortsätter, notera vilken vy och version du använder under Mer → Om appen.",
        ],
        finnsHar: "Meddelandet i appen och Mer → Om appen",
      ),
    ],
  ),
];
