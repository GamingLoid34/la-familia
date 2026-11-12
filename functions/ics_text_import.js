/* eslint-disable valid-jsdoc, max-len, require-jsdoc */
/** Shared, bounded ICS-file import for Android, iOS and web. No URL-feed changes. */
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const {createHash} = require("node:crypto");
const {gzipSync} = require("node:zlib");
const parser = require("./ics_file_parser");
const MAX_ICS_TEXT_BYTES = 5 * 1024 * 1024;
const hash = (text) => createHash("sha256").update(text).digest("hex");

function callerFamily(caller, requestedFamilyId) {
  if (!caller || !["parent", "admin"].includes(caller.role)) {
    throw new HttpsError("permission-denied", "Endast föräldrar kan importera kalenderfiler.");
  }
  const familyId = caller.familyId;
  if (typeof familyId !== "string" || !familyId.trim() || familyId.includes("/")) {
    throw new HttpsError("failed-precondition", "Användaren saknar en giltig familj.");
  }
  if (requestedFamilyId !== undefined && requestedFamilyId !== familyId) {
    throw new HttpsError("permission-denied", "Kalendern måste importeras till din egen familj.");
  }
  return familyId;
}
function validateMember(member, memberUid, familyId, kind) {
  if (memberUid && (!member || member.familyId !== familyId)) {
    throw new HttpsError("permission-denied", "Den valda personen tillhör inte din familj.");
  }
  if (kind === "schedule" && !memberUid) {
    throw new HttpsError("invalid-argument", "Välj vem schemat gäller, annars syns det inte i kalendern.");
  }
}
function fileImportId(familyId, personUid, kind, text) {
  return `ics_${hash(JSON.stringify([familyId, personUid, kind, text.replace(/^\uFEFF/, "").replace(/\r\n?/g, "\n")]))}`;
}
function checkedExisting(snapshot, familyId) {
  if (snapshot.exists && snapshot.data().familyId !== familyId) {
    throw new HttpsError("failed-precondition", "Importens identifierare är upptagen. Kontakta supporten.");
  }
  return snapshot.exists;
}
function resultFor(importId, data, alreadyImported = false) {
  return {importId, count: data.eventCount, fromDate: data.fromDate, toDate: data.toDate,
    timeZone: "Europe/Stockholm", alreadyImported, warnings: data.warnings || [],
    maxEvents: parser.MAX_EVENTS, sourcePreserved: true};
}
function makeImportHandler({getDb = () => admin.firestore(), timestamp = () => admin.firestore.FieldValue.serverTimestamp(), now = () => new Date()} = {}) {
  return async (request) => {
    if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Inloggning krävs.");
    const uid = request.auth.uid;
    const data = request.data || {};
    const {icsText} = data;
    if (typeof icsText !== "string" || !icsText.trim()) throw new HttpsError("invalid-argument", "ICS-innehåll saknas.");
    if (Buffer.byteLength(icsText, "utf8") > MAX_ICS_TEXT_BYTES) throw new HttpsError("invalid-argument", "Kalenderfilen är för stor (max 5 MB).");
    if (data.kind !== undefined && !["activity", "schedule"].includes(data.kind)) throw new HttpsError("invalid-argument", "Välj aktivitet eller schema.");
    const kind = data.kind || "schedule";
    if (data.memberUid !== undefined && data.memberUid !== null && (typeof data.memberUid !== "string" || data.memberUid.includes("/"))) {
      throw new HttpsError("invalid-argument", "Välj en giltig familjemedlem.");
    }
    const personUid = (data.memberUid || "").trim();
    const db = getDb();
    const callerRef = db.collection("users").doc(uid);
    const callerSnap = await callerRef.get();
    const familyId = callerFamily(callerSnap.exists ? callerSnap.data() : null, data.familyId);
    const memberRef = personUid ? db.collection("users").doc(personUid) : null;
    const memberSnap = memberRef ? await memberRef.get() : null;
    validateMember(memberSnap?.exists ? memberSnap.data() : null, personUid, familyId, kind);
    const name = typeof data.calendarName === "string" && data.calendarName.trim() ? data.calendarName.trim().slice(0, 200) : "Importerad kalender";
    const importId = fileImportId(familyId, personUid, kind, icsText);
    const importRef = db.collection("calendar_imports").doc(importId);
    const existing = await importRef.get();
    if (checkedExisting(existing, familyId)) return {...resultFor(importId, existing.data(), true), ...(data.preview === true ? {preview: true} : {})};
    const window = parser.importWindow(data, now());
    const {drafts, warnings} = parser.parseIcsTextToEventDrafts(icsText, window, htmlToText);
    const metadata = {name, url: "", feedUrl: "", familyId, eventCount: drafts.length,
      source: "file", autoSync: false, planningImportKind: kind, targetType: kind,
      personUid: personUid || null, createdByUid: uid, ...window, warnings,
      originalSourceId: importId, sourcePreserved: true, importFormatVersion: 2};
    if (data.preview === true) return {...resultFor(importId, metadata), preview: true};
    if (!drafts.length) return {...resultFor("", metadata), sourcePreserved: false};
    // Original bytes survive text-field shortening and recurrence materialization.
    // Small gzip/base64 chunks keep source documents safely below Firestore's 1 MiB limit.
    const compressed = gzipSync(Buffer.from(icsText, "utf8")).toString("base64");
    const chunks = compressed.match(/.{1,600000}/g) || [];
    if (Buffer.byteLength(JSON.stringify(drafts)) + compressed.length > 7 * 1024 * 1024) {
      throw new HttpsError("invalid-argument", "Importen innehåller för mycket text för en säker engångsimport. Välj ett kortare datumintervall eller en mindre fil.");
    }
    const sourceRef = db.collection("calendar_import_sources").doc(importId);
    return db.runTransaction(async (tx) => {
      // Recheck access within the atomic write, including after transaction retries.
      const freshCaller = await tx.get(callerRef);
      callerFamily(freshCaller.exists ? freshCaller.data() : null, familyId);
      const freshMember = memberRef ? await tx.get(memberRef) : null;
      const person = freshMember?.exists ? freshMember.data() : null;
      validateMember(person, personUid, familyId, kind);
      const previous = await tx.get(importRef);
      if (checkedExisting(previous, familyId)) return resultFor(importId, previous.data(), true);
      const personName = person ? String(person.name || "").trim() : "";
      for (const draft of drafts) {
        tx.set(db.collection("planner_events").doc(`${importId}_${hash(draft.icsKey).slice(0, 32)}`), {
          ...draft, piktogram: kind === "activity" ? "📋" : "📚", type: "activity",
          persons: personName ? [personName] : [], personUids: personUid ? [personUid] : [], checklist: [],
          source: "calendar", planningImportKind: kind, calendarName: name,
          calendarImportId: importId, createdBy: uid, createdByUid: uid, isPending: false, familyId,
        });
      }
      tx.set(importRef, {...metadata, assignedMember: personName || null, person: personName || null, lastSync: timestamp()});
      tx.set(sourceRef, {familyId, importId, createdByUid: uid, encoding: "gzip-base64", chunks: chunks.length,
        originalBytes: Buffer.byteLength(icsText, "utf8"), sha256: hash(icsText), savedAt: timestamp()});
      chunks.forEach((chunk, i) => tx.set(sourceRef.collection("chunks").doc(String(i).padStart(3, "0")), {index: i, data: chunk}));
      return resultFor(importId, metadata);
    });
  };
}

function htmlToText(raw) {
  if (!raw) return "";
  let t = String(raw);
  t = t.replace(/<br\s*\/?>/gi, "\n");
  t = t.replace(/<\/p>/gi, "\n\n");
  // Block som slutar ger radbrytning, annars flyter ett veckobrevs rader ihop till en.
  t = t.replace(/<\/(?:div|li|h[1-6]|tr)>/gi, "\n");
  t = t.replace(/<[^>]*>/g, "");
  // SchoolSofts nyheter skriver å, ä och ö som entiteter (&aring; eller &#229;). `&amp;` avkodas
  // sist, annars blir en text som bokstavligen innehåller "&amp;lt;" ett "<".
  t = t
      .replace(/&nbsp;/g, " ")
      .replace(/&lt;/g, "<")
      .replace(/&gt;/g, ">")
      .replace(/&quot;/g, "\"")
      .replace(/&(?:apos|#39);/g, "'")
      .replace(/&([aAoO])ring;|&([aAoOuUeE])uml;/g, (m, ring, uml) =>
        ring ? NAMED_RING[ring] : NAMED_UML[uml])
      .replace(/&eacute;/g, "é")
      .replace(/&Eacute;/g, "É")
      .replace(/&#(\d{1,7});/g, (m, n) => codePointOrSame(m, Number(n)))
      .replace(/&#x([0-9a-f]{1,6});/gi, (m, n) => codePointOrSame(m, parseInt(n, 16)))
      .replace(/&amp;/g, "&");
  t = t.replace(/\n{3,}/g, "\n\n").trim();
  return t;
}

const NAMED_RING = {a: "å", A: "Å", o: "ø", O: "Ø"};
const NAMED_UML = {a: "ä", A: "Ä", o: "ö", O: "Ö", u: "ü", U: "Ü", e: "ë", E: "Ë"};

function codePointOrSame(entity, n) {
  return Number.isInteger(n) && n > 0 && n <= 0x10ffff ? String.fromCodePoint(n) : entity;
}

exports.importIcsText = onCall({region: "us-central1", timeoutSeconds: 120, memory: "512MiB"}, makeImportHandler());
// New clients fail safely against older servers instead of importing when an
// older import handler ignores preview=true. This endpoint always forces it.
exports.previewIcsText = onCall({region: "us-central1", timeoutSeconds: 120, memory: "512MiB"}, (request) =>
  makeImportHandler()({...request, data: {...request.data, preview: true}}));
exports.htmlToText = htmlToText;
exports._test = {...parser, htmlToText, callerFamily, validateMember, fileImportId, makeImportHandler};
