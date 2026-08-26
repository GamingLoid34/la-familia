const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");
admin.initializeApp();

const calendarFeeds = require("./calendar_feeds");
exports.subscribeCalendarFeed = calendarFeeds.subscribeCalendarFeed;
exports.syncCalendarFeeds = calendarFeeds.syncCalendarFeeds;

// ─── PUSH-HJÄLPARE (ROADMAP Etapp 11) ────────────────────────────────────────
// Skickar push till familjemedlemmar. Respekterar:
//  - pushFamilyEvents === false (toggle i Inställningar)
//  - energi <= 1 (låg energi → dämpa)
//  - aktiv "Upptagen"-session just nu
// Döda tokens städas bort från users-dokumenten efter varje utskick.
async function sendFamilyPush({ familyId, excludeUids = [], onlyUids = null, title, body }) {
    if (!familyId) return;
    const db = admin.firestore();
    const usersSnap = await db.collection("users")
        .where("familyId", "==", familyId).get();

    const now = admin.firestore.Timestamp.now();
    const busySnap = await db.collection("busy_sessions")
        .where("familyId", "==", familyId)
        .where("endAt", ">", now)
        .get();
    const busyUids = new Set();
    const busyNames = new Set();
    for (const doc of busySnap.docs) {
        const b = doc.data();
        if (b.startAt && b.startAt.toMillis() <= now.toMillis()) {
            if (b.userUid) busyUids.add(b.userUid);
            if (b.userName) busyNames.add(b.userName);
        }
    }

    const tokens = [];
    const tokenOwner = {};
    for (const doc of usersSnap.docs) {
        const u = doc.data();
        if (excludeUids.includes(doc.id)) continue;
        if (onlyUids && !onlyUids.includes(doc.id)) continue;
        if (u.pushFamilyEvents === false) continue;
        if ((u.energy ?? 3) <= 1) continue;
        if (busyUids.has(doc.id) || busyNames.has(u.name)) continue;
        for (const t of (u.fcmTokens || [])) {
            tokens.push(t);
            tokenOwner[t] = doc.ref;
        }
    }
    if (tokens.length === 0) return;

    const res = await admin.messaging().sendEachForMulticast({
        tokens,
        notification: { title, body },
        android: { notification: { channelId: "family_channel" } },
    });

    const removals = [];
    res.responses.forEach((r, i) => {
        if (!r.success) {
            const code = r.error?.code || "";
            if (code.includes("registration-token-not-registered") ||
                code.includes("invalid-argument")) {
                const t = tokens[i];
                removals.push(tokenOwner[t].update({
                    fcmTokens: admin.firestore.FieldValue.arrayRemove([t]),
                }));
            }
        }
    });
    await Promise.all(removals);
    console.log(`sendFamilyPush: "${title}" till ${tokens.length} enheter.`);
}

// Ny lapp på familjetavlan → alla utom avsändaren.
exports.onFamilyNoteCreated = onDocumentCreated("family_notes/{id}", async (event) => {
    const d = event.data?.data();
    if (!d) return;
    await sendFamilyPush({
        familyId: d.familyId,
        excludeUids: [d.fromUid],
        title: "Ny lapp på familjetavlan 📌",
        body: `${d.fromName || "Någon"}: ${d.text || ""}`,
    });
});

// Ny syssla med ansvarig → bara den personen.
exports.onChoreAssigned = onDocumentCreated("chores/{id}", async (event) => {
    const d = event.data?.data();
    if (!d || !d.whoUid) return;
    await sendFamilyPush({
        familyId: d.familyId,
        onlyUids: [d.whoUid],
        title: "Ny syssla till dig ✅",
        body: `${d.piktogram || ""} ${d.chore || d.title || ""}`.trim(),
    });
});

// Tilldelning ändrad till ny person → samma push som vid ny syssla.
exports.onChoreAssignedUpdate = onDocumentUpdated("chores/{id}", async (event) => {
    const before = event.data?.before.data() || {};
    const after = event.data?.after.data() || {};
    const prevUid = typeof before.whoUid === "string" ? before.whoUid : "";
    const nextUid = typeof after.whoUid === "string" ? after.whoUid : "";
    if (!nextUid || nextUid === prevUid) return;
    await sendFamilyPush({
        familyId: after.familyId,
        onlyUids: [nextUid],
        title: "Ny syssla till dig ✅",
        body: `${after.piktogram || ""} ${after.chore || after.title || ""}`.trim(),
    });
});

// Ny/ändrad emoji-reaktion → eventets deltagare (eller hela familjen).
exports.onEventReaction = onDocumentUpdated("planner_events/{id}", async (event) => {
    const before = event.data?.before.data() || {};
    const after = event.data?.after.data() || {};
    const rb = before.reactions || {};
    const ra = after.reactions || {};

    let reactorUid = null;
    let reaction = null;
    for (const [uid, r] of Object.entries(ra)) {
        const prev = rb[uid];
        if (!prev || prev.emoji !== r.emoji) {
            reactorUid = uid;
            reaction = r;
            break;
        }
    }
    if (!reactorUid || !reaction) return;

    const targets = Array.isArray(after.personUids) && after.personUids.length > 0
        ? after.personUids.filter((u) => u !== reactorUid)
        : null;
    if (targets && targets.length === 0) return;

    await sendFamilyPush({
        familyId: after.familyId,
        excludeUids: [reactorUid],
        onlyUids: targets,
        title: `${reaction.emoji} från ${reaction.name || "någon"}`,
        body: after.title || "En aktivitet fick en reaktion",
    });
});

// ─── GÅ MED I FAMILJ VIA KOD (Callable — admin-SDK) ───────────────────────────
// Paletten speglar AppTheme.memberColorPalette (ordning viktig).
const MEMBER_COLOR_PALETTE = [
    "ff2A6F97", "ff8E3B46", "ffC2654A", "ff5C8D5C", "ffB58A2C",
    "ff6B5B95", "ff3D5A6C", "ff8C5E58", "ff4F7942", "ff8B6F47",
];

exports.joinFamilyWithCode = onCall(async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Inloggning krävs.");
    const { code, name, role } = request.data;
    if (!code || !name) throw new HttpsError("invalid-argument", "Kod och namn krävs.");

    const famSnap = await admin.firestore().collection("families")
        .where("inviteCode", "==", String(code).trim().toUpperCase()).limit(1).get();
    if (famSnap.empty) throw new HttpsError("not-found", "Ogiltig inbjudningskod.");
    const familyId = famSnap.docs[0].id;

    const safeRole = ["parent", "child", "youth"].includes(role) ? role : "child";
    const usersSnap = await admin.firestore().collection("users")
        .where("familyId", "==", familyId).get();
    const used = new Set(usersSnap.docs.map((d) => d.data().color).filter(Boolean));
    const color = MEMBER_COLOR_PALETTE.find((c) => !used.has(c))
        || MEMBER_COLOR_PALETTE[usersSnap.size % MEMBER_COLOR_PALETTE.length];

    await admin.firestore().collection("users").doc(request.auth.uid).set({
        uid: request.auth.uid,
        email: request.auth.token.email || "",
        name: String(name).trim(),
        familyId, role: safeRole, color,
        energy: 3,
        viewMode: safeRole === "parent" ? "parent" : safeRole,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    return { familyId, familyName: famSnap.docs[0].data().name || "" };
});

// ─── AVBOCKA SYSSLA (Callable — skriver chore_log + isDone atomiskt) ──────────
// Behörighet: förälder, skapare, tilldelad (whoUid), ELLER otilldelad syssla.
// Barn får INTE bocka av syskons tilldelade sysslor.
// Otilldelad → whoUid i loggen = den som bockar av.
// Logg-ID: {choreId} (engång) / {choreId}_{dateKey} (återkommande, Fas 3).
exports.completeChore = onCall(async (request) => {
    if (!request.auth) {
        throw new HttpsError("unauthenticated", "Inloggning krävs.");
    }
    const { choreId, done, dateKey: dayKey } = request.data || {};
    if (!choreId || typeof done !== "boolean") {
        throw new HttpsError("invalid-argument", "choreId och done krävs.");
    }
    const uid = request.auth.uid;
    const db = admin.firestore();

    await db.runTransaction(async (tx) => {
        const choreRef = db.collection("chores").doc(choreId);
        const choreSnap = await tx.get(choreRef);
        if (!choreSnap.exists) {
            throw new HttpsError("not-found", "Sysslan finns inte.");
        }
        const chore = choreSnap.data();

        const callerRef = db.collection("users").doc(uid);
        const callerSnap = await tx.get(callerRef);
        const caller = callerSnap.data() || {};
        if (!caller.familyId || caller.familyId !== chore.familyId) {
            throw new HttpsError("permission-denied", "Inte samma familj.");
        }

        const isParent = caller.role === "parent" || caller.role === "admin";
        const isCreator = chore.createdByUid === uid;
        const whoUid = typeof chore.whoUid === "string" ? chore.whoUid : "";
        const unassigned = !whoUid;
        const isAssignee = whoUid === uid;

        if (!isParent && !isCreator && !isAssignee && !unassigned) {
            throw new HttpsError(
                "permission-denied",
                "Du kan bara bocka av egna eller otilldelade sysslor.",
            );
        }

        const logWhoUid = whoUid || uid;
        let logWhoName = chore.who || "";
        if (!logWhoName || logWhoUid === uid) {
            logWhoName = caller.name || logWhoName || "";
        } else if (!logWhoName) {
            const assigneeSnap = await tx.get(db.collection("users").doc(logWhoUid));
            logWhoName = assigneeSnap.data()?.name || "";
        }

        const isRecurring = chore.isRecurring === true;
        const safeDay = (typeof dayKey === "string" && /^\d{4}-\d{2}-\d{2}$/.test(dayKey))
            ? dayKey
            : new Date().toISOString().slice(0, 10);
        const logId = isRecurring ? `${choreId}_${safeDay}` : choreId;
        const logRef = db.collection("chore_log").doc(logId);

        const weight = Number.isFinite(chore.points) ? Math.round(Number(chore.points)) : 0;

        if (done) {
            tx.set(logRef, {
                familyId: chore.familyId,
                choreId,
                choreTitle: chore.chore || chore.title || "",
                piktogram: chore.piktogram || "✅",
                weight,
                whoUid: logWhoUid,
                whoName: logWhoName,
                date: safeDay,
                completedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            tx.update(choreRef, { isDone: true });
        } else {
            tx.delete(logRef);
            tx.update(choreRef, { isDone: false });
        }
    });

    return { ok: true };
});

// ─── SKAPA ANVÄNDARE (Callable Function) ─────────────────────────────────────
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
            viewMode: (role === "parent" || role === "admin") ? "parent" : "child",
        });

        return { uid: userRecord.uid, success: true };
    } catch (error) {
        console.error("Kunde inte skapa användare:", error);
        throw new HttpsError("internal", error.message);
    }
});

// ─── AI VECKOPLANERING (Callable — Anthropic-proxy, endast föräldrar) ─────────
const ASK_PLANNER_SYSTEM = "Du är en svensk familjeplanerare. Familjen har barn i " +
    "olika åldrar (roll child = yngre, youth = tonåring). Svara ENDAST med giltig " +
    "JSON: {\"suggestions\":[{\"text\":\"...\",\"day\":\"YYYY-MM-DD\",\"action\":{...}|null}]}. " +
    "action är valfri (null eller utelämnad om förslaget bara är resonemang) och måste " +
    "vara en av: " +
    "{\"type\":\"assign_chore\",\"choreId\":\"...\",\"assigneeUid\":\"...\",\"assigneeName\":\"...\"}, " +
    "{\"type\":\"reschedule_chore\",\"choreId\":\"...\",\"newDate\":\"YYYY-MM-DD\"}, " +
    "{\"type\":\"create_event\",\"title\":\"...\",\"date\":\"YYYY-MM-DD\",\"time\":\"HH:mm\"|null,\"personUids\":[...]}. " +
    "Referera ENDAST id:n (choreId, uid, personUids) som finns i indatat. Max 5 förslag. " +
    "Fokusera: schemakrockar, dagar där ingen vuxen är ledig, otilldelade sysslor " +
    "(föreslå person som är ledig och har lägst belastning enligt weeklyLoad), luckor.";

const WEEKDAYS_SV = [
    "", "måndag", "tisdag", "onsdag", "torsdag", "fredag", "lördag", "söndag",
];

/** @return {string} YYYY-MM-DD i Europe/Stockholm */
function stockholmDateKey(d = new Date()) {
    return new Intl.DateTimeFormat("en-CA", {
        timeZone: "Europe/Stockholm",
        year: "numeric",
        month: "2-digit",
        day: "2-digit",
    }).format(d);
}

/** @param {string} key @return {string} */
function weekdaySvFromDateKey(key) {
    const p = key.split("-");
    if (p.length !== 3) return "";
    const dt = new Date(Date.UTC(Number(p[0]), Number(p[1]) - 1, Number(p[2])));
    const w = dt.getUTCDay();
    return WEEKDAYS_SV[w === 0 ? 7 : w] || "";
}

/** @param {string} key @param {number} days */
function addDaysToDateKey(key, days) {
    const p = key.split("-");
    const dt = new Date(Date.UTC(Number(p[0]), Number(p[1]) - 1, Number(p[2])));
    dt.setUTCDate(dt.getUTCDate() + days);
    return dt.toISOString().slice(0, 10);
}

/** Måndag för veckan som innehåller [todayKey] (YYYY-MM-DD). */
function mondayOfWeek(todayKey) {
    const p = todayKey.split("-");
    const dt = new Date(Date.UTC(Number(p[0]), Number(p[1]) - 1, Number(p[2])));
    const day = dt.getUTCDay(); // 0 = sön
    const offset = day === 0 ? -6 : 1 - day;
    dt.setUTCDate(dt.getUTCDate() + offset);
    return dt.toISOString().slice(0, 10);
}

/** @param {FirebaseFirestore.Firestore} db @param {string} familyId @param {string} todayKey */
async function consumeAiQuota(db, familyId, todayKey) {
    const ref = db.collection("ai_usage").doc(familyId);
    await db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        const data = snap.data() || {};
        const count = data.date === todayKey ? (data.count || 0) : 0;
        if (count >= 10) {
            throw new HttpsError("resource-exhausted", "Dagens AI-kvot är slut.");
        }
        tx.set(ref, { date: todayKey, count: count + 1 }, { merge: true });
    });
}

/** @param {unknown} raw */
function normalizeAction(raw) {
    if (!raw || typeof raw !== "object") return null;
    const a = /** @type {Record<string, unknown>} */ (raw);
    const type = a.type;
    if (type === "assign_chore") {
        const choreId = typeof a.choreId === "string" ? a.choreId.trim() : "";
        const assigneeUid = typeof a.assigneeUid === "string" ? a.assigneeUid.trim() : "";
        if (!choreId || !assigneeUid) return null;
        return {
            type: "assign_chore",
            choreId,
            assigneeUid,
            assigneeName: typeof a.assigneeName === "string" ? a.assigneeName.trim() : "",
        };
    }
    if (type === "reschedule_chore") {
        const choreId = typeof a.choreId === "string" ? a.choreId.trim() : "";
        const newDate = typeof a.newDate === "string" ? a.newDate.trim() : "";
        if (!choreId || !/^\d{4}-\d{2}-\d{2}$/.test(newDate)) return null;
        return { type: "reschedule_chore", choreId, newDate };
    }
    if (type === "create_event") {
        const title = typeof a.title === "string" ? a.title.trim() : "";
        const date = typeof a.date === "string" ? a.date.trim() : "";
        if (!title || !/^\d{4}-\d{2}-\d{2}$/.test(date)) return null;
        let time = null;
        if (typeof a.time === "string" && /^\d{2}:\d{2}$/.test(a.time.trim())) {
            time = a.time.trim();
        }
        const personUids = Array.isArray(a.personUids) ?
            a.personUids.filter((u) => typeof u === "string" && u.trim()).map((u) => String(u).trim()) :
            [];
        return { type: "create_event", title, date, time, personUids };
    }
    return null;
}

/** @param {string} raw */
function parseSuggestionsJson(raw) {
    let text = String(raw || "").trim();
    if (text.startsWith("```")) {
        text = text.replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/m, "").trim();
    }
    const parsed = JSON.parse(text);
    if (!parsed || !Array.isArray(parsed.suggestions)) {
        throw new Error("Ogiltigt svar från AI.");
    }
    const out = [];
    for (const item of parsed.suggestions) {
        if (!item || typeof item.text !== "string" || typeof item.day !== "string") {
            continue;
        }
        if (!/^\d{4}-\d{2}-\d{2}$/.test(item.day)) continue;
        out.push({
            text: item.text.trim(),
            day: item.day,
            action: normalizeAction(item.action),
        });
        if (out.length >= 5) break;
    }
    if (out.length === 0) throw new Error("Inga förslag i AI-svaret.");
    return out;
}

/**
 * @param {string} familyId
 * @param {string} startKey
 * @param {string} endKey
 */
async function buildFamilyPlannerSummary(familyId, startKey, endKey) {
    const db = admin.firestore();
    const weekStart = mondayOfWeek(startKey);
    const weekEnd = addDaysToDateKey(weekStart, 6);

    const [usersSnap, shiftsSnap, datedSnap, recurringSnap, choresSnap, logSnap] =
        await Promise.all([
            db.collection("users").where("familyId", "==", familyId).get(),
            db.collection("work_shifts").where("familyId", "==", familyId)
                .where("date", ">=", startKey).where("date", "<=", endKey).get(),
            db.collection("planner_events").where("familyId", "==", familyId)
                .where("date", ">=", startKey).where("date", "<=", endKey).get(),
            db.collection("planner_events").where("familyId", "==", familyId)
                .where("isRecurring", "==", true).get(),
            db.collection("chores").where("familyId", "==", familyId).get(),
            db.collection("chore_log").where("familyId", "==", familyId)
                .where("date", ">=", weekStart).where("date", "<=", weekEnd).get(),
        ]);

    const members = usersSnap.docs.map((doc) => {
        const u = doc.data();
        const role = u.role === "admin" ? "parent" : (u.role || "child");
        return {
            uid: doc.id,
            name: String(u.name || "").trim(),
            role,
        };
    }).filter((m) => m.name);

    const loadByUid = {};
    for (const m of members) {
        loadByUid[m.uid] = { uid: m.uid, name: m.name, count: 0, weightSum: 0 };
    }
    for (const doc of logSnap.docs) {
        const d = doc.data();
        const uid = typeof d.whoUid === "string" ? d.whoUid : "";
        if (!uid) continue;
        if (!loadByUid[uid]) {
            loadByUid[uid] = {
                uid,
                name: d.whoName || "",
                count: 0,
                weightSum: 0,
            };
        }
        loadByUid[uid].count += 1;
        loadByUid[uid].weightSum += Number.isFinite(d.weight) ?
            Math.round(Number(d.weight)) : 0;
    }
    const weeklyLoad = Object.values(loadByUid);

    const workShifts = shiftsSnap.docs.map((doc) => {
        const d = doc.data();
        return {
            date: d.date || "",
            start: d.startTime || "",
            end: d.endTime || "",
            who: d.who || d.person || "",
        };
    }).filter((s) => s.date);

    /** @type {Map<string, {day: string, who: string, minStart: string|null, maxEnd: string|null}>} */
    const schoolMap = new Map();
    const datedEvents = [];

    for (const doc of datedSnap.docs) {
        const d = doc.data();
        if (d.isRecurring === true) continue;
        const title = d.title || "";
        const date = d.date || "";
        if (!title || !date) continue;

        if (d.planningImportKind === "schedule") {
            const persons = Array.isArray(d.persons) ? d.persons.filter(Boolean) : [];
            const whoList = persons.length > 0 ? persons : [""];
            const t = typeof d.time === "string" ? d.time.trim() : "";
            const endRaw = typeof d.endTime === "string" ? d.endTime.trim() : "";
            const end = endRaw || t;
            for (const who of whoList) {
                const key = `${date}|${who}`;
                let block = schoolMap.get(key);
                if (!block) {
                    block = {day: date, who, minStart: null, maxEnd: null};
                    schoolMap.set(key, block);
                }
                if (t) {
                    if (!block.minStart || t < block.minStart) block.minStart = t;
                    if (end && (!block.maxEnd || end > block.maxEnd)) block.maxEnd = end;
                }
            }
            continue;
        }

        const who = Array.isArray(d.persons) ? d.persons : [];
        datedEvents.push({
            title,
            date,
            time: d.time || "",
            end: d.endTime || "",
            who,
        });
    }

    const schoolBusy = [...schoolMap.values()]
        .filter((b) => b.minStart)
        .map((b) => ({
            day: b.day,
            who: b.who,
            skola: `${b.minStart}–${b.maxEnd || b.minStart}`,
        }))
        .sort((a, b) => a.day.localeCompare(b.day) || a.who.localeCompare(b.who));

    const recurringEvents = recurringSnap.docs
        .filter((doc) => doc.data().planningImportKind !== "schedule")
        .map((doc) => {
            const d = doc.data();
            const rec = d.recurrence || {};
            const startDate = rec.startDate || d.date || "";
            const who = Array.isArray(d.persons) ? d.persons : [];
            return {
                title: d.title || "",
                recurrence: rec.type || "weekly",
                weekday: weekdaySvFromDateKey(String(startDate)),
                time: d.time || "",
                end: d.endTime || "",
                who,
            };
        }).filter((e) => e.title);

    const chores = choresSnap.docs
        .filter((doc) => doc.data().isDone !== true)
        .map((doc) => {
            const d = doc.data();
            return {
                choreId: doc.id,
                title: d.chore || d.title || "",
                who: d.who || "",
                dueDate: d.dueDate || "",
                weight: Number.isFinite(d.points) ? Number(d.points) : 0,
            };
        }).filter((c) => c.title);

    return {
        window: { from: startKey, to: endKey },
        weekLoadWindow: { from: weekStart, to: weekEnd },
        members,
        weeklyLoad,
        workShifts,
        schoolBusy,
        datedEvents,
        recurringEvents,
        chores,
    };
}

/** @param {unknown} raw @return {string|null} */
function parseYmdParam(raw) {
    if (typeof raw !== "string") return null;
    const s = raw.trim();
    if (!/^\d{4}-\d{2}-\d{2}$/.test(s)) return null;
    const [y, m, d] = s.split("-").map(Number);
    const dt = new Date(Date.UTC(y, m - 1, d));
    if (dt.getUTCFullYear() !== y || dt.getUTCMonth() !== m - 1 || dt.getUTCDate() !== d) {
        return null;
    }
    return s;
}

/** Inklusivt antal dagar mellan två YYYY-MM-DD (samma dag = 1). */
function inclusiveDaySpan(startKey, endKey) {
    const [ys, ms, ds] = startKey.split("-").map(Number);
    const [ye, me, de] = endKey.split("-").map(Number);
    const a = Date.UTC(ys, ms - 1, ds);
    const b = Date.UTC(ye, me - 1, de);
    return Math.round((b - a) / 86400000) + 1;
}

exports.askPlanner = onCall({
    region: "us-central1",
    secrets: ["LAFAMILIA_ANTHROPIC_KEY"],
    timeoutSeconds: 60,
}, async (request) => {
    if (!request.auth) {
        throw new HttpsError("unauthenticated", "Inloggning krävs.");
    }

    const apiKey = process.env.LAFAMILIA_ANTHROPIC_KEY;
    if (!apiKey) {
        throw new HttpsError("failed-precondition", "AI-nyckel saknas.");
    }

    const db = admin.firestore();
    const callerSnap = await db.collection("users").doc(request.auth.uid).get();
    if (!callerSnap.exists) {
        throw new HttpsError("permission-denied", "Användare saknas.");
    }
    const caller = callerSnap.data() || {};
    const role = caller.role || "";
    if (role !== "parent" && role !== "admin") {
        throw new HttpsError("permission-denied", "Endast föräldrar kan använda AI-planeraren.");
    }
    const familyId = caller.familyId;
    if (!familyId) {
        throw new HttpsError("failed-precondition", "Ingen familj kopplad.");
    }

    const todayKey = stockholmDateKey();
    const data = request.data || {};
    let startKey = parseYmdParam(data.startDate);
    let endKey = parseYmdParam(data.endDate);

    if (startKey == null && endKey == null) {
        startKey = todayKey;
        endKey = addDaysToDateKey(todayKey, 7);
    } else if (startKey == null || endKey == null) {
        throw new HttpsError(
            "invalid-argument",
            "Ange både startDate och endDate (YYYY-MM-DD), eller inget.",
        );
    } else if (startKey > endKey) {
        throw new HttpsError("invalid-argument", "startDate måste vara före eller samma som endDate.");
    } else if (inclusiveDaySpan(startKey, endKey) > 14) {
        throw new HttpsError("invalid-argument", "Perioden får vara högst 14 dagar.");
    }

    await consumeAiQuota(db, familyId, todayKey);

    const summary = await buildFamilyPlannerSummary(familyId, startKey, endKey);
    const payload =
        `Period: ${startKey}–${endKey}\n` + JSON.stringify(summary);

    const model = "claude-sonnet-5";
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 30000);

    let response;
    try {
        response = await fetch("https://api.anthropic.com/v1/messages", {
            method: "POST",
            signal: controller.signal,
            headers: {
                "x-api-key": apiKey,
                "anthropic-version": "2023-06-01",
                "content-type": "application/json",
            },
            body: JSON.stringify({
                model,
                max_tokens: 3000,
                system: ASK_PLANNER_SYSTEM,
                messages: [{ role: "user", content: payload }],
            }),
        });
    } catch (err) {
        if (err.name === "AbortError") {
            throw new HttpsError("unavailable", "AI-tjänsten svarade inte i tid.");
        }
        throw new HttpsError("unavailable", "Kunde inte nå AI-tjänsten.");
    } finally {
        clearTimeout(timer);
    }

    console.log(
        `askPlanner: model=${model} Anthropic status=${response.status} ` +
        `payloadLen=${payload.length} window=${startKey}..${endKey}`,
    );

    if (!response.ok) {
        throw new HttpsError("unavailable", "AI-tjänsten är tillfälligt otillgänglig.");
    }

    let body;
    try {
        body = await response.json();
    } catch (_) {
        throw new HttpsError("unavailable", "Ogiltigt svar från AI-tjänsten.");
    }

    const stopReason = body.stop_reason || null;
    const contentTypes = Array.isArray(body.content) ?
        body.content.map((b) => (b && b.type) || "?") : [];

    if (stopReason === "max_tokens") {
        console.error(
            `askPlanner: stop_reason=max_tokens contentTypes=${JSON.stringify(contentTypes)}`,
        );
        throw new HttpsError(
            "unavailable",
            "AI-svaret blev för långt — försök med kortare period.",
        );
    }

    const textBlock = (body.content || []).find((b) => b.type === "text");
    if (!textBlock || !textBlock.text) {
        console.error(
            `askPlanner: empty text stop_reason=${stopReason} ` +
            `contentTypes=${JSON.stringify(contentTypes)}`,
        );
        throw new HttpsError("unavailable", "Tomt svar från AI-tjänsten.");
    }

    let suggestions;
    try {
        suggestions = parseSuggestionsJson(textBlock.text);
    } catch (_) {
        console.error(
            `askPlanner: parse failed stop_reason=${stopReason} ` +
            `contentTypes=${JSON.stringify(contentTypes)}`,
        );
        throw new HttpsError("unavailable", "Kunde inte tolka AI-svaret.");
    }

    return { suggestions };
});

// ─── AI VECKOMENY (Callable — matplanering) ───────────────────────────────────
const ASK_MEAL_PLANNER_SYSTEM = "Du är en svensk familjekock/menyplanerare. " +
    "Svara ENDAST med giltig JSON: " +
    "{\"menu\":[{\"day\":\"YYYY-MM-DD\",\"dishId\":\"...\"|null,\"title\":\"...\"," +
    "\"emoji\":\"...\",\"ingredients\":[{\"namn\":\"...\",\"mangd\":\"...\",\"enhet\":\"...\"}]," +
    "\"steps\":[\"max 3 korta rader\"],\"prepMinutes\":30," +
    "\"leftoverOfDay\":\"YYYY-MM-DD\"|null}]}. " +
    "Regler: Blanda kända favoriter (högt antalLagningar, inte lagade senaste 2 veckorna " +
    "→ sätt dishId från rättbiblioteket) med 2–3 nya förslag (dishId null + fullt recept). " +
    "Planera 1–2 matlådedagar: en dag lagar dubbelt, leftoverOfDay pekar på lagningsdagen " +
    "och den dagen har tom ingredients-lista. Vardagar (mån–fre) max ~45 min prepMinutes. " +
    "Respektera allergier strikt. Undvik ogillar. Föredra gillar. Svenska. " +
    "En meny-rad per dag i perioden. Referera bara dishId som finns i indatat.";

/**
 * @param {string} familyId
 * @param {string} startKey
 * @param {number} days
 */
async function buildMealPlannerSummary(familyId, startKey, days) {
    const db = admin.firestore();
    const endKey = addDaysToDateKey(startKey, days - 1);
    const histStart = addDaysToDateKey(startKey, -14);

    const [familySnap, usersSnap, dishesSnap, mealsSnap, histSnap] =
        await Promise.all([
            db.collection("families").doc(familyId).get(),
            db.collection("users").where("familyId", "==", familyId).get(),
            db.collection("dishes").where("familyId", "==", familyId).get(),
            db.collection("meals").where("familyId", "==", familyId)
                .where("date", ">=", startKey).where("date", "<=", endKey).get(),
            db.collection("meals").where("familyId", "==", familyId)
                .where("date", ">=", histStart).where("date", "<", startKey).get(),
        ]);

    const fam = familySnap.data() || {};
    const prefs = fam.foodPrefs || {};
    const foodPrefs = {
        allergier: Array.isArray(prefs.allergier) ? prefs.allergier : [],
        ogillar: Array.isArray(prefs.ogillar) ? prefs.ogillar : [],
        gillar: Array.isArray(prefs.gillar) ? prefs.gillar : [],
    };

    const members = usersSnap.docs.map((doc) => {
        const u = doc.data();
        return {
            uid: doc.id,
            name: String(u.name || "").trim(),
            role: u.role === "admin" ? "parent" : (u.role || "child"),
        };
    }).filter((m) => m.name);

    const dishes = dishesSnap.docs.map((doc) => {
        const d = doc.data();
        return {
            dishId: doc.id,
            namn: d.namn || d.title || "",
            kategori: d.kategori || "ÖVRIGT",
            tillagningMin: Number.isFinite(d.tillagningMin) ? d.tillagningMin : null,
            antalLagningar: Number.isFinite(d.antalLagningar) ? d.antalLagningar : 0,
            senastLagad: d.senastLagad || null,
        };
    }).filter((d) => d.namn);

    const recentMeals = [...histSnap.docs, ...mealsSnap.docs].map((doc) => {
        const d = doc.data();
        return {
            day: d.date || "",
            title: d.title || "",
            dishId: d.dishId || null,
        };
    }).filter((m) => m.day && m.title);

    return {
        period: {startDate: startKey, days, endDate: endKey},
        personer: members.length,
        members,
        foodPrefs,
        dishes,
        recentMeals,
    };
}

/** @param {string} raw */
function parseMealMenuJson(raw) {
    let text = String(raw || "").trim();
    if (text.startsWith("```")) {
        text = text.replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/m, "").trim();
    }
    const parsed = JSON.parse(text);
    if (!parsed || !Array.isArray(parsed.menu)) {
        throw new Error("Ogiltigt meny-svar.");
    }
    const out = [];
    for (const item of parsed.menu) {
        if (!item || typeof item.day !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(item.day)) {
            continue;
        }
        if (typeof item.title !== "string" || !item.title.trim()) continue;
        const ingredients = Array.isArray(item.ingredients) ?
            item.ingredients.filter((i) => i && typeof i.namn === "string").map((i) => ({
                namn: String(i.namn).trim(),
                mangd: i.mangd != null ? String(i.mangd).trim() : "",
                enhet: i.enhet != null ? String(i.enhet).trim() : "",
            })).filter((i) => i.namn) : [];
        const steps = Array.isArray(item.steps) ?
            item.steps.filter((s) => typeof s === "string" && s.trim())
                .map((s) => s.trim()).slice(0, 3) : [];
        let leftoverOfDay = null;
        if (typeof item.leftoverOfDay === "string" &&
            /^\d{4}-\d{2}-\d{2}$/.test(item.leftoverOfDay)) {
            leftoverOfDay = item.leftoverOfDay;
        }
        const dishId = typeof item.dishId === "string" && item.dishId.trim() ?
            item.dishId.trim() : null;
        out.push({
            day: item.day,
            dishId,
            title: item.title.trim(),
            emoji: typeof item.emoji === "string" && item.emoji.trim() ?
                item.emoji.trim() : "🍽️",
            ingredients: leftoverOfDay ? [] : ingredients,
            steps,
            prepMinutes: Number.isFinite(Number(item.prepMinutes)) ?
                Math.round(Number(item.prepMinutes)) : 30,
            leftoverOfDay,
        });
        if (out.length >= 7) break;
    }
    if (out.length === 0) throw new Error("Tom meny från AI.");
    return out;
}

exports.askMealPlanner = onCall({
    region: "us-central1",
    secrets: ["LAFAMILIA_ANTHROPIC_KEY"],
    timeoutSeconds: 60,
}, async (request) => {
    if (!request.auth) {
        throw new HttpsError("unauthenticated", "Inloggning krävs.");
    }

    const apiKey = process.env.LAFAMILIA_ANTHROPIC_KEY;
    if (!apiKey) {
        throw new HttpsError("failed-precondition", "AI-nyckel saknas.");
    }

    const db = admin.firestore();
    const callerSnap = await db.collection("users").doc(request.auth.uid).get();
    if (!callerSnap.exists) {
        throw new HttpsError("permission-denied", "Användare saknas.");
    }
    const caller = callerSnap.data() || {};
    if (caller.role !== "parent" && caller.role !== "admin") {
        throw new HttpsError("permission-denied", "Endast föräldrar kan använda AI-menyn.");
    }
    const familyId = caller.familyId;
    if (!familyId) {
        throw new HttpsError("failed-precondition", "Ingen familj kopplad.");
    }

    const todayKey = stockholmDateKey();
    const data = request.data || {};
    const startKey = parseYmdParam(data.startDate) || todayKey;
    let days = Number(data.days);
    if (!Number.isFinite(days) || days < 1) days = 7;
    days = Math.floor(days);
    if (days > 7) {
        throw new HttpsError("invalid-argument", "Perioden får vara högst 7 dagar.");
    }

    await consumeAiQuota(db, familyId, todayKey);

    const summary = await buildMealPlannerSummary(familyId, startKey, days);
    const payload =
        `Period: ${startKey}, ${days} dagar\n` + JSON.stringify(summary);

    const model = "claude-sonnet-5";
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 45000);

    let response;
    try {
        response = await fetch("https://api.anthropic.com/v1/messages", {
            method: "POST",
            signal: controller.signal,
            headers: {
                "x-api-key": apiKey,
                "anthropic-version": "2023-06-01",
                "content-type": "application/json",
            },
            body: JSON.stringify({
                model,
                max_tokens: 3000,
                system: ASK_MEAL_PLANNER_SYSTEM,
                messages: [{role: "user", content: payload}],
            }),
        });
    } catch (err) {
        if (err.name === "AbortError") {
            throw new HttpsError("unavailable", "AI-tjänsten svarade inte i tid.");
        }
        throw new HttpsError("unavailable", "Kunde inte nå AI-tjänsten.");
    } finally {
        clearTimeout(timer);
    }

    console.log(
        `askMealPlanner: model=${model} status=${response.status} ` +
        `payloadLen=${payload.length} days=${days}`,
    );

    if (!response.ok) {
        throw new HttpsError("unavailable", "AI-tjänsten är tillfälligt otillgänglig.");
    }

    let body;
    try {
        body = await response.json();
    } catch (_) {
        throw new HttpsError("unavailable", "Ogiltigt svar från AI-tjänsten.");
    }

    const stopReason = body.stop_reason || null;
    const contentTypes = Array.isArray(body.content) ?
        body.content.map((b) => (b && b.type) || "?") : [];

    if (stopReason === "max_tokens") {
        console.error(
            `askMealPlanner: stop_reason=max_tokens contentTypes=${JSON.stringify(contentTypes)}`,
        );
        throw new HttpsError(
            "unavailable",
            "AI-svaret blev för långt — försök med kortare period.",
        );
    }

    const textBlock = (body.content || []).find((b) => b.type === "text");
    if (!textBlock || !textBlock.text) {
        console.error(
            `askMealPlanner: empty text stop_reason=${stopReason} ` +
            `contentTypes=${JSON.stringify(contentTypes)}`,
        );
        throw new HttpsError("unavailable", "Tomt svar från AI-tjänsten.");
    }

    let menu;
    try {
        menu = parseMealMenuJson(textBlock.text);
    } catch (_) {
        console.error(
            `askMealPlanner: parse failed stop_reason=${stopReason} ` +
            `contentTypes=${JSON.stringify(contentTypes)}`,
        );
        throw new HttpsError("unavailable", "Kunde inte tolka AI-menyn.");
    }

    return {menu};
});

// ─── RENSA GAMLA FAMILJENOTISER (>7 dagar) ───────────────────────────────────
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
