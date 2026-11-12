import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/models/user_model.dart';
import 'package:la_familia/services/visit_service.dart';
import 'package:la_familia/utils/permissions.dart';

void main() {
  UserModel makeUser({
    required String uid,
    required String name,
    String role = 'parent',
  }) {
    return UserModel(
      uid: uid,
      name: name,
      email: '$uid@test.com',
      color: 'ff6bae75',
      role: role,
      viewMode: 'parent',
      energy: 3,
    );
  }

  group('Visit booking models and permissions', () {
    test('VisitLinkModel fromMap parses correctly', () {
      final map = {
        'linkId': 'link123',
        'familyId': 'fam456',
        'personUid': 'u1',
        'personName': 'Noomi Valladares',
        'token': 'tok_abc',
        'url': 'https://la-familia-5d9f5.web.app/besok/?t=tok_abc',
        'active': true,
        'startHour': 16,
        'endHour': 20,
        'slotMinutes': 60,
        'maxPartySize': 2,
        'maxBookingsPerDay': 1,
        'daysAhead': 14,
        'createdByUid': 'uParent',
      };

      final model = VisitLinkModel.fromMap(map);
      expect(model.linkId, 'link123');
      expect(model.personName, 'Noomi Valladares');
      expect(model.token, 'tok_abc');
      expect(model.url, contains('tok_abc'));
      expect(model.startHour, 16);
      expect(model.endHour, 20);
      expect(model.weekendStartHour, 11);
      expect(model.weekendEndHour, 20);
      expect(model.arrivalStepMinutes, 30);
      expect(model.dinnerStartHour, 17);
      expect(model.dinnerEndHour, 18);
      expect(model.weekendLunchStartHour, 12);
      expect(model.weekendLunchEndHour, 13);
      expect(model.maxBookingsPerDay, 1);
      expect(model.visitMaxMinutes, 60);
    });

    test('VisitBookingModel fromMap parses correctly', () {
      final map = {
        'bookingId': 'b123',
        'linkId': 'link123',
        'familyId': 'fam456',
        'date': '2026-08-27',
        'time': '17:00',
        'names': 'Mormor & Morfar',
        'partySize': 2,
        'phone': '0701234567',
        'status': 'active',
        'editToken': 'k_edit_token_123',
        'plannerEventId': 'pe789',
      };

      final model = VisitBookingModel.fromMap(map);
      expect(model.bookingId, 'b123');
      expect(model.date, '2026-08-27');
      expect(model.time, '17:00');
      expect(model.names, 'Mormor & Morfar');
      expect(model.partySize, 2);
      expect(model.phone, '0701234567');
      expect(model.status, 'active');
      expect(model.editToken, 'k_edit_token_123');
      expect(model.plannerEventId, 'pe789');
    });

    test('canEditDoc blocks editing/deleting visit bookings (source == besok)', () {
      final parent = makeUser(uid: 'uParent', name: 'Förälder', role: 'parent');
      final child = makeUser(uid: 'uChild', name: 'Barn', role: 'child');

      final regularEvent = {
        'title': 'Fotbollsträning',
        'source': 'calendar',
        'createdByUid': 'uParent',
      };

      final visitEvent = {
        'title': '🫶 Besök: Mormor',
        'source': 'besok',
        'visitBookingId': 'b123',
        'createdByUid': 'uParent',
      };

      // Förälder får redigera vanliga events
      expect(canEditDoc(parent, regularEvent), true);

      // Förälder (och alla andra) blockeras från att redigera besöksbokning via generiska menyn
      expect(canEditDoc(parent, visitEvent), false);
      expect(canEditDoc(child, visitEvent), false);
    });

    test('VisitLinkModel parsing handles exists flag correctly', () {
      final existsFalseMap = {'exists': false};
      expect(existsFalseMap['exists'], false);

      final existsTrueMap = {
        'exists': true,
        'linkId': 'l1',
        'familyId': 'fam1',
        'personUid': 'u1',
        'personName': 'Noomi',
        'token': 'tok1',
        'url': 'https://la-familia-5d9f5.web.app/besok/?t=tok1',
        'active': true,
        'createdByUid': 'uparent',
      };

      final link = VisitLinkModel.fromMap(existsTrueMap);
      expect(link.linkId, 'l1');
      expect(link.personName, 'Noomi');
    });

    test('UserModel handles fcmTokens and pushFamilyEvents correctly', () {
      final map = {
        'name': 'Test User',
        'email': 'test@test.com',
        'color': 'ff2196f3',
        'role': 'parent',
        'viewMode': 'parent',
        'energy': 3,
        'familyId': 'fam123',
        'fcmTokens': ['token_a', 'token_b'],
        'pushFamilyEvents': true,
      };

      final user = UserModel.fromMap('u123', map);
      expect(user.fcmTokens, contains('token_a'));
      expect(user.fcmTokens, contains('token_b'));
      expect(user.pushFamilyEvents, isTrue);

      final exported = user.toMap();
      expect(exported['fcmTokens'], equals(['token_a', 'token_b']));
      expect(exported['pushFamilyEvents'], isTrue);

      final updated = user.copyWith(pushFamilyEvents: false);
      expect(updated.pushFamilyEvents, isFalse);
      expect(updated.fcmTokens.length, 2);
    });
  });
}
