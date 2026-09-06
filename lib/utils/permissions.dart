import '../models/user_model.dart';

/// Får användaren redigera/radera dokumentet?
/// Förälder/admin: ja. Ägare (`createdByUid`): ja.
/// Saknat `createdByUid` (legacy) ⇒ endast förälder.
/// OBS: Besöksbokningar (`source == 'besok'`) kan inte redigeras eller raderas
/// via den generiska aktivitetsmenyn — all hantering och avbokning sker via
/// Besöksadmin/besöksbokningssidan för att bevara bokningsstatus och atomicitet.
bool canEditDoc(UserModel? me, Map<String, dynamic> data) {
  if (me == null) return false;
  if (data['source'] == 'besok') return false;
  if (me.isParent) return true;
  final createdBy = data['createdByUid'] as String?;
  if (createdBy == null || createdBy.isEmpty) return false;
  return createdBy == me.uid;
}
