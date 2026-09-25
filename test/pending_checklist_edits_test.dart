// Packlistan utan nät (granskning 2026-09-25, punkt 1): en ändring gjord i
// Flutter utan nät får inte skriva över en avbockning som Android gjort under
// tiden. Ändringen sparas som (ursprung, formulärets lista) och slås ihop mot
// serverns senaste version när den väl körs — aldrig som en hel lista från
// telefonens kopia.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/utils/checklist_updates.dart';
import 'package:la_familia/utils/pending_checklist_edits.dart';

void main() {
  final original = <dynamic>[
    {'item': 'Benskydd', 'isDone': false, 'rowId': 'r1', 'addedAt': Timestamp.fromMillisecondsSinceEpoch(1000)},
    {'item': 'Vattenflaska', 'isDone': false},
    'Handduk',
  ];
  // Formuläret (utan nät): lägger till en rad och byter namn på en.
  final edited = [
    const PacklistRad('Benskydd', ursprungIndex: 0),
    const PacklistRad('Vattenflaska 1 l', ursprungIndex: 1),
    const PacklistRad('Handduk', ursprungIndex: 2),
    const PacklistRad('Matsäck'),
  ];

  test('kön bevarar ursprung, index och radernas extra fält', () {
    final raw = PendingChecklistEdits.encode({
      'e1': (original: original, edited: edited),
    });
    final back = PendingChecklistEdits.decode(raw)['e1']!;
    expect(back.edited, edited);
    expect(back.original, original);
    expect((back.original.first as Map)['addedAt'], isA<Timestamp>());
  });

  test('en avbockning i Android medan Flutter saknade nät överlever', () {
    final queued = PendingChecklistEdits.decode(PendingChecklistEdits.encode({
      'e1': (original: original, edited: edited),
    }))['e1']!;
    // Serverns version när nätet kommer tillbaka: Android har bockat två rader.
    final latest = <dynamic>[
      {'item': 'Benskydd', 'isDone': true, 'rowId': 'r1', 'addedAt': Timestamp.fromMillisecondsSinceEpoch(1000)},
      {'item': 'Vattenflaska', 'isDone': true},
      'Handduk',
    ];
    final merged = mergeChecklist(
      latestRows: latest,
      originalRows: queued.original,
      editedRows: queued.edited,
    );
    expect(checklistIsDone(merged[0]), isTrue, reason: 'Androids bock på Benskydd');
    expect((merged[0] as Map)['rowId'], 'r1');
    expect(checklistTextOf(merged[1]), 'Vattenflaska 1 l');
    expect(checklistIsDone(merged[1]), isTrue, reason: 'bocken följer med namnbytet');
    expect(checklistTextOf(merged.last), 'Matsäck');
    expect(merged.length, 4);
  });

  test('uppspelning två gånger lägger inte till raden igen', () {
    final once = mergeChecklist(
        latestRows: original, originalRows: original, editedRows: edited);
    final twice = mergeChecklist(
        latestRows: once, originalRows: original, editedRows: edited);
    expect(twice.where((r) => checklistTextOf(r) == 'Matsäck').length, 1);
  });

  test('trasig lagring ger tom kö i stället för krasch', () {
    expect(PendingChecklistEdits.decode('{inte json'), isEmpty);
    expect(PendingChecklistEdits.decode(null), isEmpty);
  });
}
