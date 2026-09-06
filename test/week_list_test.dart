import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:la_familia/models/user_model.dart';
import 'package:la_familia/utils/conflict_detector.dart';
import 'package:la_familia/utils/person_match.dart';
import 'package:la_familia/utils/schedule_time_utils.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('sv');
  });

  group('FAS V1 — WeekList logic and formatting', () {
    final parent1 = UserModel(
      uid: 'user_mamma',
      email: 'mamma@example.com',
      familyId: 'fam_1',
      name: 'Mamma Anna',
      role: 'parent',
      color: '#E91E63',
      viewMode: 'parent',
      energy: 3,
    );

    final parent2 = UserModel(
      uid: 'user_pappa',
      email: 'pappa@example.com',
      familyId: 'fam_1',
      name: 'Pappa Erik',
      role: 'parent',
      color: '#2196F3',
      viewMode: 'parent',
      energy: 3,
    );

    final child = UserModel(
      uid: 'user_liam',
      email: 'liam@example.com',
      familyId: 'fam_1',
      name: 'Liam',
      role: 'child',
      color: '#4CAF50',
      viewMode: 'child',
      energy: 3,
    );

    final members = [parent1, parent2, child];

    test('Seven day sections generated consistently for any Monday', () {
      final monday = DateTime(2026, 8, 31); // Måndag
      final days = List.generate(
        7,
        (i) => DateTime(monday.year, monday.month, monday.day + i),
      );

      expect(days.length, equals(7));
      expect(days.first.weekday, equals(DateTime.monday));
      expect(days.last.weekday, equals(DateTime.sunday));
      expect(DateFormat('EEEE', 'sv').format(days[0]), equals('måndag'));
      expect(DateFormat('EEEE', 'sv').format(days[6]), equals('söndag'));
    });

    test('Night shift (22:00–06:00) touches both days and is recognized as night shift', () {
      final monday = DateTime(2026, 8, 31);
      final tuesday = DateTime(2026, 9, 1);
      final wednesday = DateTime(2026, 9, 2);

      final nightShiftData = {
        'date': '2026-08-31',
        'start': '22:00',
        'end': '06:00',
        'who': 'Pappa Erik',
        'whoUid': 'user_pappa',
      };

      // Måndag kväll och tisdag morgon berörs
      expect(shiftTouchesDay(nightShiftData, monday), isTrue);
      expect(shiftTouchesDay(nightShiftData, tuesday), isTrue);
      expect(shiftTouchesDay(nightShiftData, wednesday), isFalse);
      expect(isNightShift(nightShiftData), isTrue);
    });

    test('Member dots vs family icon logic', () {
      final familyEvent = {
        'title': 'Fredagsmys',
        'time': '18:00',
      };

      final singleMemberEvent = {
        'title': 'Fotbollsträning',
        'time': '17:00',
        'personUids': ['user_liam'],
      };

      final multiMemberEvent = {
        'title': 'Utvecklingssamtal',
        'time': '14:00',
        'personUids': ['user_mamma', 'user_liam'],
      };

      expect(eventHasNoPersons(familyEvent), isTrue);
      expect(eventHasNoPersons(singleMemberEvent), isFalse);
      expect(eventHasNoPersons(multiMemberEvent), isFalse);

      List<UserModel> resolveMembers(Map<String, dynamic> d) {
        final uids = (d['personUids'] as List?)?.cast<String>() ?? [];
        return members.where((m) => uids.contains(m.uid)).toList();
      }

      expect(resolveMembers(singleMemberEvent).length, equals(1));
      expect(resolveMembers(singleMemberEvent).first.name, equals('Liam'));

      expect(resolveMembers(multiMemberEvent).length, equals(2));
      expect(resolveMembers(multiMemberEvent).map((m) => m.name),
          containsAll(['Mamma Anna', 'Liam']));
    });

    test('Items per day capping: max 4 rows before expansion', () {
      final entries = List.generate(6, (i) => 'Aktivitet ${i + 1}');
      const maxBeforeExpand = 4;

      final visibleEntries = entries.take(maxBeforeExpand).toList();
      final hasMore = entries.length > maxBeforeExpand;
      final moreCount = entries.length - maxBeforeExpand;

      expect(visibleEntries.length, equals(4));
      expect(hasMore, isTrue);
      expect(moreCount, equals(2));
      expect('＋$moreCount till', equals('＋2 till'));
    });

    test('Inline conflict formatting for adult and pickup conflicts', () {
      final monday = DateTime(2026, 8, 31);
      final adultConflict = ScheduleConflict(
        day: monday,
        start: DateTime(2026, 8, 31, 16, 0),
        end: DateTime(2026, 8, 31, 17, 0),
        adults: [parent1, parent2],
      );

      final pickupConflict = ScheduleConflict(
        day: monday,
        start: DateTime(2026, 8, 31, 17, 0),
        end: DateTime(2026, 8, 31, 18, 0),
        adults: [parent1, parent2],
        pickupLabel: '🚗 ons 17:00 — vem tar Liam?',
      );

      String formatConflict(ScheduleConflict c) {
        if (c.isPickup) return c.pickupLabel ?? 'Hämtningskrock';
        final timeStr = DateFormat('HH:mm').format(c.start);
        return '$timeStr — båda upptagna';
      }

      expect(formatConflict(adultConflict), equals('16:00 — båda upptagna'));
      expect(formatConflict(pickupConflict), equals('🚗 ons 17:00 — vem tar Liam?'));
    });
  });
}
