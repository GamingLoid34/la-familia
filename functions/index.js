const functions = require("firebase-functions");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");
admin.initializeApp();

// ─── 1. SKAPA ANVÄNDARE (Callable Function) ──────────────────────────────────
exports.createUser = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError(
            "unauthenticated",
            "Du måste vara inloggad för att skapa en användare."
        );
    }

    const { email, password, name, role, familyId, color } = data;

    if (!email || !password || !name || !familyId) {
        throw new functions.https.HttpsError(
            "invalid-argument",
            "Saknar nödvändig data för att skapa kontot."
        );
    }

    try {
        const userRecord = await admin.auth().createUser({
            email: email,
            password: password,
            displayName: name,
        });

        await admin.firestore().collection("users").doc(userRecord.uid).set({
            uid: userRecord.uid,
            email: email,
            name: name,
            familyId: familyId,
            role: role || "child",
            color: color || "ff2196f3",
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            energy: 3,
            weeklyPoints: 0,
            points: 0,
            viewMode: (role === "parent" || role === "admin") ? "parent" : "child",
        });

        return { uid: userRecord.uid, success: true };
    } catch (error) {
        console.error("Kunde inte skapa användare:", error);
        throw new functions.https.HttpsError("internal", error.message);
    }
});

// ─── 2. NOLLSTÄLL VECKOPOÄNG (Schemalagd Cron Job) ───────────────────────────
exports.resetWeeklyPoints = onSchedule({
    schedule: "59 23 * * 0", // Körs 23:59 varje söndag (0 = Söndag)
    timeZone: "Europe/Stockholm"
}, async (event) => {
    const db = admin.firestore();
    const usersSnap = await db.collection("users").get();

    if (usersSnap.empty) {
        console.log("Inga användare hittades för nollställning.");
        return null;
    }

    let batch = db.batch();
    let opCount = 0;
    const nowIso = new Date().toISOString();

    for (const doc of usersSnap.docs) {
        const data = doc.data();
        const currentPoints = data.weeklyPoints || 0;

        // Spara historik innan vi nollställer
        const historyRef = doc.ref.collection("points_history").doc();
        batch.set(historyRef, {
            points: currentPoints,
            weekOf: nowIso,
            resetAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        // Nollställ poängen
        batch.update(doc.ref, {
            weeklyPoints: 0,
            pointsResetDate: admin.firestore.FieldValue.serverTimestamp(),
        });

        opCount += 2;

        // Firestore tillåter max 500 operationer per batch. Vi delar upp i chunkar om 400.
        if (opCount >= 400) {
            await batch.commit();
            batch = db.batch();
            opCount = 0;
        }
    }

    // Skicka in eventuella återstående operationer
    if (opCount > 0) {
        await batch.commit();
    }

    console.log("Veckopoäng har nollställts och historik har sparats för alla användare.");
    return null;
});