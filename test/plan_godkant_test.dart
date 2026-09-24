// Godkännandekraven i PLAN_VARDAG_FLUTTER.md avsnitt 2, som automatiska test:
// "titeländring i Flutter återställer inte Androids avbockning; överhoppade
// förekomster förblir överhoppade efter redigering."
//
// Vägen är densamma som formuläret (AddEventSheet) tar: dokumentet öppnas som
// formulärtillstånd, titeln ändras, och sparningen byggs med
// byggAktivitetPayload. Packlistan slås ihop mot den senaste versionen med
// mergeChecklist (det saveChecklistEdit gör i sin transaktion).
import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/models/user_model.dart';
import 'package:la_familia/utils/aktivitet_formular.dart';
import 'package:la_familia/utils/aktivitet_payload.dart';
import 'package:la_familia/utils/checklist_updates.dart';
import 'package:la_familia/utils/recurrence.dart';

const _leo = UserModel(
  uid: 'leo',
  name: 'Leo',
  email: 'leo@test',
  color: 'ff2A6F97',
  role: 'child',
  viewMode: 'child',
  energy: 3,
  familyId: 'fam',
);

/// Så som Android skriver en återkommande aktivitet med packlista, där en
/// annan förälder redan bockat av en rad och ett tillfälle hoppats över.
Map<String, dynamic> _androidDokument() => {
      'title': 'Fotboll',
      'piktogram': '⚽',
      'type': 'activity',
      'date': '2026-09-24',
      'time': '17:00',
      'persons': ['Leo'],
      'personUids': ['leo'],
      'checklist': [
        {'item': 'Benskydd', 'isDone': true, 'addedBy': 'android', 'rowId': 'r1'},
        {'item': 'Vattenflaska', 'isDone': false},
      ],
      'source': 'manual',
      'createdBy': 'pappa',
      'createdByUid': 'pappa',
      'isPending': false,
      'familyId': 'fam',
      'isRecurring': true,
      'recurrence': {
        'type': 'weekly',
        'startDate': '2026-09-24',
        'endDate': null,
        'exceptions': ['2026-10-01'],
      },
      'lessonPrep': {
        'text': 'Packa väskan',
        'doneDates': ['2026-09-24'],
      },
    };

AktivitetFormularTillstand _oppna(Map<String, dynamic> doc) =>
    AktivitetFormularTillstand.redigera(
      oppning: FormularRedigering('e1', doc),
      idag: DateTime(2026, 9, 25),
      members: const [_leo],
    );

void main() {
  test('titeländring skriver bara titeln — ingen packlista, inga undantag', () {
    final doc = _androidDokument();
    final form = _oppna(doc).medTitel('Fotbollsträning');
    final p = byggAktivitetPayload(
      utkast: form.tillUtkast(const [_leo]),
      uid: 'mamma',
      familyId: 'fam',
      original: doc,
    );
    expect(p.falt, {'title': 'Fotbollsträning'});
    expect(p.taBort, isEmpty);
    expect(p.packlistanAndrad, isFalse,
        reason: 'packlistan får inte skickas när bara titeln ändrats');
    final skrivs = p.tillFirestore().keys;
    expect(skrivs.any((k) => k.startsWith('checklist')), isFalse);
    expect(skrivs.any((k) => k.startsWith('recurrence')), isFalse);
    expect(skrivs.any((k) => k.startsWith('lessonPrep')), isFalse);
    expect(skrivs.any((k) => k == 'source' || k.startsWith('createdBy')), isFalse);
  });

  test('en avbockning gjord i Android under tiden överlever en ändrad packlista', () {
    final opened = _androidDokument();
    // Någon bockar "Vattenflaska" i Android medan formuläret är öppet.
    final latest = [
      {'item': 'Benskydd', 'isDone': true, 'addedBy': 'android', 'rowId': 'r1'},
      {'item': 'Vattenflaska', 'isDone': true},
    ];
    // I Flutter läggs en rad till och formuläret sparas.
    final form = _oppna(opened).laggTillPackrad('Handduk');
    final merged = mergeChecklist(
      latestRows: latest,
      originalRows: opened['checklist'] as List,
      editedRows: form.packlista,
    );
    expect(merged, [
      {'item': 'Benskydd', 'isDone': true, 'addedBy': 'android', 'rowId': 'r1'},
      {'item': 'Vattenflaska', 'isDone': true},
      {'item': 'Handduk', 'isDone': false},
    ]);
  });

  test('överhoppad förekomst förblir överhoppad efter redigering', () {
    final doc = _androidDokument();
    final form = _oppna(doc).medTitel('Fotbollsträning');
    final p = byggAktivitetPayload(
      utkast: form.tillUtkast(const [_leo]),
      uid: 'mamma',
      familyId: 'fam',
      original: doc,
    );
    // Dokumentet efter sparningen: originalet med de skrivna fälten.
    final after = {...doc, ...p.falt};
    expect(recurringOccursOnDay(after, DateTime(2026, 10, 1)), isFalse);
    expect(recurringOccursOnDay(after, DateTime(2026, 10, 8)), isTrue);
    expect((after['recurrence'] as Map)['exceptions'], ['2026-10-01']);
  });

  test('nytt slutdatum på serien rör inte undantagen', () {
    final doc = _androidDokument();
    final form = _oppna(doc).medUpprepningSlut(DateTime(2026, 12, 17));
    final p = byggAktivitetPayload(
      utkast: form.tillUtkast(const [_leo]),
      uid: 'mamma',
      familyId: 'fam',
      original: doc,
    );
    expect(p.falt, {'recurrence.endDate': '2026-12-17'});
  });

  test('tidlös och heldag behåller sitt läge när titeln ändras', () {
    for (final mode in ['allDay', 'undecided']) {
      final doc = {
        ..._androidDokument(),
        'time': '',
        'timeMode': mode,
      }..remove('recurrence');
      doc.remove('isRecurring');
      final form = _oppna(doc).medTitel('Ny titel');
      expect(form.tidslage.lagring, mode);
      final p = byggAktivitetPayload(
        utkast: form.tillUtkast(const [_leo]),
        uid: 'mamma',
        familyId: 'fam',
        original: doc,
      );
      expect(p.falt, {'title': 'Ny titel'});
      expect(p.taBort, isEmpty);
    }
  });
}
