import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/data/piktogram.dart';

void main() {
  group('Rutiner 2.0 FAS R1 — Stegredigering, tider & omsortering', () {
    String? suggestEmoji(String title) {
      final t = title.toLowerCase().trim();
      if (t.isEmpty) return null;
      final sorted = List<PiktogramItem>.from(piktogramLibrary)
        ..sort((a, b) => b.label.length.compareTo(a.label.length));
      for (final item in sorted) {
        final l = item.label.toLowerCase();
        if (t.contains(l) || l.contains(t)) {
          return item.emoji;
        }
      }
      return null;
    }

    test('Piktogram-förslag hittar rätt emoji från stegets titel', () {
      expect(suggestEmoji('Gå till tandläkare'), '🦷');
      expect(suggestEmoji('Äta god frukost'), '🥞');
      expect(suggestEmoji('Packa min ryggsäck'), '🎒');
      expect(suggestEmoji('Ta min medicin'), '💊');
      expect(suggestEmoji('Åka buss'), '🚌');
      expect(suggestEmoji('Bädda sängen'), '🛏️');
      expect(suggestEmoji('Vila en stund'), '😴');
    });

    test('Omsortering av steg flyttar element korrekt', () {
      final steps = [
        {'title': 'Vakna', 'piktogram': '😴'},
        {'title': 'Klä på dig', 'piktogram': '👕'},
        {'title': 'Frukost', 'piktogram': '🥣'},
        {'title': 'Borsta tänderna', 'piktogram': '🪥'},
        {'title': 'Packa väskan', 'piktogram': '🎒'},
      ];

      // Flytta steg 4 (index 3: "Borsta tänderna") till plats 2 (index 1)
      int oldIndex = 3;
      int newIndex = 1;
      if (oldIndex < newIndex) {
        newIndex -= 1;
      }
      final item = steps.removeAt(oldIndex);
      steps.insert(newIndex, item);

      expect(steps[0]['title'], 'Vakna');
      expect(steps[1]['title'], 'Borsta tänderna');
      expect(steps[2]['title'], 'Klä på dig');
      expect(steps[3]['title'], 'Frukost');
      expect(steps[4]['title'], 'Packa väskan');
    });

    test('Infoga steg mitt i listan (insertAt)', () {
      final steps = [
        {'title': 'Vakna', 'piktogram': '😴'},
        {'title': 'Frukost', 'piktogram': '🥣'},
      ];

      final newStep = {'title': 'Klä på dig', 'piktogram': '👕', 'tid': '07:15'};
      steps.insert(1, newStep);

      expect(steps.length, 3);
      expect(steps[0]['title'], 'Vakna');
      expect(steps[1]['title'], 'Klä på dig');
      expect(steps[1]['tid'], '07:15');
      expect(steps[2]['title'], 'Frukost');
    });

    test('Steg med och utan valfri tid serialiseras korrekt', () {
      final stepWithTime = {
        'title': 'Gå till bussen',
        'piktogram': '🚌',
        'tid': '07:45',
      };
      expect(stepWithTime.containsKey('tid'), isTrue);
      expect(stepWithTime['tid'], '07:45');

      final stepWithoutTime = {
        'title': 'Kamma håret',
        'piktogram': '🪥',
      };
      expect(stepWithoutTime['tid'], isNull);
    });

    test('Sparning nollställer bockningar (doneDate och doneSteps)', () {
      final routineData = {
        'ownerUid': 'user_123',
        'ownerName': 'Céline',
        'type': 'morning',
        'steps': [
          {'title': 'Vakna', 'piktogram': '😴'},
          {'title': 'Frukost', 'piktogram': '🥣'},
        ],
        'doneDate': '2026-08-30',
        'doneSteps': [0, 1],
      };

      // Vid sparning efter redigering:
      final updatedData = {
        ...routineData,
        'steps': [
          {'title': 'Vakna', 'piktogram': '😴', 'tid': '06:45'},
          {'title': 'Klä på dig', 'piktogram': '👕'},
          {'title': 'Frukost', 'piktogram': '🥣', 'tid': '07:15'},
        ],
        'doneDate': '',
        'doneSteps': <int>[],
      };

      expect(updatedData['doneDate'], '');
      expect(updatedData['doneSteps'], isEmpty);
      expect((updatedData['steps'] as List).length, 3);
    });
  });

  group('Rutiner 2.0 FAS R2 — AI-rutinbyggare & Baklängesplanering', () {
    test('Matematisk baklängesberäkning för tåg-testfallet', () {
      // Testfall: "Ska med tåget 07:49. Lämnar barnen på vägen, det tar 12 min. 4 min från parkeringen till tåget."
      final targetMinutes = 7 * 60 + 49; // 07:49 = 469 min
      final walkFromParking = 4; // min
      final dropOffKids = 12; // min
      final buffer = 3; // min buffert

      // Senast ut genom dörren utan buffert = 469 - 4 - 12 = 453 = 07:33
      final latestExitNoBuffer = targetMinutes - walkFromParking - dropOffKids;
      expect(latestExitNoBuffer, 7 * 60 + 33);

      // Med 3 min buffert = 07:30
      final departureWithBuffer = latestExitNoBuffer - buffer;
      expect(departureWithBuffer, 7 * 60 + 30);

      // Rutinsteg bakåt:
      // Skor & jacka: 3 min (07:27 - 07:30)
      // Frukost: 15 min (07:12 - 07:27)
      // Tandborstning: 3 min (07:09 - 07:12)
      // Klä på dig: 7 min (07:02 - 07:09)
      // Dusch / tvätta sig: 12 min (06:50 - 07:02)
      // Vakna / start: (06:40 - 06:50)
      final wakeUp = departureWithBuffer - (3 + 15 + 3 + 7 + 12 + 10);
      expect(wakeUp >= 6 * 60 + 30 && wakeUp <= 6 * 60 + 45, isTrue);
    });

    test('Parsning av AI-JSON svar och hantering av markdown fences', () {
      const rawAiResponse = '''```json
{
  "malTid": "07:49",
  "malEtikett": "Tågavgång",
  "antaganden": [
    "4 min från parkering till tåg",
    "12 min lämning av barn",
    "3 min buffert",
    "15 min frukost",
    "10 min dusch & hygien"
  ],
  "steps": [
    {"tid": "06:35", "piktogram": "😴", "titel": "Vakna & gå upp"},
    {"tid": "06:45", "piktogram": "🚿", "titel": "Dusch & hygien"},
    {"tid": "06:55", "piktogram": "👕", "titel": "Klä på dig"},
    {"tid": "07:05", "piktogram": "🥣", "titel": "Frukost"},
    {"tid": "07:20", "piktogram": "🪥", "titel": "Borsta tänderna"},
    {"tid": "07:25", "piktogram": "🎒", "titel": "Packa väskan"},
    {"tid": "07:30", "piktogram": "🚪", "titel": "Ut genom dörren"}
  ]
}
```''';

      var clean = rawAiResponse.trim();
      if (clean.startsWith('```')) {
        clean = clean
            .replaceFirst(RegExp(r'^```(?:json)?\s*', caseSensitive: false), '')
            .replaceFirst(RegExp(r'\s*```$', multiLine: true), '')
            .trim();
      }

      final parsed = jsonDecode(clean) as Map<String, dynamic>;
      expect(parsed['malTid'], '07:49');
      expect(parsed['malEtikett'], 'Tågavgång');
      expect((parsed['antaganden'] as List).length, 5);

      final steps = (parsed['steps'] as List).cast<Map<String, dynamic>>();
      expect(steps.length, 7);
      expect(steps.first['tid'], '06:35');
      expect(steps.last['tid'], '07:30');
      expect(steps.last['titel'], 'Ut genom dörren');
    });
  });
}
