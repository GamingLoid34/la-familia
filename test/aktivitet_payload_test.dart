import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/models/user_model.dart';
import 'package:la_familia/utils/aktivitet_formular.dart';
import 'package:la_familia/utils/aktivitet_payload.dart';
import 'package:la_familia/utils/lesson_prep.dart';

/// Fälten formuläret skriver till `planner_events`.
///
/// Portad från Androids `AktivitetPayloadTest`. En ny aktivitet ska ge exakt
/// de fält Android skriver. Redigeringen skiljer sig medvetet: den skriver
/// bara det som ändrats (se gruppen "Redigering skriver bara det som ändrats").
UserModel _medlem(String uid, String name) => UserModel(
      uid: uid,
      name: name,
      email: '',
      color: 'ff2196f3',
      role: 'parent',
      viewMode: 'parent',
      energy: 3,
    );

void main() {
  final torsdag = DateTime(2026, 9, 24);
  final leo = _medlem('leo', 'Leo');
  final nina = _medlem('nina', 'Nina');

  AktivitetUtkast utkast({
    String titel = 'Tandläkare',
    DateTime? datum,
    TimeOfDay? start = const TimeOfDay(hour: 15, minute: 0),
    TimeOfDay? slut,
    String upprepning = 'none',
    DateTime? upprepningSlut,
    List<UserModel>? deltagare,
    List<PacklistRad> packlista = const [],
    bool prepAktiv = false,
    String prepText = '',
    String piktogram = '',
    Tidslage tidslage = Tidslage.klockslag,
  }) =>
      AktivitetUtkast(
        titel: titel,
        piktogram: piktogram,
        datum: datum ?? torsdag,
        tidslage: tidslage,
        starttid: start,
        sluttid: slut,
        upprepning: upprepning,
        upprepningSlut: upprepningSlut,
        deltagare: deltagare ?? [leo],
        packlista: packlista,
        forberedelseAktiv: prepAktiv,
        forberedelseText: prepText,
      );

  AktivitetPayload bygg(
    AktivitetUtkast u, {
    String uid = 'mig',
    Map<String, dynamic>? original,
  }) =>
      byggAktivitetPayload(
          utkast: u, uid: uid, familyId: 'fam', original: original);

  group('Paritet med Android', () {
    test('ny aktivitet ger exakt samma fält som Android', () {
      final p = bygg(utkast());
      expect(p.falt, {
        'title': 'Tandläkare',
        'piktogram': '📅',
        'type': 'activity',
        'date': '2026-09-24',
        'time': '15:00',
        'persons': ['Leo'],
        'personUids': ['leo'],
        'checklist': <dynamic>[],
        'source': 'manual',
        'createdBy': 'mig',
        'isPending': false,
        'familyId': 'fam',
        'createdByUid': 'mig',
      });
      expect(p.falt.keys.toList(), [
        'title', 'piktogram', 'type', 'date', 'time', 'persons',
        'personUids', 'checklist', 'source', 'createdBy', 'isPending',
        'familyId', 'createdByUid',
      ]);
      expect(p.taBort, isEmpty, reason: 'En ny aktivitet har inget att ta bort');
      expect(p.packlistanAndrad, isFalse);
    });

    test('redigering skriver inte om skaparen', () {
      // Android skriver om createdBy vid varje redigering; här behålls båda.
      final p = bygg(utkast(),
          uid: 'annan',
          original: {'title': 'Gammal', 'checklist': <dynamic>[]});
      expect(p.falt.containsKey('createdByUid'), isFalse);
      expect(p.falt.containsKey('createdBy'), isFalse);
      expect(p.falt['time'], '15:00');
    });

    test('redigering utan sluttid tar bort endTime', () {
      final p = bygg(utkast(slut: null), original: {'endTime': '16:00'});
      expect(p.taBort, contains('endTime'));
      expect(p.falt.containsKey('endTime'), isFalse);
    });

    test('ny aktivitet utan sluttid tar inte bort något', () {
      expect(bygg(utkast(slut: null)).taBort, isNot(contains('endTime')));
    });

    test('sluttid skrivs som HH:mm', () {
      final p = bygg(utkast(slut: const TimeOfDay(hour: 16, minute: 5)));
      expect(p.falt['endTime'], '16:05');
    });

    test('upprepning ger samma recurrence-block som Android', () {
      final p = bygg(utkast(
          upprepning: 'weekly', upprepningSlut: DateTime(2026, 12, 17)));
      expect(p.falt['isRecurring'], true);
      expect(p.falt['recurrence'], {
        'type': 'weekly',
        'startDate': '2026-09-24',
        'endDate': '2026-12-17',
        'exceptions': <String>[],
      });
    });

    test('upprepning tills vidare har endDate null', () {
      final rec =
          bygg(utkast(upprepning: 'biweekly')).falt['recurrence'] as Map;
      expect(rec.containsKey('endDate'), isTrue);
      expect(rec['endDate'], isNull);
    });

    test('undantag bevaras vid redigering', () {
      // Ett borttaget tillfälle ligger i exceptions. Tappas de dyker det upp
      // igen. Här skrivs exceptions inte alls, och påminnelserna får dem.
      final p = bygg(utkast(upprepning: 'weekly'), original: {
        'date': '2026-09-24',
        'isRecurring': true,
        'recurrence': {
          'type': 'weekly',
          'startDate': '2026-09-24',
          'exceptions': ['2026-10-01', '2026-10-15'],
        },
      });
      expect(p.falt.keys.where((k) => k.startsWith('recurrence')), isEmpty);
      expect((p.forPaminnelser['recurrence'] as Map)['exceptions'],
          ['2026-10-01', '2026-10-15']);
    });

    test('upprepning avstängd vid redigering tar bort serien', () {
      final p = bygg(utkast(upprepning: 'none'), original: {
        'isRecurring': true,
        'recurrence': {'type': 'weekly'},
      });
      expect(p.taBort, containsAll(['isRecurring', 'recurrence']));
    });

    test('både persons och personUids skrivs', () {
      final p = bygg(utkast(deltagare: [leo, nina]));
      expect(p.falt['persons'], ['Leo', 'Nina']);
      expect(p.falt['personUids'], ['leo', 'nina']);
    });

    test('titel trimmas och tomt piktogram blir kalender', () {
      final p = bygg(utkast(titel: '  Fotboll  ', piktogram: ''));
      expect(p.falt['title'], 'Fotboll');
      expect(p.falt['piktogram'], '📅');
    });

    test('valt piktogram behålls', () {
      expect(bygg(utkast(piktogram: '⚽')).falt['piktogram'], '⚽');
    });

    test('datum och startdatum följer formulärets datum', () {
      final p = bygg(utkast(datum: DateTime(2026, 9, 25), upprepning: 'weekly'));
      expect(p.falt['date'], '2026-09-25');
      expect((p.falt['recurrence'] as Map)['startDate'], '2026-09-25');
    });
  });

  group('Packlistan skrivs inte över i onödan', () {
    test('oförändrad packlista skickas inte vid redigering', () {
      final original = {
        'checklist': [
          {'item': 'Kamera', 'isDone': true},
          'Matsäck',
        ],
      };
      final inlast = lasPacklista(original);
      final p = bygg(utkast(titel: 'Ny titel', packlista: inlast),
          original: original);
      expect(p.falt.containsKey('checklist'), isFalse);
      expect(p.taBort, isNot(contains('checklist')));
      expect(p.packlistanAndrad, isFalse);
    });

    test('ändrad packlista sparas för sig, inte i update', () {
      final original = {
        'checklist': [
          {'item': 'Kamera', 'isDone': false},
        ],
      };
      final andrad = [...lasPacklista(original), const PacklistRad('Matsäck')];
      final p = bygg(utkast(packlista: andrad), original: original);
      expect(p.falt.containsKey('checklist'), isFalse);
      expect(p.packlistanAndrad, isTrue);
      expect(p.packlista, andrad);
    });

    test('borttagen rad räknas som ändring', () {
      final original = {
        'checklist': [
          {'item': 'Kamera'},
          {'item': 'Matsäck'},
        ],
      };
      final p = bygg(utkast(packlista: lasPacklista(original).take(1).toList()),
          original: original);
      expect(p.packlistanAndrad, isTrue);
    });

    test('ny aktivitet skickar alltid packlistan', () {
      expect(bygg(utkast()).falt['checklist'], <dynamic>[]);
      final p = bygg(utkast(packlista: const [PacklistRad('Kamera')]));
      expect(p.falt['checklist'], [
        {'item': 'Kamera', 'isDone': false},
      ]);
    });

    test('packlistan läses i alla former', () {
      final raw = {
        'checklist': [
          {'item': 'Kamera', 'isDone': true},
          'Matsäck',
          {'item': '   '},
          {'text': 'Vatten'},
        ],
      };
      expect(lasPacklista(raw), const [
        PacklistRad('Kamera', klar: true, ursprungIndex: 0),
        PacklistRad('Matsäck', ursprungIndex: 1),
        PacklistRad('Vatten', ursprungIndex: 3),
      ]);
    });
  });

  group('Förberedelse dagen innan', () {
    test('förberedelse påslagen skrivs', () {
      final p = bygg(utkast(prepAktiv: true, prepText: 'Packa gympapåsen'));
      expect(p.falt[LessonPrep.field],
          {'text': 'Packa gympapåsen', 'doneDates': <String>[]});
    });

    test('förberedelse avstängd vid redigering tas bort', () {
      final original = {LessonPrep.field: LessonPrep.withText({}, 'Packa')};
      expect(bygg(utkast(), original: original).taBort,
          contains(LessonPrep.field));
    });

    test('förberedelse med tom text skrivs inte', () {
      final p = bygg(utkast(prepAktiv: true, prepText: '  '));
      expect(p.falt.containsKey(LessonPrep.field), isFalse);
    });

    test('ändrad text skriver bara texten, avbockningarna rörs inte', () {
      final original = {
        LessonPrep.field: {
          'text': 'Packa',
          'doneDates': ['2026-09-21'],
        },
      };
      final p = bygg(utkast(prepAktiv: true, prepText: 'Packa väskan'),
          original: original);
      expect(p.falt['lessonPrep.text'], 'Packa väskan');
      expect(p.falt.containsKey(LessonPrep.field), isFalse);
      expect(p.forPaminnelser[LessonPrep.field],
          {'text': 'Packa väskan', 'doneDates': ['2026-09-21']});
    });

    test('oförändrad förberedelse skrivs inte alls', () {
      final original = {
        LessonPrep.field: {
          'text': 'Packa',
          'doneDates': ['2026-09-28', '2026-09-21'],
        },
      };
      final p =
          bygg(utkast(prepAktiv: true, prepText: 'Packa'), original: original);
      expect(p.falt.keys.where((k) => k.startsWith(LessonPrep.field)), isEmpty);
      expect(p.taBort, isNot(contains(LessonPrep.field)));
    });

    test('påslagen vid redigering av aktivitet utan förberedelse', () {
      final p = bygg(utkast(prepAktiv: true, prepText: 'Packa'),
          original: {'title': 'Tandläkare'});
      expect(p.falt[LessonPrep.field], {'text': 'Packa', 'doneDates': <String>[]});
    });
  });

  test('påminnelseunderlaget innehåller inga borttagningar', () {
    final p = bygg(utkast(), original: {'endTime': '16:00', 'timeMode': 'allDay'});
    expect(p.forPaminnelser.keys.where(p.taBort.contains), isEmpty);
    expect(p.forPaminnelser['time'], '15:00');
    expect(p.forPaminnelser['title'], 'Tandläkare');
  });

  group('Heldag och tid inte bestämd', () {
    AktivitetUtkast lage(Tidslage l, {TimeOfDay? slut}) =>
        utkast(tidslage: l, slut: slut);

    test('heldag skriver tom tid och timeMode allDay', () {
      final p = bygg(lage(Tidslage.heldag));
      expect(p.falt['time'], '');
      expect(p.falt['timeMode'], 'allDay');
    });

    test('tid inte bestämd skriver tom tid och timeMode undecided', () {
      final p = bygg(lage(Tidslage.obestamd));
      expect(p.falt['time'], '');
      expect(p.falt['timeMode'], 'undecided');
    });

    test('utan klockslag krävs ingen starttid', () {
      final p = bygg(utkast(start: null, tidslage: Tidslage.heldag));
      expect(p.falt['time'], '');
    });

    test('klockslag utan starttid är ett programmeringsfel', () {
      expect(() => bygg(utkast(start: null)), throwsArgumentError);
    });

    test('utan klockslag skrivs ingen sluttid även om en fanns i formuläret',
        () {
      final ny = bygg(lage(Tidslage.heldag,
          slut: const TimeOfDay(hour: 16, minute: 0)));
      expect(ny.falt.containsKey('endTime'), isFalse);

      final redigerad = bygg(
        lage(Tidslage.obestamd, slut: const TimeOfDay(hour: 16, minute: 0)),
        original: {'time': '15:00', 'endTime': '16:00'},
      );
      expect(redigerad.falt.containsKey('endTime'), isFalse);
      expect(redigerad.taBort, contains('endTime'));
      expect(redigerad.falt['time'], '');
    });

    test('inget tidsläge ger klockslagspåminnelse', () {
      for (final l in [Tidslage.heldag, Tidslage.obestamd]) {
        for (final upprepning in ['none', 'weekly']) {
          final p = bygg(lage(l).copyWith(upprepning: upprepning));
          final tid = ((p.forPaminnelser['time'] as String?) ?? '').trim();
          expect(tid, '', reason: '$l, $upprepning');
          expect(tid.split(':').length < 2, isTrue);
        }
      }
    });

    test('klockslag vid redigering tar bort timeMode', () {
      final p = bygg(utkast(), original: {'time': '', 'timeMode': 'allDay'});
      expect(p.falt['time'], '15:00');
      expect(p.falt.containsKey('timeMode'), isFalse);
      expect(p.taBort, contains('timeMode'));
    });

    test('klockslag utan timeMode i dokumentet skickar ingen ny borttagning',
        () {
      final p = bygg(utkast(), original: {'time': '10:00'});
      expect(p.taBort, isNot(contains('timeMode')));
    });

    test('byte mellan heldag och tid inte bestämd skriver om timeMode', () {
      final p = bygg(lage(Tidslage.obestamd),
          original: {'time': '', 'timeMode': 'allDay'});
      expect(p.falt['timeMode'], 'undecided');
      expect(p.taBort, isNot(contains('timeMode')));
    });

    test('heldag som upprepas behåller upprepningen', () {
      final p = bygg(lage(Tidslage.heldag).copyWith(upprepning: 'weekly'));
      expect(p.falt['isRecurring'], true);
      expect((p.falt['recurrence'] as Map)['type'], 'weekly');
    });

    test('klockslagsläget skriver inget nytt fält', () {
      const kanda = {
        'title', 'piktogram', 'type', 'date', 'time', 'persons',
        'personUids', 'checklist', 'source', 'createdBy', 'isPending',
        'familyId', 'createdByUid', 'endTime', 'isRecurring', 'recurrence',
        LessonPrep.field,
      };
      final p = bygg(utkast(
        slut: const TimeOfDay(hour: 16, minute: 0),
        upprepning: 'weekly',
        prepAktiv: true,
        prepText: 'x',
      ));
      expect(p.falt.keys.toSet().difference(kanda), isEmpty);
    });
  });

  group('Redigering skriver bara det som ändrats', () {
    final importerad = <String, dynamic>{
      'title': 'Gympa',
      'piktogram': '📚',
      'type': 'activity',
      'date': '2026-09-21',
      'time': '09:00',
      'endTime': '10:00',
      'persons': ['Leo'],
      'personUids': ['leo'],
      'checklist': <dynamic>[],
      'source': 'calendar',
      'planningImportKind': 'schedule',
      'calendarName': 'Skolschema',
      'calendarImportId': 'imp1',
      'icsKey': 'photo|2026-09-21|09:00|gympa',
      'createdBy': 'mamma',
      'createdByUid': 'mamma',
      'isPending': false,
      'familyId': 'fam',
      'sourceNoteId': 'not1',
    };

    AktivitetUtkast somDokumentet({String titel = 'Gympa'}) => utkast(
          titel: titel,
          piktogram: '📚',
          datum: DateTime(2026, 9, 21),
          start: const TimeOfDay(hour: 9, minute: 0),
          slut: const TimeOfDay(hour: 10, minute: 0),
        );

    test('en titeländring skriver bara titeln', () {
      final p = bygg(somDokumentet(titel: 'Idrott'),
          uid: 'barn', original: importerad);
      expect(p.falt, {'title': 'Idrott'});
      expect(p.taBort, isEmpty);
      expect(p.packlistanAndrad, isFalse);
    });

    test('en importerad aktivitet förblir importerad', () {
      final p = bygg(somDokumentet(titel: 'Idrott'),
          uid: 'barn', original: importerad);
      for (final f in ursprungsFalt) {
        expect(p.falt.containsKey(f), isFalse, reason: f);
        expect(p.taBort.contains(f), isFalse, reason: f);
      }
    });

    test('ingen ändring ger en tom redigering', () {
      final p = bygg(somDokumentet(), original: importerad);
      expect(p.tomRedigering, isTrue);
    });

    test('saknat type skrivs, som Android', () {
      // Servern (note_confirm.js) skapar aktiviteter utan type.
      final utanType = Map<String, dynamic>.of(importerad)..remove('type');
      expect(bygg(somDokumentet(), original: utanType).falt, {'type': 'activity'});
    });

    test('familjen byts aldrig av en redigering', () {
      final p = byggAktivitetPayload(
          utkast: somDokumentet(), uid: 'mig', familyId: '', original: importerad);
      expect(p.falt.containsKey('familyId'), isFalse);
    });

    test('ändrad sluttid, utan sluttid och byte till heldag', () {
      final p = bygg(somDokumentet().copyWith(tidslage: Tidslage.heldag),
          original: importerad);
      expect(p.falt, {'time': '', 'timeMode': 'allDay'});
      expect(p.taBort, {'endTime'});
    });

    test('importerad heldag öppnad och sparad utan ändring får timeMode', () {
      final lov = {
        ...importerad,
        'time': '',
        'endTime': '00:00',
      };
      expect(Tidslage.las(lov), Tidslage.heldag);
      final p = bygg(
          utkast(
            titel: 'Gympa',
            piktogram: '📚',
            datum: DateTime(2026, 9, 21),
            start: null,
            tidslage: Tidslage.heldag,
          ),
          original: lov);
      expect(p.falt, {'timeMode': 'allDay'});
      expect(p.taBort, {'endTime'});
      expect(p.falt.containsKey('source'), isFalse);
    });
  });

  group('Upprepning vid redigering', () {
    final serie = <String, dynamic>{
      'title': 'Fotboll',
      'piktogram': '⚽',
      'type': 'activity',
      'date': '2026-09-24',
      'time': '17:00',
      'persons': ['Leo'],
      'personUids': ['leo'],
      'isPending': false,
      'familyId': 'fam',
      'isRecurring': true,
      'recurrence': {
        'type': 'weekly',
        'startDate': '2026-09-24',
        'endDate': null,
        'exceptions': ['2026-10-01'],
      },
    };

    AktivitetUtkast somSerien({
      String upprepning = 'weekly',
      DateTime? slut,
      String titel = 'Fotboll',
    }) =>
        utkast(
          titel: titel,
          piktogram: '⚽',
          start: const TimeOfDay(hour: 17, minute: 0),
          upprepning: upprepning,
          upprepningSlut: slut,
        );

    test('en titeländring rör inte recurrence', () {
      final p = bygg(somSerien(titel: 'Fotbollsträning'), original: serie);
      expect(p.falt, {'title': 'Fotbollsträning'});
      expect(p.tillFirestore().keys.where((k) => k.startsWith('recurrence')),
          isEmpty);
    });

    test('nytt slutdatum skrivs som fältsökväg, undantagen rörs inte', () {
      final p = bygg(somSerien(slut: DateTime(2026, 12, 17)), original: serie);
      expect(p.falt, {'recurrence.endDate': '2026-12-17'});
      expect(p.falt.keys.any((k) => k.contains('exceptions')), isFalse);
    });

    test('ny typ skrivs som fältsökväg', () {
      final p = bygg(somSerien(upprepning: 'biweekly'), original: serie);
      expect(p.falt, {'recurrence.type': 'biweekly'});
    });

    test('daily bevaras när något annat ändras', () {
      final daglig = {
        ...serie,
        'recurrence': {
          'type': 'daily',
          'startDate': '2026-09-24',
          'exceptions': <String>[],
        },
      };
      final p = bygg(somSerien(upprepning: 'daily', titel: 'Läxor'),
          original: daglig);
      expect(p.falt, {'title': 'Läxor'});
      expect((p.forPaminnelser['recurrence'] as Map)['type'], 'daily');
    });

    test('en engångsaktivitet som börjar upprepas får hela blocket', () {
      final engang = Map<String, dynamic>.of(serie)
        ..remove('isRecurring')
        ..remove('recurrence');
      final p = bygg(somSerien(), original: engang);
      expect(p.falt, {
        'isRecurring': true,
        'recurrence': {
          'type': 'weekly',
          'startDate': '2026-09-24',
          'endDate': null,
          'exceptions': <String>[],
        },
      });
    });
  });

  test('tillFirestore gör borttagningar till FieldValue.delete()', () {
    final p = bygg(utkast(), original: {'endTime': '16:00', 'timeMode': 'allDay'});
    final data = p.tillFirestore();
    expect(data['endTime'], isA<FieldValue>());
    expect(data['timeMode'], isA<FieldValue>());
    expect(data['time'], '15:00');
  });

  test('mallen innehåller bara texterna', () {
    expect(
      aktivitetsmall(
        titel: ' Simning ',
        piktogram: '',
        packlista: const [PacklistRad('Handduk', klar: true)],
        familyId: 'fam',
      ),
      {
        'title': 'Simning',
        'piktogram': '📅',
        'checklist': ['Handduk'],
        'familyId': 'fam',
      },
    );
  });
}
