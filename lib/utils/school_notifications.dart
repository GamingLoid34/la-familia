/// Skiljer importerade schemablock från riktiga aktiviteter, och avgör vilka poster som ska
/// ge påminnelser. Port av Androids `ScheduleBlocks.kt`.
///
/// Ett schemablock är en lektion, ett rehabpass eller ett arbetspass som kommit in via
/// schemaimport eller kalenderprenumeration. Skillnaden mot en aktivitet är vad den kräver
/// av familjen: när barnen är i skolan är de där och gör det de ska, medan en träning på
/// kvällen kan behöva skjuts, packning och en påminnelse.
///
/// Alla funktioner arbetar mot dokumentets råa map, eftersom notisschemaläggaren aldrig har
/// en modell.
library;

/// Är posten ett importerat schemablock?
///
/// Två villkor: den kom från en import (`source == "calendar"`) och är märkt som schema.
/// `planningImportKind` saknas i äldre dokument och tolkas då som `"schedule"`, eftersom det
/// var det enda importen skapade innan fältet fanns.
///
/// En importerad post märkt `"activity"` är alltså **inte** ett schemablock — det är en
/// riktig aktivitet som råkar komma från en kalender, till exempel en träning i en
/// prenumererad föreningskalender.
bool isScheduleBlock(Map<String, dynamic> raw) {
  if (raw['source'] != 'calendar') return false;
  final kindRaw = raw['planningImportKind'];
  final kind = kindRaw is String ? kindRaw.trim() : '';
  return kind.isEmpty || kind == 'schedule';
}

/// Är blocket ett **skolblock**, till skillnad från rehab eller jobb?
///
/// Ordningen är: uttrycklig etikett (`schemaLabel`), sedan piktogram, sedan kalendernamn
/// (med titeln som reserv).
///
/// Fallbacken är "Skola", vilket är den befintliga kodens antagande. Det betyder att ett
/// omärkt schemablock behandlas som skola och tystnar — se [shouldRemindForEvent].
bool isSchoolBlock(Map<String, dynamic> raw) {
  if (!isScheduleBlock(raw)) return false;

  final labelRaw = raw['schemaLabel'];
  final label = labelRaw is String ? labelRaw.trim() : '';
  if (label.isNotEmpty) return label.toLowerCase() == 'skola';

  final piktogramRaw = raw['piktogram'];
  switch (piktogramRaw is String ? piktogramRaw.trim() : null) {
    case '🏥':
      return false;
    case '💼':
      return false;
    case '🏫':
      return true;
  }

  final namnRaw = raw['calendarName'] ?? raw['title'];
  final calName = namnRaw is String ? namnRaw.toLowerCase() : '';
  if (calName.contains('rehab') || calName.contains('klinik')) return false;

  return true;
}

/// Ska posten ge påminnelser?
///
/// **Skolblock** ger inga. Beställaren 2026-09-21: sex lektioner per dag och barn gav tre
/// notiser var — "börjar snart", "dags att byta" och "nu börjar" — alltså ett trettiotal
/// dagligen för något som inte kräver någon åtgärd hemma.
///
/// **Rehab och jobb behåller sina notiser.** De ser likadana ut i datamodellen men betyder
/// något annat: ett rehabpass är något man ska ta sig till.
///
/// Undantaget är en lektion med egen packlista eller förberedelse (`lessonPrep`): då har
/// någon uttryckligen sagt att den behöver förberedas, och då är en påminnelse befogad.
bool shouldRemindForEvent(Map<String, dynamic> raw) {
  if (!isSchoolBlock(raw)) return true;
  if (_lessonPrepText(raw) != null) return true;
  final checklist = raw['checklist'];
  if (checklist is! List) return false;
  return checklist.any((rad) => _checklistText(rad) != null);
}

/// Omvändningen av [shouldRemindForEvent], för anropare som frågar "ska vi hoppa över?".
///
/// Vid true ska redan schemalagda påminnelser för dokumentet (och dess instanser) tas bort:
/// ett skolblock kan ha fått notiser innan filtret fanns, och en förberedelse som tas bort
/// ska tysta blocket igen.
bool shouldSkipLessonNotification(Map<String, dynamic> raw) =>
    !shouldRemindForEvent(raw);

/// Förberedelsens text (`lessonPrep.text`), eller null när ingen är satt. Tom text räknas
/// som ingen förberedelse. Samma regel som Androids `LessonPrep.textOf`.
String? _lessonPrepText(Map<String, dynamic> raw) {
  final prep = raw['lessonPrep'];
  if (prep is! Map) return null;
  final text = prep['text'];
  if (text is! String) return null;
  final t = text.trim();
  return t.isEmpty ? null : t;
}

/// En packlistrads text, eller null när raden är tom. Samma regel som Androids
/// `ChecklistUpdates.textOf`: en map läses via `item` (reserv `text`), en sträng direkt.
String? _checklistText(Object? rad) {
  String? t;
  if (rad is Map) {
    t = (rad['item'] ?? rad['text'])?.toString().trim();
  } else if (rad is String) {
    t = rad.trim();
  }
  return (t == null || t.isEmpty) ? null : t;
}
