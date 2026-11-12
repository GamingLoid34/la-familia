import 'dart:developer' as developer;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Klient för ICS-prenumeration via Cloud Functions.
class CalendarFeedService {
  /// Ny prenumeration eller omsynk. [importId] sätts vid "Synka nu".
  static Future<({String importId, int eventCount})> subscribe({
    required String url,
    required String name,
    String? person,
    String? personUid,
    required String targetType,
    String? importId,
  }) async {
    if (FirebaseAuth.instance.currentUser == null) {
      throw StateError('Inte inloggad');
    }
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('subscribeCalendarFeed')
          .call<Map<String, dynamic>>({
        'url': url,
        'name': name,
        'person': person,
        'personUid': personUid,
        'targetType': targetType,
        if (importId != null && importId.isNotEmpty) 'importId': importId,
      });
      final data = result.data;
      return (
        importId: data['importId'] as String? ?? importId ?? '',
        eventCount: (data['eventCount'] as num?)?.toInt() ?? 0,
      );
    } catch (e, stack) {
      developer.log('subscribeCalendarFeed misslyckades',
          error: e, stackTrace: stack);
      rethrow;
    }
  }
}
