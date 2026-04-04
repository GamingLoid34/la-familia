import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_model.dart';

class FamilyService {
  static final _db = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  /// Stream of all family members for the given familyId.
  static Stream<List<UserModel>> getFamilyMembersStream(String familyId) {
    return _db
        .collection('users')
        .where('familyId', isEqualTo: familyId)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => UserModel.fromMap(doc.id, doc.data()))
            .toList()
          ..sort((a, b) {
            // Parents first, then alphabetically
            if (a.isParent && !b.isParent) return -1;
            if (!a.isParent && b.isParent) return 1;
            return a.name.compareTo(b.name);
          }));
  }

  /// Get the current user's familyId, then stream all members.
  static Stream<List<UserModel>> getCurrentFamilyStream() async* {
    final user = _auth.currentUser;
    if (user == null) {
      yield [];
      return;
    }
    final userDoc = await _db.collection('users').doc(user.uid).get();
    final familyId = userDoc.data()?['familyId'] as String?;
    if (familyId == null || familyId.isEmpty) {
      yield [];
      return;
    }
    yield* getFamilyMembersStream(familyId);
  }

  /// Fetch current user's model once (used for initial setup).
  static Future<UserModel?> getCurrentUserModel() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    final doc = await _db.collection('users').doc(user.uid).get();
    if (!doc.exists) return null;
    return UserModel.fromMap(doc.id, doc.data()!);
  }

  /// Get the familyId of the currently logged in user.
  static Future<String?> getCurrentFamilyId() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    final doc = await _db.collection('users').doc(user.uid).get();
    return doc.data()?['familyId'] as String?;
  }
}
