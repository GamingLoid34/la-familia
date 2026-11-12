import 'lathund_content.dart';

// Lathunden för den avskalade kalenderappen. Den äldre guiden finns kvar.
const kalenderLathund = <LathundKategori>[
  LathundKategori(
    emoji: "📅",
    titel: "Kalendern",
    poster: [
      LathundEntry(
        emoji: "🗓️",
        fraga: "Hur hittar jag dagens och familjens aktiviteter?",
        svar:
            "Öppna Hem eller Kalender. I kalendern kan du välja dag, vecka eller månad och filtrera på en person.",
        finnsHar: "Hem och Kalender",
        endastForaldrar: false,
      ),
      LathundEntry(
        emoji: "➕",
        fraga: "Hur lägger jag till en aktivitet?",
        svar:
            "Tryck på Lägg till och skriv en mening, till exempel ”Träning tisdag 17”. Granska förslaget och komplettera tid och personer innan du sparar. Det går också att fylla i uppgifterna manuellt.",
        finnsHar: "Kalender → Lägg till",
        endastForaldrar: false,
      ),
      LathundEntry(
        emoji: "🔁",
        fraga: "Hur ändrar jag ett tillfälle i en serie?",
        svar:
            "Öppna aktiviteten. Du kan ställa in en gång eller flytta ett tillfälle. En flyttad gång kan återställas från detaljvyn. Flytt och återställning kräver internet.",
        finnsHar: "Kalender → Aktivitet",
        endastForaldrar: false,
      ),
    ],
  ),
  LathundKategori(
    emoji: "🔒",
    titel: "Privata aktiviteter",
    poster: [
      LathundEntry(
        emoji: "🔒",
        fraga: "Vem kan skapa en privat aktivitet?",
        svar:
            "Vuxna och ungdomar kan välja Privat när de skapar en aktivitet. Den som skapade aktiviteten ser innehållet; resten av familjen ser tiden och texten Privat.",
        finnsHar: "Kalender → Lägg till → Privat",
        endastForaldrar: false,
      ),
      LathundEntry(
        emoji: "👁️",
        fraga: "Vad syns för andra?",
        svar:
            "Familjen och den gemensamma skärmen kan se att tiden är upptagen, men inte aktivitetens namn, beskrivning eller packlista. Endast ägaren kan se och ändra det privata innehållet.",
        finnsHar: "Kalender → Privat aktivitet",
        endastForaldrar: false,
      ),
    ],
  ),
  LathundKategori(
    emoji: "📥",
    titel: "Scheman och veckobrev",
    poster: [
      LathundEntry(
        emoji: "📷",
        fraga: "Hur skannar jag ett schema?",
        svar:
            "Fotografera eller välj en bild av schemat. Granska och rätta resultatet innan du importerar det till kalendern.",
        finnsHar: "Mer → Skanna schema",
        endastForaldrar: true,
      ),
      LathundEntry(
        emoji: "🔗",
        fraga: "Hur lägger jag till en annan kalender?",
        svar:
            "Lägg till länken till en kalender som skolan eller föreningen delar och välj vem kalendern gäller.",
        finnsHar: "Mer → Andra kalendrar",
        endastForaldrar: true,
      ),
      LathundEntry(
        emoji: "📨",
        fraga: "Var finns information från veckobrev?",
        svar:
            "Veckobrev och anteckningar samlas i Inkorg. Granska förslag innan de blir aktiviteter eller uppgifter. Uppgifter och förberedelser finns under Uppgifter.",
        finnsHar: "Mer → Inkorg eller Uppgifter",
        endastForaldrar: true,
      ),
      LathundEntry(
        emoji: "💼",
        fraga: "Hur lägger jag in arbetspass?",
        svar: "Välj vem som arbetar, tider och datum i arbetsschemat.",
        finnsHar: "Mer → Arbetsschema",
        endastForaldrar: true,
      ),
    ],
  ),
  LathundKategori(
    emoji: "⚙️",
    titel: "Inställningar och Hem",
    poster: [
      LathundEntry(
        emoji: "🌓",
        fraga: "Hur väljer jag ljust eller mörkt läge?",
        svar:
            "Välj Följ enheten, Ljust eller Mörkt under utseende. Valet gäller den enhet du använder.",
        finnsHar: "Inställningar → Utseende",
        endastForaldrar: false,
      ),
      LathundEntry(
        emoji: "🏠",
        fraga: "Var finns sysslor, timer och mat?",
        svar:
            "Dessa funktioner hör till den separata Hem-appen. Den här appen fokuserar på familjens kalender och planering.",
        finnsHar: "Hem-appen",
        endastForaldrar: false,
      ),
    ],
  ),
];
