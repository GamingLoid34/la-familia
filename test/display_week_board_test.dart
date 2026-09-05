// ignore_for_file: subtype_of_sealed_class
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/models/user_model.dart';
import 'package:la_familia/screens/display/display_formatters.dart';
import 'package:la_familia/screens/display/display_scene_models.dart';
import 'package:la_familia/utils/date_utils.dart';
import 'package:la_familia/utils/week_bucketing.dart';

class MockDocSnapshot implements QueryDocumentSnapshot {
  @override
  final String id;
  final Map<String, dynamic> _data;

  MockDocSnapshot(this.id, this._data);

  @override
  Map<String, dynamic> data() => _data;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('FAS 1 — Storskärm: Week Bucketing & Night Mode', () {
    test('getWeekDays generates 7 consecutive days starting on Monday', () {
      final monday = DateTime(2026, 8, 31);
      final days = getWeekDays(monday);

      expect(days.length, 7);
      expect(days.first, monday);
      expect(days.last, DateTime(2026, 9, 6));
      expect(days[0].weekday, DateTime.monday);
      expect(days[6].weekday, DateTime.sunday);
    });

    test('Default schedule detects night interval correctly (v3)', () {
      final schedule = DisplayConfig.defaultConfig().schedule;
      expect(resolveScheduledScene(DateTime(2026, 9, 2, 22, 0), schedule), 'natt');
      expect(resolveScheduledScene(DateTime(2026, 9, 2, 23, 30), schedule), 'natt');
      expect(resolveScheduledScene(DateTime(2026, 9, 3, 3, 0), schedule), 'natt');
      expect(resolveScheduledScene(DateTime(2026, 9, 3, 5, 29), schedule), 'natt');
      expect(resolveScheduledScene(DateTime(2026, 9, 3, 5, 30), schedule), 'morgon'); // onsdag = 3 = vardag
      expect(resolveScheduledScene(DateTime(2026, 9, 3, 8, 30), schedule), 'standard');
      expect(resolveScheduledScene(DateTime(2026, 9, 2, 12, 0), schedule), 'standard');
      expect(resolveScheduledScene(DateTime(2026, 9, 2, 17, 0), schedule), 'kvall');
    });

    test('bucketWeekData initializes maps for members and family', () {
      final members = <UserModel>[
        const UserModel(
          uid: 'user1',
          name: 'Liam',
          email: 'liam@test.com',
          role: 'child',
          viewMode: 'child',
          energy: 3,
          color: 'ff2A6F97',
          familyId: 'fam1',
        ),
        const UserModel(
          uid: 'user2',
          name: 'Noomi',
          email: 'noomi@test.com',
          role: 'parent',
          viewMode: 'parent',
          energy: 3,
          color: 'ff8E3B46',
          familyId: 'fam1',
        ),
      ];
      final monday = DateTime(2026, 8, 31);
      final result = bucketWeekData(
        members: members,
        events: const [],
        shifts: const [],
        weekStart: monday,
      );

      expect(result.days.length, 7);
      expect(result.byMember.containsKey('user1'), isTrue);
      expect(result.byMember.containsKey('user2'), isTrue);
      expect(result.byMember['user1']![dateKey(monday)], isEmpty);
      expect(result.familyFor(monday), isEmpty);
      expect(result.hasFamilyEvents, isFalse);
    });
  });

  group('FAS 1.2 — Kompakt tidsformat', () {
    test('formatCompactTime removes leading zeros and :00', () {
      expect(formatCompactTime('17:00'), equals('17'));
      expect(formatCompactTime('08:15–14:00'), equals('8:15–14'));
      expect(formatCompactTime('07:30–16:00'), equals('7:30–16'));
      expect(formatCompactTime('18:30–19:30'), equals('18:30–19:30'));
      expect(formatCompactTime('08:00'), equals('8'));
      expect(formatCompactTime('08:05'), equals('8:05'));
      expect(formatCompactTime('14:00', '22:00'), equals('14–22'));
      expect(formatCompactTime('–06:00'), equals('–6'));
      expect(formatCompactTime('–06:30'), equals('–6:30'));
    });
  });

  group('FAS 1.2 — Familjefold (foldFamilyEvents)', () {
    final u1 = const UserModel(
      uid: 'u1',
      name: 'Liam',
      email: 'liam@test.com',
      role: 'child',
      viewMode: 'child',
      energy: 3,
      color: 'ff2A6F97',
      familyId: 'fam1',
    );
    final u2 = const UserModel(
      uid: 'u2',
      name: 'Noomi',
      email: 'noomi@test.com',
      role: 'parent',
      viewMode: 'parent',
      energy: 3,
      color: 'ff8E3B46',
      familyId: 'fam1',
    );
    final members = [u1, u2];
    final monday = DateTime(2026, 8, 31);

    test('Alla medlemmar kopplade till event -> foldas till Familjen-raden', () {
      final allEvent = MockDocSnapshot('all_ev', {
        'title': 'Städtimmen',
        'date': '2026-08-31',
        'personUids': ['u1', 'u2'],
        'time': '18:00',
      });

      final raw = bucketWeekData(
        members: members,
        events: [allEvent],
        shifts: const [],
        weekStart: monday,
      );

      // Före fold: eventet ligger i båda personernas rader
      expect(raw.eventsFor(u1, monday).length, 1);
      expect(raw.eventsFor(u2, monday).length, 1);
      expect(raw.familyFor(monday), isEmpty);

      // Efter fold: eventet tas bort från personraderna och hamnar i Familjen-raden
      final foldRes = foldFamilyEvents(raw, members);
      expect(foldRes.bucketing.eventsFor(u1, monday), isEmpty);
      expect(foldRes.bucketing.eventsFor(u2, monday), isEmpty);
      expect(foldRes.bucketing.familyFor(monday).length, 1);
      expect(foldRes.bucketing.familyFor(monday).first.id, equals('all_ev'));
      expect(foldRes.foldedDocIds.contains('all_ev'), isTrue);
      expect(foldRes.bucketing.hasFamilyEvents, isTrue);
    });

    test('Alla utom en medlem kopplad -> foldas INTE', () {
      final partialEvent = MockDocSnapshot('partial_ev', {
        'title': 'Fotbollsträning',
        'date': '2026-08-31',
        'personUids': ['u1'],
        'time': '17:00',
      });

      final raw = bucketWeekData(
        members: members,
        events: [partialEvent],
        shifts: const [],
        weekStart: monday,
      );

      final foldRes = foldFamilyEvents(raw, members);
      expect(foldRes.bucketing.eventsFor(u1, monday).length, 1);
      expect(foldRes.bucketing.eventsFor(u2, monday), isEmpty);
      expect(foldRes.bucketing.familyFor(monday), isEmpty);
      expect(foldRes.foldedDocIds.contains('partial_ev'), isFalse);
      expect(foldRes.bucketing.hasFamilyEvents, isFalse);
    });

    test('Inga personer kopplade -> ligger kvar i Familjen-raden som förut', () {
      final pureFamilyEvent = MockDocSnapshot('fam_ev', {
        'title': 'Gemensam middag',
        'date': '2026-08-31',
        'personUids': <String>[],
        'persons': <String>[],
        'time': '19:00',
      });

      final raw = bucketWeekData(
        members: members,
        events: [pureFamilyEvent],
        shifts: const [],
        weekStart: monday,
      );

      expect(raw.familyFor(monday).length, 1);

      final foldRes = foldFamilyEvents(raw, members);
      expect(foldRes.bucketing.familyFor(monday).length, 1);
      expect(foldRes.bucketing.familyFor(monday).first.id, equals('fam_ev'));
      expect(foldRes.foldedDocIds.contains('fam_ev'), isFalse);
      expect(foldRes.bucketing.hasFamilyEvents, isTrue);
    });
  });
}
