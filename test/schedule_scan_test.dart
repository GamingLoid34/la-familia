import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/models/user_model.dart';
import 'package:la_familia/services/schedule_scan_service.dart';
import 'package:la_familia/utils/date_utils.dart';
import 'package:la_familia/utils/quick_add_parser.dart';
import 'package:la_familia/utils/schedule_time_utils.dart';

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

  group('ScheduleScan models and helpers', () {
    test('ParsedScheduleEvent toMap and fromMap works correctly', () {
      final ev = ParsedScheduleEvent(
        date: '2026-08-24',
        time: '07:30',
        endTime: '08:30',
        title: 'Träning i personlig vård',
        location: 'Kliniken',
        selected: true,
      );

      final map = ev.toMap();
      expect(map['date'], '2026-08-24');
      expect(map['time'], '07:30');
      expect(map['endTime'], '08:30');
      expect(map['title'], 'Träning i personlig vård');
      expect(map['location'], 'Kliniken');

      final fromMap = ParsedScheduleEvent.fromMap(map);
      expect(fromMap.date, ev.date);
      expect(fromMap.time, ev.time);
      expect(fromMap.endTime, ev.endTime);
      expect(fromMap.title, ev.title);
      expect(fromMap.location, ev.location);
      expect(fromMap.selected, true);
    });

    test('Fuzzy person hint matching matches Noomi accurately', () {
      final members = [
        makeUser('u1', 'Noomi Valladares'),
        makeUser('u2', 'Oscar Valladares'),
        makeUser('u3', 'Céline Valladares'),
      ];

      // Exact match on first name
      expect(foldName('Noomi'), foldName('noomi'));

      // Fuzzy match when hint is "Nomi"
      final foldedHint = foldName('Nomi');
      UserModel? matched;
      int? bestDist;
      for (final m in members) {
        final first = m.name.split(' ').first;
        final foldedFirst = foldName(first);
        final threshold = foldedFirst.length >= 5 ? 2 : (foldedFirst.length >= 3 ? 1 : 0);
        final d = levenshtein(foldedHint, foldedFirst);
        if (d <= threshold) {
          if (bestDist == null || d < bestDist) {
            bestDist = d;
            matched = m;
          }
        }
      }
      expect(matched, isNotNull);
      expect(matched!.name, 'Noomi Valladares');
    });

    test('Veckoflytt adderar och subtraherar 7 dagar', () {
      final ev = ParsedScheduleEvent(
        date: '2026-08-24',
        time: '10:00',
        title: 'Arbetsterapeut Hampus',
      );

      final d = parseDate(ev.date)!;
      final nextWeek = d.add(const Duration(days: 7));
      expect(dateKey(nextWeek), '2026-08-31');

      final prevWeek = d.subtract(const Duration(days: 7));
      expect(dateKey(prevWeek), '2026-08-17');
    });

    test('schemaLabelFor and schemaPiktogramFor correctly identifies types', () {
      // 1. Explicit schemaLabel
      final docRehab = {'schemaLabel': 'Rehab', 'piktogram': '🏥'};
      expect(schemaLabelFor(docRehab), 'Rehab');
      expect(schemaPiktogramFor(docRehab), '🏥');

      final docJob = {'schemaLabel': 'Jobb', 'piktogram': '💼'};
      expect(schemaLabelFor(docJob), 'Jobb');
      expect(schemaPiktogramFor(docJob), '💼');

      final docAnnat = {'schemaLabel': 'Schema', 'piktogram': '📋'};
      expect(schemaLabelFor(docAnnat), 'Schema');
      expect(schemaPiktogramFor(docAnnat), '📋');

      // 2. Legacy / Befintlig Noomi rehab-vecka utan schemaLabel (piktogram 🏥)
      final docLegacyRehab = {'piktogram': '🏥', 'title': 'Fysioterapi'};
      expect(schemaLabelFor(docLegacyRehab), 'Rehab');
      expect(schemaPiktogramFor(docLegacyRehab), '🏥');

      // 3. Fallback från calendarName med "rehab"
      final docNameRehab = {'calendarName': 'Rehab Noomi v.35', 'title': 'Läkarsamtal'};
      expect(schemaLabelFor(docNameRehab), 'Rehab');
      expect(schemaPiktogramFor(docNameRehab), '🏥');

      // 4. Céline skola (default eller 🏫)
      final docSchool = {'piktogram': '🏫', 'title': 'Matematik'};
      expect(schemaLabelFor(docSchool), 'Skola');
      expect(schemaPiktogramFor(docSchool), '🏫');

      final docDefault = {'title': 'Svenska'};
      expect(schemaLabelFor(docDefault), 'Skola');
      expect(schemaPiktogramFor(docDefault), '🏫');
    });

    test('scheduleBlockLabel builds accurate banners with emojis', () {
      final rehabEvents = [
        {'time': '08:30', 'endTime': '09:15', 'piktogram': '🏥', 'title': 'Fysioterapi'},
        {'time': '10:00', 'endTime': '15:00', 'piktogram': '🏥', 'title': 'Bassängträning'},
      ];
      expect(scheduleBlockLabel(rehabEvents), '🏥 Rehab 08:30–15:00');

      final schoolEvents = [
        {'time': '08:45', 'endTime': '10:00', 'piktogram': '🏫', 'title': 'Svenska'},
        {'time': '10:15', 'endTime': '14:00', 'piktogram': '🏫', 'title': 'Matematik'},
      ];
      expect(
        scheduleBlockLabel(schoolEvents, title: 'Skola · Céline', piktogram: '🏫'),
        '🏫 Skola · Céline 08:45–14:00',
      );
    });
  });
}
