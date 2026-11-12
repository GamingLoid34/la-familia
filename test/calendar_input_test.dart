import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/models/user_model.dart';
import 'package:la_familia/utils/quick_add_parser.dart';
import 'package:la_familia/utils/calendar_input.dart';

void main() {
  final now = DateTime(2026, 10, 23, 10);
  UserModel member(String id, String name) => UserModel(
    uid: id,
    name: name,
    email: '$id@test.local',
    role: 'child',
    viewMode: 'parent',
    color: 'ff6bae75',
    energy: 3,
  );
  final celine = member('c', 'Céline');
  QuickAddDraft parse(String text, {List<UserModel>? members}) => parseQuickAdd(
    text,
    members: members ?? [celine],
    now: now,
    calendarOnly: true,
  )!;
  test('calendar input preserves meal and shopping words as activities', () {
    for (final text in [
      'Middag hos farmor imorgon kl 18',
      'Handla presenter imorgon kl 10',
    ]) {
      final draft = parse(text);
      expect(draft.intent, QuickAddIntent.activity);
      expect(draft.title, startsWith(text.split(' ').first));
      expect(draft.rawText, text);
    }
  });
  test('spoken bare hour and accent folding match Android form', () {
    final patch = CalendarInputPatch.fromDraft(
      parse('Tandläkare Celine torsdag 15'),
    );
    expect(patch.title, 'Tandläkare');
    expect(patch.time!.hour, 15);
    expect(patch.date, DateTime(2026, 10, 29));
    expect(patch.personNames, ['Céline']);
  });
  test(
    'omitted fields preserve the manual draft instead of defaulting to today',
    () {
      final patch = CalendarInputPatch.fromDraft(parse('Tandläkare'));
      expect(patch.date, isNull);
      expect(patch.time, isNull);
      expect(patch.personNames, isNull);
      expect(patch.recurrence, isNull);
    },
  );
  test('unknown and ambiguous names stay in text, never silently assigned', () {
    expect(parse('BUP Selin imorgon kl 9').persons, isEmpty);
    final draft = parse(
      'Träning Alex imorgon',
      members: [member('a', 'Alex Ett'), member('b', 'Alex Två')],
    );
    expect(draft.persons, isEmpty);
    expect(draft.title, contains('Alex'));
  });
  test('weekly recurrence is retained in editable draft', () {
    expect(
      CalendarInputPatch.fromDraft(
        parse('Fotboll varje tisdag kl 17'),
      ).recurrence,
      'weekly',
    );
  });
  test('a day of month or team number is never used as a bare hour', () {
    expect(
      CalendarInputPatch.fromDraft(parse('Tandläkare 15/11')).time,
      isNull,
    );
    expect(
      CalendarInputPatch.fromDraft(parse('Fotboll P11 torsdag')).time,
      isNull,
    );
  });
}
