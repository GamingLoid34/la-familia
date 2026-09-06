import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/models/user_model.dart';

void main() {
  group('FAS V2 — Verktyg tools list and permissions', () {
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

    final child = UserModel(
      uid: 'user_child',
      email: 'child@example.com',
      familyId: 'fam_1',
      name: 'Liam',
      role: 'child',
      color: '#2196F3',
      viewMode: 'child',
      energy: 3,
    );

    final vardagTools = [
      'Timer',
      'Inköpslista',
      'Mat & matsedel',
      'Lathund',
    ];

    final planeringTools = [
      'Arbetsschema',
      'Vardagsplan',
      'Morgon & kväll',
      'Besök',
    ];

    final importTools = [
      'Skanna schema',
      'Kalenderimport',
      'Sysslostatistik',
    ];

    test('All 11 tools are defined in exact specification order', () {
      final allTools = [...vardagTools, ...planeringTools, ...importTools];
      expect(allTools.length, equals(11));
      expect(allTools[0], equals('Timer'));
      expect(allTools[1], equals('Inköpslista'));
      expect(allTools[2], equals('Mat & matsedel'));
      expect(allTools[3], equals('Lathund'));
      expect(allTools[4], equals('Arbetsschema'));
      expect(allTools[5], equals('Vardagsplan'));
      expect(allTools[6], equals('Morgon & kväll'));
      expect(allTools[7], equals('Besök'));
      expect(allTools[8], equals('Skanna schema'));
      expect(allTools[9], equals('Kalenderimport'));
      expect(allTools[10], equals('Sysslostatistik'));
    });

    test('Child user only has access to VARDAG tools', () {
      List<String> getAvailableTools(UserModel user) {
        final tools = <String>[...vardagTools];
        if (user.isParent) {
          tools.addAll(planeringTools);
          tools.addAll(importTools);
        }
        return tools;
      }

      final childTools = getAvailableTools(child);
      expect(childTools.length, equals(4));
      expect(childTools, equals(vardagTools));

      final parentTools = getAvailableTools(parent);
      expect(parentTools.length, equals(11));
      expect(parentTools.contains('Arbetsschema'), isTrue);
      expect(parentTools.contains('Skanna schema'), isTrue);
    });
  });
}
