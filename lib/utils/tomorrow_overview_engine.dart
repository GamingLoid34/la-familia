import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/note_model.dart';
import '../models/task_model.dart';
import '../models/user_model.dart';
import 'conflict_detector.dart';
import 'date_utils.dart';

/// Regelmotor för förälderns "Inför i morgon".
///
/// Trogen port av Android-appens `TomorrowOverviewEngine.kt`. Den läser bara
/// redan befintlig familjedata; urval och sortering är medvetet frikopplade
/// från widgets och Firestore-strömmar.
///
/// Hjälparna som Android-motorn anropar (återkomst, personmatchning, sysslor,
/// arbetspass, packlista, lektionsförberedelse) finns som privata kopior längst
/// ned i filen. Flutters egna hjälpare i `recurrence.dart`, `person_match.dart`
/// m.fl. skiljer sig i kantfall (t.ex. `cast<String>()` som kastar på
/// icke-strängar, `parseDate` som inte trimmar och som normaliserar ogiltiga
/// datum som 2026-02-30). Här måste utfallet bli exakt som i Android.
///
/// Indata byggs så här ur Firestore:
/// ```dart
/// final events = docs.map((d) => {'id': d.id, ...d.data()}).toList();
/// ```
/// och likadant för `work_shifts` (dagens + morgondagens) och `chores`.
/// Konflikterna kommer från `detectPickupConflicts` för morgondagen.
enum TomorrowOverviewKind {
  conflict,

  /// Regel 2: öppen uppgift som är försenad eller förfaller idag eller i morgon.
  urgentTask,
  checklist,

  /// Regel 3: förberedelse till en viss förekomst av en aktivitet — antingen
  /// lektionens egen förberedelse (`lessonPrep`) eller en uppgift med
  /// `eventId` + `occurrenceDate` = i morgon.
  prepTask,

  /// Regel 4: en anteckning väntar på granskning eller misslyckades.
  noteReview,
  event,
  school,
  workShift,
  chore,

  /// Regel 9: uppgift som nått sitt visningsdatum men inte är brådskande.
  upcomingTask,

  /// Regel 10: bekräftad information vars giltighet täcker morgondagen.
  noteInfo,
}

/// En `planner_events`-post som motorn läser. Motsvarar Androids
/// `PlannerEventModel`, men bara fälten motorn behöver. [raw] är hela
/// dokumentet, eftersom hjälparna arbetar på kartan.
class TomorrowOverviewEvent {
  final String id;
  final String title;
  final String piktogram;
  final String time;
  final bool isRecurring;
  final Map<dynamic, dynamic>? recurrence;
  final Map<String, dynamic> raw;

  const TomorrowOverviewEvent({
    required this.id,
    this.title = '',
    this.piktogram = '📅',
    this.time = '',
    this.isRecurring = false,
    this.recurrence,
    this.raw = const {},
  });

  /// [data] är dokumentets innehåll. Id:t tas från [id] eller, om det
  /// saknas, från kartans `id`-nyckel.
  factory TomorrowOverviewEvent.fromMap(Map<String, dynamic> data,
      {String? id}) {
    final rec = data['recurrence'];
    return TomorrowOverviewEvent(
      id: id ?? _str(data['id']) ?? '',
      title: _str(data['title']) ?? '',
      piktogram: _str(data['piktogram']) ?? '📅',
      time: _str(data['time']) ?? '',
      isRecurring: data['isRecurring'] is bool ? data['isRecurring'] : false,
      recurrence: rec is Map ? rec : null,
      raw: data,
    );
  }
}

/// En syssla (`chores`). Motsvarar Androids `ChoreModel`.
class TomorrowOverviewChore {
  final String id;
  final String chore;
  final String piktogram;
  final String who;
  final String whoUid;
  final String? dueDate;
  final Map<String, dynamic> raw;

  const TomorrowOverviewChore({
    required this.id,
    this.chore = '',
    this.piktogram = '🧹',
    this.who = '',
    this.whoUid = '',
    this.dueDate,
    this.raw = const {},
  });

  factory TomorrowOverviewChore.fromMap(Map<String, dynamic> data,
      {String? id}) {
    final c = _str(data['chore']);
    return TomorrowOverviewChore(
      id: id ?? _str(data['id']) ?? '',
      chore: (c != null && !_isBlank(c)) ? c : (_str(data['title']) ?? ''),
      piktogram: _str(data['piktogram']) ?? '🧹',
      who: _str(data['who']) ?? '',
      whoUid: _str(data['whoUid']) ?? '',
      dueDate: _str(data['dueDate']),
      raw: data,
    );
  }

  /// Rubriken: `chore`, annars `title`.
  String get displayTitle =>
      _isBlank(chore) ? (_str(raw['title']) ?? '') : chore;

  bool get _hasNoAssignee {
    final rot = raw['rotationUids'];
    return _isBlank(whoUid) && _isBlank(who) && (rot is! List || rot.isEmpty);
  }
}

/// Ett arbetspass (`work_shifts`). Motsvarar Androids `WorkShiftModel`.
class TomorrowOverviewShift {
  final String id;
  final String date;
  final String who;
  final String whoUid;
  final String startTime;
  final String endTime;
  final Map<String, dynamic> raw;

  const TomorrowOverviewShift({
    required this.id,
    this.date = '',
    this.who = '',
    this.whoUid = '',
    this.startTime = '',
    this.endTime = '',
    this.raw = const {},
  });

  factory TomorrowOverviewShift.fromMap(Map<String, dynamic> data,
      {String? id}) =>
      TomorrowOverviewShift(
        id: id ?? _str(data['id']) ?? '',
        date: _str(data['date']) ?? '',
        who: _str(data['who']) ?? '',
        whoUid: _str(data['whoUid']) ?? '',
        startTime: _str(data['startTime'] ?? data['start']) ?? '',
        endTime: _str(data['endTime'] ?? data['end']) ?? '',
        raw: data,
      );
}

/// En rad i "Inför i morgon".
class TomorrowOverviewItem {
  final TomorrowOverviewKind kind;
  final String title;

  /// Varför raden visas. Dagen står alltid i texten ("I morgon · 17:00",
  /// "Skulle varit klar idag", "Gäller 23 sep–1 okt" …).
  final String reason;
  final String piktogram;

  /// Dagen raden gäller, så att gränssnittet kan skriva datum/veckodag.
  ///
  /// Morgondagen för aktiviteter, konflikter, packlistor, förberedelser,
  /// arbetspass, sysslor och information. För uppgifter deadline-dagen
  /// (försenade ligger alltså före idag); en förberedelseuppgift utan deadline
  /// får förekomstens dag. `null` för uppgifter utan deadline och för
  /// anteckningar som väntar på granskning — de gäller ingen viss dag.
  final DateTime? date;

  /// Händelsen raden hör till (aktivitet, packlista, lektionsförberedelse,
  /// konflikt med matchad aktivitet).
  final TomorrowOverviewEvent? event;

  /// Förekomstens datumnyckel (`YYYY-MM-DD`) när raden pekar på en händelse
  /// eller en förberedelseuppgift. Behövs för återkommande serier.
  final String? occurrenceDate;

  /// Radens plats i händelsens `checklist` (index i dokumentets lista).
  final int? checklistIndex;
  final TomorrowOverviewChore? chore;

  /// Arbetspasset. Finns inte i Android-raden, men skadar inte och låter
  /// gränssnittet visa passets datum.
  final TomorrowOverviewShift? shift;
  final UserModel? member;
  final TaskModel? task;
  final NoteModel? note;
  final String sortKey;

  const TomorrowOverviewItem({
    required this.kind,
    required this.title,
    required this.reason,
    required this.piktogram,
    this.date,
    this.event,
    this.occurrenceDate,
    this.checklistIndex,
    this.chore,
    this.shift,
    this.member,
    this.task,
    this.note,
    this.sortKey = '99:99',
  });

  /// Händelsens dokument-id, om raden pekar på en händelse.
  String? get eventId => event?.id;

  /// Som Androids `TomorrowOverviewPreview`: allt utom arbetspass går att
  /// trycka på; anteckningsrader alltid, övriga när de har något att öppna.
  bool get isClickable {
    if (kind == TomorrowOverviewKind.workShift) return false;
    if (kind == TomorrowOverviewKind.noteInfo ||
        kind == TomorrowOverviewKind.noteReview) {
      return true;
    }
    return task != null || event != null || chore != null || member != null;
  }
}

class TomorrowOverviewEngine {
  TomorrowOverviewEngine._();

  /// Bygger "Inför i morgon" för dagen efter [today].
  ///
  /// - [events]: `planner_events` för i morgon plus alla återkommande, som
  ///   kartor med `id`. Importerade skolblock ska med — motorn döljer vanliga
  ///   lektioner själv.
  /// - [shifts]: dagens och morgondagens `work_shifts` (dagens behövs för
  ///   nattpass som pågår över midnatt).
  /// - [chores]: familjens alla sysslor.
  /// - [conflicts]: hämtningskonflikter för i morgon.
  /// - [notes]: anteckningar den inloggade får läsa. Andras privata får aldrig
  ///   ingå.
  /// - [currentUid]: den inloggade. `null` betyder att filtret nedan inte
  ///   gör något.
  /// - [baraMinaUppgifter]: visa bara uppgifter som är mina eller
  ///   otilldelade. Gäller **bara uppgifter** — aktiviteter, sysslor,
  ///   konflikter och anteckningar rör familjens gemensamma dag och kan inte
  ///   filtreras utan att något viktigt riskerar att försvinna tyst.
  ///
  /// Middagsraden ("Välj middag" / "Middag i morgon") finns inte: den togs
  /// bort i Android 2026-09-23 eftersom den inte användes.
  static List<TomorrowOverviewItem> build({
    required DateTime today,
    required List<UserModel> members,
    List<Map<String, dynamic>> events = const [],
    List<Map<String, dynamic>> shifts = const [],
    List<Map<String, dynamic>> chores = const [],
    List<ScheduleConflict> conflicts = const [],
    List<TaskModel> tasks = const [],
    List<NoteModel> notes = const [],
    String? currentUid,
    bool baraMinaUppgifter = false,
  }) {
    final todayDay = DateTime(today.year, today.month, today.day);
    final tomorrow = DateTime(today.year, today.month, today.day + 1);
    final todayKey = dateKey(todayDay);
    final tomorrowKey = dateKey(tomorrow);

    // Samma dokument kan komma två gånger (morgondagens fråga och de
    // återkommandes). Första förekomsten per id vinner, som distinctBy.
    final seenEvents = <String>{};
    final visibleEvents = <TomorrowOverviewEvent>[];
    for (final m in events) {
      final e = TomorrowOverviewEvent.fromMap(m);
      if (!_eventOccursOnDay(e.raw, tomorrow)) continue;
      if (seenEvents.add(e.id)) visibleEvents.add(e);
    }

    final items = <TomorrowOverviewItem>[];

    // Planen: "Samma uppgift visas en gång även om flera regler träffar." En
    // aktivitet som redan förklaras av en konfliktrad får därför ingen egen
    // rad längre ned — annars stod "Fotboll 17:00" både som konflikt och som
    // vanlig aktivitet.
    final conflictEventIds = <String>{};

    for (final conflict in conflicts) {
      if (!_sameDay(conflict.day, tomorrow)) continue;
      final hm = '${_two(conflict.start.hour)}:${_two(conflict.start.minute)}';
      TomorrowOverviewEvent? match;
      final title = conflict.eventTitle;
      if (title != null) {
        for (final event in visibleEvents) {
          final child = conflict.child;
          if (event.title == title &&
              event.time == hm &&
              (child == null ||
                  _eventIncludesPerson(event.raw, child.uid, child.name))) {
            match = event;
            break;
          }
        }
      }
      if (match != null) conflictEventIds.add(match.id);
      items.add(TomorrowOverviewItem(
        kind: TomorrowOverviewKind.conflict,
        title: conflict.pickupLabel ?? 'Kontrollera lämning eller hämtning',
        reason: 'Kontrollera vem som lämnar eller hämtar',
        piktogram: '🚗',
        date: tomorrow,
        event: match,
        occurrenceDate: match != null ? tomorrowKey : null,
        member: conflict.child,
        sortKey: hm,
      ));
    }

    // Förberedelse inför en lektion. Till skillnad från packlistan nedan
    // fungerar den även för återkommande serier, eftersom avbockningen är per
    // datum (lessonPrep.doneDates) och inte per rad.
    //
    // Detta är enda vägen för ett vanligt skolblock in i överblicken: annars
    // döljs de. Har användaren uttryckligen bett om en förberedelse är det
    // däremot något att göra kvällen före.
    for (final event in visibleEvents) {
      if (!TomorrowOverviewLessonPrep.showsForLesson(event.raw, tomorrow)) {
        continue;
      }
      final text = TomorrowOverviewLessonPrep.textOf(event.raw);
      if (text == null) continue;
      final people = _peopleLabel(event, members);
      final tid = event.time.trim().isNotEmpty ? ' kl. ${event.time}' : '';
      UserModel? member;
      for (final m in members) {
        if (_eventIncludesPerson(event.raw, m.uid, m.name)) {
          member = m;
          break;
        }
      }
      items.add(TomorrowOverviewItem(
        kind: TomorrowOverviewKind.prepTask,
        title: _isBlank(people) ? text : '$text · $people',
        reason: '${_ifBlank(event.title, 'Lektionen')} i morgon$tid',
        piktogram: '🎒',
        date: tomorrow,
        event: event,
        occurrenceDate: tomorrowKey,
        member: member,
        // Lektionens tid, så förberedelserna hamnar i dagens ordning.
        sortKey: _sortTime(event.time),
      ));
    }

    // Packlistan visas även för en aktivitet som redan har en konfliktrad; det
    // är två olika saker att göra (packa respektive lösa hämtningen). Bara
    // engångsaktiviteter: packlistans bockar gäller hela dokumentet.
    for (final event in visibleEvents) {
      if (event.isRecurring || event.recurrence != null) continue;
      final rows = event.raw['checklist'];
      if (rows is! List) continue;
      for (var index = 0; index < rows.length; index++) {
        final row = rows[index];
        final text = _checklistTextOf(row);
        if (text == null || _checklistIsDone(row)) continue;
        items.add(TomorrowOverviewItem(
          kind: TomorrowOverviewKind.checklist,
          title: text,
          reason: 'Inför ${_ifBlank(event.title, 'aktiviteten')} i morgon',
          piktogram: '☐',
          date: tomorrow,
          event: event,
          occurrenceDate: tomorrowKey,
          checklistIndex: index,
          // Aktivitetens tid först, sedan radens plats i listan, så att
          // packlistan behåller den ordning föräldern lagt in raderna i.
          sortKey: '${_sortTime(event.time)}#${index.toString().padLeft(3, '0')}',
        ));
      }
    }

    // Vanliga lektioner hör till kalendern. Särskilda skolhändelser (prov,
    // läxa, utflykt …) behåller sin titel och person, även när de importerats
    // som schema.
    final shownEvents = visibleEvents
        .where((e) => !_isSchoolBlock(e) || _isSchoolHighlight(e))
        .where((e) => !conflictEventIds.contains(e.id))
        .toList();
    _stableSort(shownEvents,
        (a, b) => _sortTime(a.time).compareTo(_sortTime(b.time)));
    for (final event in shownEvents) {
      final people = _peopleLabel(event, members);
      // "I morgon" står först och alltid. Utan det blev raden bara
      // "17:00 · Céline", och det gick inte att avgöra om den gällde idag
      // eller i morgon — andra rader i samma lista säger "idag".
      final reason = [
        'I morgon',
        if (!_isBlank(event.time)) event.time,
        if (!_isBlank(people)) people,
      ].join(' · ');
      items.add(TomorrowOverviewItem(
        kind: TomorrowOverviewKind.event,
        title: _ifBlank(event.title, 'Aktivitet'),
        reason: reason,
        piktogram: _ifBlank(event.piktogram, '📅'),
        date: tomorrow,
        event: event,
        occurrenceDate: tomorrowKey,
        sortKey: _sortTime(event.time),
      ));
    }

    // Arbetspass för vuxna, även nattpass från idag som pågår över midnatt.
    final seenShifts = <String>{};
    final yesterday = DateTime(tomorrow.year, tomorrow.month, tomorrow.day - 1);
    for (final m in shifts) {
      final shift = TomorrowOverviewShift.fromMap(m);
      if (!seenShifts.add(shift.id)) continue;
      final byParent = members.any(
          (u) => u.isParent && _assignedToPerson(shift.raw, u.uid, u.name));
      if (!byParent || !_shiftTouchesDay(shift, tomorrow)) continue;
      final shiftDay = _parseDate(shift.date);
      final overnight = shiftDay != null && _sameDay(shiftDay, yesterday);
      items.add(TomorrowOverviewItem(
        kind: TomorrowOverviewKind.workShift,
        title: '${_ifBlank(shift.who, 'Vuxen')} arbetar',
        reason: overnight
            ? 'pågår till ${shift.endTime}'
            : '${shift.startTime}–${shift.endTime}',
        piktogram: '💼',
        date: tomorrow,
        shift: shift,
        // Ett pass som redan pågår vid midnatt sorteras först, övriga på
        // starttid.
        sortKey: overnight ? '00:00' : _sortTime(shift.startTime),
      ));
    }

    for (final m in chores) {
      final chore = TomorrowOverviewChore.fromMap(m);
      final raw = chore.raw;
      if (_choreDoneOnDay(raw, tomorrow)) continue;
      final recurring = _choreIsRecurring(raw);
      final occurs = _choreOccursOnDay(raw, tomorrow);
      final due = _parseDate(chore.dueDate);
      final dueTomorrow =
          due != null && _sameDay(due, tomorrow) && (!recurring || occurs);
      final unassignedRecurring =
          recurring && occurs && chore._hasNoAssignee;
      if (!dueTomorrow && !unassignedRecurring) continue;
      final recurringUnassigned = recurring && chore._hasNoAssignee;
      items.add(TomorrowOverviewItem(
        kind: TomorrowOverviewKind.chore,
        title: chore.displayTitle,
        reason: recurringUnassigned
            ? 'Saknar ansvarig i morgon'
            : 'Förfaller i morgon',
        piktogram: chore.piktogram,
        date: tomorrow,
        chore: chore,
      ));
    }

    // Regel 2, 3 och 9. En uppgift kan träffa flera av dem men ska ändå bara
    // visas en gång, så varje uppgift hamnar i exakt en hög.
    //
    // Listan heter "Inför i morgon", så den slutar vid i morgon. Ett bredare
    // fönster (+2 dagar) underkändes i Android 2026-09-20: en uppgift som
    // förfaller om tre dagar hör hemma i Uppgifter, inte i kvällens
    // förberedelse.
    final openTasks = tasks.where((task) {
      if (task.isDone) return false;
      if (!baraMinaUppgifter || currentUid == null) return true;
      // Otilldelade visas alltid: annars kan en uppgift ingen tagit ansvar för
      // försvinna helt, och det vore värre än att se en för mycket.
      return task.assigneeUid == null || task.assigneeUid == currentUid;
    });

    for (final task in openTasks) {
      final dueDate = task.dueDate;
      final urgent = task.isOverdue(todayKey) ||
          dueDate == todayKey ||
          dueDate == tomorrowKey;
      // En förberedelse hör till morgondagens förekomst av en aktivitet.
      final preparation =
          task.eventId != null && task.occurrenceDate == tomorrowKey;
      // Regel 9: har nått sitt visningsdatum (utan showFromDate syns den
      // direkt) — men bara inom fönstret. Uppgifter UTAN deadline visas så
      // fort showFromDate passerats; de har inget datum att ligga utanför
      // fönstret med, och att dölja dem vore att tappa dem helt.
      final inomFonster = dueDate == null || dueDate.compareTo(tomorrowKey) <= 0;
      final showFrom = task.showFromDate;
      final visible =
          (showFrom == null || showFrom.compareTo(todayKey) <= 0) && inomFonster;

      final TomorrowOverviewKind kind;
      if (urgent) {
        kind = TomorrowOverviewKind.urgentTask;
      } else if (preparation) {
        kind = TomorrowOverviewKind.prepTask;
      } else if (visible) {
        kind = TomorrowOverviewKind.upcomingTask;
      } else {
        continue;
      }
      UserModel? member;
      for (final m in members) {
        if (m.uid == task.assigneeUid) {
          member = m;
          break;
        }
      }
      final dueTime = task.hasTime ? task.dueTime : null;
      items.add(TomorrowOverviewItem(
        kind: kind,
        title: task.title,
        reason: _taskReason(task, todayKey, tomorrowKey, members),
        piktogram: kind == TomorrowOverviewKind.prepTask ? '🎒' : '📌',
        date: _parseDate(dueDate) ??
            (preparation ? _parseDate(task.occurrenceDate) : null),
        occurrenceDate: preparation ? task.occurrenceDate : null,
        member: member,
        task: task,
        sortKey: dueTime != null ? _sortTime(dueTime) : '99:99',
      ));
    }

    // Regel 4: anteckningar som behöver uppmärksamhet. Granskning och
    // misslyckad tolkning är två olika tillstånd och hålls isär.
    for (final n in notes) {
      if (n.isDeleted) continue;
      final String reason;
      if (n.needsReview) {
        reason = 'Förslag att granska';
      } else if (n.failed) {
        reason = 'Tolkningen gick inte igenom';
      } else {
        continue;
      }
      items.add(TomorrowOverviewItem(
        kind: TomorrowOverviewKind.noteReview,
        title: _ifEmpty(_firstLine(n.text), 'Anteckning'),
        reason: reason,
        piktogram: n.failed ? '⚠️' : '📥',
        note: n,
      ));
    }

    // Regel 10: bekräftad information vars giltighetsfönster täcker
    // morgondagen.
    for (final n in notes) {
      if (n.isDeleted) continue;
      if (n.status != NoteModel.statusConfirmed) continue;
      // Utan fönster är det ingen upplysning som gäller en viss dag.
      if (n.validFrom == null && n.validTo == null) continue;
      if (!n.coversDay(tomorrowKey)) continue;
      // Info-förslagets egen titel, inte brevets första rad: ett veckobrev
      // med flera saker visade annars sin inledning som om det vore beskedet.
      // Brevets rad används bara när förslaget saknar titel.
      final infoTitle = _take80(infoForslag(n)?.title.trim() ?? '');
      items.add(TomorrowOverviewItem(
        kind: TomorrowOverviewKind.noteInfo,
        title: infoTitle.isNotEmpty
            ? infoTitle
            : _ifEmpty(_firstLine(n.text), 'Information'),
        reason: _validityReason(n),
        piktogram: '💬',
        date: tomorrow,
        note: n,
      ));
    }

    _stableSort(items, (a, b) {
      final p = _priorityOf(a.kind).compareTo(_priorityOf(b.kind));
      if (p != 0) return p;
      final s = a.sortKey.compareTo(b.sortKey);
      if (s != 0) return s;
      return a.title.compareTo(b.title);
    });
    return items;
  }

  /// Info-förslaget i en anteckning, om det finns.
  ///
  /// AVVIKELSE från Android: där krävs `action.isConfirmed`, men servern
  /// (`functions/note_confirm.js`) sätter aldrig åtgärdernas status — den
  /// sätter bara anteckningens `status: 'confirmed'`. Åtgärderna står kvar
  /// som `pending`, så Androids villkor träffar i praktiken aldrig och
  /// rubriken blir alltid brevets första rad. Här används därför första
  /// `info`-förslaget oavsett status, med ett undantag: ett uttryckligen
  /// avfärdat förslag (`dismissed`) används inte. Det undantaget ger samma
  /// utfall som Android i det enda fall där Android och "oavsett status"
  /// skulle skilja sig åt med data som faktiskt kan förekomma.
  static NoteAction? infoForslag(NoteModel note) {
    final actions = note.interpretation?.actions ?? const <NoteAction>[];
    for (final a in actions) {
      if (a.type == NoteAction.typeInfo && a.status != 'dismissed') return a;
    }
    return null;
  }

  /// Varför informationen visas just nu, med datum i klartext
  /// ("Gäller 23 sep–1 okt").
  static String _validityReason(NoteModel note) {
    final fran = _kortDatum(note.validFrom);
    final till = _kortDatum(note.validTo);
    if (fran != null && till != null) return 'Gäller $fran–$till';
    if (till != null) return 'Gäller till $till';
    if (fran != null) return 'Gäller från $fran';
    return 'Gäller i morgon';
  }

  static const _kortaManader = [
    'jan', 'feb', 'mar', 'apr', 'maj', 'jun', //
    'jul', 'aug', 'sep', 'okt', 'nov', 'dec',
  ];

  static String? _kortDatum(String? key) {
    final d = _parseDate(key);
    if (d == null) return key;
    return '${d.day} ${_kortaManader[d.month - 1]}';
  }

  /// Planens krav: varje rad förklarar varför den visas.
  static String _taskReason(
    TaskModel task,
    String todayKey,
    String tomorrowKey,
    List<UserModel> members,
  ) {
    final due = task.dueDate;
    final String when;
    if (due == null) {
      when = 'Ingen deadline';
    } else if (due.compareTo(todayKey) < 0) {
      when = 'Skulle varit klar $due';
    } else if (due == todayKey) {
      // Inte "Senast idag": i en lista som heter "Inför i morgon" läses det
      // som en motsägelse. Raden ska säga varför den ligger kvar.
      when = 'Skulle varit klar idag';
    } else if (due == tomorrowKey) {
      when = 'Senast i morgon';
    } else {
      when = 'Senast $due';
    }
    final time = (task.hasTime && task.dueTime != null) ? ' ${task.dueTime}' : '';

    // Vem uppgiften GÄLLER, inte vem som ska göra den. En förälder med tre
    // barn måste kunna se vilket barn läxan gäller.
    final gallerNamn = members
        .where((m) => task.aboutUids.contains(m.uid))
        .map((m) => _firstName(m.name))
        .join(', ');
    final galler = gallerNamn.isNotEmpty ? ' · $gallerNamn' : '';

    // Ansvarig visas bara när den skiljer sig från den uppgiften gäller.
    // Annars blir det "Leo · Leo".
    var ansvarig = '';
    for (final m in members) {
      if (m.uid == task.assigneeUid) {
        if (!task.aboutUids.contains(m.uid)) {
          ansvarig = ' · ${_firstName(m.name)}';
        }
        break;
      }
    }
    return '$when$time$galler$ansvarig';
  }

  static bool _isSchoolBlock(TomorrowOverviewEvent e) {
    final kind = e.raw['planningImportKind'];
    return e.raw['source'] == 'calendar' &&
        (kind is String ? kind : 'schedule') == 'schedule';
  }

  /// Skolhändelser som föräldern behöver veta om, till skillnad från vanliga
  /// lektioner. Sammansättningar fångas ("Matteprov", "Glosförhör"), medan
  /// ordgränserna hindrar falska träffar som "Provisorisk" och
  /// "Improvisation".
  static final _schoolHighlight = RegExp(
    r'(?<!\p{L})(?:\p{L}*prov(?:et)?|\p{L}*läxa(?:n)?|läxor|\p{L}*förhör(?:et)?|redovisning|inlämning|utflykt|studiebesök|friluftsdag|idrottsdag|temadag|utvecklingssamtal)(?!\p{L})',
    caseSensitive: false,
    unicode: true,
  );

  static bool _isSchoolHighlight(TomorrowOverviewEvent e) =>
      _schoolHighlight.hasMatch(e.title);

  static String _peopleLabel(
          TomorrowOverviewEvent event, List<UserModel> members) =>
      members
          .where((m) => _eventIncludesPerson(event.raw, m.uid, m.name))
          .map((m) => _firstName(m.name))
          .join(', ');

  /// Ordningen i planens regeltabell.
  static int _priorityOf(TomorrowOverviewKind kind) {
    switch (kind) {
      case TomorrowOverviewKind.conflict:
        return 1;
      case TomorrowOverviewKind.urgentTask:
        return 2;
      case TomorrowOverviewKind.checklist:
      case TomorrowOverviewKind.prepTask:
        return 3;
      case TomorrowOverviewKind.noteReview:
        return 4;
      case TomorrowOverviewKind.event:
      case TomorrowOverviewKind.school:
        return 5;
      case TomorrowOverviewKind.workShift:
        return 6;
      case TomorrowOverviewKind.chore:
        return 7;
      case TomorrowOverviewKind.upcomingTask:
        return 9;
      case TomorrowOverviewKind.noteInfo:
        return 10;
    }
  }
}

/// Förberedelse inför en lektion (Androids `LessonPrep`).
///
/// Lektionen bär en mall i fältet `lessonPrep: {text, doneDates}`, och
/// tillfällena härleds vid läsning ur seriens egen återkomstregel. En bock
/// gäller därför bara ett tillfälle.
class TomorrowOverviewLessonPrep {
  TomorrowOverviewLessonPrep._();

  /// Fältnamnet på händelsedokumentet.
  static const field = 'lessonPrep';

  /// Förberedelsens text, eller null när ingen är satt. Tom text räknas som
  /// ingen förberedelse.
  static String? textOf(Map<String, dynamic> raw) {
    final prep = raw[field];
    if (prep is! Map) return null;
    final text = prep['text'];
    if (text is! String) return null;
    final t = text.trim();
    return t.isEmpty ? null : t;
  }

  /// Datum där förberedelsen redan är avbockad.
  static List<String> doneDates(Map<String, dynamic> raw) {
    final prep = raw[field];
    if (prep is! Map) return const [];
    return _stringList(prep['doneDates']);
  }

  /// Är förberedelsen avbockad för [lessonDay]?
  static bool isDoneOn(Map<String, dynamic> raw, DateTime lessonDay) =>
      doneDates(raw).contains(dateKey(lessonDay));

  /// Ska en förberedelserad visas kvällen före [lessonDay]?
  static bool showsForLesson(Map<String, dynamic> raw, DateTime lessonDay) =>
      textOf(raw) != null &&
      _eventOccursOnDay(raw, lessonDay) &&
      !isDoneOn(raw, lessonDay);

  /// Stabil nyckel för lektionsserien ett dokument tillhör: import + titel +
  /// personer. Importerade scheman är ett dokument per tillfälle, så
  /// dokument-id duger inte. Utan import räcker dokument-id:t.
  static String seriesKey(Map<String, dynamic> raw, String eventId) {
    final importId = raw['calendarImportId'];
    if (importId is! String || _isBlank(importId)) return eventId;
    final title = (_str(raw['title']) ?? '').trim().toLowerCase();
    final persons = raw['personUids'] is List
        ? ((raw['personUids'] as List)
                .where((e) => e != null)
                .map((e) => e.toString())
                .where((s) => !_isBlank(s))
                .toList()
              ..sort())
            .join(',')
        : '';
    return '$importId|$title|$persons';
  }
}

// ---------------------------------------------------------------------------
// Privata hjälpare, portade exakt från Android.
// ---------------------------------------------------------------------------

String? _str(Object? v) => v is String ? v : null;

/// Kotlins `isBlank()`.
bool _isBlank(String s) => s.trim().isEmpty;

String _ifBlank(String s, String fallback) => _isBlank(s) ? fallback : s;

String _ifEmpty(String s, String fallback) => s.isEmpty ? fallback : s;

String _two(int n) => n.toString().padLeft(2, '0');

String _take80(String s) => s.length > 80 ? s.substring(0, 80) : s;

/// Kotlins `substringBefore(' ')`.
String _firstName(String name) => name.split(' ').first;

/// Kotlins `lineSequence().firstOrNull()?.trim()?.take(80).orEmpty()`: den
/// allra första raden, även om den är tom (skiljer sig från
/// [NoteModel.firstLine], som tar första icke-tomma).
String _firstLine(String text) =>
    _take80(text.split(RegExp(r'\r\n|\n|\r')).first.trim());

/// `HH:MM` för sortering; allt annat hamnar sist.
String _sortTime(String s) {
  final t = s.trim();
  if (!RegExp(r'^\d{1,2}:\d{2}$').hasMatch(t)) return '99:99';
  return t.padLeft(5, '0');
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

List<String> _stringList(Object? v) => v is List
    ? v.where((e) => e != null).map((e) => e.toString()).toList()
    : const [];

/// Stabil sortering, som Kotlins `sortedWith`. Darts `List.sort` är inte
/// stabil.
void _stableSort<T>(List<T> list, int Function(T a, T b) compare) {
  final indexed = [for (var i = 0; i < list.length; i++) (i, list[i])];
  indexed.sort((a, b) {
    final c = compare(a.$2, b.$2);
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  for (var i = 0; i < indexed.length; i++) {
    list[i] = indexed[i].$2;
  }
}

final _intPattern = RegExp(r'^[+-]?\d+$');

/// Androids `DateUtils.parseDate`: trimmar, kräver giltigt datum (inte
/// 2026-02-30) och tål Timestamp/DateTime. Ger en lokal dag utan klockslag.
DateTime? _parseDate(Object? v) {
  if (v == null) return null;
  if (v is Timestamp) {
    final d = v.toDate();
    return DateTime(d.year, d.month, d.day);
  }
  if (v is DateTime) return DateTime(v.year, v.month, v.day);
  if (v is! String) return null;
  final t = v.trim();
  if (t.isEmpty) return null;
  final parts = t.split('-');
  if (parts.length < 3) return null;
  if (!parts.take(3).every(_intPattern.hasMatch)) return null;
  final y = int.parse(parts[0]);
  final m = int.parse(parts[1]);
  final d = int.parse(parts[2]);
  final date = DateTime(y, m, d);
  if (date.year != y || date.month != m || date.day != d) return null;
  return date;
}

/// Heldagar mellan två dagar, oberoende av sommartid.
int _daysBetween(DateTime a, DateTime b) =>
    DateTime.utc(b.year, b.month, b.day)
        .difference(DateTime.utc(a.year, a.month, a.day))
        .inDays;

/// Androids `RecurrenceUtils.recurringOccursOnDay`.
bool _recurringOccursOnDay(Map<dynamic, dynamic> d, DateTime day) {
  final rec = d['recurrence'];
  if (rec is! Map) return false;
  final start = _parseDate(rec['startDate'] ?? d['date'] ?? d['dueDate']);
  if (start == null) return false;
  if (_daysBetween(start, day) < 0) return false;

  final endRaw = rec['endDate'];
  if (endRaw is String && !_isBlank(endRaw)) {
    final end = _parseDate(endRaw);
    if (end != null && _daysBetween(end, day) > 0) return false;
  }

  if (_stringList(rec['exceptions']).contains(dateKey(day))) return false;

  final type = _str(rec['type']) ?? '';
  switch (type) {
    case 'daily':
      return true;
    case 'weekly':
      return day.weekday == start.weekday;
    case 'biweekly':
      return day.weekday == start.weekday && _daysBetween(start, day) % 14 == 0;
    case 'monthly':
      return day.day == start.day;
    default:
      return false;
  }
}

/// Androids `RecurrenceUtils.eventOccursOnDay`.
bool _eventOccursOnDay(Map<dynamic, dynamic> d, DateTime day) {
  if (d['recurrence'] != null) return _recurringOccursOnDay(d, day);
  final date = _parseDate(d['date']);
  return date != null && _sameDay(date, day);
}

/// Androids `PersonMatchUtils.eventIncludesPerson`: uid-fältet vinner.
bool _eventIncludesPerson(Map<String, dynamic> d, String uid, String name) {
  final uids = _stringList(d['personUids']);
  if (uids.isNotEmpty) return uids.contains(uid);
  return _stringList(d['persons']).contains(name);
}

/// Androids `PersonMatchUtils.assignedToPerson`: `whoUid` vinner över `who`.
bool _assignedToPerson(Map<String, dynamic> d, String uid, String name) {
  final whoUid = _str(d['whoUid']) ?? '';
  if (whoUid.isNotEmpty) return whoUid == uid;
  return (_str(d['who']) ?? '') == name;
}

bool _choreIsRecurring(Map<String, dynamic> d) =>
    d['isRecurring'] == true && d['recurrence'] is Map;

bool _choreOccursOnDay(Map<String, dynamic> d, DateTime day) {
  if (_choreIsRecurring(d)) return _recurringOccursOnDay(d, day);
  final raw = d['dueDate'];
  if (raw == null) return true;
  if (raw is String && _isBlank(raw)) return true;
  final parsed = _parseDate(raw);
  if (parsed == null) return true;
  return _sameDay(parsed, day);
}

bool _choreDoneOnDay(Map<String, dynamic> d, DateTime day) {
  if (_choreIsRecurring(d)) {
    return _stringList(d['doneDates']).contains(dateKey(day));
  }
  return d['isDone'] == true;
}

/// Packlistans radtext oavsett format: karta med `item`, karta med `text`
/// eller ren sträng (Androids `ChecklistUpdates.textOf`).
String? _checklistTextOf(Object? row) {
  if (row is Map) {
    final v = row['item'] ?? row['text'];
    if (v == null) return null;
    final t = v.toString().trim();
    return t.isEmpty ? null : t;
  }
  if (row is String) {
    final t = row.trim();
    return t.isEmpty ? null : t;
  }
  return null;
}

/// En ren sträng är alltid obockad.
bool _checklistIsDone(Object? row) => row is Map && row['isDone'] == true;

/// Androids `parseShiftTime`: `H:MM` med giltigt klockslag, annars null.
/// Ger minuter sedan midnatt.
int? _parseShiftMinutes(String time) {
  final t = time.trim();
  if (t.isEmpty) return null;
  final parts = t.split(':');
  if (parts.length < 2) return null;
  if (!_intPattern.hasMatch(parts[0]) || !_intPattern.hasMatch(parts[1])) {
    return null;
  }
  final h = int.parse(parts[0]);
  final m = int.parse(parts[1]);
  if (h < 0 || h > 23 || m < 0 || m > 59) return null;
  return h * 60 + m;
}

/// Androids `ScheduleTimeUtils.shiftTouchesDay`: passets intervall (slutet
/// rullas till nästa dag om det inte är efter starten) överlappar [day].
/// Räknas i UTC så att sommartid inte flyttar gränserna.
bool _shiftTouchesDay(TomorrowOverviewShift shift, DateTime day) {
  final d = _parseDate(shift.date);
  if (d == null) return false;
  final s = _parseShiftMinutes(shift.startTime);
  final e = _parseShiftMinutes(shift.endTime);
  if (s == null || e == null) return false;
  final base = DateTime.utc(d.year, d.month, d.day);
  final start = base.add(Duration(minutes: s));
  var end = base.add(Duration(minutes: e));
  if (!end.isAfter(start)) end = end.add(const Duration(days: 1));
  final dayStart = DateTime.utc(day.year, day.month, day.day);
  final dayEnd = dayStart.add(const Duration(days: 1));
  return start.isBefore(dayEnd) && end.isAfter(dayStart);
}
