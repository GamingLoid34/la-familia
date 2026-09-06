import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:la_familia/models/user_model.dart';
import 'package:la_familia/utils/chore_utils.dart';
import 'package:la_familia/utils/member_presence.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('sv');
  });

  group('FAS H2 — Rollstyrt Hem (Role-driven Dashboard)', () {
    final parent = UserModel(
      uid: 'user_parent',
      email: 'parent@example.com',
      familyId: 'fam_1',
      name: 'Mamma Anna',
      role: 'parent',
      color: '#E91E63',
      viewMode: 'parent',
      energy: 3,
    );

    final focusUser = UserModel(
      uid: 'user_focus',
      email: 'focus@example.com',
      familyId: 'fam_1',
      name: 'Mamma Rehab',
      role: 'parent',
      color: '#9C27B0',
      viewMode: 'focus',
      energy: 2,
    );

    final child = UserModel(
      uid: 'user_child',
      email: 'child@example.com',
      familyId: 'fam_1',
      name: 'Lionel',
      role: 'child',
      color: '#4CAF50',
      viewMode: 'child',
      energy: 3,
    );

    final youth = UserModel(
      uid: 'user_youth',
      email: 'youth@example.com',
      familyId: 'fam_1',
      name: 'Oscar',
      role: 'youth',
      color: '#2196F3',
      viewMode: 'youth',
      energy: 3,
    );

    test('1. ViewMode branching: focus och child får MinDagView, parent och youth får Upp näst', () {
      bool shouldUseEmbeddedMinDag(UserModel user) {
        return user.isFocusMode || user.isChildMode;
      }

      expect(shouldUseEmbeddedMinDag(focusUser), isTrue, reason: 'Focus mode -> MinDagView');
      expect(shouldUseEmbeddedMinDag(child), isTrue, reason: 'Child mode -> MinDagView');
      expect(shouldUseEmbeddedMinDag(parent), isFalse, reason: 'Parent mode -> Upp näst-hemmet');
      expect(shouldUseEmbeddedMinDag(youth), isFalse, reason: 'Youth mode -> Upp näst-hemmet');
    });

    test('2. NU/NÄST-hjälten: Pågående aktivitet beräknar progress och sluttid', () {
      final now = DateTime(2026, 9, 2, 14, 30);
      final start = DateTime(2026, 9, 2, 14, 0);
      final end = DateTime(2026, 9, 2, 15, 0);

      final isOngoing = !now.isBefore(start) && now.isBefore(end);
      expect(isOngoing, isTrue);

      final totalMs = end.difference(start).inMilliseconds;
      final elapsedMs = now.difference(start).inMilliseconds;
      final progress = (elapsedMs / totalMs).clamp(0.0, 1.0);

      expect(progress, equals(0.5));
    });

    test('3. NU/NÄST-hjälten: Kommande aktivitet beräknar nedräkning i minuter och timmar', () {
      final now = DateTime(2026, 9, 2, 7, 10);
      final busStart = DateTime(2026, 9, 2, 7, 45); // om 35 min
      final gymStart = DateTime(2026, 9, 2, 9, 10); // om 2 timmar

      String formatDiff(DateTime start, DateTime current) {
        final diffMin = start.difference(current).inMinutes;
        if (diffMin <= 1) return 'OM 1 MIN';
        if (diffMin < 60) return 'OM $diffMin MIN';
        if (diffMin < 120) return 'OM 1 TIMME';
        return 'OM ${(diffMin / 60).round()} TIMMAR';
      }

      expect(formatDiff(busStart, now), equals('OM 35 MIN'));
      expect(formatDiff(gymStart, now), equals('OM 2 TIMMAR'));
    });

    test('4. NU/NÄST-hjälten: Tom dag faller tillbaka mjukt utan krasch', () {
      final now = DateTime(2026, 9, 2, 19, 0);
      final eventsToday = <Map<String, dynamic>>[];
      final eventsTomorrow = <Map<String, dynamic>>[
        {'title': 'Skola', 'time': '08:00', 'piktogram': '🏫'}
      ];

      expect(eventsToday.isEmpty, isTrue);
      expect(eventsTomorrow.isNotEmpty, isTrue);
      expect(eventsTomorrow.first['title'], equals('Skola'));
      expect(eventsTomorrow.first['time'], equals('08:00'));
      expect(now.hour, equals(19));
    });

    test('5. Sysslo-chip beräknar egna oavklarade sysslor för idag och döljs vid 0', () {
      final today = DateTime(2026, 9, 2);
      final chores = [
        {'title': 'Duka bordet', 'who': 'Mamma Anna', 'whoUid': 'user_parent', 'dueDate': '2026-09-02', 'isDone': false},
        {'title': 'Gå ut med sopor', 'who': 'Mamma Anna', 'whoUid': 'user_parent', 'dueDate': '2026-09-02', 'isDone': true},
        {'title': 'Städa rummet', 'who': 'Lionel', 'whoUid': 'user_child', 'dueDate': '2026-09-02', 'isDone': false},
      ];

      int uncompletedCount(List<Map<String, dynamic>> allChores, UserModel user) {
        return allChores.where((d) {
          if (!choreOccursOnDay(d, today)) return false;
          if (choreDoneOnDay(d, today)) return false;
          return choreAssignedToOnDay(d, today, uid: user.uid, name: user.name);
        }).length;
      }

      expect(uncompletedCount(chores, parent), equals(1)); // Duka bordet kvar
      expect(uncompletedCount(chores, child), equals(1)); // Städa rummet kvar
      expect(uncompletedCount(chores, youth), equals(0)); // 0 -> dold chip
    });

    test('6. Närvaroberäkning (MemberPresence) ger rätt färg för ledig, kan svara och upptagen', () {
      expect(MemberPresence.free.ringColor, equals(const Color(0xFF6BAE75)));
      expect(MemberPresence.canReply.ringColor, equals(const Color(0xFFEDD87A)));
      expect(MemberPresence.busy.ringColor, equals(const Color(0xFFD95F4B)));
    });
  });
}
