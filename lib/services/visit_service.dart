import 'dart:developer' as developer;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Modell för besökslänk (`visit_links`).
class VisitLinkModel {
  final String linkId;
  final String familyId;
  final String personUid;
  final String personName;
  final String token;
  final String url;
  final bool active;
  final int startHour;
  final int endHour;
  final int weekendStartHour;
  final int weekendEndHour;
  final int slotMinutes;
  final int arrivalStepMinutes;
  final int dinnerStartHour;
  final int dinnerEndHour;
  final int weekendLunchStartHour;
  final int weekendLunchEndHour;
  final int maxPartySize;
  final int maxBookingsPerDay;
  final int visitMaxMinutes;
  final int daysAhead;
  final String createdByUid;

  const VisitLinkModel({
    required this.linkId,
    required this.familyId,
    required this.personUid,
    required this.personName,
    required this.token,
    required this.url,
    required this.active,
    this.startHour = 16,
    this.endHour = 20,
    this.weekendStartHour = 11,
    this.weekendEndHour = 20,
    this.slotMinutes = 60,
    this.arrivalStepMinutes = 30,
    this.dinnerStartHour = 17,
    this.dinnerEndHour = 18,
    this.weekendLunchStartHour = 12,
    this.weekendLunchEndHour = 13,
    this.maxPartySize = 2,
    this.maxBookingsPerDay = 1,
    this.visitMaxMinutes = 60,
    this.daysAhead = 14,
    required this.createdByUid,
  });

  factory VisitLinkModel.fromMap(Map<String, dynamic> m) {
    return VisitLinkModel(
      linkId: m['linkId'] as String? ?? '',
      familyId: m['familyId'] as String? ?? '',
      personUid: m['personUid'] as String? ?? '',
      personName: m['personName'] as String? ?? '',
      token: m['token'] as String? ?? '',
      url: m['url'] as String? ?? '',
      active: m['active'] as bool? ?? true,
      startHour: (m['startHour'] as num?)?.toInt() ?? 16,
      endHour: (m['endHour'] as num?)?.toInt() ?? 20,
      weekendStartHour: (m['weekendStartHour'] as num?)?.toInt() ?? 11,
      weekendEndHour: (m['weekendEndHour'] as num?)?.toInt() ?? 20,
      slotMinutes: (m['slotMinutes'] as num?)?.toInt() ?? 60,
      arrivalStepMinutes: (m['arrivalStepMinutes'] as num?)?.toInt() ?? 30,
      dinnerStartHour: (m['dinnerStartHour'] as num?)?.toInt() ?? 17,
      dinnerEndHour: (m['dinnerEndHour'] as num?)?.toInt() ?? 18,
      weekendLunchStartHour: (m['weekendLunchStartHour'] as num?)?.toInt() ?? 12,
      weekendLunchEndHour: (m['weekendLunchEndHour'] as num?)?.toInt() ?? 13,
      maxPartySize: (m['maxPartySize'] as num?)?.toInt() ?? 2,
      maxBookingsPerDay: (m['maxBookingsPerDay'] as num?)?.toInt() ?? 1,
      visitMaxMinutes: (m['visitMaxMinutes'] as num?)?.toInt() ?? 60,
      daysAhead: (m['daysAhead'] as num?)?.toInt() ?? 14,
      createdByUid: m['createdByUid'] as String? ?? '',
    );
  }
}

/// Modell för en aktiv eller avbokad besöksbokning (`visit_bookings`).
class VisitBookingModel {
  final String bookingId;
  final String linkId;
  final String familyId;
  final String date;
  final String time;
  final String names;
  final int partySize;
  final String phone;
  final String status;
  final String editToken;
  final String? plannerEventId;

  const VisitBookingModel({
    required this.bookingId,
    required this.linkId,
    required this.familyId,
    required this.date,
    required this.time,
    required this.names,
    required this.partySize,
    required this.phone,
    required this.status,
    this.editToken = '',
    this.plannerEventId,
  });

  factory VisitBookingModel.fromMap(Map<String, dynamic> m) {
    return VisitBookingModel(
      bookingId: m['bookingId'] as String? ?? '',
      linkId: m['linkId'] as String? ?? '',
      familyId: m['familyId'] as String? ?? '',
      date: m['date'] as String? ?? '',
      time: m['time'] as String? ?? '',
      names: m['names'] as String? ?? '',
      partySize: (m['partySize'] as num?)?.toInt() ?? 1,
      phone: m['phone'] as String? ?? '',
      status: m['status'] as String? ?? 'active',
      editToken: m['editToken'] as String? ?? '',
      plannerEventId: m['plannerEventId'] as String?,
    );
  }
}

/// Klientwrapper för Cloud Functions relaterade till besöksbokning.
class VisitService {
  /// Hämtar befintlig aktiv besökslänk. Returnerar null om ingen aktiv länk finns och inget personUid angavs.
  static Future<VisitLinkModel?> createOrGetVisitLink({String? personUid}) async {
    if (FirebaseAuth.instance.currentUser == null) {
      throw StateError('Inte inloggad');
    }
    try {
      final res = await FirebaseFunctions.instance
          .httpsCallable('createOrGetVisitLink')
          .call<Map<String, dynamic>>({
        if (personUid != null && personUid.isNotEmpty) 'personUid': personUid,
      });
      final data = res.data;
      if (data['exists'] == false) {
        return null;
      }
      return VisitLinkModel.fromMap(Map<String, dynamic>.from(data));
    } catch (e, stack) {
      developer.log('createOrGetVisitLink misslyckades',
          error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Skapar en ny bokningslänk med ny token och deaktiverar gamla länkar.
  static Future<VisitLinkModel> regenerateVisitLink({
    String? linkId,
    String? personUid,
  }) async {
    if (FirebaseAuth.instance.currentUser == null) {
      throw StateError('Inte inloggad');
    }
    try {
      final res = await FirebaseFunctions.instance
          .httpsCallable('regenerateVisitLink')
          .call<Map<String, dynamic>>({
        if (linkId != null && linkId.isNotEmpty) 'linkId': linkId,
        if (personUid != null && personUid.isNotEmpty) 'personUid': personUid,
      });
      return VisitLinkModel.fromMap(Map<String, dynamic>.from(res.data));
    } catch (e, stack) {
      developer.log('regenerateVisitLink misslyckades',
          error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Sätter status för en specifik dag ('green', 'yellow', 'red').
  static Future<void> setVisitDayStatus({
    required String linkId,
    required String date,
    required String status,
  }) async {
    if (FirebaseAuth.instance.currentUser == null) {
      throw StateError('Inte inloggad');
    }
    try {
      await FirebaseFunctions.instance
          .httpsCallable('setVisitDayStatus')
          .call<Map<String, dynamic>>({
        'linkId': linkId,
        'date': date,
        'status': status,
      });
    } catch (e, stack) {
      developer.log('setVisitDayStatus misslyckades',
          error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Listar aktiva besöksbokningar från och med angivet datum.
  static Future<List<VisitBookingModel>> listVisitBookings({
    String? linkId,
    String? fromDate,
  }) async {
    if (FirebaseAuth.instance.currentUser == null) {
      throw StateError('Inte inloggad');
    }
    try {
      final res = await FirebaseFunctions.instance
          .httpsCallable('listVisitBookings')
          .call<Map<String, dynamic>>({
        if (linkId != null && linkId.isNotEmpty) 'linkId': linkId,
        if (fromDate != null && fromDate.isNotEmpty) 'fromDate': fromDate,
      });
      final rawList = res.data['bookings'] as List<dynamic>? ?? const [];
      return rawList
          .map((b) => VisitBookingModel.fromMap(
              Map<String, dynamic>.from(b as Map)))
          .toList();
    } catch (e, stack) {
      developer.log('listVisitBookings misslyckades',
          error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Avbokar en bokning i adminläget (förälder) och tar bort kalenderhändelsen.
  static Future<void> cancelVisitBookingAdmin({
    required String bookingId,
  }) async {
    if (FirebaseAuth.instance.currentUser == null) {
      throw StateError('Inte inloggad');
    }
    try {
      await FirebaseFunctions.instance
          .httpsCallable('cancelVisitBookingAdmin')
          .call<Map<String, dynamic>>({
        'bookingId': bookingId,
      });
    } catch (e, stack) {
      developer.log('cancelVisitBookingAdmin misslyckades',
          error: e, stackTrace: stack);
      rethrow;
    }
  }
}
