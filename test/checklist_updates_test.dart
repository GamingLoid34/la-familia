import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/utils/aktivitet_payload.dart';
import 'package:la_familia/utils/checklist_updates.dart';

/// Packlistan utan att skriva över andras avbockningar.
///
/// Första gruppen är portad från Androids `ChecklistUpdatesTest`. Resten
/// prövar [mergeChecklist], formulärets redigering mot den senaste versionen.
void main() {
  group('Avbockning (Android)', () {
    test('bockning bevarar färska fält och andras redan bockade rader', () {
      final fresh = [
        {'item': 'Skor', 'isDone': true},
        {'item': 'Matsäck', 'isDone': false, 'extra': 'bevaras'},
      ];
      final result = completeChecklistRow(fresh, 1, 'Matsäck');
      expect(result[0], fresh[0]);
      expect(result[1], {'item': 'Matsäck', 'isDone': true, 'extra': 'bevaras'});
      expect(completeChecklistRow(result, 1, 'Matsäck'), result);
    });

    test('omflyttad eller borttagen rad avvisas i stället för att bocka en annan',
        () {
      final changed = [
        {'item': 'Vatten', 'isDone': false},
      ];
      expect(() => completeChecklistRow(changed, 0, 'Skor'),
          throwsA(isA<ChecklistChangedException>()));
      expect(() => completeChecklistRow(changed, 1, 'Skor'),
          throwsA(isA<ChecklistChangedException>()));
    });

    test('meddelandet går att visa som det är', () {
      try {
        completeChecklistRow(const [], 0, 'Skor');
        fail('ska kasta');
      } on ChecklistChangedException catch (e) {
        expect(e.message,
            'Packlistan har ändrats. Öppna aktiviteten och försök igen.');
      }
    });

    test('en strängrad kan bockas och blir då en map', () {
      final rows = [
        'Stövlar',
        {'item': 'Matsäck', 'isDone': false},
      ];
      final result = completeChecklistRow(rows, 0, 'Stövlar');
      expect(result[0], {'item': 'Stövlar', 'isDone': true});
      expect(result[1], rows[1]);
    });

    test('en rad med text-nyckeln kan bockas', () {
      final rows = [
        {'text': 'Matsäck', 'isDone': false},
      ];
      expect(completeChecklistRow(rows, 0, 'Matsäck').single,
          {'text': 'Matsäck', 'isDone': true});
    });

    test('textOf och isDone tolkar alla tre radformat', () {
      expect(checklistTextOf({'item': ' Skor '}), 'Skor');
      expect(checklistTextOf({'text': 'Skor'}), 'Skor');
      expect(checklistTextOf('Skor'), 'Skor');
      expect(checklistTextOf({'item': '   '}), isNull);
      expect(checklistTextOf(42), isNull);
      expect(checklistIsDone({'item': 'Skor', 'isDone': true}), isTrue);
      expect(checklistIsDone('Skor'), isFalse);
    });

    test('en bock kan ångras utan att andra rader rörs', () {
      final rows = [
        {'item': 'Skor', 'isDone': true, 'av': 'mamma'},
        'Matsäck',
      ];
      final result = setChecklistRowDone(rows, 0, 'Skor', done: false);
      expect(result[0], {'item': 'Skor', 'isDone': false, 'av': 'mamma'});
      expect(result[1], 'Matsäck');
    });
  });

  group('mergeChecklist', () {
    List<dynamic> merge(
      List<dynamic> latest,
      List<dynamic> original,
      List<PacklistRad> edited,
    ) =>
        mergeChecklist(
            latestRows: latest, originalRows: original, editedRows: edited);

    final original = <dynamic>[
      {'item': 'Kamera', 'isDone': false, 'radId': 'a'},
      'Matsäck',
      {'text': 'Vatten', 'isDone': true},
    ];

    List<PacklistRad> inlast() => lasPacklista({'checklist': original});

    test('oförändrad lista ger den senaste listan exakt', () {
      // Någon bockade Kamera medan formuläret stod öppet.
      final latest = [
        {'item': 'Kamera', 'isDone': true, 'radId': 'a', 'av': 'pappa'},
        'Matsäck',
        {'text': 'Vatten', 'isDone': true},
      ];
      final result = merge(latest, original, inlast());
      expect(result, latest);
      expect(checklistRowsEqual(result, latest), isTrue);
    });

    test('ny rad läggs till utan att andras bockar nollställs', () {
      final latest = [
        {'item': 'Kamera', 'isDone': true, 'radId': 'a'},
        'Matsäck',
        {'text': 'Vatten', 'isDone': true},
      ];
      final result =
          merge(latest, original, [...inlast(), const PacklistRad('Handduk')]);
      expect(result, [
        ...latest,
        {'item': 'Handduk', 'isDone': false},
      ]);
    });

    test('borttagen rad tas bort, övriga rader behåller sin form', () {
      final edited = inlast()..removeAt(1);
      final result = merge(original, original, edited);
      expect(result, [original[0], original[2]]);
    });

    test('namnbyte behåller format, isDone och extra fält', () {
      final latest = [
        {'item': 'Kamera', 'isDone': true, 'radId': 'a'},
        'Matsäck',
        {'text': 'Vatten', 'isDone': true},
      ];
      final e = inlast();
      e[0] = e[0].medText('Kamera och laddare');
      e[1] = e[1].medText('Matsäck och kex');
      e[2] = e[2].medText('Vattenflaska');
      expect(merge(latest, original, e), [
        {'item': 'Kamera och laddare', 'isDone': true, 'radId': 'a'},
        'Matsäck och kex',
        {'text': 'Vattenflaska', 'isDone': true},
      ]);
    });

    test('rader som någon annan lagt till under tiden behålls', () {
      // T.ex. serverns add_checklist_item från inkorgen.
      final latest = [
        ...original,
        {'item': 'Regnjacka', 'isDone': false, 'sourceNoteId': 'n1'},
      ];
      final edited = inlast()..removeAt(0);
      expect(merge(latest, original, edited), [
        'Matsäck',
        {'text': 'Vatten', 'isDone': true},
        {'item': 'Regnjacka', 'isDone': false, 'sourceNoteId': 'n1'},
      ]);
    });

    test('en rad borttagen av någon annan kommer inte tillbaka', () {
      final latest = [original[0], original[2]];
      final result =
          merge(latest, original, [...inlast(), const PacklistRad('Handduk')]);
      expect(result, [
        original[0],
        original[2],
        {'item': 'Handduk', 'isDone': false},
      ]);
    });

    test('en namnbytt rad som någon annan tagit bort läggs till som ny', () {
      final latest = [original[1], original[2]];
      final e = inlast();
      e[0] = e[0].medText('Kamera och laddare');
      final result = merge(latest, original, e);
      expect(result, [
        {'item': 'Kamera och laddare', 'isDone': false},
        'Matsäck',
        {'text': 'Vatten', 'isDone': true},
      ]);
    });

    test('omflyttade rader hittas på text', () {
      final latest = [
        {'text': 'Vatten', 'isDone': true},
        {'item': 'Kamera', 'isDone': true, 'radId': 'a'},
        'Matsäck',
      ];
      final edited = inlast()..removeAt(1); // Matsäck bort
      expect(merge(latest, original, edited), [
        {'text': 'Vatten', 'isDone': true},
        {'item': 'Kamera', 'isDone': true, 'radId': 'a'},
      ]);
    });

    test('dubbletter hålls isär via index', () {
      final orig = <dynamic>[
        {'item': 'Vatten', 'isDone': true},
        {'item': 'Vatten', 'isDone': false},
      ];
      final edited = lasPacklista({'checklist': orig})..removeAt(1);
      expect(merge(orig, orig, edited), [
        {'item': 'Vatten', 'isDone': true},
      ]);
      final edited2 = lasPacklista({'checklist': orig})..removeAt(0);
      expect(merge(orig, orig, edited2), [
        {'item': 'Vatten', 'isDone': false},
      ]);
    });

    test('samma nya rad som någon annan redan lagt till läggs inte till igen',
        () {
      final latest = [
        ...original,
        {'item': 'Handduk', 'isDone': true},
      ];
      final result =
          merge(latest, original, [...inlast(), const PacklistRad('Handduk')]);
      expect(result, latest);
    });

    test('ny rad mitt i listan hamnar på sin plats', () {
      final e = inlast()..insert(1, const PacklistRad('Kex'));
      expect(merge(original, original, e), [
        original[0],
        {'item': 'Kex', 'isDone': false},
        original[1],
        original[2],
      ]);
    });

    test('ny rad först i listan', () {
      final e = [const PacklistRad('Kex'), ...inlast()];
      expect(merge(original, original, e).first, {'item': 'Kex', 'isDone': false});
    });

    test('formulärets klar skrivs aldrig på befintliga rader', () {
      final e = [
        for (final r in inlast())
          PacklistRad(r.text, klar: !r.klar, ursprungIndex: r.ursprungIndex),
      ];
      expect(merge(original, original, e), original);
    });

    test('rader utan index matchas på text', () {
      // Ett formulär som byggt listan utan ursprungIndex.
      final latest = [
        {'item': 'Kamera', 'isDone': true, 'radId': 'a'},
        'Matsäck',
        {'text': 'Vatten', 'isDone': true},
      ];
      final e = const [
        PacklistRad('Kamera'),
        PacklistRad('Vatten'),
        PacklistRad('Kex'),
      ];
      expect(merge(latest, original, e), [
        {'item': 'Kamera', 'isDone': true, 'radId': 'a'},
        {'text': 'Vatten', 'isDone': true},
        {'item': 'Kex', 'isDone': false},
      ]);
    });

    test('tom lista i formuläret tar bort ursprungsraderna men inte andras nya',
        () {
      final latest = [...original, 'Regnjacka'];
      expect(merge(latest, original, const []), ['Regnjacka']);
    });

    test('tom text räknas som borttagen rad', () {
      final e = inlast();
      e[1] = e[1].medText('   ');
      expect(merge(original, original, e), [original[0], original[2]]);
    });

    test('tomma och okända rader i den senaste listan lämnas orörda', () {
      final latest = [...original, 42, {'item': ''}];
      expect(merge(latest, original, inlast()), latest);
    });

    test('ursprungslistan från en ny tom aktivitet', () {
      expect(merge(const [], const [], const [PacklistRad('Kamera')]), [
        {'item': 'Kamera', 'isDone': false},
      ]);
    });
  });

  test('checklistRowsEqual jämför djupt', () {
    expect(
        checklistRowsEqual([
          {'item': 'a', 'x': [1, 2]},
        ], [
          {'x': [1, 2], 'item': 'a'},
        ]),
        isTrue);
    expect(checklistRowsEqual(['a'], ['b']), isFalse);
    expect(checklistRowsEqual([{'item': 'a'}], [{'item': 'a', 'isDone': false}]),
        isFalse);
  });
}
