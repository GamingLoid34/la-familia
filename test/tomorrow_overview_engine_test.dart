import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/models/note_model.dart';
import 'package:la_familia/models/task_model.dart';
import 'package:la_familia/models/user_model.dart';
import 'package:la_familia/utils/conflict_detector.dart';
import 'package:la_familia/utils/tomorrow_overview_engine.dart';

// Port av Android-appens TomorrowOverview*Test.kt. Varje grupp motsvarar en
// Kotlin-testklass; bara syntaxen är anpassad. Sist kommer tester för Flutters
// avvikelse i info-rubriken.

typedef Kind = TomorrowOverviewKind;

UserModel user(String uid, String name, String role) => UserModel(
      uid: uid,
      name: name,
      email: '',
      color: 'ff2196f3',
      role: role,
      viewMode: role == 'admin' ? 'parent' : role,
      energy: 3,
    );

DateTime dayBefore(DateTime d) => DateTime(d.year, d.month, d.day - 1);

String key(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Motsvarar Androids `PlannerEventModel.fromMap(id, standard + overrides)`.
Map<String, dynamic> eventMap(String id, [Map<String, dynamic> overrides = const {}]) => {
      'id': id,
      'date': '2026-09-18',
      'title': 'Test',
      'time': '09:00',
      ...overrides,
    };

TaskModel task({
  String id = 't',
  String title = 'Boka tid',
  String? dueDate,
  String? dueTime,
  bool hasTime = false,
  String? showFromDate,
  String? assigneeUid,
  List<String> aboutUids = const [],
  String status = TaskModel.statusOpen,
  String? eventId,
  String? occurrenceDate,
}) =>
    TaskModel(
      id: id,
      familyId: 'f',
      title: title,
      dueDate: dueDate,
      dueTime: dueTime,
      hasTime: hasTime,
      showFromDate: showFromDate,
      assigneeUid: assigneeUid,
      aboutUids: aboutUids,
      status: status,
      eventId: eventId,
      occurrenceDate: occurrenceDate,
      createdByUid: 'adult',
    );

void main() {
  // -------------------------------------------------------------------------
  group('TomorrowOverviewEngineTest', () {
    final tomorrow = DateTime(2026, 9, 18);
    final child = user('child', 'Namn som inte ska matcha', 'child');
    final adult = user('adult', 'Alex', 'parent');

    List<TomorrowOverviewItem> build({
      List<Map<String, dynamic>> events = const [],
      List<Map<String, dynamic>> shifts = const [],
      List<TaskModel> tasks = const [],
    }) =>
        TomorrowOverviewEngine.build(
          today: dayBefore(tomorrow),
          members: [adult, child],
          events: events,
          shifts: shifts,
          tasks: tasks,
        );

    test('uid wins over name when showing event person', () {
      final event = eventMap('e', {
        'personUids': ['child'],
        'persons': ['Alex'],
      });
      final items = build(events: [event]);
      // Raden inleds med "I morgon", så personen är sista fältet.
      expect(
          items.singleWhere((it) => it.kind == Kind.event).reason.split(' · ').last,
          'Namn');
    });

    test('ordinary school blocks do not create reminders', () {
      final first = eventMap('one', {
        'source': 'calendar',
        'planningImportKind': 'schedule',
        'personUids': ['child'],
        'time': '08:00',
        'endTime': '10:00',
      });
      final second = eventMap('two', {
        'source': 'calendar',
        'planningImportKind': 'schedule',
        'personUids': ['child'],
        'time': '11:00',
        'endTime': '14:00',
      });
      expect(build(events: [first, second]), isEmpty);
    });

    test('imported exams retain title and child among ordinary lessons', () {
      final rows = build(
        events: ['Matematik', 'Matteprov', 'Engelskaläxa', 'Utflykt']
            .map((title) => eventMap(title, {
                  'title': title,
                  'source': 'calendar',
                  'personUids': ['child'],
                }))
            .toList(),
      ).where((it) => it.kind == Kind.event).toList();
      expect(rows.map((it) => it.title).toSet(),
          {'Matteprov', 'Engelskaläxa', 'Utflykt'});
      expect(rows.every((it) => it.reason.contains('Namn')), isTrue);
    });

    test('sammansatta ord med forhor och prov fangas', () {
      // Sammansättningar är vanligare än grundorden i verkliga scheman.
      final rows = build(
        events: ['Glosförhör', 'Matteprov', 'Provet i NO']
            .map((title) => eventMap(title, {
                  'title': title,
                  'source': 'calendar',
                  'personUids': ['child'],
                }))
            .toList(),
      ).where((it) => it.kind == Kind.event).toList();
      expect(rows.length, 3);
    });

    test('ord som bara innehaller prov matchar inte', () {
      // Utan ordgränserna skulle "Provisorisk" och "Improvisation" matcha.
      final rows = build(
        events: ['Provisorisk lokal', 'Improvisation', 'Matematik']
            .map((title) => eventMap(title, {
                  'title': title,
                  'source': 'calendar',
                  'personUids': ['child'],
                }))
            .toList(),
      );
      expect(rows, isEmpty, reason: 'Fick: ${rows.map((it) => it.title)}');
    });

    test('uppgift langt fram visas inte i infor imorgon', () {
      final langtFram =
          task(id: 'sen', title: 'Engelska läxa', dueDate: '2026-09-28');
      final items = build(tasks: [langtFram]);
      expect(items.where((it) => it.task != null), isEmpty);
    });

    test('uppgift som forfaller imorgon visas', () {
      final imorgon =
          task(id: 'imorgon', title: 'Ta med gympapåse', dueDate: '2026-09-18');
      expect(build(tasks: [imorgon]).where((it) => it.task != null).length, 1);
    });

    test('uppgift dagen efter imorgon visas INTE', () {
      // Ett fönster på +2 dagar var för brett.
      final overmorgon =
          task(id: 'sen', title: 'Lämna tillbaka bok', dueDate: '2026-09-19');
      expect(build(tasks: [overmorgon]).where((it) => it.task != null), isEmpty);
    });

    test('uppgift utan deadline visas fortfarande', () {
      final utanDatum = task(id: 'fri', title: 'Ringa tandläkaren');
      expect(build(tasks: [utanDatum]).where((it) => it.task != null).length, 1);
    });

    test('en helt tom kvall ger inga rader alls', () {
      expect(build(), isEmpty);
    });

    test('ingen middagsrad nar kvallen har annat innehall', () {
      final items = build(events: [eventMap('e')]);
      expect(
          items.any((it) => it.title == 'Välj middag' || it.piktogram == '🍽️'),
          isFalse);
    });

    test('recurring exception is not shown', () {
      final recurring = eventMap('rec', {
        'isRecurring': true,
        'date': '2026-09-11',
        'recurrence': {
          'type': 'weekly',
          'startDate': '2026-09-11',
          'exceptions': ['2026-09-18'],
        },
      });
      expect(build(events: [recurring]).any((it) => it.event?.id == 'rec'),
          isFalse);
    });

    test('night shift from previous day is included', () {
      final shift = {
        'id': 'night',
        'date': '2026-09-17',
        'who': 'Fel namn',
        'whoUid': 'adult',
        'startTime': '22:00',
        'endTime': '06:00',
      };
      expect(build(shifts: [shift]).any((it) => it.kind == Kind.workShift),
          isTrue);
    });

    test('shift ending at midnight does not continue into following day', () {
      final shift = {
        'id': 'midnight',
        'date': '2026-09-16',
        'who': 'Alex',
        'whoUid': 'adult',
        'startTime': '16:00',
        'endTime': '00:00',
      };
      expect(build(shifts: [shift]).any((it) => it.kind == Kind.workShift),
          isFalse);
    });

    test('checklist belongs only to one time event', () {
      final recurring = eventMap('rec', {
        'isRecurring': true,
        'recurrence': {'type': 'weekly', 'startDate': '2026-09-18'},
        'checklist': [
          {'item': 'Delad', 'isDone': false},
        ],
      });
      final oneOff = eventMap('one', {
        'checklist': [
          {'item': 'Packa', 'isDone': false},
        ],
      });
      final checklist = build(events: [recurring, oneOff])
          .where((it) => it.kind == Kind.checklist);
      expect(checklist.map((it) => it.title).toList(), ['Packa']);
    });

    test('due chore is shown even when assigned', () {
      final chore = {
        'id': 'c',
        'chore': 'Betala',
        'dueDate': '2026-09-18',
        'whoUid': 'adult',
      };
      final items = TomorrowOverviewEngine.build(
        today: dayBefore(tomorrow),
        members: [adult, child],
        chores: [chore],
      );
      expect(
          items.any((it) =>
              it.kind == Kind.chore && it.reason == 'Förfaller i morgon'),
          isTrue);
    });
  });

  // -------------------------------------------------------------------------
  group('TomorrowOverviewClarityTest', () {
    final tomorrow = DateTime(2026, 9, 18);
    final adult = user('adult', 'Céline', 'parent');

    List<TomorrowOverviewItem> build({
      List<Map<String, dynamic>> events = const [],
      List<TaskModel> tasks = const [],
    }) =>
        TomorrowOverviewEngine.build(
          today: dayBefore(tomorrow),
          members: [adult],
          events: events,
          tasks: tasks,
        );

    TaskModel clarityTask(String? dueDate, {String id = 't'}) =>
        TaskModel.fromMap(id, {
          'title': 'Engelska läxa',
          'dueDate': dueDate,
          'isDone': false,
        });

    test('handelserad sager att den galler i morgon', () {
      final middag = eventMap('middag', {
        'title': 'Céline lagar middag',
        'time': '17:00',
        'personUids': ['adult'],
      });
      final rad =
          build(events: [middag]).singleWhere((it) => it.kind == Kind.event);
      expect(rad.reason.startsWith('I morgon'), isTrue,
          reason: "Raden måste säga vilken dag den gäller, fick: '${rad.reason}'");
      // Klockslag och person ska finnas kvar — dagen läggs till, inget tas bort.
      expect(rad.reason.contains('17:00'), isTrue);
      expect(rad.reason.contains('Céline'), isTrue);
    });

    test('handelse utan klockslag sager anda i morgon', () {
      final rad = build(events: [
        eventMap('heldag', {'title': 'Utflykt', 'time': ''}),
      ]).singleWhere((it) => it.kind == Kind.event);
      expect(rad.reason.startsWith('I morgon'), isTrue);
    });

    test('ingen handelserad saknar dagsangivelse', () {
      final items = build(events: [
        eventMap('a', {'title': 'Möte', 'time': '09:00'}),
        eventMap('b', {'title': 'Träning', 'time': ''}),
      ]);
      for (final rad in items.where((it) => it.kind == Kind.event)) {
        expect(rad.reason.toLowerCase().contains('i morgon'), isTrue,
            reason: "Händelserad utan dag: '${rad.title}' → '${rad.reason}'");
      }
    });

    test('uppgift med dagens deadline sager att den skulle varit klar', () {
      final rad = build(tasks: [clarityTask('2026-09-17')])
          .singleWhere((it) => it.task != null);
      expect(rad.reason == 'Senast idag', isFalse,
          reason: 'Får inte formuleras som en deadline som fortfarande gäller');
      expect(rad.reason.contains('idag'), isTrue);
    });

    test('uppgift med morgondagens deadline sager i morgon', () {
      final rad = build(tasks: [clarityTask('2026-09-18')])
          .singleWhere((it) => it.task != null);
      expect(rad.reason.toLowerCase().contains('i morgon'), isTrue,
          reason: "Fick: '${rad.reason}'");
    });

    test('ingen rad blandar ihop idag och i morgon', () {
      final items = build(
        events: [
          eventMap('e', {'title': 'Middag', 'time': '17:00'}),
        ],
        tasks: [
          clarityTask('2026-09-17', id: 'igar'),
          clarityTask('2026-09-18', id: 'imorgon'),
        ],
      );
      for (final rad
          in items.where((it) => it.task != null || it.kind == Kind.event)) {
        final r = rad.reason.toLowerCase();
        expect(r.contains('idag') || r.contains('i morgon'), isTrue,
            reason: "Rad utan dagsangivelse: '${rad.title}' → '${rad.reason}'");
      }
    });
  });

  // -------------------------------------------------------------------------
  group('TomorrowOverviewConflictTest', () {
    final tomorrow = DateTime(2026, 9, 18);
    final child = user('child', 'Liam Larsson', 'child');
    final adult = user('adult', 'Alex Larsson', 'parent');

    ScheduleConflict pickup(String? eventTitle, int hour, int minute) {
      final start = DateTime(2026, 9, 18, hour, minute);
      return ScheduleConflict(
        day: tomorrow,
        start: start,
        end: start.add(const Duration(minutes: 30)),
        adults: [adult],
        pickupLabel:
            '🚗 fre ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')} — vem tar Liam?',
        child: child,
        eventTitle: eventTitle,
      );
    }

    List<TomorrowOverviewItem> build({
      List<Map<String, dynamic>> events = const [],
      List<Map<String, dynamic>> shifts = const [],
      List<ScheduleConflict> conflicts = const [],
    }) =>
        TomorrowOverviewEngine.build(
          today: dayBefore(tomorrow),
          members: [adult, child],
          events: events,
          shifts: shifts,
          conflicts: conflicts,
        );

    Map<String, dynamic> football() => eventMap('fotboll', {
          'title': 'Fotboll',
          'time': '17:00',
          'personUids': ['child'],
        });

    test('konflikten ligger overst och ersatter aktivitetens egen rad', () {
      final items =
          build(events: [football()], conflicts: [pickup('Fotboll', 17, 0)]);
      expect(items.first.kind, Kind.conflict);
      // Planen: "Samma uppgift visas en gång även om flera regler träffar."
      expect(
          items.any((it) => it.kind == Kind.event && it.event?.id == 'fotboll'),
          isFalse);
    });

    test('konflikten pekar pa aktiviteten sa raden kan oppnas', () {
      final conflict = build(
          events: [football()], conflicts: [pickup('Fotboll', 17, 0)]).first;
      expect(conflict.event?.id, 'fotboll');
      expect(conflict.member, child);
    });

    test('skolkonflikt utan aktivitet pekar pa barnet i stallet', () {
      // Lämning och hämtning saknar eventTitle.
      final conflict = build(conflicts: [pickup(null, 7, 30)]).first;
      expect(conflict.event, isNull);
      expect(conflict.member, child);
    });

    test('en annan aktivitet vid samma tid behaller sin rad', () {
      final piano = eventMap('piano', {
        'title': 'Piano',
        'time': '17:00',
        'personUids': ['child'],
      });
      final items = build(
          events: [football(), piano], conflicts: [pickup('Fotboll', 17, 0)]);
      expect(
          items.where((it) => it.kind == Kind.event && it.event?.id == 'piano'),
          isNotEmpty);
    });

    test('konflikter sorteras pa klockslag inte pa titel', () {
      final items = build(conflicts: [pickup(null, 16, 0), pickup(null, 7, 30)])
          .where((it) => it.kind == Kind.conflict);
      expect(items.map((it) => it.sortKey).toList(), ['07:30', '16:00']);
    });

    test('arbetspass sorteras pa starttid inte pa fornamn', () {
      final late = {
        'id': 'late',
        'date': '2026-09-18',
        'who': 'Alex',
        'whoUid': 'adult',
        'startTime': '14:00',
        'endTime': '22:00',
      };
      final early = {
        'id': 'early',
        'date': '2026-09-18',
        'who': 'Bea',
        'whoUid': 'adult',
        'startTime': '06:00',
        'endTime': '14:00',
      };
      final shifts = build(shifts: [late, early])
          .where((it) => it.kind == Kind.workShift);
      expect(shifts.map((it) => it.title).toList(),
          ['Bea arbetar', 'Alex arbetar']);
    });

    test('packlistan visas aven for en aktivitet som har en konflikt', () {
      final trip = eventMap('utflykt', {
        'title': 'Utflykt',
        'time': '09:00',
        'personUids': ['child'],
        'checklist': [
          {'item': 'Matsäck', 'isDone': false},
        ],
      });
      final items =
          build(events: [trip], conflicts: [pickup('Utflykt', 9, 0)]);
      // Att packa och att lösa hämtningen är två olika saker att göra.
      expect(
          items
              .where((it) => it.kind == Kind.checklist)
              .map((it) => it.title)
              .toList(),
          ['Matsäck']);
    });

    test('strangrader i packlistan visas och behaller sitt index', () {
      final trip = eventMap('utflykt', {
        'title': 'Utflykt',
        'checklist': [
          'Stövlar',
          {'item': 'Matsäck', 'isDone': false},
        ],
      });
      final rows =
          build(events: [trip]).where((it) => it.kind == Kind.checklist);
      expect(rows.map((it) => it.title).toList(), ['Stövlar', 'Matsäck']);
      expect(rows.map((it) => it.checklistIndex).toList(), [0, 1]);
    });

    test('vanliga skolblock utan sluttid ger ingen paminnelse', () {
      final first = eventMap('l1', {
        'source': 'calendar',
        'planningImportKind': 'schedule',
        'personUids': ['child'],
        'time': '08:00',
        'endTime': '09:00',
      });
      final last = eventMap('l2', {
        'source': 'calendar',
        'planningImportKind': 'schedule',
        'personUids': ['child'],
        'time': '14:00',
        'endTime': '',
      });
      expect(build(events: [first, last]), isEmpty);
    });

    test('skolprov visar sin titel i stallet for schemats etikett', () {
      final block = eventMap('l1', {
        'source': 'calendar',
        'planningImportKind': 'schedule',
        'personUids': ['child'],
        'schemaLabel': 'Skola | 7B',
        'title': 'Prov i engelska',
        'time': '08:00',
        'endTime': '14:00',
      });
      final exam =
          build(events: [block]).singleWhere((it) => it.kind == Kind.event);
      expect(exam.title, 'Prov i engelska');
      expect(exam.reason.contains('Liam'), isTrue);
    });
  });

  // -------------------------------------------------------------------------
  group('TomorrowOverviewLessonPrepTest', () {
    final today = DateTime(2026, 9, 20);
    final tomorrow = DateTime(2026, 9, 21);
    final leandro = user('leandro', 'Leandro Larsson', 'child');
    final emilio = user('emilio', 'Emilio Larsson', 'child');

    /// En importerad skollektion: separat dokument per tillfälle.
    Map<String, dynamic> lektion({
      String id = 'l1',
      String title = 'Gympa',
      String date = '2026-09-21',
      String time = '09:00',
      String person = 'leandro',
      Map<String, dynamic>? prep,
      Map<String, dynamic>? recurrence,
    }) =>
        {
          'id': id,
          'title': title,
          'date': date,
          'time': time,
          'personUids': [person],
          'source': 'calendar',
          'planningImportKind': 'schedule',
          'calendarImportId': 'imp1',
          TomorrowOverviewLessonPrep.field: ?prep,
          'recurrence': ?recurrence,
        };

    Map<String, dynamic> prep(String text,
            {List<String> done = const []}) =>
        {'text': text, 'doneDates': done};

    List<TomorrowOverviewItem> build(List<Map<String, dynamic>> events,
            {DateTime? day, List<UserModel>? members}) =>
        TomorrowOverviewEngine.build(
          today: day ?? today,
          members: members ?? [leandro, emilio],
          events: events,
        );

    test('forberedelse visas med text lektion och barn', () {
      final rader = build([lektion(prep: prep('Packa gympapåsen'))]);
      final rad = rader.singleWhere((it) => it.kind == Kind.prepTask);
      expect(rad.title, 'Packa gympapåsen · Leandro');
      expect(rad.reason, 'Gympa i morgon kl. 09:00');
      expect(rad.piktogram, '🎒');
      expect(rad.member, leandro);
    });

    test('vanlig lektion utan forberedelse visas inte alls', () {
      expect(build([lektion()]), isEmpty);
    });

    test('forberedelse pa lektion utan tid utelamnar klockslaget', () {
      final rad = build([lektion(time: '', prep: prep('Ta med kamera'))])
          .singleWhere((it) => it.kind == Kind.prepTask);
      expect(rad.reason.replaceAll('Gympa', 'Temadag'), 'Temadag i morgon');
    });

    test('avbockat tillfalle visas inte', () {
      final avbockad =
          lektion(prep: prep('Packa gympapåsen', done: ['2026-09-21']));
      expect(build([avbockad]).any((it) => it.kind == Kind.prepTask), isFalse);
    });

    test('avbockning av ett tillfalle paverkar inte nasta', () {
      final iMorgon = lektion(
          id: 'l1',
          date: '2026-09-21',
          prep: prep('Packa gympapåsen', done: ['2026-09-21']));
      final nastaVecka = lektion(
          id: 'l2',
          date: '2026-09-28',
          prep: prep('Packa gympapåsen', done: ['2026-09-21']));

      expect(build([iMorgon]).any((it) => it.kind == Kind.prepTask), isFalse);

      final nasta = build([nastaVecka], day: DateTime(2026, 9, 27));
      expect(nasta.where((it) => it.kind == Kind.prepTask).length, 1);
    });

    test('aterkommande lektion ger forberedelse varje gang', () {
      final serie = lektion(
        prep: prep('Packa gympapåsen'),
        recurrence: {'type': 'weekly', 'startDate': '2026-09-21'},
      );
      expect(build([serie]).where((it) => it.kind == Kind.prepTask).length, 1);

      final omEnVecka =
          build([serie], day: DateTime(2026, 9, 27), members: [leandro]);
      expect(omEnVecka.where((it) => it.kind == Kind.prepTask).length, 1);
    });

    test('serie med slutdatum slutar ge forberedelser', () {
      final serie = lektion(
        prep: prep('Packa gympapåsen'),
        recurrence: {
          'type': 'weekly',
          'startDate': '2026-09-21',
          'endDate': '2026-09-21',
        },
      );
      expect(build([serie]).where((it) => it.kind == Kind.prepTask).length, 1);

      final efterSlut =
          build([serie], day: DateTime(2026, 9, 27), members: [leandro]);
      expect(efterSlut.any((it) => it.kind == Kind.prepTask), isFalse);
    });

    test('installt tillfalle ger ingen forberedelse', () {
      final serie = lektion(
        prep: prep('Packa gympapåsen'),
        recurrence: {
          'type': 'weekly',
          'startDate': '2026-09-14',
          'exceptions': ['2026-09-21'],
        },
      );
      expect(build([serie]).any((it) => it.kind == Kind.prepTask), isFalse);
    });

    test('tva barns lektioner ger varsin rad', () {
      final rader = build([
        lektion(id: 'a', person: 'leandro', prep: prep('Packa gympapåsen')),
        lektion(id: 'b', person: 'emilio', prep: prep('Ta med simkläder')),
      ]).where((it) => it.kind == Kind.prepTask).toList();
      expect(rader.length, 2);
      expect(rader.any((it) => it.title == 'Packa gympapåsen · Leandro'),
          isTrue);
      expect(
          rader.any((it) => it.title == 'Ta med simkläder · Emilio'), isTrue);
    });

    test('ett barns avbockning paverkar inte det andra', () {
      final rader = build([
        lektion(
            id: 'a',
            person: 'leandro',
            prep: prep('Packa gympapåsen', done: ['2026-09-21'])),
        lektion(id: 'b', person: 'emilio', prep: prep('Packa gympapåsen')),
      ]).where((it) => it.kind == Kind.prepTask).toList();
      expect(rader.length, 1);
      expect(rader.single.title, 'Packa gympapåsen · Emilio');
    });

    test('samma lektion tva ganger ger en rad', () {
      // Omladdning och synk kan ge samma dokument två gånger i listan.
      final samma = lektion(prep: prep('Packa gympapåsen'));
      final rader = build([samma, samma])
          .where((it) => it.kind == Kind.prepTask)
          .toList();
      expect(rader.length, 1);
    });

    test('samma serie som tva dokument ger tva rader bara om bada infaller',
        () {
      // Två dokument för SAMMA dag med olika id kan motorn inte känna igen.
      final rader = build([
        lektion(id: 'a', prep: prep('Packa gympapåsen')),
        lektion(id: 'b', prep: prep('Packa gympapåsen')),
      ]).where((it) => it.kind == Kind.prepTask).toList();
      expect(rader.length, 2);
    });

    test('forberedelse och prov pa samma dag visas bada', () {
      final rader = build([
        lektion(id: 'a', title: 'Gympa', prep: prep('Packa gympapåsen')),
        lektion(id: 'b', title: 'Matteprov'),
      ]);
      expect(rader.where((it) => it.kind == Kind.prepTask).length, 1);
      expect(rader.where((it) => it.kind == Kind.event).length, 1);
    });

    test('serienyckeln skiljer barn at', () {
      final a = lektion(id: 'a', person: 'leandro');
      final b = lektion(id: 'b', person: 'emilio');
      expect(
          TomorrowOverviewLessonPrep.seriesKey(a, 'a') !=
              TomorrowOverviewLessonPrep.seriesKey(b, 'b'),
          isTrue);
    });

    test('serienyckeln ar samma for tva tillfallen i samma serie', () {
      final v1 = lektion(id: 'a', date: '2026-09-21');
      final v2 = lektion(id: 'b', date: '2026-09-28');
      expect(TomorrowOverviewLessonPrep.seriesKey(v1, 'a'),
          TomorrowOverviewLessonPrep.seriesKey(v2, 'b'));
    });

    test('serienyckeln skiljer olika lektioner at', () {
      final gympa = lektion(id: 'a', title: 'Gympa');
      final slojd = lektion(id: 'b', title: 'Slöjd');
      expect(
          TomorrowOverviewLessonPrep.seriesKey(gympa, 'a') !=
              TomorrowOverviewLessonPrep.seriesKey(slojd, 'b'),
          isTrue);
    });

    test('manuell lektion utan import anvander sitt eget id', () {
      final manuell = <String, dynamic>{'title': 'Gympa', 'date': '2026-09-21'};
      expect(TomorrowOverviewLessonPrep.seriesKey(manuell, 'abc'), 'abc');
    });

    test('raden bar lektionens id och tillfallets datum', () {
      // Extra i Flutter: gränssnittet behöver källan och dagen.
      final rad = build([lektion(prep: prep('Packa gympapåsen'))])
          .singleWhere((it) => it.kind == Kind.prepTask);
      expect(rad.eventId, 'l1');
      expect(rad.occurrenceDate, key(tomorrow));
      expect(rad.date, tomorrow);
    });
  });

  // -------------------------------------------------------------------------
  group('TomorrowOverviewNoteTest', () {
    final today = DateTime(2026, 9, 17);
    final adult = user('adult', 'Alex Larsson', 'parent');

    NoteModel note({
      String id = 'n1',
      required String status,
      int? revision,
      String? validFrom,
      String? validTo,
      String text = 'Veckobrev från skolan',
      DateTime? deletedAt,
      NoteInterpretation? interpretation,
    }) =>
        NoteModel(
          id: id,
          familyId: 'f1',
          ownerUid: 'adult',
          text: text,
          status: status,
          validFrom: validFrom,
          validTo: validTo,
          deletedAt: deletedAt,
          interpretation: interpretation ??
              (revision != null ? NoteInterpretation(revision: revision) : null),
        );

    List<TomorrowOverviewItem> build({
      List<NoteModel> notes = const [],
      List<Map<String, dynamic>> events = const [],
    }) =>
        TomorrowOverviewEngine.build(
          today: today,
          members: [adult],
          events: events,
          notes: notes,
        );

    TomorrowOverviewItem single(NoteModel n) =>
        build(notes: [n]).singleWhere((it) => it.note != null);

    test('en anteckning som vantar pa granskning visas', () {
      final item = single(note(status: NoteModel.statusNeedsReview, revision: 1));
      expect(item.kind, Kind.noteReview);
      expect(item.reason, 'Förslag att granska');
    });

    test('en misslyckad tolkning skiljs fran en som vantar pa granskning', () {
      final item = single(note(status: NoteModel.statusFailed));
      expect(item.kind, Kind.noteReview);
      expect(item.reason, 'Tolkningen gick inte igenom');
      expect(item.piktogram, '⚠️');
    });

    test('en anteckning som tolkas just nu stor inte overblicken', () {
      expect(
          build(notes: [note(status: NoteModel.statusInterpreting)])
              .any((it) => it.note != null),
          isFalse);
    });

    test('en mjukraderad anteckning visas aldrig', () {
      final deleted = note(
          status: NoteModel.statusNeedsReview,
          revision: 1,
          deletedAt: DateTime.now());
      expect(build(notes: [deleted]).any((it) => it.note != null), isFalse);
    });

    test('forsta raden ur texten blir rubrik', () {
      final long = note(
        status: NoteModel.statusNeedsReview,
        revision: 1,
        text: 'Veckobrev 38\nUtflykt på torsdag, ta med matsäck.',
      );
      expect(single(long).title, 'Veckobrev 38');
    });

    test('bekraftad information vars fonster tacker morgondagen visas', () {
      final info = note(
          status: NoteModel.statusConfirmed,
          validFrom: '2026-09-01',
          validTo: '2026-09-30');
      final item = single(info);
      expect(item.kind, Kind.noteInfo);
      expect(item.reason, 'Gäller 1 sep–30 sep');
    });

    test('ett besked som gatt ut slutar visas dagen efter', () {
      final expired =
          note(status: NoteModel.statusConfirmed, validTo: '2026-09-17');
      expect(build(notes: [expired]).any((it) => it.note != null), isFalse);
    });

    test('ett besked som borjar galla senare visas inte an', () {
      final future =
          note(status: NoteModel.statusConfirmed, validFrom: '2026-10-01');
      expect(build(notes: [future]).any((it) => it.note != null), isFalse);
    });

    test('en bekraftad anteckning utan giltighetsfonster ar ingen upplysning',
        () {
      final confirmed = note(status: NoteModel.statusConfirmed);
      expect(build(notes: [confirmed]).any((it) => it.note != null), isFalse);
    });

    test('info-forslagets titel visas i stallet for brevets forsta rad', () {
      final brev = note(
        status: NoteModel.statusConfirmed,
        validFrom: '2026-09-17',
        validTo: '2026-09-30',
        text: 'På tisdag den 22/9 är det studiedag.\nDet är bad igen på torsdag.',
        interpretation: const NoteInterpretation(revision: 1, actions: [
          NoteAction(
              id: 'a1',
              type: NoteAction.typeCreateEvent,
              title: 'Bad',
              status: 'confirmed'),
          NoteAction(
              id: 'a2',
              type: NoteAction.typeInfo,
              title: 'Studiedag tisdag',
              status: 'confirmed'),
        ]),
      );
      expect(single(brev).title, 'Studiedag tisdag');
    });

    test('ett info-forslag som inte bekraftats ger brevets forsta rad', () {
      final brev = note(
        status: NoteModel.statusConfirmed,
        validTo: '2026-09-30',
        text: 'Rad ett\nRad två',
        interpretation: const NoteInterpretation(revision: 1, actions: [
          NoteAction(
              id: 'a',
              type: NoteAction.typeInfo,
              title: 'Ej bekräftad',
              status: 'dismissed'),
        ]),
      );
      expect(single(brev).title, 'Rad ett');
    });

    test('en dold rad visas inte i morgon', () {
      // Dölj sätter validTo till idag.
      final dold = note(
          status: NoteModel.statusConfirmed,
          validFrom: '2026-09-10',
          validTo: key(today));
      expect(build(notes: [dold]).any((it) => it.note != null), isFalse);
    });

    test('granskning ligger fore aktiviteter och information sist', () {
      final items = build(
        notes: [
          note(
              id: 'n1',
              status: NoteModel.statusNeedsReview,
              revision: 1,
              text: 'Granska mig'),
          note(
              id: 'n2',
              status: NoteModel.statusConfirmed,
              validTo: '2026-09-30',
              text: 'Info till sist'),
        ],
        events: [
          {'id': 'e', 'date': '2026-09-18', 'title': 'Träning', 'time': '17:00'},
        ],
      );
      final titles = items.map((it) => it.title).toList();
      expect(titles.indexOf('Granska mig') < titles.indexOf('Träning'), isTrue);
      expect(
          titles.indexOf('Info till sist') > titles.indexOf('Träning'), isTrue);
    });
  });

  // -------------------------------------------------------------------------
  group('TomorrowOverviewPersonTest', () {
    final today = DateTime(2026, 9, 17);
    final pappa = user('p', 'Oskar Larsson', 'parent');
    final mamma = user('m', 'Nina Larsson', 'parent');
    final barn = user('b', 'Leo Larsson', 'child');

    TaskModel personTask({List<String> about = const [], String? assignee}) =>
        task(
          id: 't_${about.join('-')}_$assignee',
          title: 'Engelska läxa',
          dueDate: '2026-09-18',
          aboutUids: about,
          assigneeUid: assignee,
        );

    List<TomorrowOverviewItem> build(List<TaskModel> tasks,
            {String? currentUid, bool baraMina = false}) =>
        TomorrowOverviewEngine.build(
          today: today,
          members: [pappa, mamma, barn],
          tasks: tasks,
          currentUid: currentUid,
          baraMinaUppgifter: baraMina,
        );

    TomorrowOverviewItem single(TaskModel t) =>
        build([t]).singleWhere((it) => it.task != null);

    test('uppgiften namnger barnet den galler', () {
      final item = single(personTask(about: ['b']));
      expect(item.reason.contains('Leo'), isTrue,
          reason: 'Skulle namna barnet, fick: ${item.reason}');
    });

    test('flera barn raknas upp', () {
      final item = single(personTask(about: ['b', 'm']));
      expect(item.reason.contains('Leo'), isTrue);
      expect(item.reason.contains('Nina'), isTrue);
    });

    test('utan barnkoppling namns ingen', () {
      expect(single(personTask()).reason, 'Senast i morgon');
    });

    test('ansvarig visas nar den skiljer sig fran den uppgiften galler', () {
      final item = single(personTask(about: ['b'], assignee: 'p'));
      expect(item.reason.contains('Leo'), isTrue);
      expect(item.reason.contains('Oskar'), isTrue);
    });

    test('ansvarig upprepas inte nar den ar samma person', () {
      // Annars blir det "Leo · Leo", vilket ser ut som ett fel.
      final item = single(personTask(about: ['b'], assignee: 'b'));
      expect(item.reason.split('Leo').length - 1, 1);
    });

    test('utan filter visas andras uppgifter som forut', () {
      final items =
          build([personTask(assignee: 'm')], currentUid: 'p', baraMina: false);
      expect(items.where((it) => it.task != null).length, 1);
    });

    test('med filter doljs uppgift tilldelad nagon annan', () {
      final items =
          build([personTask(assignee: 'm')], currentUid: 'p', baraMina: true);
      expect(items.where((it) => it.task != null), isEmpty);
    });

    test('med filter visas min egen uppgift', () {
      final items =
          build([personTask(assignee: 'p')], currentUid: 'p', baraMina: true);
      expect(items.where((it) => it.task != null).length, 1);
    });

    test('otilldelade visas alltid', () {
      // En uppgift ingen tagit ansvar för får inte försvinna för alla.
      final items = build([personTask()], currentUid: 'p', baraMina: true);
      expect(items.where((it) => it.task != null).length, 1);
    });

    test('filtret gor ingenting utan inloggad anvandare', () {
      final items =
          build([personTask(assignee: 'm')], currentUid: null, baraMina: true);
      expect(items.where((it) => it.task != null).length, 1);
    });

    test('filtret ror inte aktiviteter eller sysslor', () {
      // Bara uppgifter filtreras. Familjens gemensamma dag ska inte kunna
      // tappa poster tyst.
      final items = TomorrowOverviewEngine.build(
        today: today,
        members: [pappa, mamma, barn],
        chores: [
          {
            'id': 'c',
            'familyId': 'f',
            'chore': 'Diska',
            'dueDate': '2026-09-18',
            'whoUid': 'm',
          },
        ],
        currentUid: 'p',
        baraMinaUppgifter: true,
      );
      expect(items.where((it) => it.chore != null).length, 1);
    });
  });

  // -------------------------------------------------------------------------
  group('TomorrowOverviewReviewTest', () {
    final day = DateTime(2026, 9, 18);
    final adults = [user('a', 'Alex', 'parent')];

    Map<String, dynamic> event(String id,
            [Map<String, dynamic> extra = const {}]) =>
        {'id': id, 'date': key(day), 'time': '09:00', 'title': id, ...extra};

    List<TomorrowOverviewItem> build({
      List<Map<String, dynamic>> events = const [],
      List<Map<String, dynamic>> chores = const [],
      List<Map<String, dynamic>> shifts = const [],
      List<UserModel>? members,
    }) =>
        TomorrowOverviewEngine.build(
          today: dayBefore(day),
          members: members ?? adults,
          events: events,
          chores: chores,
          shifts: shifts,
        );

    test('engine preserves all rows for Show all and deduplicates event documents',
        () {
      final events = [for (var i = 1; i <= 8; i++) event('event-$i')];
      final rows = build(events: [...events, events.first]);
      expect(rows.where((it) => it.kind == Kind.event).length, 8);
      expect(rows.length, 8); // bara aktiviteterna; middagsraden är borttagen
    });

    test('only unfinished one-off preparations are shown before activity rows',
        () {
      final pack = [
        {'item': 'Skor', 'isDone': false},
        {'item': 'Vatten', 'isDone': true},
      ];
      final recurring = {'type': 'daily', 'startDate': key(dayBefore(day))};
      final rows = build(events: [
        event('one', {'checklist': pack}),
        event('weekly',
            {'checklist': pack, 'isRecurring': true, 'recurrence': recurring}),
        // Recurrence är auktoritativ även på äldre poster utan isRecurring.
        event('older-recurring', {'checklist': pack, 'recurrence': recurring}),
      ]);
      final preparations =
          rows.where((it) => it.kind == Kind.checklist).toList();
      expect(preparations.length, 1);
      expect(preparations.single.event?.id, 'one');
      expect(rows.first.title, 'Skor');
    });

    test('due assigned chore is shown but undated and already completed chores are not',
        () {
      Map<String, dynamic> chore(String id, Map<String, dynamic> extra) =>
          {'id': id, 'chore': id, ...extra};
      final rows = build(chores: [
        chore('due', {'dueDate': key(day), 'whoUid': 'a', 'who': 'Alex'}),
        chore('undated', {}),
        chore('done', {'dueDate': key(day), 'isDone': true}),
      ]).where((it) => it.kind == Kind.chore).toList();
      expect(rows.map((it) => it.chore?.id).toList(), ['due']);
      expect(rows.single.reason.contains('Saknar ansvarig'), isFalse);
    });

    test('recurring chore excluded on exception even if its original due date matches',
        () {
      final chore = {
        'id': 'exception',
        'chore': 'Undantag',
        'dueDate': key(day),
        'isRecurring': true,
        'recurrence': {
          'type': 'daily',
          'startDate': key(day),
          'exceptions': [key(day)],
        },
      };
      expect(build(chores: [chore]).any((it) => it.kind == Kind.chore), isFalse);
    });

    test('night ending at midnight does not occupy following day but six am does',
        () {
      Map<String, dynamic> shift(String id, String end) => {
            'id': id,
            'date': key(dayBefore(day)),
            'startTime': '21:00',
            'endTime': end,
            'who': 'Alex',
            'whoUid': 'a',
          };
      expect(
          build(shifts: [shift('midnight', '00:00')])
              .any((it) => it.kind == Kind.workShift),
          isFalse);
      final overnight = build(shifts: [shift('night', '06:00')])
          .singleWhere((it) => it.kind == Kind.workShift);
      expect(overnight.reason.contains('06:00'), isTrue);
    });

    test('ordinary school for multiple children does not fill the overview', () {
      final children = [
        user('c1', 'Kim Ett', 'child'),
        user('c2', 'Kim Två', 'child'),
      ];
      final events = children
          .map((person) => event(person.uid, {
                'source': 'calendar',
                'planningImportKind': 'schedule',
                'personUids': [person.uid],
                'endTime': '14:00',
              }))
          .toList();
      expect(build(events: events, members: [...adults, ...children]), isEmpty);
    });

    test('school and normal activities share chronological order', () {
      final rows = build(events: [
        event('late-school',
            {'source': 'calendar', 'time': '10:00', 'endTime': '14:00'}),
        event('early-event', {'time': '07:00'}),
      ]);
      expect(rows.first.event?.id, 'early-event');
    });

    test('en planerad middag ger ingen rad i overblicken', () {
      // Middagsraden är borttagen; motorn tar inte ens emot en middag.
      final rows = build(events: [
        {'id': 'e', 'date': key(day), 'title': 'Träning', 'time': '17:00'},
      ]);
      expect(rows.map((it) => it.title).toList(), ['Träning']);
    });
  });

  // -------------------------------------------------------------------------
  group('TomorrowOverviewTaskTest', () {
    final today = DateTime(2026, 9, 17);
    final adult = user('adult', 'Alex Larsson', 'parent');
    final other = user('other', 'Bea Larsson', 'parent');

    TaskModel t(
      String? dueDate, {
      String? showFrom,
      String? eventId,
      String? occurrence,
      String title = 'Boka tid',
      String? assignee,
      String status = TaskModel.statusOpen,
      bool hasTime = false,
      String? dueTime,
    }) =>
        task(
          id: 't${dueDate}_${showFrom}_$eventId',
          title: title,
          dueDate: dueDate,
          showFromDate: showFrom,
          eventId: eventId,
          occurrenceDate: occurrence,
          assigneeUid: assignee,
          status: status,
          hasTime: hasTime,
          dueTime: dueTime,
        );

    List<TomorrowOverviewItem> build(List<TaskModel> tasks) =>
        TomorrowOverviewEngine.build(
          today: today,
          members: [adult, other],
          tasks: tasks,
        );

    TomorrowOverviewItem single(TaskModel task) =>
        build([task]).singleWhere((it) => it.task != null);

    test('forsenad uppgift ar bradskande', () {
      final item = single(t('2026-09-10'));
      expect(item.kind, Kind.urgentTask);
      expect(item.reason.startsWith('Skulle varit klar'), isTrue);
    });

    test('uppgift som forfaller idag eller i morgon ar bradskande', () {
      expect(single(t('2026-09-17')).reason, 'Skulle varit klar idag');
      expect(single(t('2026-09-18')).reason, 'Senast i morgon');
    });

    test('ett framtida showFromDate doljer uppgiften helt', () {
      expect(
          build([t(null, showFrom: '2026-09-25')]).any((it) => it.task != null),
          isFalse);
    });

    test('en bradskande deadline visas aven om showFromDate inte natts', () {
      final item = single(t('2026-09-18', showFrom: '2026-09-25'));
      expect(item.kind, Kind.urgentTask);
    });

    test('uppgift utan deadline visas nar showFromDate natts', () {
      final item = single(t(null, showFrom: '2026-09-17'));
      expect(item.kind, Kind.upcomingTask);
      expect(item.reason, 'Ingen deadline');
    });

    test('forberedelse till morgondagens forekomst hamnar bland packlistan', () {
      final item = single(t(null, eventId: 'traning', occurrence: '2026-09-18'));
      expect(item.kind, Kind.prepTask);
    });

    test('forberedelse till en annan vecka visas inte som forberedelse', () {
      final item = single(t(null, eventId: 'traning', occurrence: '2026-09-25'));
      expect(item.kind, Kind.upcomingTask);
    });

    test('en uppgift som traffar flera regler visas bara en gang', () {
      final items = build([
        t('2026-09-18', eventId: 'traning', occurrence: '2026-09-18'),
      ]).where((it) => it.task != null).toList();
      expect(items.length, 1);
      expect(items.single.kind, Kind.urgentTask);
    });

    test('avbockad uppgift visas inte', () {
      final done = t('2026-09-10', status: TaskModel.statusDone);
      expect(build([done]).any((it) => it.task != null), isFalse);
    });

    test('ansvarig visas i motiveringen och som medlem pa raden', () {
      final item = single(t('2026-09-18', assignee: 'other'));
      expect(item.reason.endsWith('· Bea'), isTrue);
      expect(item.member, other);
    });

    test('bradskande uppgifter ligger fore kommande', () {
      final items = build([
        t(null, showFrom: '2026-09-01', title: 'Kommande'),
        t('2026-09-18', title: 'Brådskande'),
      ]);
      final order = items.map((it) => it.title).toList();
      expect(order.contains('Brådskande') && order.contains('Kommande'), isTrue);
      expect(order.indexOf('Brådskande') < order.indexOf('Kommande'), isTrue);
    });

    test('klockslag styr ordningen mellan bradskande uppgifter', () {
      final items = build([
        t('2026-09-18', title: 'Sen', hasTime: true, dueTime: '16:00'),
        t('2026-09-18', title: 'Tidig', hasTime: true, dueTime: '08:00'),
      ]).where((it) => it.kind == Kind.urgentTask);
      expect(items.map((it) => it.title).toList(), ['Tidig', 'Sen']);
    });

    test('raden bar uppgiftens datum', () {
      // Extra i Flutter: dagen raden gäller, för datum/veckodag i gränssnittet.
      expect(single(t('2026-09-10')).date, DateTime(2026, 9, 10));
      expect(single(t(null, showFrom: '2026-09-01')).date, isNull);
      expect(
          single(t(null, eventId: 'traning', occurrence: '2026-09-18')).date,
          DateTime(2026, 9, 18));
    });
  });

  // -------------------------------------------------------------------------
  // Flutters avvikelse: servern sätter aldrig åtgärdernas status till
  // "confirmed", så info-rubriken tas från första info-förslaget oavsett
  // status (utom uttryckligen avfärdade).
  group('Info-rubrik (Flutter-avvikelse)', () {
    final today = DateTime(2026, 9, 17);
    final adult = user('adult', 'Alex Larsson', 'parent');

    TomorrowOverviewItem infoRow(List<NoteAction> actions,
        {String text = 'Brevets första rad\nMer text'}) {
      final n = NoteModel(
        id: 'n',
        familyId: 'f',
        ownerUid: 'adult',
        text: text,
        status: NoteModel.statusConfirmed,
        validTo: '2026-09-30',
        interpretation: NoteInterpretation(revision: 1, actions: actions),
      );
      return TomorrowOverviewEngine.build(
        today: today,
        members: [adult],
        notes: [n],
      ).singleWhere((it) => it.kind == Kind.noteInfo);
    }

    test('ett info-forslag med status pending ger forslagets titel', () {
      // Så ser servern ut i verkligheten: åtgärderna står kvar som pending.
      final row = infoRow(const [
        NoteAction(id: 'a', type: NoteAction.typeInfo, title: 'Studiedag'),
      ]);
      expect(row.title, 'Studiedag');
      expect(row.reason, 'Gäller till 30 sep');
      expect(row.piktogram, '💬');
      expect(row.date, DateTime(2026, 9, 18));
    });

    test('ett info-forslag utan status fran servern ger forslagets titel', () {
      final action = NoteAction.fromMap(
          {'id': 'a', 'type': 'info', 'title': '  Bad på torsdag  '})!;
      expect(infoRow([action]).title, 'Bad på torsdag');
    });

    test('forsta info-forslaget vinner och andra typer hoppas over', () {
      final row = infoRow(const [
        NoteAction(id: 'e', type: NoteAction.typeCreateEvent, title: 'Bad'),
        NoteAction(id: 'i1', type: NoteAction.typeInfo, title: 'Första'),
        NoteAction(id: 'i2', type: NoteAction.typeInfo, title: 'Andra'),
      ]);
      expect(row.title, 'Första');
    });

    test('ett info-forslag utan titel ger brevets forsta rad', () {
      final row = infoRow(const [
        NoteAction(id: 'a', type: NoteAction.typeInfo, title: '   '),
      ]);
      expect(row.title, 'Brevets första rad');
    });

    test('ett avfardat forslag hoppas over till nasta info-forslag', () {
      final row = infoRow(const [
        NoteAction(
            id: 'a', type: NoteAction.typeInfo, title: 'Nej', status: 'dismissed'),
        NoteAction(id: 'b', type: NoteAction.typeInfo, title: 'Ja'),
      ]);
      expect(row.title, 'Ja');
    });

    test('lang titel kortas till 80 tecken och tom text ger Information', () {
      final lang = 'x' * 100;
      expect(
          infoRow([NoteAction(id: 'a', type: NoteAction.typeInfo, title: lang)])
              .title
              .length,
          80);
      expect(infoRow(const [], text: '').title, 'Information');
    });
  });
}
