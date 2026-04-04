import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_model.dart';

class UserService {
  static final _db = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  /// Stream of the current user's UserModel. Emits null if not logged in.
  static Stream<UserModel?> getCurrentUserStream() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value(null);
    return _db.collection('users').doc(user.uid).snapshots().map((snap) {
      if (!snap.exists) return null;
      return UserModel.fromMap(snap.id, snap.data()!);
    });
  }

  /// One-shot fetch of the current user's model.
  static Future<UserModel?> getCurrentUserModel() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    final snap = await _db.collection('users').doc(user.uid).get();
    if (!snap.exists) return null;
    return UserModel.fromMap(snap.id, snap.data()!);
  }

  /// Update the viewMode for a user. Parents can update children's modes.
  static Future<void> updateViewMode(String uid, String mode) async {
    assert(['parent', 'focus', 'youth'].contains(mode));
    await _db.collection('users').doc(uid).update({'viewMode': mode});
  }

  /// Update energy level (1-4) for the current user.
  static Future<void> updateEnergy(String uid, int energy) async {
    final clamped = energy.clamp(1, 4);
    await _db.collection('users').doc(uid).update({'energy': clamped});
  }

  /// Add points to a user. Pass negative to subtract.
  static Future<void> addPoints(String uid, int points) async {
    await _db.collection('users').doc(uid).update({
      'weeklyPoints': FieldValue.increment(points),
      'points': FieldValue.increment(points), // legacy field
    });
  }

  /// Reset weekly points for all family members. Call every Monday.
  static Future<void> resetWeeklyPoints(String familyId) async {
    final members = await _db
        .collection('users')
        .where('familyId', isEqualTo: familyId)
        .get();

    final batch = _db.batch();
    for (final doc in members.docs) {
      // Save history before resetting
      batch.set(
        _db
            .collection('users')
            .doc(doc.id)
            .collection('points_history')
            .doc(),
        {
          'points': doc.data()['weeklyPoints'] ?? 0,
          'weekOf': DateTime.now().toIso8601String(),
          'resetAt': FieldValue.serverTimestamp(),
        },
      );
      batch.update(doc.reference, {
        'weeklyPoints': 0,
        'pointsResetDate': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }
}
