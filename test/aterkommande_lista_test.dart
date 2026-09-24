import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/models/user_model.dart';
import 'package:la_familia/utils/aterkommande_lista.dart';

/// Listan "Återkommande". Portad från Androids `AterkommandeListaTest`.
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
  final emilio = _medlem('e', 'Emilio Valladares');
  final celine = _medlem('c', 'Céline');
  final members = [emilio, celine];

  const varjeTorsdag = {'type': 'weekly', 'startDate': '2026-09-24'};

  (String, Map<String, dynamic>) event(String id, String title,
          [Map<String, dynamic> extra = const {}]) =>
      (id, {'title': title, 'date': '2026-09-24', ...extra});

  List<AterkommandeRad> bygg(
    List<(String, Map<String, dynamic>)> events, [
    List<(String, Map<String, dynamic>)> chores = const [],
  ]) =>
      byggAterkommandeLista(events: events, chores: chores, members: members);

  test('aktiviteter och sysslor som upprepas visas tillsammans', () {
    final middag = event('m', 'Emilio lagar middag', {
      'time': '17:00',
      'persons': ['Emilio Valladares'],
      'isRecurring': true,
      'recurrence': varjeTorsdag,
    });
    final tvatt = ('t', <String, dynamic>{
      'chore': 'Tvätta ditt eget',
      'isRecurring': true,
      'dueTime': '18:00',
      'who': 'Céline',
      'recurrence': varjeTorsdag,
    });
    final rader = bygg([middag], [tvatt]);

    expect(rader.map((r) => r.titel), ['Emilio lagar middag', 'Tvätta ditt eget']);
    expect(rader[0].typ, AterkommandeTyp.aktivitet);
    expect(rader[0].typ.etikett, 'Aktivitet');
    expect(rader[0].vem, 'Emilio');
    expect(rader[0].nar, 'Varje torsdag 17:00');
    expect(rader[0].piktogram, '📅');
    expect(rader[1].typ, AterkommandeTyp.syssla);
    expect(rader[1].typ.etikett, 'Syssla');
    expect(rader[1].vem, 'Céline');
    expect(rader[1].nar, 'Varje torsdag 18:00');
    expect(rader[1].piktogram, '🧹');
  });

  test('engångssaker tas inte med', () {
    final engang = event('e1', 'Tandläkare', {'time': '15:00'});
    final engangsSyssla = ('s1', <String, dynamic>{'chore': 'Städa'});
    expect(bygg([engang], [engangsSyssla]), isEmpty);
  });

  test('utan personer gäller det hela familjen', () {
    final fika = event('f', 'Fredagsfika',
        {'isRecurring': true, 'recurrence': varjeTorsdag});
    expect(bygg([fika]).single.vem, 'Hela familjen');
  });

  test('personer utan namn hittas via uid', () {
    final e = event('u', 'Bad', {
      'personUids': ['c'],
      'isRecurring': true,
      'recurrence': varjeTorsdag,
    });
    expect(bygg([e]).single.vem, 'Céline');
  });

  test('samma aktivitet två gånger visas en gång', () {
    final e =
        event('d', 'Dans', {'isRecurring': true, 'recurrence': varjeTorsdag});
    expect(bygg([e, e]).length, 1);
  });

  test('bara-dag-etiketten', () {
    final idag = DateTime(2026, 9, 23);
    expect(baraDagEtikett(idag, idag), 'Bara idag');
    expect(baraDagEtikett(DateTime(2026, 9, 24), idag), 'Bara i morgon');
    expect(baraDagEtikett(DateTime(2026, 9, 29), idag), 'Bara tisdag 29 sep');
  });

  test('turordning, daglig upprepning och sortering', () {
    final disk = ('z', <String, dynamic>{
      'title': 'diska',
      'isRecurring': true,
      'rotationUids': ['e', 'c', 'okänd'],
      'recurrence': {'type': 'daily', 'startDate': '2026-09-24'},
    });
    final bad = event('a', 'Bad', {
      'isRecurring': true,
      'recurrence': {'type': 'monthly', 'startDate': '2026-09-24'},
      'piktogram': '🛁',
    });
    final rader = bygg([bad], [disk]);
    expect(rader.map((r) => r.titel), ['Bad', 'diska']);
    expect(rader[0].nar, 'Den 24:e varje månad');
    expect(rader[0].piktogram, '🛁');
    expect(rader[1].vem, 'Turas om: Emilio, Céline');
    expect(rader[1].nar, 'Varje dag');
  });

  test('okänd upprepningstyp och tom titel', () {
    final e = event('x', '  ', {
      'isRecurring': true,
      'recurrence': {'type': 'yearly', 'startDate': '2026-09-24'},
      'time': ' 08:00 ',
    });
    final r = bygg([e]).single;
    expect(r.titel, 'Aktivitet');
    expect(r.nar, 'Upprepas 08:00');
  });

  test('en syssla med isRecurring men utan recurrence tas inte med', () {
    final s = ('s', <String, dynamic>{'chore': 'Städa', 'isRecurring': true});
    expect(bygg(const [], [s]), isEmpty);
  });
}
