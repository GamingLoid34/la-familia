import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/models/user_model.dart';
import 'package:la_familia/utils/quick_add_parser.dart';

void main() {
  UserModel makeUser(String uid, String name) {
    return UserModel(
      uid: uid,
      name: name,
      email: '$uid@test.com',
      color: 'ff6bae75',
      role: 'child',
      viewMode: 'parent',
      energy: 3,
    );
  }

  group('quick_add_parser fuzzy and tolerant name matching', () {
    test('1. BUP Selin 26 augusti 08.30 matchar Céline Andersson via fuzzy Levenshtein', () {
      final members = [
        makeUser('u1', 'Céline Andersson'),
        makeUser('u2', 'Oscar Valladares'),
      ];
      final now = DateTime(2026, 8, 20, 10, 0);
      final draft = parseQuickAdd(
        'BUP Selin 26 augusti 08.30',
        members: members,
        now: now,
      );

      expect(draft, isNotNull);
      expect(draft!.title, 'BUP');
      expect(draft.persons.length, 1);
      expect(draft.persons.first.name, 'Céline Andersson');
      expect(draft.date.day, 26);
      expect(draft.date.month, 8);
      expect(draft.time, '08:30');
    });

    test('2. Tandläkare Celine imorgon kl 9 matchar Céline via accentvikning', () {
      final members = [
        makeUser('u1', 'Céline Andersson'),
      ];
      final now = DateTime(2026, 8, 20, 10, 0);
      final draft = parseQuickAdd(
        'Tandläkare Celine imorgon kl 9',
        members: members,
        now: now,
      );

      expect(draft, isNotNull);
      expect(draft!.title, 'Tandläkare');
      expect(draft.persons.length, 1);
      expect(draft.persons.first.name, 'Céline Andersson');
      expect(draft.date.day, 21);
      expect(draft.time, '09:00');
    });

    test('3. Köp selleri fredag matchar ingen person och behåller selleri i varorna', () {
      final members = [
        makeUser('u1', 'Céline Andersson'),
        makeUser('u2', 'Oscar Valladares'),
      ];
      final now = DateTime(2026, 8, 20, 10, 0);
      final draft = parseQuickAdd(
        'Köp selleri fredag',
        members: members,
        now: now,
      );

      expect(draft, isNotNull);
      expect(draft!.intent, QuickAddIntent.shopping);
      expect(draft.persons, isEmpty);
      expect(draft.title, contains('Selleri'));
    });

    test('3b. Aktivitet med ordet selleri matchar inte Céline (distans 3 > tröskel 2)', () {
      final members = [
        makeUser('u1', 'Céline Andersson'),
        makeUser('u2', 'Oscar Valladares'),
      ];
      final now = DateTime(2026, 8, 20, 10, 0);
      final draft = parseQuickAdd(
        'Hacka selleri fredag',
        members: members,
        now: now,
      );

      expect(draft, isNotNull);
      expect(draft!.intent, QuickAddIntent.activity);
      expect(draft.persons, isEmpty);
      expect(draft.title, 'Hacka selleri');
    });

    test('4. Två medlemmar Lina och Nina med ordet Mina matchar ingen (tvetydigt)', () {
      final members = [
        makeUser('u1', 'Lina Svensson'),
        makeUser('u2', 'Nina Svensson'),
      ];
      final now = DateTime(2026, 8, 20, 10, 0);
      final draft = parseQuickAdd(
        'Gympa Mina tisdag',
        members: members,
        now: now,
      );

      expect(draft, isNotNull);
      expect(draft!.persons, isEmpty);
      expect(draft.title, 'Gympa Mina');
    });

    test('5. Fotboll Oskar tisdag med medlem Oscar matchar (distans 1)', () {
      final members = [
        makeUser('u1', 'Oscar Valladares'),
      ];
      final now = DateTime(2026, 8, 20, 10, 0);
      final draft = parseQuickAdd(
        'Fotboll Oskar tisdag',
        members: members,
        now: now,
      );

      expect(draft, isNotNull);
      expect(draft!.title, 'Fotboll');
      expect(draft.persons.length, 1);
      expect(draft.persons.first.name, 'Oscar Valladares');
    });
  });
}
