import 'package:firebase_auth/firebase_auth.dart';

import '../providers/family_provider.dart';

/// Är samma session fortfarande aktiv? Sant bara om Firebase-inloggningen,
/// providerns användare och providerns familj alla är de som gällde när
/// arbetet startade. Används av packlistekön före varje serveranrop, så att
/// ett konto- eller familjebyte mitt i en sparning aldrig raderar en köpost.
///
/// [authUid] kan bytas ut i tester; standard är Firebase-inloggningen.
bool Function() sessionGuard({
  required String uid,
  required String familyId,
  required FamilyProvider provider,
  String? Function()? authUid,
}) {
  final currentAuthUid =
      authUid ?? () => FirebaseAuth.instance.currentUser?.uid;
  return () =>
      currentAuthUid() == uid &&
      provider.currentUser?.uid == uid &&
      provider.currentUser?.familyId == familyId;
}
