/* eslint-disable max-len */
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

/**
 * Builds the callable handler without requiring real Auth accounts in tests.
 * @param {object} services Firebase Admin services.
 * @return {Function} Callable request handler.
 */
function createUserHandler(services) {
  return async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Du måste vara inloggad för att skapa en användare.");
    }
    const {email, password, name, role = "child", familyId, color} = request.data || {};
    if (![email, password, name, familyId].every((value) => typeof value === "string" && value.trim())) {
      throw new HttpsError("invalid-argument", "Saknar nödvändig data för att skapa kontot.");
    }
    if (!["parent", "admin", "child", "youth"].includes(role)) {
      throw new HttpsError("invalid-argument", "Ogiltig roll.");
    }

    // Admin SDK bypasses Firestore rules: validate BEFORE creating an Auth account.
    const caller = await services.firestore().collection("users").doc(request.auth.uid).get();
    const profile = caller.exists ? caller.data() : null;
    if (!profile || !["parent", "admin"].includes(profile.role) || profile.familyId !== familyId) {
      throw new HttpsError("permission-denied", "Du måste vara förälder i samma familj för att skapa en medlem.");
    }
    const family = await services.firestore().collection("families").doc(familyId).get();
    if (!family.exists) {
      throw new HttpsError("failed-precondition", "Familjen finns inte längre.");
    }

    try {
      const userRecord = await services.auth().createUser({email, password, displayName: name});
      await services.firestore().collection("users").doc(userRecord.uid).set({
        uid: userRecord.uid,
        email,
        name,
        familyId,
        role,
        color: color || "ff2196f3",
        createdAt: services.firestore.FieldValue.serverTimestamp(),
        energy: 3,
        viewMode: (role === "parent" || role === "admin") ? "parent" : "child",
      });
      return {uid: userRecord.uid, success: true};
    } catch (error) {
      throw new HttpsError("internal", error.message);
    }
  };
}

exports.createUser = onCall(createUserHandler(admin));
exports._test = {createUserHandler};
