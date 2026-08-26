import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'family_service.dart';

/// Engångsmigrationer som körs vid app-uppstart.
///
/// Alla migrationer ska vara **idempotenta** — säkra att köra om och om igen.
class MigrationService {
  /// Tilldelar en unik medlemsfärg till den inloggade användaren om de:
  ///  - saknar färg, eller
  ///  - har gamla default-grön (`ff6bae75`) som onboarding råkade lämna kvar.
  ///
  /// Hämtar nästa lediga färg från [FamilyService.assignNextAvailableColor]
  /// och uppdaterar `users/{uid}.color`. Fire-and-forget — blockera inte UI.
  static Future<void> backfillMemberColors() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final myDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      if (!myDoc.exists) return;
      final data = myDoc.data()!;
      final currentColor = (data['color'] as String?)?.toLowerCase();
      final familyId = data['familyId'] as String?;
      if (familyId == null || familyId.isEmpty) return;

      // Kör bara om användaren har gamla default-färgen eller saknar färg.
      if (currentColor == null ||
          currentColor.isEmpty ||
          currentColor == 'ff6bae75') {
        final newColor =
            await FamilyService.assignNextAvailableColor(familyId);
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .update({'color': newColor});
        developer.log(
          'backfillMemberColors: $uid fick färg $newColor',
          name: 'MigrationService',
        );
      }
    } catch (e, stack) {
      developer.log(
        'backfillMemberColors error',
        name: 'MigrationService',
        error: e,
        stackTrace: stack,
      );
    }
  }
}
