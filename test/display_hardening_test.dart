import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/models/user_model.dart';
import 'package:la_familia/screens/display/display_log.dart';
import 'package:la_familia/screens/display/display_shell.dart';
import 'package:la_familia/screens/display/display_week_board.dart';
import 'package:la_familia/screens/display/display_week_data.dart';

void main() {
  group('FAS 2.2 — Storskärm: Driftshärdning', () {
    test('1. Tick-hoppsdetektorns beslutslogik (evaluateTickJump)', () {
      final t0 = DateTime(2026, 9, 5, 2, 0, 0);

      // Normal tick: 60 sekunder
      final tNormal = t0.add(const Duration(seconds: 60));
      final reloadAt3 = DateTime(2026, 9, 5, 3, 0, 0);
      expect(
        evaluateTickJump(
          lastTick: t0,
          currentTick: tNormal,
          scheduledReload: reloadAt3,
        ),
        TickJumpDecision.normal,
      );

      // Litet hopp: 90 sekunder (fortfarande normalt / inom tolerans)
      final t90 = t0.add(const Duration(seconds: 90));
      expect(
        evaluateTickJump(
          lastTick: t0,
          currentTick: t90,
          scheduledReload: reloadAt3,
        ),
        TickJumpDecision.normal,
      );

      // Hopp utan passerad reload (sov 5 minuter, kl 02:00 -> 02:05, reload är kl 03:00)
      final tJumpNoReload = t0.add(const Duration(minutes: 5));
      expect(
        evaluateTickJump(
          lastTick: t0,
          currentTick: tJumpNoReload,
          scheduledReload: reloadAt3,
        ),
        TickJumpDecision.jumpWithoutMissedReload,
      );

      // Hopp med passerad reload (sov från 02:55 till 03:05, reload var kl 03:00)
      final tBeforeReload = DateTime(2026, 9, 5, 2, 55, 0);
      final tAfterReload = DateTime(2026, 9, 5, 3, 5, 0);
      expect(
        evaluateTickJump(
          lastTick: tBeforeReload,
          currentTick: tAfterReload,
          scheduledReload: reloadAt3,
        ),
        TickJumpDecision.jumpWithMissedReload,
      );
    });

    test('2. Ringbufferten i DisplayLog (max 100, kronologisk ordning)', () {
      final log = DisplayLog.instance;
      log.clear();

      // Lägg till 120 poster
      for (var i = 0; i < 120; i++) {
        log.log('test', 'Meddelande $i');
      }

      // Ska vara max 100 poster
      expect(log.entries.length, 100);

      // De äldsta 20 ska ha rullats ut -> första posten är #20, sista är #119
      expect(log.entries.first.message, 'Meddelande 20');
      expect(log.entries.last.message, 'Meddelande 119');

      log.clear();
      expect(log.entries.isEmpty, true);
    });

    test('3. Väderbackoffens intervall (computeWeatherBackoff)', () {
      expect(computeWeatherBackoff(0), const Duration(minutes: 1));
      expect(computeWeatherBackoff(1), const Duration(minutes: 1));
      expect(computeWeatherBackoff(2), const Duration(minutes: 2));
      expect(computeWeatherBackoff(3), const Duration(minutes: 5));
      expect(computeWeatherBackoff(10), const Duration(minutes: 5));
    });

    test('4. Robust medlemsjämförelse (haveSameMemberUids)', () {
      final userA = UserModel(
        uid: 'u1',
        name: 'Anna',
        email: 'anna@example.com',
        role: 'parent',
        viewMode: 'standard',
        color: 'ffff0000',
        energy: 3,
      );
      final userB = UserModel(
        uid: 'u2',
        name: 'Björn',
        email: 'bjorn@example.com',
        role: 'parent',
        viewMode: 'standard',
        color: 'ff00ff00',
        energy: 3,
      );
      final userC = UserModel(
        uid: 'u3',
        name: 'Céline',
        email: 'celine@example.com',
        role: 'child',
        viewMode: 'standard',
        color: 'ff0000ff',
        energy: 3,
      );

      final List<UserModel> list1 = [userA, userB];
      // Ny listinstans med samma användare
      final list2 = [userA, userB];
      expect(identical(list1, list2), false);
      expect(haveSameMemberUids(list1, list2), true);

      // Olika ordning
      final listReversed = [userB, userA];
      expect(haveSameMemberUids(list1, listReversed), false);

      // Olika längd
      final listLonger = [userA, userB, userC];
      expect(haveSameMemberUids(list1, listLonger), false);

      // Annan användare
      final listDifferent = [userA, userC];
      expect(haveSameMemberUids(list1, listDifferent), false);
    });

    test('5. Resume-koalescering (shouldHandleResume: max 1 per 30s)', () {
      final t0 = DateTime(2026, 9, 5, 12, 0, 0);

      // Första resume: lastHandledResume är null -> ska hanteras
      expect(
        shouldHandleResume(now: t0, lastHandledResume: null),
        isTrue,
      );

      // Andra resume 10 sekunder senare -> koalesceras (inom 30s)
      final t10 = t0.add(const Duration(seconds: 10));
      expect(
        shouldHandleResume(now: t10, lastHandledResume: t0),
        isFalse,
      );

      // Tredje resume 29 sekunder senare -> koalesceras (inom 30s)
      final t29 = t0.add(const Duration(seconds: 29));
      expect(
        shouldHandleResume(now: t29, lastHandledResume: t0),
        isFalse,
      );

      // Fjärde resume exakt 30 sekunder senare -> ska hanteras
      final t30 = t0.add(const Duration(seconds: 30));
      expect(
        shouldHandleResume(now: t30, lastHandledResume: t0),
        isTrue,
      );

      // Femte resume 45 sekunder senare -> ska hanteras
      final t45 = t0.add(const Duration(seconds: 45));
      expect(
        shouldHandleResume(now: t45, lastHandledResume: t0),
        isTrue,
      );
    });

    test('6. Väderns färskhetsspärr (shouldSkipManualWeatherFetch: < 5 min)', () {
      final t0 = DateTime(2026, 9, 5, 12, 0, 0);

      // Ingen tidigare lyckad hämtning -> hoppa inte över
      expect(
        shouldSkipManualWeatherFetch(now: t0, lastSuccessfulFetch: null),
        isFalse,
      );

      // Manuell trigger 2 minuter efter lyckad hämtning -> hoppa över (< 5 min)
      final t2m = t0.add(const Duration(minutes: 2));
      expect(
        shouldSkipManualWeatherFetch(now: t2m, lastSuccessfulFetch: t0),
        isTrue,
      );

      // Manuell trigger 4 minuter och 59 sekunder efter -> hoppa över (< 5 min)
      final t4m59s = t0.add(const Duration(minutes: 4, seconds: 59));
      expect(
        shouldSkipManualWeatherFetch(now: t4m59s, lastSuccessfulFetch: t0),
        isTrue,
      );

      // Manuell trigger exakt 5 minuter efter -> hoppa inte över (>= 5 min)
      final t5m = t0.add(const Duration(minutes: 5));
      expect(
        shouldSkipManualWeatherFetch(now: t5m, lastSuccessfulFetch: t0),
        isFalse,
      );

      // Manuell trigger 10 minuter efter -> hoppa inte över
      final t10m = t0.add(const Duration(minutes: 10));
      expect(
        shouldSkipManualWeatherFetch(now: t10m, lastSuccessfulFetch: t0),
        isFalse,
      );
    });
  });
}
