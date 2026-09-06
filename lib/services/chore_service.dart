import 'dart:developer' as developer;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/date_utils.dart';

/// Klient för `completeChore`-callablen (Fas 2–3).
class ChoreService {
  /// Bockar av / ångrar en syssla via servern.
  /// Engångs → `isDone` + logg `choreId`.
  /// Återkommande → `doneDates` arrayUnion/Remove + logg `{choreId}_{dateKey}`.
  static Future<void> completeChore({
    required String choreId,
    required bool done,
    String? dayKey,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw StateError('Inte inloggad');
    }
    try {
      await FirebaseFunctions.instance
          .httpsCallable('completeChore')
          .call<Map<String, dynamic>>({
        'choreId': choreId,
        'done': done,
        'dateKey': dayKey ?? dateKey(DateTime.now()),
      });
    } catch (e, stack) {
      developer.log('completeChore misslyckades', error: e, stackTrace: stack);
      rethrow;
    }
  }
}
