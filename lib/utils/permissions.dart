import '../models/user_model.dart';

/// Får användaren redigera/radera dokumentet?
/// Förälder/admin: ja. Ägare (`createdByUid`): ja.
/// Saknat `createdByUid` (legacy) ⇒ endast förälder.
bool canEditDoc(UserModel? me, Map<String, dynamic> data) {
  if (me == null) return false;
  if (me.isParent) return true;
  final createdBy = data['createdByUid'] as String?;
  if (createdBy == null || createdBy.isEmpty) return false;
  return createdBy == me.uid;
}
