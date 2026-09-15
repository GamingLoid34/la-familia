import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/screens/display/display_formatters.dart';

void main() {
  group('formatHeroPrefix', () {
    test('med plats returnerar "Ut genom dörren"', () {
      expect(formatHeroPrefix('Tandläkaren'), 'Ut genom dörren');
      expect(formatHeroPrefix('Sporthallen A'), 'Ut genom dörren');
      expect(formatHeroPrefix('  Simhallen  '), 'Ut genom dörren');
    });

    test('utan plats (null) returnerar "Härnäst"', () {
      expect(formatHeroPrefix(null), 'Härnäst');
    });

    test('tom sträng returnerar "Härnäst"', () {
      expect(formatHeroPrefix(''), 'Härnäst');
      expect(formatHeroPrefix('   '), 'Härnäst');
      expect(formatHeroPrefix('\t\n'), 'Härnäst');
    });
  });
}
