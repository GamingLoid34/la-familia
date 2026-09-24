import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/models/user_model.dart';
import 'package:la_familia/screens/display/display_scene_models.dart';
import 'package:la_familia/widgets/min_dag_skollunch.dart';

/// Skollunch i Min dag (spec 4.2). Port av Androids `SchoolMenuLookup`-tester plus
/// blockbygget (11:00–11:45, "Namn: rätt").
void main() {
  final fredag = DateTime(2026, 9, 25);

  final vecka = <Map<String, dynamic>>[
    {'date': '2026-09-24', 'lunch': 'Fiskgratäng'},
    {
      'date': ' 2026-09-25 ',
      'lunch': ' Köttbullar med potatis ',
      'vegetarian': 'Sojabullar',
      'note': 'Glass till efterrätt',
    },
    {'date': '2026-09-26', 'lunch': '   '},
  ];

  group('skolmatVeckonyckel', () {
    test('vanlig vecka', () {
      expect(skolmatVeckonyckel(fredag), '2026-W39');
    });

    test('1 januari kan höra till föregående ISO-år', () {
      // 2027-01-01 är en fredag i ISO-vecka 53 av 2026.
      expect(skolmatVeckonyckel(DateTime(2027, 1, 1)), '2026-W53');
    });

    test('ensiffrig vecka får inledande nolla', () {
      expect(skolmatVeckonyckel(DateTime(2026, 1, 7)), '2026-W02');
    });
  });

  group('skolLunchFor', () {
    test('hittar dagen och trimmar', () {
      final l = skolLunchFor(vecka, fredag)!;
      expect(l.ratt, 'Köttbullar med potatis');
      expect(l.vegetarisk, 'Sojabullar');
      expect(l.notering, 'Glass till efterrätt');
    });

    test('tom rätt räknas som ingen lunch', () {
      expect(skolLunchFor(vecka, DateTime(2026, 9, 26)), isNull);
    });

    test('saknad dag ger null', () {
      expect(skolLunchFor(vecka, DateTime(2026, 9, 28)), isNull);
    });
  });

  group('skolLunchKortEtikett', () {
    test('med vegetariskt', () {
      expect(
        skolLunchKortEtikett(skolLunchFor(vecka, fredag)!),
        'Köttbullar med potatis · veg: Sojabullar',
      );
    });

    test('utan vegetariskt', () {
      expect(
        skolLunchKortEtikett(skolLunchFor(vecka, DateTime(2026, 9, 24))!),
        'Fiskgratäng',
      );
    });
  });

  group('byggSkolLunchBlock', () {
    UserModel medlem(String uid, String namn) =>
        UserModel.fromMap(uid, {'name': namn, 'role': 'child'});

    final config = DisplaySkolmatConfig.fromMap({
      'schools': [
        {
          'id': 'manual_1',
          'name': 'Egen matsedel',
          'source': 'manual',
          'memberUids': ['leo', 'mia'],
        },
        {
          'id': 'manual_2',
          'name': 'Utan vecka',
          'source': 'manual',
          'memberUids': ['sam'],
        },
      ],
    });
    final skolmat = SkolmatDag(config: config, veckor: {'manual_1': vecka});
    final medlemmar = [
      medlem('leo', 'Leandro Valladares'),
      medlem('mia', 'Mia'),
      medlem('sam', 'Sam'),
      medlem('mamma', 'Mamma'),
    ];

    test('ett block per barn vars skola har lunch, 11:00–11:45', () {
      final block = byggSkolLunchBlock(
        skolmat: skolmat,
        medlemmar: medlemmar,
        dag: fredag,
      );
      expect(block.map((b) => b.titel), [
        'Leandro: Köttbullar med potatis · veg: Sojabullar',
        'Mia: Köttbullar med potatis · veg: Sojabullar',
      ]);
      expect(block.first.start, DateTime(2026, 9, 25, 11, 0));
      expect(block.first.slut, DateTime(2026, 9, 25, 11, 45));
      expect(block.first.data['piktogram'], '🍎');
      expect(block.first.data['time'], '11:00');
      expect(block.first.data['endTime'], '11:45');
    });

    test('dag utan lunch ger inga block', () {
      expect(
        byggSkolLunchBlock(
          skolmat: skolmat,
          medlemmar: medlemmar,
          dag: DateTime(2026, 9, 26),
        ),
        isEmpty,
      );
    });

    test('ingen skolmat inläst ger inga block', () {
      expect(
        byggSkolLunchBlock(skolmat: null, medlemmar: medlemmar, dag: fredag),
        isEmpty,
      );
    });
  });
}
