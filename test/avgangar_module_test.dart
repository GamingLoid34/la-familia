import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/screens/display/modules/avgangar_module.dart';

void main() {
  group('FAS 5 — avgangar_module: calculateMinutesUntil', () {
    test('1. Normal tidsdifferens inom samma dygn', () {
      final now = DateTime(2026, 9, 9, 7, 10);
      expect(calculateMinutesUntil('07:15', now), 5);
      expect(calculateMinutesUntil('07:10', now), 0);
      expect(calculateMinutesUntil('07:05', now), -5);
      expect(calculateMinutesUntil('08:10', now), 60);
    });

    test('2. Wrap över midnatt', () {
      final lateNight = DateTime(2026, 9, 9, 23, 55);
      // Avgång kl 00:05 nästa dygn är 10 minuter bort
      expect(calculateMinutesUntil('00:05', lateNight), 10);

      final earlyMorning = DateTime(2026, 9, 9, 0, 5);
      // Avgång kl 23:55 igår är passerad (-10 min)
      expect(calculateMinutesUntil('23:55', earlyMorning), -10);
    });

    test('3. Ogiltigt tidsformat returnerar negativt värde', () {
      final now = DateTime(2026, 9, 9, 12, 0);
      expect(calculateMinutesUntil('ogiltig', now), -999);
      expect(calculateMinutesUntil('', now), -999);
    });
  });

  group('FAS 5.3 — avgangar_module: calculateWalkMinutes & formatWalkingLabel (PIN-TESTER)', () {
    test('1. Gå-logik: gåOm = scheduledMin - walkMinutes (walkMinutes = 5)', () {
      // 15 min till avgång enligt tidtabell, 5 min promenad -> gå om 10 min
      expect(calculateWalkMinutes(15, walkMinutes: 5), 10);

      // 5 min till avgång, 5 min promenad -> gå om 0 min (GÅ NU)
      expect(calculateWalkMinutes(5, walkMinutes: 5), 0);

      // 3 min till avgång, 5 min promenad -> -2 min (hinns ej)
      expect(calculateWalkMinutes(3, walkMinutes: 5), -2);
    });

    test('2. Formatering av gå-etiketter (FAS 5.3: gåOm 1 eller 0 -> GÅ NU)', () {
      expect(formatWalkingLabel(12), 'gå om 12 min');
      expect(formatWalkingLabel(2), 'gå om 2 min');
      expect(formatWalkingLabel(1), 'GÅ NU');
      expect(formatWalkingLabel(0), 'GÅ NU');
      expect(formatWalkingLabel(-1), 'hinns ej');
      expect(formatWalkingLabel(-10), 'hinns ej');
    });

    test('3. PIN-TESTER: Beställarens exakta tre verifieringsfall (now 06:45, walk 5)', () {
      final nowPin = DateTime(2026, 9, 9, 6, 45);

      // Fall A: now 06:45, scheduled 07:17, walk 5 -> "gå om 27 min"
      final diffA = calculateMinutesUntil('07:17', nowPin);
      final gaOmA = calculateWalkMinutes(diffA, walkMinutes: 5);
      expect(gaOmA, 27);
      expect(formatWalkingLabel(gaOmA), 'gå om 27 min');

      // Fall B: now 06:45, scheduled 06:49, walk 5 -> "hinns ej"
      final diffB = calculateMinutesUntil('06:49', nowPin);
      final gaOmB = calculateWalkMinutes(diffB, walkMinutes: 5);
      expect(gaOmB, -1);
      expect(formatWalkingLabel(gaOmB), 'hinns ej');

      // Fall C: now 06:45, scheduled 06:51, walk 5 -> "GÅ NU" (gåOm 1)
      final diffC = calculateMinutesUntil('06:51', nowPin);
      final gaOmC = calculateWalkMinutes(diffC, walkMinutes: 5);
      expect(gaOmC, 1);
      expect(formatWalkingLabel(gaOmC), 'GÅ NU');
    });

    test('4. FAS 5.7: Gå-etikett vid lång väntan (gåOm > 60 min -> gå kl HH:mm)', () {
      final now = DateTime(2026, 9, 9, 7, 0);

      // gåOm = 620 min (10 timmar och 20 minuter från 07:00 -> 17:20)
      expect(formatWalkingLabel(620, now: now), 'gå kl 17:20');

      // gåOm = 61 min (1 timme och 1 minut från 07:00 -> 08:01)
      expect(formatWalkingLabel(61, now: now), 'gå kl 08:01');

      // gåOm = 60 min (under eller lika med 60 min är oförändrat)
      expect(formatWalkingLabel(60, now: now), 'gå om 60 min');
      expect(formatWalkingLabel(59, now: now), 'gå om 59 min');
    });
  });

  group('FAS 5.3 — avgangar_module: formatTransitDestinationLabel (målorienterade etiketter)', () {
    test('1. Terminus innehåller Linköping -> Tåg mot Linköping', () {
      expect(formatTransitDestinationLabel('Linköping C'), 'Tåg mot Linköping');
      expect(formatTransitDestinationLabel('Linköping Central'), 'Tåg mot Linköping');
    });

    test('2. Terminus innehåller Norrköping -> Tåg mot Linköping', () {
      expect(formatTransitDestinationLabel('Norrköping C'), 'Tåg mot Linköping');
      expect(formatTransitDestinationLabel('Norrköping'), 'Tåg mot Linköping');
    });

    test('3. Terminus innehåller Mjölby -> Tåg mot Linköping · byte i Mjölby', () {
      expect(formatTransitDestinationLabel('Mjölby'), 'Tåg mot Linköping · byte i Mjölby');
      expect(formatTransitDestinationLabel('Mjölby station'), 'Tåg mot Linköping · byte i Mjölby');
    });

    test('4. Fallback för andra destinationer och mod', () {
      expect(formatTransitDestinationLabel('Nässjö C'), 'Tåg mot Nässjö C');
      expect(formatTransitDestinationLabel('Tranås', mode: 'bus'), 'Buss mot Tranås');
    });
  });

  group('FAS 5 — avgangar_module: matchesTransitFilter', () {
    const trainMjolby = TransitDeparture(
      line: 'Östgötapendeln',
      mode: 'train',
      destination: 'Mjölby station',
      scheduled: '07:49',
      realtime: '07:49',
      delayedMin: 0,
      cancelled: false,
      stopId: '740000041',
      stopName: 'Tranås station',
      stopIcon: '🚆',
    );

    const trainLinkoping = TransitDeparture(
      line: 'Östgötapendeln',
      mode: 'train',
      destination: 'Linköping C',
      scheduled: '08:02',
      realtime: '08:06',
      delayedMin: 4,
      cancelled: false,
      stopId: '740000041',
      stopName: 'Tranås station',
      stopIcon: '🚆',
    );

    const trainNorrkoping = TransitDeparture(
      line: 'Östgötapendeln',
      mode: 'train',
      destination: 'Norrköping C',
      scheduled: '08:22',
      realtime: '08:22',
      delayedMin: 0,
      cancelled: false,
      stopId: '740000041',
      stopName: 'Tranås station',
      stopIcon: '🚆',
    );

    const trainNassjo = TransitDeparture(
      line: 'Krösatåget',
      mode: 'train',
      destination: 'Nässjö C',
      scheduled: '07:55',
      realtime: '07:55',
      delayedMin: 0,
      cancelled: false,
      stopId: '740000041',
      stopName: 'Tranås station',
      stopIcon: '🚆',
    );

    const busTranas = TransitDeparture(
      line: '120',
      mode: 'bus',
      destination: 'Tranås station',
      scheduled: '07:45',
      realtime: '07:45',
      delayedMin: 0,
      cancelled: false,
      stopId: '740025574',
      stopName: 'Tranås Storgatan 26',
      stopIcon: '🚌',
    );

    test('1. Standardfilter släpper igenom Mjölby, Linköping och Norrköping (train)', () {
      expect(matchesTransitFilter(trainMjolby), true);
      expect(matchesTransitFilter(trainLinkoping), true);
      expect(matchesTransitFilter(trainNorrkoping), true);
    });

    test('2. Standardfilter exkluderar södergående Krösatåg och bussar', () {
      expect(matchesTransitFilter(trainNassjo), false);
      expect(matchesTransitFilter(busTranas), false);
    });

    test('3. Custom-filter för mod och destination', () {
      expect(
        matchesTransitFilter(
          busTranas,
          allowedModes: ['bus'],
          allowedDestinations: ['tranås'],
        ),
        true,
      );
    });
  });

  group('FAS 5.3 — avgangar_module: formatFooterDeparture', () {
    final now = DateTime(2026, 9, 9, 7, 27);

    test('1. Tidtabell i tid med gå om X min (scheduled 07:49, now 07:27, walk 5)', () {
      // 07:49 -> 22 min till avgång -> gåOm = 22 - 5 = 17 min
      const dep = TransitDeparture(
        line: 'Östgötapendeln',
        mode: 'train',
        destination: 'Linköping C',
        scheduled: '07:49',
        realtime: '07:49',
        delayedMin: 0,
        cancelled: false,
        stopId: '740000041',
        stopName: 'Tranås station',
        stopIcon: '🚆',
      );

      expect(
        formatFooterDeparture(dep, now, walkMinutes: 5),
        '🚆 Tåg mot Linköping · gå om 17 min (07:49)',
      );
    });

    test('2. Försenad avgång: gåOm beräknas på scheduled-tid, med förseningsbadge', () {
      const dep = TransitDeparture(
        line: 'Östgötapendeln',
        mode: 'train',
        destination: 'Linköping C',
        scheduled: '07:49',
        realtime: '07:53',
        delayedMin: 4,
        cancelled: false,
        stopId: '740000041',
        stopName: 'Tranås station',
        stopIcon: '🚆',
      );

      expect(
        formatFooterDeparture(dep, now, walkMinutes: 5),
        '🚆 Tåg mot Linköping · gå om 17 min (07:49, +4 min sen)',
      );
    });

    test('3. GÅ NU när gåOm <= 1 (scheduled 07:33, now 07:27, walk 5 -> gåOm 1)', () {
      const dep = TransitDeparture(
        line: 'Östgötapendeln',
        mode: 'train',
        destination: 'Mjölby',
        scheduled: '07:33',
        realtime: '07:33',
        delayedMin: 0,
        cancelled: false,
        stopId: '740000041',
        stopName: 'Tranås station',
        stopIcon: '🚆',
      );

      expect(
        formatFooterDeparture(dep, now, walkMinutes: 5),
        '🚆 Tåg mot Linköping · byte i Mjölby · GÅ NU (07:33)',
      );
    });

    test('4. Hinns ej när gåOm < 0 (scheduled 07:30, now 07:27, walk 5 -> gåOm -2)', () {
      const dep = TransitDeparture(
        line: 'Östgötapendeln',
        mode: 'train',
        destination: 'Mjölby',
        scheduled: '07:30',
        realtime: '07:30',
        delayedMin: 0,
        cancelled: false,
        stopId: '740000041',
        stopName: 'Tranås station',
        stopIcon: '🚆',
      );

      expect(
        formatFooterDeparture(dep, now, walkMinutes: 5),
        '🚆 Tåg mot Linköping · byte i Mjölby · hinns ej (07:30)',
      );
    });

    test('5. Inställd avgång', () {
      const dep = TransitDeparture(
        line: 'Östgötapendeln',
        mode: 'train',
        destination: 'Linköping C',
        scheduled: '07:49',
        realtime: '07:49',
        delayedMin: 0,
        cancelled: true,
        stopId: '740000041',
        stopName: 'Tranås station',
        stopIcon: '🚆',
      );

      expect(
        formatFooterDeparture(dep, now, walkMinutes: 5),
        '🚆 Tåg mot Linköping · Inställd (07:49)',
      );
    });

    test('6. Pin-test från beställaren: avgång 07:17 vid now 06:45, walk 5 -> gå om 27 min', () {
      final nowPin = DateTime(2026, 9, 9, 6, 45);
      const dep = TransitDeparture(
        line: 'Östgötapendeln',
        mode: 'train',
        destination: 'Linköping C',
        scheduled: '07:17',
        realtime: '07:17',
        delayedMin: 0,
        cancelled: false,
        stopId: '740000041',
        stopName: 'Tranås station',
        stopIcon: '🚆',
      );

      expect(
        formatFooterDeparture(dep, nowPin, walkMinutes: 5),
        '🚆 Tåg mot Linköping · gå om 27 min (07:17)',
      );
    });
  });

  group('FAS 5 — avgangar_module: filterAndSortUpcomingDepartures', () {
    final now = DateTime(2026, 9, 9, 8, 0);

    test('1. Filtrerar bort passerade avgångar och felaktiga destinationer/modes', () {
      const past = TransitDeparture(
        line: '1',
        mode: 'train',
        destination: 'Linköping C',
        scheduled: '07:50',
        realtime: '07:50',
        delayedMin: 0,
        cancelled: false,
        stopId: '1',
        stopName: 'Tranås station',
        stopIcon: '🚆',
      );

      const southTrain = TransitDeparture(
        line: '2',
        mode: 'train',
        destination: 'Nässjö C',
        scheduled: '08:04',
        realtime: '08:04',
        delayedMin: 0,
        cancelled: false,
        stopId: '1',
        stopName: 'Tranås station',
        stopIcon: '🚆',
      );

      const bus = TransitDeparture(
        line: '3',
        mode: 'bus',
        destination: 'Mjölby',
        scheduled: '08:05',
        realtime: '08:05',
        delayedMin: 0,
        cancelled: false,
        stopId: '1',
        stopName: 'Tranås station',
        stopIcon: '🚌',
      );

      const northTrain1 = TransitDeparture(
        line: '4',
        mode: 'train',
        destination: 'Mjölby',
        scheduled: '08:15',
        realtime: '08:15',
        delayedMin: 0,
        cancelled: false,
        stopId: '1',
        stopName: 'Tranås station',
        stopIcon: '🚆',
      );

      const northTrain2 = TransitDeparture(
        line: '5',
        mode: 'train',
        destination: 'Linköping C',
        scheduled: '08:35',
        realtime: '08:40',
        delayedMin: 5,
        cancelled: false,
        stopId: '1',
        stopName: 'Tranås station',
        stopIcon: '🚆',
      );

      final result = filterAndSortUpcomingDepartures(
        [northTrain2, past, southTrain, bus, northTrain1],
        now,
        limit: 3,
      );

      // Endast norrgående tåg i framtiden (Mjölby 08:15 och Linköping 08:35) ska matchas
      expect(result.length, 2);
      expect(result[0].line, '4');
      expect(result[1].line, '5');
    });
  });

  group('FAS 5 — avgangar_module: computeTransitBackoff', () {
    test('Exponentiell backoff med maxgräns 300s', () {
      expect(computeTransitBackoff(60), 120);
      expect(computeTransitBackoff(120), 240);
      expect(computeTransitBackoff(240), 300);
      expect(computeTransitBackoff(300), 300);
    });
  });

  group('FAS 6b — avgangar_module: Per-hållplats-filtrering och gångtid', () {
    test('1. Busshållplats med eget läge och destinationer ärver inte tågfilter', () {
      final now = DateTime(2026, 9, 9, 8, 0);

      const busDeparture = TransitDeparture(
        line: '150',
        mode: 'bus',
        destination: 'Stoeryd',
        scheduled: '08:12',
        realtime: '08:12',
        delayedMin: 0,
        cancelled: false,
        stopId: 'bus_stop',
        stopName: 'Tranås Storgatan',
        stopIcon: '🚌',
      );

      const otherBusDeparture = TransitDeparture(
        line: '151',
        mode: 'bus',
        destination: 'Sommen',
        scheduled: '08:20',
        realtime: '08:20',
        delayedMin: 0,
        cancelled: false,
        stopId: 'bus_stop',
        stopName: 'Tranås Storgatan',
        stopIcon: '🚌',
      );

      // Rotfiltret har modes: ['train'], men denna hållplats har modes: ['bus'] och destinations: ['Stoeryd']
      final filtered = filterAndSortUpcomingDepartures(
        [busDeparture, otherBusDeparture],
        now,
        allowedModes: ['bus'],
        allowedDestinations: ['stoeryd'],
      );

      expect(filtered.length, 1);
      expect(filtered.first.destination, 'Stoeryd');
    });

    test('2. Tomt destinationsfilter tillåter alla destinationer', () {
      final now = DateTime(2026, 9, 9, 8, 0);

      const bus1 = TransitDeparture(
        line: '1',
        mode: 'bus',
        destination: 'Stoeryd',
        scheduled: '08:10',
        realtime: '08:10',
        delayedMin: 0,
        cancelled: false,
        stopId: 'bus_stop',
        stopName: 'Storgatan',
        stopIcon: '🚌',
      );

      const bus2 = TransitDeparture(
        line: '2',
        mode: 'bus',
        destination: 'Sjukhuset',
        scheduled: '08:15',
        realtime: '08:15',
        delayedMin: 0,
        cancelled: false,
        stopId: 'bus_stop',
        stopName: 'Storgatan',
        stopIcon: '🚌',
      );

      final filtered = filterAndSortUpcomingDepartures(
        [bus1, bus2],
        now,
        allowedModes: ['bus'],
        allowedDestinations: [], // tomt = alla
      );

      expect(filtered.length, 2);
    });

    test('3. formatFooterDeparture anpassar gå-etikett efter specifik hållplats gångtid', () {
      final now = DateTime(2026, 9, 9, 8, 0);

      const departure = TransitDeparture(
        line: '1',
        mode: 'train',
        destination: 'Linköping C',
        scheduled: '08:10', // 10 min till avgång
        realtime: '08:10',
        delayedMin: 0,
        cancelled: false,
        stopId: 'station',
        stopName: 'Tranås station',
        stopIcon: '🚆',
      );

      // Med walkMinutes: 5 -> scheduled 10 min bort -> gåOm = 5 min -> "gå om 5 min"
      final label5 = formatFooterDeparture(departure, now, walkMinutes: 5);
      expect(label5.contains('gå om 5 min'), true);

      // Med walkMinutes: 9 -> scheduled 10 min bort -> gåOm = 1 min -> "GÅ NU"
      final label9 = formatFooterDeparture(departure, now, walkMinutes: 9);
      expect(label9.contains('GÅ NU'), true);

      // Med walkMinutes: 12 -> scheduled 10 min bort -> gåOm = -2 min -> "hinns ej"
      final label12 = formatFooterDeparture(departure, now, walkMinutes: 12);
      expect(label12.contains('hinns ej'), true);
    });
  });
}
