import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/utils/svenska_dagar.dart';

void main() {
  group('FAS 5 — Svenska namnsdagar', () {
    test('1. Kända datum returnerar officiella namn', () {
      expect(namnsdagFor(DateTime(2026, 1, 2)), ['Svea']);
      expect(namnsdagFor(DateTime(2026, 1, 19)), ['Henrik', 'Henry']);
      expect(namnsdagFor(DateTime(2026, 2, 28)), ['Maria', 'Maja']);
      expect(namnsdagFor(DateTime(2026, 3, 12)), ['Viktoria', 'Regina']);
      expect(namnsdagFor(DateTime(2026, 3, 31)), ['Ester', 'Noa']);
      expect(namnsdagFor(DateTime(2026, 6, 6)), ['Gustav', 'Gösta']);
      expect(namnsdagFor(DateTime(2026, 7, 29)), ['Olof', 'Olle']);
      expect(namnsdagFor(DateTime(2026, 11, 2)), ['Tobias', 'Tim']);
      expect(namnsdagFor(DateTime(2026, 12, 3)), ['Lydia', 'Cornelia']);
      expect(namnsdagFor(DateTime(2026, 12, 24)), ['Eva']);
    });

    test('2. Skottdagen 29 februari och namnlösa dagar är tomma', () {
      expect(namnsdagFor(DateTime(2024, 2, 29)), isEmpty);
      expect(namnsdagFor(DateTime(2026, 1, 1)), isEmpty);
      expect(namnsdagFor(DateTime(2026, 12, 25)), isEmpty);
    });
  });

  group('FAS 5 — Påskberäkning & rörliga helgdagar (Gauss/Meeus)', () {
    test('1. Påskdagen beräknas korrekt för flera år', () {
      expect(SvenskaDagar.paskdagen(2024), DateTime(2024, 3, 31));
      expect(SvenskaDagar.paskdagen(2025), DateTime(2025, 4, 20));
      expect(SvenskaDagar.paskdagen(2026), DateTime(2026, 4, 5));
      expect(SvenskaDagar.paskdagen(2027), DateTime(2027, 3, 28));
    });

    test('2. Midsommardagen infaller lördagen mellan 20 och 26 juni', () {
      final midsommar2026 = SvenskaDagar.midsommardagen(2026);
      expect(midsommar2026.weekday, DateTime.saturday);
      expect(midsommar2026, DateTime(2026, 6, 20));

      final midsommar2025 = SvenskaDagar.midsommardagen(2025);
      expect(midsommar2025.weekday, DateTime.saturday);
      expect(midsommar2025, DateTime(2025, 6, 21));
    });

    test('3. Alla helgons dag infaller lördagen mellan 31 okt och 6 nov', () {
      final allhelgona2026 = SvenskaDagar.allaHelgonsDag(2026);
      expect(allhelgona2026.weekday, DateTime.saturday);
      expect(allhelgona2026, DateTime(2026, 10, 31));

      final allhelgona2025 = SvenskaDagar.allaHelgonsDag(2025);
      expect(allhelgona2025.weekday, DateTime.saturday);
      expect(allhelgona2025, DateTime(2025, 11, 1));
    });
  });

  group('FAS 5 — Röda dagar & helgdagar', () {
    test('1. Fasta helgdagar identifieras', () {
      expect(rodDagFor(DateTime(2026, 1, 1)), 'Nyårsdagen');
      expect(rodDagFor(DateTime(2026, 1, 6)), 'Trettondedag jul');
      expect(rodDagFor(DateTime(2026, 5, 1)), 'Första maj');
      expect(rodDagFor(DateTime(2026, 6, 6)), 'Sveriges nationaldag');
      expect(rodDagFor(DateTime(2026, 12, 25)), 'Juldagen');
      expect(rodDagFor(DateTime(2026, 12, 26)), 'Annandag jul');
    });

    test('2. Påskhelgens röda dagar 2026', () {
      expect(rodDagFor(DateTime(2026, 4, 3)), 'Långfredagen');
      expect(rodDagFor(DateTime(2026, 4, 5)), 'Påskdagen');
      expect(rodDagFor(DateTime(2026, 4, 6)), 'Annandag påsk');
      expect(rodDagFor(DateTime(2026, 5, 14)), 'Kristi himmelsfärdsdag');
      expect(rodDagFor(DateTime(2026, 5, 24)), 'Pingstdagen');
    });

    test('3. Midsommar och Alla helgons dag', () {
      expect(rodDagFor(DateTime(2026, 6, 20)), 'Midsommardagen');
      expect(rodDagFor(DateTime(2026, 10, 31)), 'Alla helgons dag');
    });

    test('4. Söndagar räknas som röd dag', () {
      // 13 september 2026 är en vanlig söndag
      expect(rodDagFor(DateTime(2026, 9, 13)), 'Söndag');
      expect(isRodDag(DateTime(2026, 9, 13)), true);
    });

    test('5. Vanliga vardagar är inte röd dag', () {
      // Tisdag 8 september 2026
      expect(rodDagFor(DateTime(2026, 9, 8)), isNull);
      expect(isRodDag(DateTime(2026, 9, 8)), false);
    });
  });

  group('FAS 5 — Flaggdagar', () {
    test('1. Fasta och rörliga flaggdagar', () {
      expect(flaggdagFor(DateTime(2026, 6, 6)), 'Sveriges nationaldag');
      expect(isFlaggdag(DateTime(2026, 6, 6)), true);

      expect(flaggdagFor(DateTime(2026, 4, 5)), 'Påskdagen');
      expect(isFlaggdag(DateTime(2026, 4, 5)), true);

      expect(flaggdagFor(DateTime(2026, 5, 24)), 'Pingstdagen');
      expect(flaggdagFor(DateTime(2026, 6, 20)), 'Midsommardagen');

      expect(flaggdagFor(DateTime(2026, 1, 28)), 'Konungens namnsdag');
      expect(flaggdagFor(DateTime(2026, 3, 12)), 'Kronprinsessans namnsdag');
      expect(flaggdagFor(DateTime(2026, 4, 30)), 'Konungens födelsedag');
    });

    test('2. Vanlig dag är inte flaggdag', () {
      expect(flaggdagFor(DateTime(2026, 9, 8)), isNull);
      expect(isFlaggdag(DateTime(2026, 9, 8)), false);
    });
  });
}
