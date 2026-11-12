import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/utils/activity_start_time.dart';

/// Det AddEventSheet sparar för starttiden (bygge 1, beslut 2026-09-23).
///
/// Förut fick en tidlös aktivitet det klockslag som råkade vara när formuläret
/// öppnades. Nu förblir den tidlös tills någon själv väljer en starttid.
void main() {
  const nu = TimeOfDay(hour: 14, minute: 37); // "när formuläret öppnades"
  String fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  group('Ny aktivitet', () {
    test('sparar klockslaget som förut', () {
      final tid = activityTimeFields(
        start: const ActivityStartTime.timed(TimeOfDay(hour: 15, minute: 0)),
        end: const TimeOfDay(hour: 16, minute: 30),
        editing: false,
      );
      expect(tid.fields, {'time': '15:00', 'endTime': '16:30'});
      expect(tid.removals, isEmpty);
    });
  });

  group('Aktivitet utan tid', () {
    test('ett tomt klockslag läses som ingen tid', () {
      final start = ActivityStartTime.fromDoc({'time': ''}, fallback: nu);
      expect(start.untimed, isTrue);
      expect(ActivityStartTime.fromDoc({}, fallback: nu).untimed, isTrue);
    });

    test('knappen visar inget klockslag som inte sparas', () {
      final start = ActivityStartTime.fromDoc({'time': ''}, fallback: nu);
      expect(start.label(fmt), 'Starttid: Ingen tid');
      expect(start.label(fmt), isNot(contains('14:37')));
    });

    test('redigering utan ändrad tid förblir utan tid', () {
      final doc = {'time': '', 'timeMode': 'allDay'};
      final tid = activityTimeFields(
        start: ActivityStartTime.fromDoc(doc, fallback: nu),
        end: null,
        editing: true,
      );
      expect(tid.fields['time'], '');
      expect(tid.fields.containsKey('endTime'), isFalse);
      expect(tid.removals, contains('endTime'));
      // timeMode lämnas orört; update() behåller det.
      expect(tid.fields.containsKey('timeMode'), isFalse);
      expect(tid.removals, isNot(contains('timeMode')));
    });

    test('en inläst sluttid sparas inte utan starttid', () {
      // Kalenderimporten skriver endTime "00:00" på heldagshändelser.
      final tid = activityTimeFields(
        start: ActivityStartTime.fromDoc({'time': '', 'endTime': '00:00'}, fallback: nu),
        end: const TimeOfDay(hour: 0, minute: 0),
        editing: true,
      );
      expect(tid.fields.containsKey('endTime'), isFalse);
      expect(tid.removals, contains('endTime'));
    });

    test('inget klockslag till påminnelserna', () {
      // notification_service.dart avbryter när time inte har formen hh:mm.
      final tid = activityTimeFields(
        start: ActivityStartTime.fromDoc({'time': ''}, fallback: nu),
        end: null,
        editing: true,
      );
      expect(tid.fields['time']!.split(':').length < 2, isTrue);
    });
  });

  group('Redigering där ett klockslag väljs', () {
    test('blir tidsatt och timeMode tas bort', () {
      final start = ActivityStartTime.fromDoc({'time': '', 'timeMode': 'undecided'}, fallback: nu)
          .picked(const TimeOfDay(hour: 9, minute: 5));
      expect(start.untimed, isFalse);
      expect(start.label(fmt), 'Starttid: 09:05');

      final tid = activityTimeFields(start: start, end: null, editing: true);
      expect(tid.fields['time'], '09:05');
      expect(tid.removals, containsAll(['timeMode', 'endTime']));
    });

    test('en tidsatt aktivitet behåller sitt klockslag', () {
      final start = ActivityStartTime.fromDoc({'time': '17:30'}, fallback: nu);
      expect(start.untimed, isFalse);
      final tid = activityTimeFields(
        start: start,
        end: const TimeOfDay(hour: 18, minute: 0),
        editing: true,
      );
      expect(tid.fields, {'time': '17:30', 'endTime': '18:00'});
    });
  });
}
