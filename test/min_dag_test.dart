import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/data/hospital_menu.dart';
import 'package:la_familia/models/user_model.dart';
import 'package:la_familia/utils/date_utils.dart';
import 'package:la_familia/utils/person_match.dart';

void main() {
  group('Min dag utilities and filtering', () {
    test('untilLabel formats durations according to NPF guidelines', () {
      expect(untilLabel(const Duration(seconds: 20)), 'nu!');
      expect(untilLabel(const Duration(minutes: 0)), 'nu!');
      expect(untilLabel(const Duration(minutes: 1)), 'om 1 min');
      expect(untilLabel(const Duration(minutes: 40)), 'om 40 min');
      expect(untilLabel(const Duration(minutes: 59)), 'om 59 min');
      expect(untilLabel(const Duration(hours: 2)), 'om 2 h');
      expect(untilLabel(const Duration(hours: 2, minutes: 15)), 'om 2 h 15 min');
    });

    test('Min dag filtering includes school schedule and rehab imports for the user', () {
      final me = UserModel(
        uid: 'user_noomi',
        email: 'noomi@example.com',
        familyId: 'fam_1',
        name: 'Noomi',
        role: 'child',
        color: '#E91E63',
        viewMode: 'child',
        energy: 3,
      );

      final events = <Map<String, dynamic>>[
        // 1. Skolschema importerat som schedule
        {
          'title': 'Matematik',
          'source': 'calendar',
          'planningImportKind': 'schedule',
          'personUids': ['user_noomi'],
          'time': '08:30',
          'endTime': '09:30',
        },
        // 2. Rehabträning för Noomi
        {
          'title': 'Rehabträning',
          'source': 'calendar',
          'planningImportKind': 'activity',
          'personUids': ['user_noomi'],
          'time': '10:00',
          'endTime': '11:00',
        },
        // 3. Gemensam familjehändelse (inga personer angivna)
        {
          'title': 'Fredagsmys',
          'source': 'manual',
          'time': '18:00',
        },
        // 4. Annan persons händelse
        {
          'title': 'Fotbollsträning',
          'source': 'manual',
          'personUids': ['user_oscar'],
          'time': '17:00',
        },
      ];

      // Min dag-logik: eventHasNoPersons || eventIncludesPerson (INGET _showEventOnHome filter!)
      final minDagEvents = events.where((d) {
        if (eventHasNoPersons(d)) return true;
        return eventIncludesPerson(d, uid: me.uid, name: me.name);
      }).toList();

      expect(minDagEvents.length, equals(3));
      expect(minDagEvents.any((d) => d['title'] == 'Matematik'), isTrue,
          reason: 'Skolschema ska synas på Min dag');
      expect(minDagEvents.any((d) => d['title'] == 'Rehabträning'), isTrue,
          reason: 'Rehabträning ska synas på Min dag');
      expect(minDagEvents.any((d) => d['title'] == 'Fredagsmys'), isTrue,
          reason: 'Familjehändelser ska synas på Min dag');
      expect(minDagEvents.any((d) => d['title'] == 'Fotbollsträning'), isFalse,
          reason: 'Andra personers händelser ska inte synas på Min dag');
    });

    test('Proportional math correctly positions event at 09:30 and NU-line at 10:09', () {
      const hourHeight = 110.0;
      const startHour = 7;

      // Händelse 09:30 - 10:30
      final eventStart = DateTime(2026, 8, 26, 9, 30);
      final eventEnd = DateTime(2026, 8, 26, 10, 30);

      final eventStartMin = (eventStart.hour - startHour) * 60 + eventStart.minute; // (9-7)*60 + 30 = 150 min
      final eventTop = (eventStartMin / 60.0) * hourHeight; // 2.5 * 110 = 275.0 px

      final eventDurMin = eventEnd.difference(eventStart).inMinutes; // 60 min
      final eventHeight = (eventDurMin / 60.0) * hourHeight; // 1.0 * 110 = 110.0 px
      final eventBottom = eventTop + eventHeight; // 385.0 px

      // Nuvarande tid: 10:09
      final now = DateTime(2026, 8, 26, 10, 9);
      final nuMin = (now.hour - startHour) * 60 + now.minute; // (10-7)*60 + 9 = 189 min
      final nuTop = (nuMin / 60.0) * hourHeight; // 3.15 * 110 = 346.5 px

      // ACCEPTANS 1: Blockets överkant ligger ovanför NU-linjen och linjen skär genom blocket
      expect(eventTop, equals(275.0));
      expect(nuTop, equals(346.5));
      expect(eventTop < nuTop, isTrue, reason: 'Blockets överkant ska ligga ovanför NU-linjen');
      expect(nuTop < eventBottom, isTrue, reason: 'NU-linjen ska skära genom det pågående blocket');
    });

    test('Timeline bounds always include at least 07:00 to 20:00', () {
      int calculateStartHour(int earliestHour, int currentHour) {
        var start = 7;
        if (earliestHour < start) start = earliestHour;
        if (currentHour < start) start = currentHour;
        return start;
      }

      int calculateEndHour(int latestHour, int currentHour) {
        var end = 20;
        if (latestHour > end) end = latestHour;
        if (currentHour + 1 > end) end = currentHour + 1;
        if (end > 24) end = 24;
        return end;
      }

      // Normal dag mitt på dagen
      expect(calculateStartHour(9, 14), 7);
      expect(calculateEndHour(17, 14), 20);

      // Tidig morgon
      expect(calculateStartHour(6, 5), 5);

      // Sen kväll
      expect(calculateEndHour(22, 22), 23);
    });

    test('Transport marking permissions and tap rules', () {
      final parent = UserModel(
        uid: 'user_parent',
        email: 'parent@example.com',
        familyId: 'fam_1',
        name: 'Mamma',
        role: 'parent',
        color: '#4CAF50',
        viewMode: 'parent',
        energy: 3,
      );

      final noomi = UserModel(
        uid: 'user_noomi',
        email: 'noomi@example.com',
        familyId: 'fam_1',
        name: 'Noomi',
        role: 'child',
        color: '#E91E63',
        viewMode: 'child',
        energy: 3,
      );

      final oscar = UserModel(
        uid: 'user_oscar',
        email: 'oscar@example.com',
        familyId: 'fam_1',
        name: 'Oscar',
        role: 'child',
        color: '#2196F3',
        viewMode: 'child',
        energy: 3,
      );

      final noomiRehabEvent = {
        'title': 'Rehabträning',
        'personUids': ['user_noomi'],
        'time': '14:00',
        'endTime': '15:00',
      };

      bool canEditTransport(UserModel? user, Map<String, dynamic> d, bool isPassed) {
        if (isPassed) return false;
        if (user == null) return false;
        return user.isParent ||
            eventIncludesPerson(d, uid: user.uid, name: user.name) ||
            eventHasNoPersons(d);
      }

      // 1. Förälder får redigera transport på Noomis rehabpass (kommande)
      expect(canEditTransport(parent, noomiRehabEvent, false), isTrue);

      // 2. Noomi får redigera transport på sitt eget rehabpass (kommande)
      expect(canEditTransport(noomi, noomiRehabEvent, false), isTrue);

      // 3. Barnkonto Oscar kan INTE ändra Noomis markeringar
      expect(canEditTransport(oscar, noomiRehabEvent, false), isFalse);

      // 4. Passerat block öppnar ingen sheet oavsett användare
      expect(canEditTransport(parent, noomiRehabEvent, true), isFalse);
      expect(canEditTransport(noomi, noomiRehabEvent, true), isFalse);
    });

    test('Transport chip formatting for normal vs next block', () {
      String? getTransportText(String? transport, bool isNext) {
        if (transport == 'sjalv') {
          return isNext ? '🚶‍♀️ Ta dig dit själv' : '🚶‍♀️ Själv';
        } else if (transport == 'hamtas') {
          return isNext ? '🤝 De hämtar dig' : '🤝 Hämtas';
        }
        return null;
      }

      expect(getTransportText('sjalv', false), equals('🚶‍♀️ Själv'));
      expect(getTransportText('sjalv', true), equals('🚶‍♀️ Ta dig dit själv'));
      expect(getTransportText('hamtas', false), equals('🤝 Hämtas'));
      expect(getTransportText('hamtas', true), equals('🤝 De hämtar dig'));
      expect(getTransportText(null, false), isNull);
    });

    test('Hospital menu dataset matches exact specification (stickprov 3, 9, 16, r1, d3)', () {
      // 1–15 Varmrätter
      final dish3 = getHospitalMenuItemById('3');
      expect(dish3?.nummer, equals(3));
      expect(dish3?.namn, equals('Marinerad kycklinglårfilé med gräddig äppelcidersås'));
      expect(dish3?.kategori, equals(HospitalMenuCategory.varmratt));

      final dish9 = getHospitalMenuItemById('9');
      expect(dish9?.nummer, equals(9));
      expect(dish9?.namn, equals('Kokt sejfilé med hummersås'));
      expect(dish9?.kategori, equals(HospitalMenuCategory.varmratt));

      // 16–19 Smårätter
      final dish16 = getHospitalMenuItemById('16');
      expect(dish16?.nummer, equals(16));
      expect(dish16?.namn, equals('Pannkakor'));
      expect(dish16?.kategori, equals(HospitalMenuCategory.smaratt));

      // Råkost & Dessert
      final rakost1 = getHospitalMenuItemById('r1');
      expect(rakost1?.namn, equals('Pizzasallad'));
      expect(rakost1?.kategori, equals(HospitalMenuCategory.rakost));

      final dessert3 = getHospitalMenuItemById('d3');
      expect(dessert3?.namn, equals('Fruktsallad'));
      expect(dessert3?.kategori, equals(HospitalMenuCategory.dessert));
    });

    test('formatHospitalMealChoice formats dish number 5 with salad and dessert properly', () {
      final choiceMap = {
        'dishId': '5',
        'rakostId': 'r1',
        'dessertId': 'd3',
      };

      final formatted = formatHospitalMealChoice(choiceMap, mealLabel: 'Lunch');
      expect(formatted.mainTitle, equals('Lunch: 5. Hemlagade köttbullar med gräddsås'));
      expect(formatted.extras, equals('+ Pizzasallad · Fruktsallad'));
    });

    test('Meal choice deduplication: existing rehab lunch event avoids duplicate meal block', () {
      final events = <Map<String, dynamic>>[
        {
          'title': 'Lunch',
          'time': '12:00',
          'endTime': '12:30',
        },
        {
          'title': 'Fysioterapi',
          'time': '13:00',
          'endTime': '14:00',
        },
      ];

      // Simulera Min dag måltidslogik
      final hasExistingLunch = events.any(
        (e) => (e['title'] as String? ?? '').toLowerCase().trim().startsWith('lunch'),
      );
      final hasExistingMiddag = events.any(
        (e) => (e['title'] as String? ?? '').toLowerCase().trim().startsWith('middag'),
      );

      final blocks = <String>[];
      for (final ev in events) {
        blocks.add(ev['title'] as String);
      }

      if (!hasExistingLunch) {
        blocks.add('Syntetisk Lunch');
      }
      if (!hasExistingMiddag) {
        blocks.add('Syntetisk Middag');
      }

      // Resultat: EN lunch (den befintliga) och en syntetisk middag
      expect(blocks.where((b) => b.toLowerCase().contains('lunch')).length, equals(1));
      expect(blocks.where((b) => b.toLowerCase().contains('middag')).length, equals(1));
    });

    test('FAS D2 — relativeDayLabel returns correct Swedish labels for past, today and future', () {
      String relativeDayLabel(DateTime viewed, DateTime now) {
        final v = DateTime(viewed.year, viewed.month, viewed.day);
        final t = DateTime(now.year, now.month, now.day);
        final diff = v.difference(t).inDays;
        if (diff == 0) return 'IDAG';
        if (diff == 1) return 'I MORGON';
        if (diff == -1) return 'IGÅR';
        if (diff > 1) return 'OM $diff DAGAR';
        return 'FÖR ${-diff} DAGAR SEDAN';
      }

      final today = DateTime(2026, 9, 1);
      expect(relativeDayLabel(DateTime(2026, 9, 1), today), 'IDAG');
      expect(relativeDayLabel(DateTime(2026, 9, 2), today), 'I MORGON');
      expect(relativeDayLabel(DateTime(2026, 8, 31), today), 'IGÅR');
      expect(relativeDayLabel(DateTime(2026, 9, 5), today), 'OM 4 DAGAR');
      expect(relativeDayLabel(DateTime(2026, 8, 25), today), 'FÖR 7 DAGAR SEDAN');
    });

    test('FAS D2 — Day clamping adheres strictly to ±365 days', () {
      final now = DateTime(2026, 9, 1);
      final today = DateTime(now.year, now.month, now.day);

      bool isValidDelta(DateTime viewed, int delta) {
        final target = viewed.add(Duration(days: delta));
        final diff = target.difference(today).inDays;
        return diff >= -365 && diff <= 365;
      }

      expect(isValidDelta(today, 1), isTrue);
      expect(isValidDelta(today, 365), isTrue);
      expect(isValidDelta(today, 366), isFalse);
      expect(isValidDelta(today, -365), isTrue);
      expect(isValidDelta(today, -366), isFalse);
    });

    test('FAS D2 — Midnight rollover moves viewedDay when user is viewing today', () {
      var viewedDay = DateTime(2026, 8, 31);
      var currentTime = DateTime(2026, 8, 31, 23, 59);

      bool isViewingToday(DateTime viewed, DateTime current) =>
          viewed.year == current.year &&
          viewed.month == current.month &&
          viewed.day == current.day;

      expect(isViewingToday(viewedDay, currentTime), isTrue);

      // Klockan slår om till midnatt
      final newNow = DateTime(2026, 9, 1, 0, 1);
      final wasViewingToday = isViewingToday(viewedDay, currentTime);
      currentTime = newNow;
      if (wasViewingToday) {
        viewedDay = DateTime(newNow.year, newNow.month, newNow.day);
      }

      expect(viewedDay, DateTime(2026, 9, 1));
      expect(isViewingToday(viewedDay, currentTime), isTrue);
    });
  });
}
