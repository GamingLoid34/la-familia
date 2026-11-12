import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/data/lathund_content.dart';
import 'package:la_familia/utils/quick_add_parser.dart';

void main() {
  group('Lathund content and filtering tests', () {
    test('All categories and entries are well-formed', () {
      expect(lathundInnehall, isNotEmpty);

      for (final kat in lathundInnehall) {
        expect(kat.emoji, isNotEmpty);
        expect(kat.titel, isNotEmpty);
        expect(kat.poster, isNotEmpty);

        for (final entry in kat.poster) {
          expect(entry.emoji, isNotEmpty);
          expect(entry.fraga, isNotEmpty);
          expect(entry.svar, isNotEmpty);
          expect(entry.finnsHar, isNotEmpty);
          expect(entry.steg.length, lessThanOrEqualTo(3),
              reason: 'Varje post får ha max 3 steg: ${entry.fraga}');
        }
      }
    });

    test('Search "röst" finds snabbfältsposten', () {
      String normalize(String s) => foldName(s.toLowerCase().trim());
      bool matches(LathundEntry e, String query) {
        final q = normalize(query);
        return normalize(e.fraga).contains(q) ||
            normalize(e.svar).contains(q) ||
            normalize(e.finnsHar).contains(q);
      }

      final hits = <LathundEntry>[];
      for (final kat in lathundInnehall) {
        for (final entry in kat.poster) {
          if (matches(entry, 'röst')) {
            hits.add(entry);
          }
        }
      }

      expect(hits, isNotEmpty);
      expect(hits.any((e) => e.fraga.contains('röst') || e.svar.contains('röst')), isTrue);
    });

    test('Lathund contains "Varför fick jag ingen avisering?" in Påminnelser & Notiser', () {
      final notifCat = lathundInnehall.firstWhere((k) => k.titel == 'Påminnelser & Notiser');
      final entry = notifCat.poster.firstWhere((e) => e.fraga.contains('ingen avisering'));
      expect(entry.svar, contains('Upptagen'));
      expect(entry.svar, contains('energinivå'));
      expect(entry.svar, contains('15 minuter'));
      expect(entry.svar, contains('Felsök notiser'));

      final reminderLevelsEntry = notifCat.poster.firstWhere((e) => e.fraga.contains('Vilka påminnelser'));
      expect(reminderLevelsEntry.svar, contains('tre nivåer'));
      expect(reminderLevelsEntry.svar, contains('15 minuter innan'));
      expect(reminderLevelsEntry.svar, contains('övergångsvarning 10 minuter'));
      expect(reminderLevelsEntry.svar, contains('startpåminnelse'));

      final scanCat = lathundInnehall.firstWhere((k) => k.titel == 'Kalenderimport & Scheman');
      final scanEntry = scanCat.poster.firstWhere((e) => e.fraga.contains('schemaskanning'));
      expect(scanEntry.svar, contains('Skola, Rehab, Jobb'));
    });

    List<LathundKategori> filterForRole(bool isParent) {
      final filteredCategories = <LathundKategori>[];
      for (final kat in lathundInnehall) {
        final validEntries = kat.poster.where((e) {
          if (!isParent && e.endastForaldrar) return false;
          return true;
        }).toList();

        if (validEntries.isNotEmpty) {
          filteredCategories.add(LathundKategori(
            emoji: kat.emoji,
            titel: kat.titel,
            poster: validEntries,
          ));
        }
      }
      return filteredCategories;
    }

    test('Child filter removes all parent-only entries and leaves no empty categories', () {
      final filteredCategories = filterForRole(false);

      // Inga tomma kategorier
      for (final kat in filteredCategories) {
        expect(kat.poster, isNotEmpty);
        for (final entry in kat.poster) {
          expect(entry.endastForaldrar, isFalse,
              reason: 'Barn ska aldrig se endastForaldrar-poster');
        }
      }

      // Föräldra-kategorier som bara har endastForaldrar-poster (t.ex. Besöksbokning, Kalenderimport) ska filtreras bort för barn
      expect(filteredCategories.any((k) => k.titel == 'Besöksbokning'), isFalse);
      expect(filteredCategories.any((k) => k.titel == 'Kalenderimport & Scheman'), isFalse);
    });

    test('Parent sees all entries and categories', () {
      final filteredCategories = filterForRole(true);

      expect(filteredCategories.length, equals(lathundInnehall.length));
      expect(filteredCategories.any((k) => k.titel == 'Besöksbokning'), isTrue);
      expect(filteredCategories.any((k) => k.titel == 'Kalenderimport & Scheman'), isTrue);
    });
  });
}
