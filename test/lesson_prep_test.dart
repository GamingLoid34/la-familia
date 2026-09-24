import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/utils/lesson_prep.dart';

/// Förberedelse inför återkommande lektioner, avbockad per tillfälle.
///
/// Portad från Androids `LessonPrepTest` och serienyckeltesterna i
/// `TomorrowOverviewLessonPrepTest`.
void main() {
  // Måndag 21 september 2026.
  final mandag = DateTime(2026, 9, 21);
  final nastaMandag = DateTime(2026, 9, 28);

  Map<String, dynamic> gympa({
    String? prepText = 'Packa gympapåsen',
    List<String> doneDates = const [],
    String? endDate,
    List<String> exceptions = const [],
    String startDate = '2026-09-21',
  }) {
    final rec = <String, dynamic>{
      'type': 'weekly',
      'startDate': startDate,
      'endDate': ?endDate,
      if (exceptions.isNotEmpty) 'exceptions': exceptions,
    };
    return {
      'title': 'Gympa',
      'date': startDate,
      'time': '09:00',
      'personUids': ['leandro'],
      'recurrence': rec,
      if (prepText != null)
        LessonPrep.field: {'text': prepText, 'doneDates': doneDates},
    };
  }

  group('Grundläggande', () {
    test('utan fält finns ingen förberedelse', () {
      final utan = gympa(prepText: null);
      expect(LessonPrep.textOf(utan), isNull);
      expect(LessonPrep.isEnabled(utan), isFalse);
      expect(LessonPrep.showsForLesson(utan, mandag), isFalse);
    });

    test('tom text räknas som ingen förberedelse', () {
      final tom = gympa(prepText: '   ');
      expect(LessonPrep.isEnabled(tom), isFalse);
      expect(LessonPrep.showsForLesson(tom, mandag), isFalse);
    });

    test('påslagen förberedelse visas kvällen före lektionen', () {
      expect(LessonPrep.showsForLesson(gympa(), mandag), isTrue);
      expect(LessonPrep.textOf(gympa()), 'Packa gympapåsen');
    });
  });

  group('Flera tillfällen och avbockning', () {
    test('förberedelsen återkommer varje vecka', () {
      final lektion = gympa();
      expect(LessonPrep.showsForLesson(lektion, mandag), isTrue);
      expect(LessonPrep.showsForLesson(lektion, nastaMandag), isTrue);
      expect(LessonPrep.showsForLesson(lektion, DateTime(2026, 10, 26)), isTrue);
    });

    test('avbockning gäller BARA det tillfället', () {
      final lektion = gympa(doneDates: ['2026-09-21']);
      expect(LessonPrep.showsForLesson(lektion, mandag), isFalse,
          reason: 'måndagen ska vara avbockad');
      expect(LessonPrep.showsForLesson(lektion, nastaMandag), isTrue,
          reason: 'nästa måndag ska ha en egen');
    });

    test('en återkommande förberedelse blir aldrig klar för gott', () {
      var lektion = gympa();
      for (var v = 0; v < 5; v++) {
        final dag = DateTime(2026, 9, 21 + 7 * v);
        expect(LessonPrep.showsForLesson(lektion, dag), isTrue);
        lektion = {
          ...lektion,
          LessonPrep.field: LessonPrep.toggled(lektion, dag, done: true),
        };
        expect(LessonPrep.showsForLesson(lektion, dag), isFalse);
      }
      expect(LessonPrep.showsForLesson(lektion, DateTime(2026, 10, 26)), isTrue);
    });

    test('avbockning går att ångra', () {
      final lektion = gympa(doneDates: ['2026-09-21']);
      expect(LessonPrep.toggled(lektion, mandag, done: false)['doneDates'],
          <String>[]);
    });

    test('avbockning behåller texten', () {
      final efter = LessonPrep.toggled(gympa(), mandag, done: true);
      expect(efter['text'], 'Packa gympapåsen');
      expect(efter['doneDates'], ['2026-09-21']);
    });

    test('upprepad avbockning ger inga dubbletter', () {
      final lektion = gympa(doneDates: ['2026-09-21']);
      expect(LessonPrep.toggled(lektion, mandag, done: true)['doneDates'],
          ['2026-09-21']);
    });

    test('avbockade datum sorteras', () {
      final lektion = gympa(doneDates: ['2026-10-05', '2026-09-21']);
      expect(LessonPrep.toggled(lektion, nastaMandag, done: true)['doneDates'],
          ['2026-09-21', '2026-09-28', '2026-10-05']);
    });

    test('skrivningen lägger bara till eller tar bort ett datum', () {
      final pa = LessonPrep.toggleUpdate(mandag, done: true);
      expect(pa.keys, ['lessonPrep.doneDates']);
      expect(pa['lessonPrep.doneDates'], isA<FieldValue>());
      final av = LessonPrep.toggleUpdate(mandag, done: false);
      expect(av.keys, ['lessonPrep.doneDates']);
      expect(av['lessonPrep.doneDates'], isA<FieldValue>());
    });
  });

  group('Schemats gränser', () {
    test('efter slutdatum visas ingen förberedelse', () {
      final terminslut = gympa(endDate: '2026-10-05');
      expect(LessonPrep.showsForLesson(terminslut, DateTime(2026, 10, 5)), isTrue);
      expect(
          LessonPrep.showsForLesson(terminslut, DateTime(2026, 10, 12)), isFalse);
    });

    test('inställt tillfälle ger ingen förberedelse', () {
      final medUndantag = gympa(exceptions: ['2026-09-28']);
      expect(LessonPrep.showsForLesson(medUndantag, mandag), isTrue);
      expect(LessonPrep.showsForLesson(medUndantag, nastaMandag), isFalse);
      expect(LessonPrep.showsForLesson(medUndantag, DateTime(2026, 10, 5)),
          isTrue);
    });

    test('före seriens start visas ingenting', () {
      final lektion = gympa(startDate: '2026-09-28');
      expect(LessonPrep.showsForLesson(lektion, mandag), isFalse);
      expect(LessonPrep.showsForLesson(lektion, nastaMandag), isTrue);
    });

    test('fel veckodag ger ingen förberedelse', () {
      expect(LessonPrep.showsForLesson(gympa(), DateTime(2026, 9, 22)), isFalse);
    });

    test('flyttad lektion följer med till nytt datum', () {
      final flyttad = gympa(startDate: '2026-09-22');
      expect(LessonPrep.showsForLesson(flyttad, mandag), isFalse);
      expect(LessonPrep.showsForLesson(flyttad, DateTime(2026, 9, 22)), isTrue);
    });
  });

  test('fungerar även för en lektion utan återkomst', () {
    final engangs = <String, dynamic>{
      'title': 'Temadag',
      'date': '2026-09-21',
      LessonPrep.field: {'text': 'Ta med kamera', 'doneDates': <String>[]},
    };
    expect(LessonPrep.showsForLesson(engangs, mandag), isTrue);
    expect(LessonPrep.showsForLesson(engangs, nastaMandag), isFalse);
  });

  group('Åtskilda serier', () {
    test('två barns lektioner har varsin förberedelse', () {
      final leandro = gympa(doneDates: ['2026-09-21']);
      final emilio = gympa();
      expect(LessonPrep.showsForLesson(leandro, mandag), isFalse);
      expect(LessonPrep.showsForLesson(emilio, mandag), isTrue);
    });

    test('samma barn kan ha olika texter på olika lektioner', () {
      expect(LessonPrep.textOf(gympa(prepText: 'Packa gympapåsen')),
          'Packa gympapåsen');
      expect(LessonPrep.textOf(gympa(prepText: 'Ta med virket')),
          'Ta med virket');
    });
  });

  group('Ändra och stänga av', () {
    test('texten går att ändra utan att tappa avbockningar', () {
      final ny = LessonPrep.withText(
          gympa(doneDates: ['2026-09-21']), 'Packa gympapåsen och vattenflaska');
      expect(ny['text'], 'Packa gympapåsen och vattenflaska');
      expect(ny['doneDates'], ['2026-09-21']);
    });

    test('texten trimmas', () {
      expect(LessonPrep.withText(gympa(), '  Packa väskan  ')['text'],
          'Packa väskan');
    });
  });

  group('Serienyckeln', () {
    Map<String, dynamic> lektion({
      String title = 'Gympa',
      String person = 'leandro',
      String date = '2026-09-21',
    }) =>
        {
          'title': title,
          'date': date,
          'personUids': [person],
          'calendarImportId': 'imp1',
        };

    test('serienyckeln skiljer barn åt', () {
      expect(LessonPrep.seriesKey(lektion(person: 'leandro'), 'a'),
          isNot(LessonPrep.seriesKey(lektion(person: 'emilio'), 'b')));
    });

    test('serienyckeln är samma för två tillfällen i samma serie', () {
      expect(LessonPrep.seriesKey(lektion(date: '2026-09-21'), 'a'),
          LessonPrep.seriesKey(lektion(date: '2026-09-28'), 'b'));
    });

    test('serienyckeln skiljer olika lektioner åt', () {
      expect(LessonPrep.seriesKey(lektion(title: 'Gympa'), 'a'),
          isNot(LessonPrep.seriesKey(lektion(title: 'Slöjd'), 'b')));
    });

    test('titeln normaliseras', () {
      expect(LessonPrep.seriesKey(lektion(title: 'Gympa'), 'a'),
          LessonPrep.seriesKey(lektion(title: ' gympa '), 'b'));
    });

    test('manuell lektion utan import använder sitt eget id', () {
      expect(
          LessonPrep.seriesKey({'title': 'Gympa', 'date': '2026-09-21'}, 'abc'),
          'abc');
    });
  });
}
