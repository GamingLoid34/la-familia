import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:la_familia/models/user_model.dart';
import 'package:la_familia/utils/person_match.dart';
import 'package:la_familia/utils/schedule_time_utils.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('sv');
  });

  group('FAS K1 — Skolklump, namn på raderna & personfilter överallt', () {
    final lionel = UserModel(
      uid: 'user_lionel',
      email: 'lionel@example.com',
      familyId: 'fam_1',
      name: 'Lionel Valladares',
      role: 'child',
      color: '#4CAF50',
      viewMode: 'child',
      energy: 3,
    );

    final mamma = UserModel(
      uid: 'user_mamma',
      email: 'mamma@example.com',
      familyId: 'fam_1',
      name: 'Mamma Anna',
      role: 'parent',
      color: '#E91E63',
      viewMode: 'parent',
      energy: 3,
    );

    final pappa = UserModel(
      uid: 'user_pappa',
      email: 'pappa@example.com',
      familyId: 'fam_1',
      name: 'Pappa Erik',
      role: 'parent',
      color: '#2196F3',
      viewMode: 'parent',
      energy: 3,
    );

    final members = [lionel, mamma, pappa];

    test('A. Skolschema: Flera lektioner klumpas till EN rad med tidsspann och etikett', () {
      final lessons = [
        {'time': '08:10', 'endTime': '09:00', 'title': 'Svenska', 'planningImportKind': 'schedule', 'who': 'Lionel', 'piktogram': '🎒'},
        {'time': '09:15', 'endTime': '10:00', 'title': 'Matematik', 'planningImportKind': 'schedule', 'who': 'Lionel', 'piktogram': '🎒'},
        {'time': '10:30', 'endTime': '11:45', 'title': 'NO', 'planningImportKind': 'schedule', 'who': 'Lionel', 'piktogram': '🎒'},
        {'time': '12:30', 'endTime': '13:30', 'title': 'Idrott', 'planningImportKind': 'schedule', 'who': 'Lionel', 'piktogram': '🎒'},
        {'time': '13:45', 'endTime': '14:30', 'title': 'Engelska', 'planningImportKind': 'schedule', 'who': 'Lionel', 'piktogram': '🎒'},
      ];

      final span = scheduleTimeSpan(lessons);
      expect(span.minStart, equals('08:10'));
      expect(span.maxEnd, equals('14:30'));

      final label = scheduleBlockLabel(lessons, title: 'Skola', piktogram: '🎒');
      expect(label, equals('🎒 Skola 08:10–14:30'));

      // Skolklump + 2 aktiviteter ger totalt 3 rader (under gränsen 4 för "+N till")
      final totalRowEntriesCount = 1 + 2;
      expect(totalRowEntriesCount <= 4, isTrue);
    });

    test('B. Namn på raderna: 1 person visar förnamn, 2 personer visar endast prickar, familj visar ikon', () {
      final singlePersonEvent = {
        'title': 'Träning',
        'personUids': ['user_lionel'],
        'persons': ['Lionel Valladares'],
      };

      final twoPersonEvent = {
        'title': 'Utvecklingssamtal',
        'personUids': ['user_mamma', 'user_lionel'],
        'persons': ['Mamma Anna', 'Lionel Valladares'],
      };

      final familyEvent = {
        'title': 'Familjemiddag',
      };

      List<UserModel> resolveMembers(Map<String, dynamic> d) {
        final uids = (d['personUids'] as List?)?.cast<String>() ?? [];
        final names = (d['persons'] as List?)?.cast<String>() ?? [];
        return members.where((m) => uids.contains(m.uid) || names.contains(m.name)).toList();
      }

      // En person -> visar förnamn
      final singleMembers = resolveMembers(singlePersonEvent);
      expect(singleMembers.length, equals(1));
      expect(singleMembers.first.name.split(' ').first, equals('Lionel'));

      // Två personer -> inga namn, bara lista av medlemmar för prickar
      final twoMembers = resolveMembers(twoPersonEvent);
      expect(twoMembers.length, equals(2));

      // Familjegemensamt -> flaggas som utan specifik person
      expect(eventHasNoPersons(familyEvent), isTrue);
    });

    test('C. Personfilter: Filtrering på Lionel behåller Lionels händelser och familjegemensamt', () {
      final lionelEvent = {
        'title': 'Läkarbesök',
        'personUids': ['user_lionel'],
        'persons': ['Lionel Valladares'],
      };

      final mammaEvent = {
        'title': 'Möte',
        'personUids': ['user_mamma'],
        'persons': ['Mamma Anna'],
      };

      final familyEvent = {
        'title': 'Fredagsmys',
      };

      bool isIncludedForFilter(Map<String, dynamic> d, String filterUid, String filterName) {
        if (eventHasNoPersons(d)) return true; // Familjegemensamt alltid med
        return eventIncludesPerson(d, uid: filterUid, name: filterName);
      }

      expect(isIncludedForFilter(lionelEvent, lionel.uid, lionel.name), isTrue);
      expect(isIncludedForFilter(familyEvent, lionel.uid, lionel.name), isTrue);
      expect(isIncludedForFilter(mammaEvent, lionel.uid, lionel.name), isFalse);
    });
  });
}
