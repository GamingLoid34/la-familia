const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");
admin.initializeApp();

// ─── 1. SKAPA ANVÄNDARE (Callable Function) ──────────────────────────────────
exports.createUser = onCall(async (request) => {
    if (!request.auth) {
        throw new HttpsError(
            "unauthenticated",
            "Du måste vara inloggad för att skapa en användare."
        );
    }

    const { email, password, name, role, familyId, color } = request.data;

    if (!email || !password || !name || !familyId) {
        throw new HttpsError(
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
        throw new HttpsError("internal", error.message);
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

// ─── MIGRERING: ZERO-PADDA DATUMFÄLT (engångs, ROADMAP Etapp 2.4) ────────────
// Paddar `date`/`dueDate` från t.ex. "2026-5-3" till "2026-05-03" i
// planner_events, chores och work_shifts. Endast förälder/admin får köra.
// Idempotent — säker att köra flera gånger. TA EN FIRESTORE-BACKUP FÖRST.
// Ta bort funktionen (och dess anropsknapp) när migreringen är verifierad.
exports.migrateDateFormatOnce = onCall(async (request) => {
    if (!request.auth) {
        throw new HttpsError("unauthenticated", "Inloggning krävs.");
    }
    const callerDoc = await admin.firestore()
        .collection("users").doc(request.auth.uid).get();
    const callerRole = callerDoc.data()?.role;
    if (callerRole !== "admin" && callerRole !== "parent") {
        throw new HttpsError("permission-denied", "Endast förälder/admin.");
    }

    const collections = ["planner_events", "chores", "work_shifts"];
    const unpadded = /^(\d{4})-(\d{1,2})-(\d{1,2})$/;
    let migrated = 0;

    for (const coll of collections) {
        const snap = await admin.firestore().collection(coll).get();
        let batch = admin.firestore().batch();
        let count = 0;

        for (const doc of snap.docs) {
            const d = doc.data();
            const updates = {};
            for (const field of ["date", "dueDate"]) {
                const v = d[field];
                if (typeof v === "string") {
                    const m = v.match(unpadded);
                    if (m) {
                        const padded = `${m[1]}-${m[2].padStart(2, "0")}-${m[3].padStart(2, "0")}`;
                        if (padded !== v) updates[field] = padded;
                    }
                }
            }
            if (Object.keys(updates).length > 0) {
                batch.update(doc.ref, updates);
                count++;
                migrated++;
                if (count >= 400) {
                    await batch.commit();
                    batch = admin.firestore().batch();
                    count = 0;
                }
            }
        }
        if (count > 0) await batch.commit();
    }

    console.log(`migrateDateFormatOnce: paddade ${migrated} dokument.`);
    return { migrated };
});

// ─── MIGRERING: BACKFILL PERSON-UIDS (engångs, ROADMAP Etapp 3.3) ────────────
// Mappar namn → uid i befintlig data: planner_events.persons → personUids,
// chores.who → whoUid, work_shifts.who → whoUid, busy_sessions.userName →
// userUid. Idempotent: hoppar över dokument som redan har uid-fält.
exports.backfillPersonUids = onCall(async (request) => {
    if (!request.auth) {
        throw new HttpsError("unauthenticated", "Inloggning krävs.");
    }
    const callerDoc = await admin.firestore()
        .collection("users").doc(request.auth.uid).get();
    const callerRole = callerDoc.data()?.role;
    if (callerRole !== "admin" && callerRole !== "parent") {
        throw new HttpsError("permission-denied", "Endast förälder/admin.");
    }

    // Bygg namn→uid per familj
    const usersSnap = await admin.firestore().collection("users").get();
    const byFamily = {}; // familyId -> { name -> uid }
    for (const doc of usersSnap.docs) {
        const u = doc.data();
        if (!u.familyId || !u.name) continue;
        (byFamily[u.familyId] ??= {})[u.name] = doc.id;
    }
    const uidFor = (familyId, name) => byFamily[familyId]?.[name] || "";

    let migrated = 0;
    let batch = admin.firestore().batch();
    let count = 0;
    const flush = async (force = false) => {
        if (count >= 400 || (force && count > 0)) {
            await batch.commit();
            batch = admin.firestore().batch();
            count = 0;
        }
    };

    // planner_events: persons[] -> personUids[]
    const events = await admin.firestore().collection("planner_events").get();
    for (const doc of events.docs) {
        const d = doc.data();
        if (Array.isArray(d.personUids) && d.personUids.length > 0) continue;
        const persons = Array.isArray(d.persons) ? d.persons : [];
        if (persons.length === 0) continue;
        const uids = persons.map((n) => uidFor(d.familyId, n)).filter(Boolean);
        if (uids.length === 0) continue;
        batch.update(doc.ref, { personUids: uids });
        count++; migrated++;
        await flush();
    }

    // chores + work_shifts: who -> whoUid
    for (const coll of ["chores", "work_shifts"]) {
        const snap = await admin.firestore().collection(coll).get();
        for (const doc of snap.docs) {
            const d = doc.data();
            if (typeof d.whoUid === "string" && d.whoUid.length > 0) continue;
            const who = d.who;
            if (typeof who !== "string" || who.length === 0) continue;
            const uid = uidFor(d.familyId, who);
            if (!uid) continue;
            batch.update(doc.ref, { whoUid: uid });
            count++; migrated++;
            await flush();
        }
    }

    // busy_sessions: userName -> userUid
    const busy = await admin.firestore().collection("busy_sessions").get();
    for (const doc of busy.docs) {
        const d = doc.data();
        if (typeof d.userUid === "string" && d.userUid.length > 0) continue;
        const uid = uidFor(d.familyId, d.userName);
        if (!uid) continue;
        batch.update(doc.ref, { userUid: uid });
        count++; migrated++;
        await flush();
    }

    await flush(true);
    console.log(`backfillPersonUids: uppdaterade ${migrated} dokument.`);
    return { migrated };
});

// ─── 3. RENSA GAMLA FAMILJENOTISER (>7 dagar) ────────────────────────────────
exports.cleanupOldFamilyNotes = onSchedule({
    schedule: "0 3 * * *",
    timeZone: "Europe/Stockholm",
}, async (event) => {
    const db = admin.firestore();
    const cutoff = new Date();
    cutoff.setDate(cutoff.getDate() - 7);

    const oldNotes = await db.collection("family_notes")
        .where("createdAt", "<", cutoff)
        .get();

    let batch = db.batch();
    let count = 0;
    for (const doc of oldNotes.docs) {
        batch.delete(doc.ref);
        count++;
        if (count >= 400) {
            await batch.commit();
            batch = db.batch();
            count = 0;
        }
    }
    if (count > 0) {
        await batch.commit();
    }
    console.log(`Tog bort ${oldNotes.size} gamla familjenotiser.`);
    return null;
});