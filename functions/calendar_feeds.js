/* eslint-disable valid-jsdoc, max-len */
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");
const ical = require("node-ical");

const MAX_ICS_BYTES = 2 * 1024 * 1024;
const MAX_EVENTS_PER_FEED = 500;
const FETCH_TIMEOUT_MS = 20000;

/**
 * @return {string} YYYY-MM-DD i Europe/Stockholm
 */
function stockholmDateKey(d = new Date()) {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "Europe/Stockholm",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(d);
}

/**
 * @param {Date} d
 * @return {{ date: string, time: string }}
 */
function stockholmDateAndTime(d) {
  const parts = Object.fromEntries(
      new Intl.DateTimeFormat("en-GB", {
        timeZone: "Europe/Stockholm",
        year: "numeric",
        month: "2-digit",
        day: "2-digit",
        hour: "2-digit",
        minute: "2-digit",
        hourCycle: "h23",
      }).formatToParts(d).filter((p) => p.type !== "literal")
          .map((p) => [p.type, p.value]),
  );
  const date = `${parts.year}-${parts.month}-${parts.day}`;
  const time = `${parts.hour}:${parts.minute}`;
  return {date, time};
}

/**
 * @param {string} url
 * @return {Promise<string>}
 */
async function fetchIcsText(url) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);
  try {
    const res = await fetch(url, {
      signal: controller.signal,
      redirect: "follow",
      headers: {"user-agent": "LaFamiliaCalendarSync/1.0"},
    });
    if (!res.ok) {
      throw new Error(`HTTP ${res.status}`);
    }
    const buf = Buffer.from(await res.arrayBuffer());
    if (buf.byteLength > MAX_ICS_BYTES) {
      throw new Error("ICS-filen är för stor (max 2 MB).");
    }
    return buf.toString("utf8");
  } finally {
    clearTimeout(timer);
  }
}

/**
 * @param {string} icsText
 * @return {Array<{
 *   icsKey: string,
 *   title: string,
 *   date: string,
 *   time: string,
 *   endTime: string|null,
 *   location: string,
 *   description: string,
 *   startMs: number,
 * }>}
 */
function parseIcsToEvents(icsText) {
  const data = ical.sync.parseICS(icsText);
  const out = [];

  for (const key of Object.keys(data)) {
    const ev = data[key];
    if (!ev || ev.type !== "VEVENT") continue;
    if (!(ev.start instanceof Date) || Number.isNaN(ev.start.getTime())) continue;

    const title = String(ev.summary || "").trim();
    if (!title) continue;

    const uid = String(ev.uid || key || "").trim() || key;
    const icsKey = `${uid}|${ev.start.toISOString()}`;

    const isAllDay = ev.datetype === "date";
    const {date, time: startHm} = stockholmDateAndTime(ev.start);
    const time = isAllDay || (startHm === "00:00") ? "" : startHm;

    let endTime = null;
    if (!isAllDay && ev.end instanceof Date && !Number.isNaN(ev.end.getTime())) {
      const endParts = stockholmDateAndTime(ev.end);
      if (endParts.date === date && endParts.time !== "00:00") {
        endTime = endParts.time;
      } else if (endParts.date > date || endParts.time !== startHm) {
        endTime = endParts.time;
      }
    }

    let location = String(ev.location || "").trim();
    if (location.length > 2000) location = `${location.slice(0, 2000)}…`;

    let description = String(ev.description || "").trim();
    if (description.length > 15000) description = `${description.slice(0, 15000)}…`;

    out.push({
      icsKey,
      title,
      date,
      time,
      endTime,
      location,
      description,
      startMs: ev.start.getTime(),
    });
  }

  out.sort((a, b) => a.startMs - b.startMs);
  return out;
}

/**
 * @param {FirebaseFirestore.Firestore} db
 * @param {Array<{ref: FirebaseFirestore.DocumentReference, data?: object, delete?: boolean}>} ops
 */
async function commitInChunks(db, ops) {
  const CHUNK = 400;
  for (let i = 0; i < ops.length; i += CHUNK) {
    const batch = db.batch();
    for (const op of ops.slice(i, i + CHUNK)) {
      if (op.delete) {
        batch.delete(op.ref);
      } else {
        batch.set(op.ref, op.data, {merge: op.merge === true});
      }
    }
    await batch.commit();
  }
}

/** Schema → böcker, aktivitet → clipboard. */
function piktogramForKind(targetType) {
  return targetType === "activity" ? "📋" : "📚";
}

/**
 * Kopplar kalender till familjemedlem via uid, exakt namn, eller
 * namn som ingår i kalendernamnet ("Emilios skolschema" → Emilio).
 */
async function resolvePersonFromFamily(
    db, familyId, personName, personId, calendarName,
) {
  const snap = await db.collection("users")
      .where("familyId", "==", familyId).get();
  const members = snap.docs.map((d) => ({
    uid: d.id,
    name: String((d.data() || {}).name || "").trim(),
  })).filter((m) => m.name);

  if (personId) {
    const m = members.find((x) => x.uid === personId);
    return {
      personName: personName || (m && m.name) || "",
      personId,
    };
  }
  if (personName) {
    const exact = members.find((x) => x.name === personName);
    if (exact) return {personName: exact.name, personId: exact.uid};
  }
  const hay = `${personName} ${calendarName || ""}`.toLowerCase();
  const hits = members
      .filter((m) => hay.includes(m.name.toLowerCase()))
      .sort((a, b) => b.name.length - a.name.length);
  if (hits.length) {
    return {personName: hits[0].name, personId: hits[0].uid};
  }
  return {personName: personName || "", personId: personId || ""};
}

/**
 * Bygger Firestore-fält för en kalenderhändelse.
 * @param {object} ev
 * @param {object} meta
 */
function eventFieldsFromParsed(ev, meta) {
  const fields = {
    title: ev.title,
    piktogram: piktogramForKind(meta.targetType),
    type: "activity",
    date: ev.date,
    time: ev.time,
    persons: meta.person ? [meta.person] : [],
    personUids: meta.personUid ? [meta.personUid] : [],
    checklist: [],
    source: "calendar",
    planningImportKind: meta.targetType,
    calendarName: meta.name,
    calendarImportId: meta.importId,
    createdBy: meta.createdByUid,
    createdByUid: meta.createdByUid,
    isPending: false,
    familyId: meta.familyId,
    icsKey: ev.icsKey,
  };
  if (ev.endTime) fields.endTime = ev.endTime;
  if (ev.description) fields.calendarDescription = ev.description;
  if (ev.location) fields.location = ev.location;
  return fields;
}

/**
 * Synkar en feed: skapa / uppdatera / radera framtida events.
 * @return {Promise<{eventCount: number}>}
 */
async function syncFeedDocument(importSnap, {
  icsText = null,
  createdByUid = null,
  overrideMeta = null,
} = {}) {
  const db = admin.firestore();
  const data = importSnap.data() || {};
  const importId = importSnap.id;
  const familyId = data.familyId;
  if (!familyId) throw new Error("Saknar familyId");

  const feedUrl = data.feedUrl || data.url || "";
  if (!feedUrl && !icsText) throw new Error("Saknar feedUrl");

  const text = icsText || await fetchIcsText(feedUrl);
  let parsed = parseIcsToEvents(text);

  const todayKey = stockholmDateKey();
  // Behåll framtida + idag; cap 500 (närmaste först).
  parsed = parsed.filter((e) => e.date >= todayKey).slice(0, MAX_EVENTS_PER_FEED);

  const feedByKey = new Map(parsed.map((e) => [e.icsKey, e]));

  const existingSnap = await db.collection("planner_events")
      .where("familyId", "==", familyId)
      .where("calendarImportId", "==", importId)
      .get();

  const meta = {
    importId,
    familyId,
    name: (overrideMeta && overrideMeta.name) || data.name || "Kalender",
    person: (overrideMeta && overrideMeta.person) || data.person ||
      data.assignedMember || "",
    personUid: (overrideMeta && overrideMeta.personUid) || data.personUid || "",
    targetType: (overrideMeta && overrideMeta.targetType) ||
      data.planningImportKind || data.targetType || "schedule",
    createdByUid: createdByUid || data.createdByUid || "",
  };
  if (meta.targetType !== "activity") meta.targetType = "schedule";
  if (!meta.person || !meta.personUid) {
    const resolved = await resolvePersonFromFamily(
        db, familyId, meta.person, meta.personUid, meta.name);
    meta.person = resolved.personName;
    meta.personUid = resolved.personId;
  }

  const wantPik = piktogramForKind(meta.targetType);
  const ops = [];
  let liveCount = 0;

  for (const doc of existingSnap.docs) {
    const d = doc.data();
    const icsKey = d.icsKey;
    const eventDate = d.date || "";
    const isFuture = eventDate >= todayKey;

    if (!icsKey) {
      // Legacy utan icsKey: rör inte förflutna; framtida utan nyckel lämnas
      // (nästa sync skapar nya med icsKey).
      if (isFuture) {
        // Ta bort framtida legacy utan nyckel så de kan ersättas rent.
        ops.push({ref: doc.ref, delete: true});
      }
      continue;
    }

    if (!isFuture) {
      // Rör aldrig det förflutna.
      continue;
    }

    const fresh = feedByKey.get(icsKey);
    if (!fresh) {
      ops.push({ref: doc.ref, delete: true});
      continue;
    }

    feedByKey.delete(icsKey);
    liveCount++;

    const wantPersons = meta.person ? [meta.person] : [];
    const wantUids = meta.personUid ? [meta.personUid] : [];
    const havePersons = Array.isArray(d.persons) ? d.persons : [];
    const haveUids = Array.isArray(d.personUids) ? d.personUids : [];

    const changed =
      d.title !== fresh.title ||
      (d.time || "") !== (fresh.time || "") ||
      (d.endTime || "") !== (fresh.endTime || "") ||
      (d.location || "") !== (fresh.location || "") ||
      (d.date || "") !== fresh.date ||
      (d.planningImportKind || "") !== meta.targetType ||
      (d.calendarName || "") !== meta.name ||
      (d.piktogram || "") !== wantPik ||
      havePersons.join("\0") !== wantPersons.join("\0") ||
      haveUids.join("\0") !== wantUids.join("\0");

    if (changed) {
      const fields = eventFieldsFromParsed(fresh, meta);
      // Behåll createdByUid om den fanns.
      if (d.createdByUid) {
        fields.createdByUid = d.createdByUid;
        fields.createdBy = d.createdByUid;
      }
      ops.push({ref: doc.ref, data: fields, merge: true});
    }
  }

  for (const fresh of feedByKey.values()) {
    liveCount++;
    const ref = db.collection("planner_events").doc();
    ops.push({
      ref,
      data: eventFieldsFromParsed(fresh, {
        ...meta,
        createdByUid: meta.createdByUid || createdByUid || "",
      }),
    });
  }

  const importUpdate = {
    lastSync: admin.firestore.FieldValue.serverTimestamp(),
    eventCount: liveCount,
    name: meta.name,
    planningImportKind: meta.targetType,
    targetType: meta.targetType,
    person: meta.person || null,
    personUid: meta.personUid || null,
    assignedMember: meta.person || null,
  };
  if (feedUrl) {
    importUpdate.feedUrl = feedUrl;
    importUpdate.url = feedUrl;
  }
  ops.push({ref: importSnap.ref, data: importUpdate, merge: true});

  await commitInChunks(db, ops);
  return {eventCount: liveCount};
}

/**
 * Callable: prenumerera på ICS-URL eller synka om befintlig.
 * data: { url, name, person, personUid, targetType, importId? }
 */
exports.subscribeCalendarFeed = onCall({
  region: "us-central1",
  timeoutSeconds: 120,
  memory: "512MiB",
}, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Inloggning krävs.");
  }
  const uid = request.auth.uid;
  const db = admin.firestore();

  const callerSnap = await db.collection("users").doc(uid).get();
  if (!callerSnap.exists) {
    throw new HttpsError("permission-denied", "Användare saknas.");
  }
  const caller = callerSnap.data() || {};
  if (caller.role !== "parent" && caller.role !== "admin") {
    throw new HttpsError("permission-denied", "Endast föräldrar.");
  }
  const familyId = caller.familyId;
  if (!familyId) {
    throw new HttpsError("failed-precondition", "Ingen familj.");
  }

  const {
    url,
    name,
    person,
    personUid,
    targetType,
    importId,
  } = request.data || {};

  const kind = targetType === "activity" ? "activity" : "schedule";
  const displayName = (typeof name === "string" && name.trim()) ?
    name.trim() : "Kalender";
  let personName = typeof person === "string" ? person.trim() : "";
  let personId = typeof personUid === "string" ? personUid.trim() : "";

  if (!personName || !personId) {
    const resolved = await resolvePersonFromFamily(
        db, familyId, personName, personId, displayName);
    personName = resolved.personName;
    personId = resolved.personId;
  }

  try {
    if (importId && typeof importId === "string") {
      const importRef = db.collection("calendar_imports").doc(importId);
      const importSnap = await importRef.get();
      if (!importSnap.exists) {
        throw new HttpsError("not-found", "Prenumerationen finns inte.");
      }
      const existing = importSnap.data() || {};
      if (existing.familyId !== familyId) {
        throw new HttpsError("permission-denied", "Fel familj.");
      }
      if (existing.importKind === "photo") {
        throw new HttpsError("invalid-argument", "Foto-importer kan inte synkas om som feed.");
      }

      const feedUrl = (typeof url === "string" && url.trim()) ?
        url.trim() : (existing.feedUrl || existing.url || "");
      if (!feedUrl) {
        throw new HttpsError("invalid-argument", "Saknar ICS-URL.");
      }

      if (feedUrl !== (existing.feedUrl || existing.url)) {
        await importRef.update({feedUrl, url: feedUrl, autoSync: true});
      }

      const refreshed = await importRef.get();
      const result = await syncFeedDocument(refreshed, {
        createdByUid: uid,
        overrideMeta: {
          name: displayName,
          person: personName,
          personUid: personId,
          targetType: kind,
        },
      });
      return {importId, eventCount: result.eventCount, synced: true};
    }

    if (typeof url !== "string" || !url.trim()) {
      throw new HttpsError("invalid-argument", "ICS-URL krävs.");
    }
    const feedUrl = url.trim();
    const icsText = await fetchIcsText(feedUrl);

    const importRef = db.collection("calendar_imports").doc();
    await importRef.set({
      familyId,
      name: displayName,
      person: personName || null,
      personUid: personId || null,
      assignedMember: personName || null,
      targetType: kind,
      planningImportKind: kind,
      feedUrl,
      url: feedUrl,
      autoSync: true,
      source: "url",
      eventCount: 0,
      createdByUid: uid,
      lastSync: admin.firestore.FieldValue.serverTimestamp(),
    });

    const importSnap = await importRef.get();
    const result = await syncFeedDocument(importSnap, {
      icsText,
      createdByUid: uid,
      overrideMeta: {
        name: displayName,
        person: personName,
        personUid: personId,
        targetType: kind,
      },
    });

    return {importId: importRef.id, eventCount: result.eventCount, synced: true};
  } catch (err) {
    if (err instanceof HttpsError) throw err;
    console.error("subscribeCalendarFeed error:", err.message || err);
    throw new HttpsError(
        "unavailable",
        err.message || "Kunde inte hämta eller synka kalendern.",
    );
  }
});

/** Nattlig synk av alla autoSync-feeds. */
exports.syncCalendarFeeds = onSchedule({
  schedule: "30 4 * * *",
  timeZone: "Europe/Stockholm",
  region: "us-central1",
  timeoutSeconds: 540,
  memory: "512MiB",
}, async () => {
  const db = admin.firestore();
  const snap = await db.collection("calendar_imports")
      .where("autoSync", "==", true)
      .get();

  let ok = 0;
  let fail = 0;
  for (const doc of snap.docs) {
    const d = doc.data() || {};
    // Foto-importer får ALDRIG synkas som feeds, och importer utan url ignoreras.
    if (d.importKind === "photo" || !(d.feedUrl || d.url)) continue;
    try {
      await syncFeedDocument(doc);
      ok++;
    } catch (err) {
      fail++;
      console.error(
          `syncCalendarFeeds: misslyckades för ${doc.id}:`,
          err.message || err,
      );
    }
  }
  console.log(`syncCalendarFeeds: klar ok=${ok} fail=${fail} total=${snap.size}`);
  return null;
});

exports.commitInChunks = commitInChunks;
