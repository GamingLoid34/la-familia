// UPPDATERA vid varje ny funktion — lathunden ska alltid spegla appens verkliga läge.

class LathundEntry {
  final String emoji;
  final String fraga;
  final String svar;
  final List<String> steg; // max 3, kan vara tom
  final String finnsHar; // t.ex. 'Kalendern → ⋮-menyn'
  final bool endastForaldrar;

  const LathundEntry({
    required this.emoji,
    required this.fraga,
    required this.svar,
    this.steg = const [],
    required this.finnsHar,
    this.endastForaldrar = false,
  });
}

class LathundKategori {
  final String emoji;
  final String titel;
  final List<LathundEntry> poster;

  const LathundKategori({
    required this.emoji,
    required this.titel,
    required this.poster,
  });
}

const List<LathundKategori> lathundInnehall = [
  LathundKategori(
    emoji: '🏠',
    titel: 'Hem & dagen',
    poster: [
      LathundEntry(
        emoji: '☀️',
        fraga: 'Vad visar hemvyn?',
        svar: 'Hemvyn ger en samlad bild av just denna dag. Här ser du dagens aktiviteter, morgon- och kvällsrutiner, sysslor, måltider och en förhandstitt på vad som händer imorgon.',
        finnsHar: 'Fliken Hem',
      ),
      LathundEntry(
        emoji: '🔋',
        fraga: 'Hur fungerar energinivån?',
        svar: 'Du kan välja mellan fyra energinivåer: tom på energi (slut), låg energi, okej energi eller full av energi (toppen). Det hjälper resten av familjen att förstå hur du mår idag.',
        steg: [
          'Klicka på din batterisymbol i toppen på hemvyn.',
          'Välj den nivå som stämmer bäst med dagsformen.',
          'Nivån sparas direkt och visas för familjen.',
        ],
        finnsHar: 'Hem → Profil/batteri i toppen',
      ),
      LathundEntry(
        emoji: '⛔',
        fraga: 'Vad innebär upptagen-status?',
        svar: 'Om du behöver vila, jobbar eller inte vill bli störd kan du sätta en upptagen-status med en tid. Då syns en röd ring runt din profil.',
        steg: [
          'Öppna kalendern och tryck på symbolen för Stör ej / upptagen.',
          'Välj aktivitet (t.ex. Vila eller Jobb) och hur länge.',
        ],
        finnsHar: 'Kalendern → Symbolen ⛔ i listen',
      ),
      LathundEntry(
        emoji: '🌦️',
        fraga: 'Hur fungerar vädret och klädråden?',
        svar: 'Överst visas aktuell temperatur och vädersymbol för er hemort. Appen ger även ett enkelt och tydligt klädråd anpassat efter dagens temperatur och nederbörd.',
        finnsHar: 'Hem → Vädret i toppen',
      ),
      LathundEntry(
        emoji: '🎨',
        fraga: 'Varför har varje dag en egen färg?',
        svar: 'Appen följer den klassiska NPF-färgstandarden för veckodagar: måndag är grön, tisdag blå, onsdag vit/grå, torsdag brun, fredag gul, lördag rosa och söndag röd. Färgerna gör det lätt att hålla koll på tiden.',
        finnsHar: 'Genomgående i hela appen',
      ),
      LathundEntry(
        emoji: '🧭',
        fraga: 'Vad är Min dag?',
        svar: 'Min dag är en proportionell tidslinje över din dag. Det mörka NU-strecket visar exakt var på dagen du är och flyttar sig automatiskt minut för minut med klockan. Klara saker bockas av, pågående aktivitet lyfts fram och luckor mellan tider syns tydligt. Tryck på en pågående eller kommande aktivitet för att markera om du tar dig dit själv eller blir hämtad. Om du scrollar bort tar den flytande NU-knappen dig direkt tillbaka till nuet.',
        finnsHar: 'Hem → Knappen Min dag',
      ),
      LathundEntry(
        emoji: '📌',
        fraga: 'Vad är familjetavlan?',
        svar: 'Familjetavlan är en remsa där ni kan sätta upp snabba lappar, viktiga meddelanden eller se vem som tagit ansvar för en hämtning.',
        steg: [
          'Tryck på ＋ på tavlan på hemskärmen eller i kalendern.',
          'Skriv ett kort meddelande och spara.',
        ],
        finnsHar: 'Hem & Kalendern → Tavlan',
      ),
    ],
  ),

  LathundKategori(
    emoji: '📅',
    titel: 'Kalendern',
    poster: [
      LathundEntry(
        emoji: '🗓️',
        fraga: 'Vilka vyer finns i kalendern och när används de?',
        svar: 'Kalendern har fyra lägen: "Dag" för detaljer med piktogram, "Vecka" för familjens gemensamma översikt, "Månad" för långsiktig planering och "Agenda" för en ren tidslinje uppifrån och ned.',
        finnsHar: 'Kalendern → Väljaren överst (Dag / Vecka / Månad / Agenda)',
      ),
      LathundEntry(
        emoji: '➕',
        fraga: 'Hur lägger jag till en ny händelse?',
        svar: 'Du kan antingen trycka på den stora ＋-knappen eller skriva direkt i snabbfältet.',
        steg: [
          'Tryck på ＋-knappen längst ned till höger.',
          'Fyll i titel, datum, tid, personer och välj piktogram.',
          'Tryck på "Spara aktivitet".',
        ],
        finnsHar: 'Kalendern → ＋-knappen',
      ),
      LathundEntry(
        emoji: '✏️',
        fraga: 'Hur redigerar eller tar jag bort en händelse?',
        svar: 'Klicka på händelsen i kalendern för att se detaljerna. Där kan du ändra tid, checklista eller radera den.',
        finnsHar: 'Kalendern → Klicka på valfri händelse',
      ),
      LathundEntry(
        emoji: '🔁',
        fraga: 'Hur fungerar återkommande händelser?',
        svar: 'För aktiviteter som upprepas regelbundet (t.ex. träningar) kan du välja upprepning "Varje vecka" eller "Varannan vecka". Då syns de automatiskt på rätt dagar framöver.',
        finnsHar: 'Formuläret för att lägga till/ändra aktivitet',
      ),
      LathundEntry(
        emoji: '🖼️',
        fraga: 'Vad är piktogram och checklistor?',
        svar: 'Piktogram är bildsymboler som gör händelsen visuell och lätt att förstå för alla. Du kan också lägga till en packlista eller delmoment som kan bockas av.',
        finnsHar: 'Aktivitetsdetaljer & Skapa aktivitet',
      ),
      LathundEntry(
        emoji: '👥',
        fraga: 'Vad är skillnaden på familjeraden och personrader?',
        svar: 'I veckovyn har varje person sin egen rad med sina personliga tider. Högst upp finns familjeraden för gemensamma aktiviteter som rör alla.',
        finnsHar: 'Kalendern → Veckovyn',
      ),
      LathundEntry(
        emoji: '🚨',
        fraga: 'Vad betyder konfliktvarningarna överst i kalendern?',
        svar: 'Om två vuxna är upptagna samtidigt eller om det uppstår en krock vid en hämtning varnar kalendern med en röd skylt. Klicka på skylten för att se detaljer och ta ansvar ("Jag tar det").',
        finnsHar: 'Kalendern → Varningsremsan överst',
      ),
    ],
  ),

  LathundKategori(
    emoji: '⚡',
    titel: 'Snabbfältet',
    poster: [
      LathundEntry(
        emoji: '🎙️',
        fraga: 'Hur använder jag röst eller text i snabbfältet?',
        svar: 'I snabbfältet kan du skriva en hel mening på vanlig svenska eller trycka på mikrofonen och tala. Appen tolkar automatiskt vad du menar.',
        finnsHar: 'Kalendern → Snabbfältet nederst',
      ),
      LathundEntry(
        emoji: '💬',
        fraga: 'Vilka exempel förstår snabbfältet?',
        svar: 'Du kan säga till exempel: "Fotboll Oscar tisdag 17.00", "Tandläkare Céline 3/9 kl 9", "Syssla dammsuga Liam", "Middag tacos fredag" eller "Handla mjölk och bröd".',
        finnsHar: 'Kalendern → Snabbfältet',
      ),
      LathundEntry(
        emoji: '🧠',
        fraga: 'Vad händer innan något sparas från snabbfältet?',
        svar: 'Appen visar alltid ett bekräftelseblad där du ser hur texten tolkades. Där kan du justera detaljer innan du godkänner och sparar.',
        finnsHar: 'Bekräftelsebladet efter inmatning',
      ),
    ],
  ),

  LathundKategori(
    emoji: '📥',
    titel: 'Kalenderimport & Scheman',
    poster: [
      LathundEntry(
        emoji: '🔗',
        fraga: 'Hur prenumererar jag på ett skolschema eller webbkalender?',
        svar: 'Klistra in en webcal- eller ics-länk från skolan eller föreningen. Händelserna uppdateras då regelbundet och syns direkt i familjens kalender.',
        finnsHar: 'Kalendern → ⋮-menyn → Kalenderimport',
        endastForaldrar: true,
      ),
      LathundEntry(
        emoji: '🏫',
        fraga: 'Vad är skillnaden på "Schema" och "Aktivitet" vid import?',
        svar: 'Väljer du "Schema" klumpas skollektionerna ihop till ett lugnt skolblock i agendan så att kalendern inte blir plottrig. Väljer du "Aktivitet" visas varje lektion som en egen händelse.',
        finnsHar: 'Kalenderimport → Välj typ',
        endastForaldrar: true,
      ),
      LathundEntry(
        emoji: '📷',
        fraga: 'Hur fungerar schemaskanning med kameran?',
        svar: 'Du kan fota eller ladda upp en bild av ett tryckt veckoschema eller pappersschema. AI läser av tider och händelser automatiskt. På granskningssidan väljer du typ av schema (Skola, Rehab, Jobb eller Annat) så att rätt banner och piktogram visas i kalendern.',
        finnsHar: 'Kalendern → ⋮-menyn → Skanna schema 📷',
        endastForaldrar: true,
      ),
      LathundEntry(
        emoji: '💼',
        fraga: 'Hur lägger man in arbetstider och skift?',
        svar: 'Under Schema kan föräldrar lägga in arbetspass och skifttider. Det gör att krockar vid hämtningar och närvaro beräknas automatiskt.',
        finnsHar: 'Kalendern → ⋮-menyn → Schema',
        endastForaldrar: true,
      ),
      LathundEntry(
        emoji: '🗑️',
        fraga: 'Vad händer om jag tar bort en kalenderimport?',
        svar: 'Om du raderar en import tas alla händelser som kom från den länken bort automatiskt. Dina manuella händelser påverkas inte.',
        finnsHar: 'Kalenderimport → Soptunnan på en import',
        endastForaldrar: true,
      ),
    ],
  ),

  LathundKategori(
    emoji: '🫶',
    titel: 'Besöksbokning',
    poster: [
      LathundEntry(
        emoji: '🌐',
        fraga: 'Vad är besökslänken och hur delas den?',
        svar: 'Besökslänken är en webbsida där vänner och släkt kan välja en ledig ankomsttid för att hälsa på Noomi. För att spara på Noomis krafter under rehabiliteringen tillåts max ett sällskap per dag och besöket är max en timme. Dela länken via sms eller meddelande.',
        finnsHar: 'Kalendern → ⋮-menyn → Besöksbokning',
        endastForaldrar: true,
      ),
      LathundEntry(
        emoji: '⏱️',
        fraga: 'Hur fungerar regeln om max ett sällskap per dag och max 1 timme?',
        svar: 'När ett sällskap har anmält sig på en dag stängs dagen automatiskt för nya anmälningar med texten "Ett besök är redan inbokat". Besöket läggs in i kalendern med en timmes sluttid. Befintliga anmälningar som redan fanns före regeln påverkas inte automatiskt.',
        finnsHar: 'Webbsidan för besök (/besok/) & Kalendern',
        endastForaldrar: true,
      ),
      LathundEntry(
        emoji: '🚦',
        fraga: 'Vad innebär dagsläget 💚💛❤️?',
        svar: 'Grönt betyder välkommen. Gult betyder att Noomi är lite tröttare och korta besök uppskattas. Rött betyder vilodag och stänger automatiskt alla besökstider den dagen.',
        finnsHar: 'Besöksbokning → Läge för vald dag',
        endastForaldrar: true,
      ),
      LathundEntry(
        emoji: '📋',
        fraga: 'Var ser jag inbokade besökare?',
        svar: 'I admin-vyn under Besöksbokning listas alla kommande besök med datum, ankomsttid, besökarnas namn och telefonnummer.',
        finnsHar: 'Besöksbokning → Kommande bokningar',
        endastForaldrar: true,
      ),
      LathundEntry(
        emoji: '🔗',
        fraga: 'Hur kopierar jag en ändringslänk till en besökare?',
        svar: 'Klicka på länkikonen bredvid besöket i listan. Då kopieras besökarens personliga hanteringslänk så att du kan skicka den till hen.',
        finnsHar: 'Besöksbokning → Länkikonen 🔗 på en bokning',
        endastForaldrar: true,
      ),
      LathundEntry(
        emoji: '🔍',
        fraga: 'Hur hittar besökaren sin borttappade anmälan?',
        svar: 'På den publika webbsidan finns länken "Redan anmäld men tappat bort din länk?". Besökaren anger sitt telefonnummer och får direkt upp sina besökstider.',
        finnsHar: 'Webbsidan för besök (/besok/)',
        endastForaldrar: true,
      ),
      LathundEntry(
        emoji: '📞',
        fraga: 'Hur meddelas besökare om dagsformen ändras?',
        svar: 'Eftersom telefonnummer sparas vid anmälan ringer eller sms:ar familjen direkt till de inbokade besökarna om orken eller läget plötsligt förändras.',
        finnsHar: 'Besöksbokning → Telefonlänken på bokningen',
        endastForaldrar: true,
      ),
    ],
  ),

  LathundKategori(
    emoji: '🍽️',
    titel: 'Mat & Måltider',
    poster: [
      LathundEntry(
        emoji: '🍲',
        fraga: 'Hur planerar jag veckans matsedel?',
        svar: 'Under Matplanering kan du planera lunch och middag för varje dag i veckan så att hela familjen vet vad som serveras.',
        finnsHar: 'Hem → Knappen Matplanering (eller Kalendern → ⋮ → Mat)',
      ),
      LathundEntry(
        emoji: '✨',
        fraga: 'Hur fungerar AI-menyn för mat?',
        svar: 'Tryck på AI-knappen i matplaneraren för att få förslag på en varierad veckomatsedel som tar hänsyn till familjens allergier, favoriter och ogillad mat.',
        finnsHar: 'Matplanering → AI-förslag ✨',
        endastForaldrar: true,
      ),
      LathundEntry(
        emoji: '🥗',
        fraga: 'Var ställer jag in familjens matpreferenser?',
        svar: 'Under Inställningar kan föräldrar fylla i allergier, vad familjen ogillar och vad som är favoriträtter. AI-menyn anpassar sig efter detta.',
        finnsHar: 'Inställningar → Matpreferenser',
        endastForaldrar: true,
      ),
      LathundEntry(
        emoji: '🛒',
        fraga: 'Kan jag skicka matvaror direkt till inköpslistan?',
        svar: 'Ja, från måltidsplaneringen kan ingredienser läggas till direkt på den gemensamma inköpslistan.',
        finnsHar: 'Matplanering → Lägg till i inköpslistan',
      ),
      LathundEntry(
        emoji: '🏥',
        fraga: 'Hur väljer jag min mat på sjukhuset?',
        svar: 'Tryck på lunch- eller middagsblocket i Min dag. Välj din rätt med samma nummer som på sjukhusets pappersmeny, samt råkost och dessert om du vill. Ditt val sparas och visas direkt i din tidslinje.',
        finnsHar: 'Hem → Min dag → Tryck på Lunch eller Middag',
      ),
    ],
  ),

  LathundKategori(
    emoji: '🧹',
    titel: 'Sysslor & Rutiner',
    poster: [
      LathundEntry(
        emoji: '✅',
        fraga: 'Hur bockar jag av en syssla?',
        svar: 'Gå till fliken Sysslor eller titta på hemskärmen under "Dagens sysslor". Klicka på cirkeln bredvid sysslan för att markera den som klar.',
        finnsHar: 'Fliken Sysslor & Hemvyn',
      ),
      LathundEntry(
        emoji: '🔄',
        fraga: 'Vad är roterande sysslor?',
        svar: 'Roterande sysslor (t.ex. duka eller gå ut med soporna) flyttas automatiskt till nästa person i familjen varje dag.',
        finnsHar: 'Fliken Sysslor',
      ),
      LathundEntry(
        emoji: '🌅',
        fraga: 'Hur fungerar morgon- och kvällsrutiner?',
        svar: 'Rutiner är fasta checklistor för morgon och kväll (t.ex. borsta tänder, packa väska). De visas som tydliga kort på hemskärmen.',
        finnsHar: 'Hemvyn & Inställningar → Morgon- & kvällsrutiner',
      ),
      LathundEntry(
        emoji: '🧭',
        fraga: 'Vad är Vardagsplanen?',
        svar: 'Vardagsplanen är familjens grundmall för veckan med fasta tider för uppstigning, skola, middag och läggdags.',
        finnsHar: 'Inställningar → Vardagsplan — hela veckoupplägget',
        endastForaldrar: true,
      ),
      LathundEntry(
        emoji: '📊',
        fraga: 'Var finns statistik över gjorda sysslor?',
        svar: 'Föräldrar kan se en sammanställning över hur många sysslor som gjorts per person.',
        finnsHar: 'Sysslor → Statistikikonen i toppen',
        endastForaldrar: true,
      ),
    ],
  ),

  LathundKategori(
    emoji: '🛒',
    titel: 'Inköp & Timer',
    poster: [
      LathundEntry(
        emoji: '📝',
        fraga: 'Hur fungerar den delade inköpslistan?',
        svar: 'Alla i familjen kan skriva upp varor på inköpslistan. När du är i affären bockar du av varorna med ett tryck så försvinner de i realtid.',
        finnsHar: 'Hem → Knappen Inköpslista',
      ),
      LathundEntry(
        emoji: '⏱️',
        fraga: 'Hur använder jag timern?',
        svar: 'Timern är en visuell nedräknare med tydlig färg och symboler. Den passar perfekt för skärmtid, läxläsning eller tandborstning.',
        finnsHar: 'Hem → Knappen Timer',
      ),
    ],
  ),

  LathundKategori(
    emoji: '🤖',
    titel: 'AI-hjälpen',
    poster: [
      LathundEntry(
        emoji: '💡',
        fraga: 'Vad gör AI-planeraren?',
        svar: 'AI-planeraren kan analysera familjens vecka och ge smarta förslag på tidsluckor, förberedelser och påminnelser.',
        finnsHar: 'Inställningar → Testa AI-planeraren',
        endastForaldrar: true,
      ),
      LathundEntry(
        emoji: '🛡️',
        fraga: 'Godkänns AI-förslag alltid av en förälder?',
        svar: 'Ja, AI sparar eller ändrar aldrig någonting på egen hand. Du får alltid se förslagen i en lista och godkänner själv vad du vill spara.',
        finnsHar: 'AI-planeraren',
        endastForaldrar: true,
      ),
      LathundEntry(
        emoji: '⏳',
        fraga: 'Finns det en kvot för AI-funktioner?',
        svar: 'Ja, föräldrakonton har en generös daglig kvot för att köra AI-analyser och menygenereringar.',
        finnsHar: 'AI-tjänsterna i appen',
        endastForaldrar: true,
      ),
    ],
  ),

  LathundKategori(
    emoji: '🔔',
    titel: 'Påminnelser & Notiser',
    poster: [
      LathundEntry(
        emoji: '⏰',
        fraga: 'Vilka påminnelser skickar appen?',
        svar: 'Appen har tre nivåer av påminnelser för aktiviteter: 15 minuter innan start, en övergångsvarning 10 minuter innan ("Om 10 min: byta aktivitet"), samt en startpåminnelse exakt när aktiviteten börjar (valbar per telefon, perfekt om man vilar mellan passen).',
        finnsHar: 'Inställningar → Aviseringar',
      ),
      LathundEntry(
        emoji: '📢',
        fraga: 'Vad är familjehändelse-notiser?',
        svar: 'Det är pushnotiser som skickas när någon i familjen skriver en lapp på tavlan, reagerar på en händelse eller tilldelar en syssla.',
        finnsHar: 'Inställningar → Aviseringar → Familjehändelser',
      ),
      LathundEntry(
        emoji: '🛠️',
        fraga: 'Vad gör jag om notiser inte dyker upp?',
        svar: 'Kontrollera att aviseringar är aktiverade i telefonens egna inställningar och att reglagen under Aviseringar i appen är påslagna.',
        finnsHar: 'Telefonens inställningar & Inställningar i appen',
      ),
      LathundEntry(
        emoji: '❓',
        fraga: 'Varför fick jag ingen avisering?',
        svar: 'Du notifieras inte om saker du själv gör (t.ex. dina egna lappar på tavlan). Familjepush pausas dessutom automatiskt när du har läget "Upptagen" igång eller har lägsta energinivån (1/5). För att en aktivitetspåminnelse ska skapas måste aktiviteten sparas mer än 15 minuter innan start. Du kan kontrollera allt i felsökspanelen under Inställningar → Aviseringar → Felsök notiser 🔧.',
        finnsHar: 'Inställningar → Aviseringar',
      ),
    ],
  ),

  LathundKategori(
    emoji: '👨‍👩‍👧‍👦',
    titel: 'Roller & Behörigheter',
    poster: [
      LathundEntry(
        emoji: '🔑',
        fraga: 'Vad kan föräldrar som barn inte kan?',
        svar: 'Föräldrar kan bjuda in medlemmar, importera och skanna scheman, hantera besöksbokningen, ändra alla händelser och köra AI-planeraren. Barn och ungdomar har full tillgång till sitt eget schema, kan bocka av sysslor, sätta energinivå, skriva i snabbfältet och skapa egna aktiviteter.',
        finnsHar: 'Hela appen',
      ),
      LathundEntry(
        emoji: '🔒',
        fraga: 'Vem kan redigera eller radera en händelse?',
        svar: 'Den person som skapade händelsen kan alltid ändra den. Föräldrar kan dessutom ändra och radera alla familjens händelser.',
        finnsHar: 'Aktivitetsdetaljer → ⋮-menyn',
      ),
    ],
  ),

  LathundKategori(
    emoji: '⚙️',
    titel: 'Inställningar & Anpassningar',
    poster: [
      LathundEntry(
        emoji: '🧘',
        fraga: 'Vad är lågstimuli-läget?',
        svar: 'Lågstimuli-läget ger ett lugnare och mer avskalat utseende. Skuggor, gradienter och starka kontraster tas bort till förmån för mjuka, platta färger.',
        finnsHar: 'Inställningar → Lågstimuli-läge',
      ),
      LathundEntry(
        emoji: '🔍',
        fraga: 'Vad är skillnaden på visningsläget "Allt" och "Fokus"?',
        svar: '"Allt" visar alla sektioner, menyer och kalendervyer. "Fokus" ger en förenklad vy med bara det viktigaste (t.ex. Dag och Agenda i kalendern). I kalendern visas en "Visa allt"-knapp under väljaren så att du enkelt kan gå tillbaka till full vy. Min dag-knappen på Hem öppnar bara helskärmstidslinjen och byter inte ditt visningsläge.',
        finnsHar: 'Inställningar → Vis-läge (Allt / Fokus) samt Kalendern',
      ),
      LathundEntry(
        emoji: '🏠',
        fraga: 'Hur ställer jag in familjens hemposition?',
        svar: 'Under Inställningar kan föräldrar ange orten där familjen bor. Det krävs för att väder och klädråd ska stämma.',
        finnsHar: 'Inställningar → Hemposition',
        endastForaldrar: true,
      ),
      LathundEntry(
        emoji: '👤',
        fraga: 'Hur ändrar jag familjemedlemmar eller bjuder in nya?',
        svar: 'Föräldrar kan lägga till barn och ungdomar, bjuda in medlemmar med inbjudningskod eller ändra namn och roller.',
        finnsHar: 'Inställningar → Hantera familj & Bjud in',
        endastForaldrar: true,
      ),
    ],
  ),
];
