import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/data/stadzoner.dart';
import 'package:la_familia/utils/chore_utils.dart';
import 'package:la_familia/widgets/trasa_chip.dart';

void main() {
  group('Städläge FAS S1 — Delsteg & Runner-logik', () {
    ({String emoji, String text}) parseStepTitle(String rawTitle, String fallbackEmoji) {
      final trimmed = rawTitle.trim();
      if (trimmed.isEmpty) return (emoji: fallbackEmoji, text: '');
      final spaceIdx = trimmed.indexOf(' ');
      if (spaceIdx > 0) {
        final candidate = trimmed.substring(0, spaceIdx).trim();
        final rest = trimmed.substring(spaceIdx + 1).trim();
        final hasAlphaNumeric = RegExp(r'[a-zA-Z0-9åäöÅÄÖ]').hasMatch(candidate);
        if (!hasAlphaNumeric && candidate.isNotEmpty) {
          return (emoji: candidate, text: rest);
        }
      }
      return (emoji: fallbackEmoji, text: trimmed);
    }

    test('Emoji parser splits leading emoji from step title correctly', () {
      final p1 = parseStepTitle('🛏️ Bädda sängen ordentligt', '🧹');
      expect(p1.emoji, '🛏️');
      expect(p1.text, 'Bädda sängen ordentligt');

      final p2 = parseStepTitle('🧸 Plocka leksaker från golvet', '🧹');
      expect(p2.emoji, '🧸');
      expect(p2.text, 'Plocka leksaker från golvet');

      final p3 = parseStepTitle('🗑️ Töm papperskorgen', '🧹');
      expect(p3.emoji, '🗑️');
      expect(p3.text, 'Töm papperskorgen');

      final p4 = parseStepTitle('Dammsug mattan', '🧹');
      expect(p4.emoji, '🧹');
      expect(p4.text, 'Dammsug mattan');

      final p5 = parseStepTitle('', '🧹');
      expect(p5.emoji, '🧹');
      expect(p5.text, '');
    });

    test('Substep progression lands on correct uncompleted index', () {
      final substeps = [
        {'title': '🛏️ Bädda sängen', 'isDone': true},
        {'title': '🧸 Plocka leksaker', 'isDone': true},
        {'title': '🗑️ Töm papperskorgen', 'isDone': false},
        {'title': '🧹 Dammsug golvet', 'isDone': false},
      ];

      final activeIndex = substeps.indexWhere((s) => s['isDone'] == false);
      expect(activeIndex, 2);
      expect(substeps[activeIndex]['title'], '🗑️ Töm papperskorgen');

      final completedCount = substeps.where((s) => s['isDone'] == true).length;
      expect(completedCount, 2);
      expect(substeps.length, 4);

      final upcoming = <Map<String, dynamic>>[];
      for (int i = 0; i < substeps.length; i++) {
        if (i != activeIndex && substeps[i]['isDone'] == false) {
          upcoming.add(substeps[i]);
        }
      }
      expect(upcoming.length, 1);
      expect(upcoming.first['title'], '🧹 Dammsug golvet');
    });

    test('All steps completed triggers completion and reset for recurring chores', () {
      final substeps = [
        {'title': '🛏️ Bädda sängen', 'isDone': true},
        {'title': '🧸 Plocka leksaker', 'isDone': true},
        {'title': '🗑️ Töm papperskorgen', 'isDone': true},
        {'title': '🧹 Dammsug golvet', 'isDone': true},
      ];

      final allDone = substeps.every((s) => s['isDone'] == true);
      expect(allDone, isTrue);

      final choreData = {
        'chore': 'Städa rummet',
        'isRecurring': true,
        'recurrence': {
          'type': 'daily',
          'startDate': '2026-08-01',
        },
        'doneDates': <String>[],
      };

      expect(choreIsRecurring(choreData), isTrue);

      final resetSubsteps = substeps.map((s) => {
        'title': s['title'],
        'isDone': false,
      }).toList();

      expect(resetSubsteps.every((s) => s['isDone'] == false), isTrue);
      expect(resetSubsteps.length, 4);
      expect(resetSubsteps[0]['title'], '🛏️ Bädda sängen');
    });

    test('AgendaChoreRow substep indicator criteria (hasSubsteps && !isDone)', () {
      final choreWithSteps = {
        'chore': 'Städa rummet',
        'substeps': [
          {'title': 'Plocka', 'isDone': false},
          {'title': 'Dammsuga', 'isDone': false},
        ],
        'isDone': false,
      };
      final hasSubsteps1 = (choreWithSteps['substeps'] as List).isNotEmpty;
      final isDone1 = choreDoneOnDay(choreWithSteps, DateTime.now());
      expect(hasSubsteps1 && !isDone1, isTrue);

      final choreWithoutSteps = {
        'chore': 'Vattna blommor',
        'substeps': <dynamic>[],
        'isDone': false,
      };
      final hasSubsteps2 = (choreWithoutSteps['substeps'] as List).isNotEmpty;
      expect(hasSubsteps2, isFalse);

      final completedChoreWithSteps = {
        'chore': 'Städa köket',
        'substeps': [
          {'title': 'Torka bord', 'isDone': true},
        ],
        'isDone': true,
      };
      final isDone3 = choreDoneOnDay(completedChoreWithSteps, DateTime.now());
      expect(isDone3, isTrue);
      expect((completedChoreWithSteps['substeps'] as List).isNotEmpty && !isDone3, isFalse);
    });
  });

  group('Städzoner FAS S2 — Zondata, Färgguide, Hub & Startkit', () {
    test('Alla 7 zoner är definierade med exakta data och Ronald McDonald Hus-färger', () {
      expect(stadZoner.length, 7);

      final badrum = stadZonByKey('stad_badrum');
      expect(badrum, isNotNull);
      expect(badrum!.titel, 'Badrum');
      expect(badrum.piktogram, '🚿');
      expect(badrum.farg, 'gul');
      expect(badrum.fargHex, '#F4C430');
      expect(badrum.trasaLabel, 'GUL TRASA');
      expect(badrum.verktyg, ['Gul trasa', 'Allrent', 'Duschskrapa']);
      expect(badrum.steg.length, 5);
      expect(badrum.points, 10);

      final toalett = stadZonByKey('stad_toalett');
      expect(toalett, isNotNull);
      expect(toalett!.titel, 'Toalett');
      expect(toalett.piktogram, '🚽');
      expect(toalett.farg, 'rod');
      expect(toalett.fargHex, '#E05B5B');
      expect(toalett.trasaLabel, 'RÖD TRASA');
      expect(toalett.verktyg, ['Röd trasa eller papper', 'WC-rent', 'Toaborste']);
      expect(toalett.steg.length, 4);

      final kok = stadZonByKey('stad_kok');
      expect(kok, isNotNull);
      expect(kok!.titel, 'Kök');
      expect(kok.piktogram, '🍳');
      expect(kok.farg, 'vit');
      expect(kok.fargHex, '#FFFFFF');
      expect(kok.trasaLabel, 'VIT TRASA');
      expect(kok.verktyg, ['Vit trasa', 'Allrent']);
      expect(kok.steg.length, 6);

      final damm = stadZonByKey('stad_damm');
      expect(damm, isNotNull);
      expect(damm!.titel, 'Damm & ytor');
      expect(damm.piktogram, '🛋️');
      expect(damm.farg, 'bla');
      expect(damm.fargHex, '#4A90D9');
      expect(damm.trasaLabel, 'BLÅ TRASA');
      expect(damm.verktyg, ['Blå trasa']);
      expect(damm.steg.length, 5);

      final golv = stadZonByKey('stad_golv');
      expect(golv, isNotNull);
      expect(golv!.titel, 'Golv');
      expect(golv.piktogram, '🧹');
      expect(golv.farg, isNull);
      expect(golv.fargHex, isNull);
      expect(golv.trasaLabel, isNull);
      expect(golv.verktyg, ['Dammsugare', 'Vileda-mopp']);
      expect(golv.steg.length, 5);

      final textil = stadZonByKey('stad_textil');
      expect(textil, isNotNull);
      expect(textil!.titel, 'Sängar & tvätt');
      expect(textil.piktogram, '🛏️');
      expect(textil.farg, isNull);
      expect(textil.fargHex, isNull);
      expect(textil.trasaLabel, isNull);
      expect(textil.verktyg, ['Tvättkorg']);
      expect(textil.steg.length, 3);

      final sopor = stadZonByKey('stad_sopor');
      expect(sopor, isNotNull);
      expect(sopor!.titel, 'Sopor & återvinning');
      expect(sopor.piktogram, '🗑️');
      expect(sopor.farg, isNull);
      expect(sopor.fargHex, isNull);
      expect(sopor.trasaLabel, isNull);
      expect(sopor.verktyg, ['Soppåsar']);
      expect(sopor.steg.length, 3);
    });

    test('StadZon.color parsar fargHex korrekt', () {
      final badrum = stadZonByKey('stad_badrum')!;
      expect(badrum.color, const Color(0xFFF4C430));

      final toalett = stadZonByKey('stad_toalett')!;
      expect(toalett.color, const Color(0xFFE05B5B));

      final kok = stadZonByKey('stad_kok')!;
      expect(kok.color, const Color(0xFFFFFFFF));

      final damm = stadZonByKey('stad_damm')!;
      expect(damm.color, const Color(0xFF4A90D9));

      final golv = stadZonByKey('stad_golv')!;
      expect(golv.color, isNull);
    });

    test('stadStartkitVaror innehåller exakt de 9 specificerade artiklarna', () {
      expect(stadStartkitVaror.length, 9);
      expect(stadStartkitVaror, [
        'Röda mikrofibertrasor (toaletten)',
        'Extra moppdynor Vileda H2PrO',
        'Duschskrapa',
        'Tvättpåse för mikrofiber',
        'Städkaddy/bärlåda',
        'Toaborste (en per toalett)',
        'Gummihandskar',
        'Etiketter + krokar till städskåpet',
        'Dammvippa med skaft',
      ]);
    });

    test('getNextSaturday beräknar lördag korrekt från olika veckodagar', () {
      // Måndag 2026-08-24 -> Lördag 2026-08-29 (5 dagar fram)
      final mon = DateTime(2026, 8, 24);
      final satFromMon = getNextSaturday(mon);
      expect(satFromMon.weekday, DateTime.saturday);
      expect(satFromMon.day, 29);

      // Fredag 2026-08-28 -> Lördag 2026-08-29 (1 dag fram)
      final fri = DateTime(2026, 8, 28);
      final satFromFri = getNextSaturday(fri);
      expect(satFromFri.weekday, DateTime.saturday);
      expect(satFromFri.day, 29);

      // Lördag 2026-08-29 -> Lördag 2026-08-29 (0 dagar fram)
      final sat = DateTime(2026, 8, 29);
      final satFromSat = getNextSaturday(sat);
      expect(satFromSat.weekday, DateTime.saturday);
      expect(satFromSat.day, 29);

      // Söndag 2026-08-30 -> Lördag 2026-09-05 (6 dagar fram)
      final sun = DateTime(2026, 8, 30);
      final satFromSun = getNextSaturday(sun);
      expect(satFromSun.weekday, DateTime.saturday);
      expect(satFromSun.day, 5);
      expect(satFromSun.month, 9);
    });

    testWidgets('TrasaChip renderar färgad cirkel för badrum och verktygstext för golv', (tester) async {
      final badrumZon = stadZonByKey('stad_badrum')!;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TrasaChip.fromZon(badrumZon),
          ),
        ),
      );
      expect(find.text('GUL TRASA'), findsOneWidget);

      final golvZon = stadZonByKey('stad_golv')!;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TrasaChip.fromZon(golvZon),
          ),
        ),
      );
      expect(find.text('Dammsugare · Vileda-mopp'), findsOneWidget);
    });
  });
}
