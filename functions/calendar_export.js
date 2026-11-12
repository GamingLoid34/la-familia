/* eslint-disable max-len, require-jsdoc */
"use strict";

const {onCall, HttpsError} = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const {buildIcalendar, CalendarExportError} = require("./calendar_ical");

const MAX_DOCUMENTS = 10000;
const MAX_RESPONSE_BYTES = 8 * 1024 * 1024;
const DETAIL_FIELDS = ["title", "piktogram", "checklist", "lessonPrep", "description", "calendarDescription", "location"];

function parseOptions(data) {
  if (!data || typeof data !== "object" || Array.isArray(data) || !["family", "personal"].includes(data.scope)) {
    throw new HttpsError("invalid-argument", "Välj familjens eller din egen kalender.");
  }
  if (Object.keys(data).some((key) => !["scope", "includeImported"].includes(key)) || (data.includeImported != null && typeof data.includeImported !== "boolean")) {
    throw new HttpsError("invalid-argument", "Exportvalen är ogiltiga. Uppdatera appen och försök igen.");
  }
  return {scope: data.scope, includeImported: data.includeImported === true};
}

function isImported(data) {
  return ["calendar", "ics", "google", "outlook", "icloud"].includes(data.source) || !!data.calendarImportId || !!data.calendarSourceId;
}

function includesPerson(data, uid, name) {
  const uids = Array.isArray(data.personUids) ? data.personUids : [];
  const names = Array.isArray(data.persons) ? data.persons : [];
  if (uids.length) return uids.includes(uid);
  return !names.length || (typeof name === "string" && name !== "" && names.includes(name));
}

function assignedToPerson(data, uid, name) {
  return data.whoUid ? data.whoUid === uid : typeof name === "string" && name !== "" && data.who === name;
}

async function buildCalendarExport({db, uid, data, now = new Date()}) {
  if (!uid) throw new HttpsError("unauthenticated", "Logga in för att exportera din kalender.");
  const {scope, includeImported} = parseOptions(data);
  // One read-only snapshot prevents an account/family change during the request
  // from combining events and private details belonging to different families.
  const snapshot = await db.runTransaction(async (tx) => {
    const profile = await tx.get(db.collection("users").doc(uid));
    const user = profile.exists ? profile.data() : null;
    if (!user || !["parent", "admin", "youth", "child"].includes(user.role) || typeof user.familyId !== "string" || !user.familyId || user.familyId.includes("/")) {
      throw new HttpsError("permission-denied", "Ditt konto saknar en verifierad familj. Logga in igen.");
    }
    if (scope === "family" && !["parent", "admin"].includes(user.role)) throw new HttpsError("permission-denied", "Endast en förälder kan exportera hela familjens kalender. Du kan exportera din egen.");
    const familyId = user.familyId;
    const family = await tx.get(db.collection("families").doc(familyId));
    if (!family.exists) throw new HttpsError("failed-precondition", "Familjen kunde inte hittas. Logga in igen.");
    const planner = await tx.get(db.collection("planner_events").where("familyId", "==", familyId).limit(MAX_DOCUMENTS + 1));
    const work = await tx.get(db.collection("work_shifts").where("familyId", "==", familyId).limit(MAX_DOCUMENTS + 1));
    if (planner.size > MAX_DOCUMENTS || work.size > MAX_DOCUMENTS) throw new HttpsError("resource-exhausted", "Kalendern är för stor för en enda export. Kontakta support för en fullständig export.");
    const counts = {pending: 0, imported: 0};
    const select = (doc, isWork) => {
      const value = doc.data();
      // Defense in depth: never trust a caller-supplied family id or rely on a
      // mocked/misconfigured query to enforce the boundary.
      if (value.familyId !== familyId) return null;
      if (value.visibility === "private") {
        if (scope !== "personal" || isWork || value.privateOwnerUid !== uid) return null;
      } else if (scope === "personal" && !(isWork ? assignedToPerson(value, uid, user.name) : includesPerson(value, uid, user.name))) return null;
      if (value.isPending === true) {
        counts.pending++;
        return null;
      }
      if (!includeImported && isImported(value)) {
        counts.imported++;
        return null;
      }
      return {id: doc.id, data: value};
    };
    const events = planner.docs.map((doc) => select(doc, false)).filter(Boolean);
    const shifts = work.docs.map((doc) => select(doc, true)).filter(Boolean);
    const privateEvents = events.filter((event) => event.data.visibility === "private");
    // Only this account's private collection is ever addressed. A parent does
    // not gain access to a child's private details through family export.
    for (let index = 0; index < privateEvents.length; index += 100) {
      const chunk = privateEvents.slice(index, index + 100);
      const refs = chunk.map((event) => db.collection("private_activities").doc(uid).collection("events").doc(event.id));
      const details = await tx.getAll(...refs);
      for (let i = 0; i < chunk.length; i++) {
        const detail = details[i].exists ? details[i].data() : null;
        if (!detail || detail.ownerUid !== uid || detail.familyId !== familyId || typeof detail.title !== "string" || !detail.title.trim()) {
          throw new HttpsError("failed-precondition", "En privat aktivitet kunde inte läsas fullständigt. Ingen fil skapades. Försök igen när aktiviteten har synkroniserats.");
        }
        // Discard possible presentation data accidentally stored on a marker.
        const merged = {...chunk[i].data};
        for (const field of ["description", "calendarDescription", "note", "location", "transport", ...DETAIL_FIELDS]) delete merged[field];
        for (const field of DETAIL_FIELDS) if (Object.hasOwn(detail, field)) merged[field] = detail[field];
        chunk[i].data = merged;
      }
    }
    return {events, shifts, counts, familyId};
  }, {readOnly: true});
  const warnings = [];
  if (snapshot.counts.imported) warnings.push(`${snapshot.counts.imported} aktiviteter från andra kalendrar har utelämnats för att undvika dubletter i ursprungskalendern.`);
  if (snapshot.counts.pending) warnings.push(`${snapshot.counts.pending} obekräftade förslag ingår inte i kalenderexporten.`);
  if (includeImported && [...snapshot.events, ...snapshot.shifts].some((event) => isImported(event.data))) warnings.push("Importerade aktiviteter ingår som de finns i Vardag. Flerdagshändelser kan vara uppdelade per dag och importerade serier kan bestå av enskilda tillfällen. Import till ursprungskalendern kan ge dubletter.");
  let calendar;
  try {
    calendar = buildIcalendar({...snapshot, scope, now, warnings});
  } catch (error) {
    if (error instanceof CalendarExportError) throw new HttpsError("failed-precondition", error.message);
    throw error;
  }
  const result = {filename: `vardag-${scope === "family" ? "familj" : "min-kalender"}-${now.toISOString().slice(0, 10)}.ics`, ...calendar};
  if (Buffer.byteLength(JSON.stringify(result), "utf8") > MAX_RESPONSE_BYTES) throw new HttpsError("resource-exhausted", "Kalenderfilen är för stor för en enda export. Kontakta support för en fullständig export.");
  return result;
}

exports.exportCalendar = onCall({region: "us-central1", timeoutSeconds: 120, memory: "512MiB"}, (request) =>
  buildCalendarExport({db: admin.firestore(), uid: request.auth?.uid, data: request.data}));
exports._test = {buildCalendarExport, parseOptions, isImported, includesPerson, assignedToPerson, MAX_DOCUMENTS, MAX_RESPONSE_BYTES};
