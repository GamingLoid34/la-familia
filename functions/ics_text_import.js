/* eslint-disable valid-jsdoc, max-len, require-jsdoc */
/**
 * Callable importIcsText — Android-porten har ingen egen ICS-parser
 * (Fas 11 i MIGRATION_PLAN.md). Klienten läser .ics-filen och skickar
 * texten hit; servern kör EXAKT samma tolkning som Flutter-klientens
 * lokala parser i lib/screens/calendar_import_page.dart
 * (`_parseAndSaveIcs`), inte `calendar_feeds.js:parseIcsToEvents` (som
 * konverterar till Europe/Stockholm och används av URL-prenumerationer).
 *
 * Skillnad mot parseIcsToEvents som är avsiktlig och måste bevaras:
 * - DTSTART/DTEND tolkas som NAIVA lokala tider (ingen tidszonskonvertering),
 *   precis som klientens _parseDtstart.
 * - Ingen icsKey, ingen diff mot befintliga events — detta är en
 *   engångsimport ("Alternativ 2 — Ladda upp .ics-fil"), inte en
 *   omsynkbar prenumeration.
 * - calendar_imports-dokumentet får source: "file" (inte "url"/"calendar_imports"-diff-städning).
 */
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const {commitInChunks} = require("./calendar_feeds");

const MAX_ICS_TEXT_BYTES = 5 * 1024 * 1024;
const MAX_EVENTS = 200;
const MAX_DESCRIPTION_CHARS = 15000;
const MAX_LOCATION_CHARS = 2000;

/** Vecklar upp radbrytna ICS-rader (fortsättningsrader börjar med space/tab). */
function unfoldLines(icsText) {
  const raw = icsText.replace(/\r\n/g, "\n").replace(/\r/g, "\n").split("\n");
  const lines = [];
  for (const line of raw) {
    if ((line.startsWith(" ") || line.startsWith("\t")) && lines.length) {
      lines[lines.length - 1] += line.substring(1);
    } else {
      lines.push(line);
    }
  }
  return lines;
}

/** Grupperar rader till VEVENT-block, samma logik som klientens _parseAndSaveIcs. */
function extractVevents(lines) {
  const events = [];
  let current = null;
  for (const line of lines) {
    const t = line.trim();
    if (t === "BEGIN:VEVENT") {
      current = {};
    } else if (t === "END:VEVENT" && current) {
      events.push(current);
      current = null;
    } else if (current) {
      const idx = line.indexOf(":");
      if (idx > 0) {
        const keyRaw = line.substring(0, idx);
        const val = line.substring(idx + 1).trim();
        const key = keyRaw.split(";")[0].toUpperCase();
        current[key] = val;
      }
    }
  }
  return events;
}

function decodeIcsText(text) {
  return String(text || "")
      .replace(/\\n/g, "\n")
      .replace(/\\,/g, ",")
      .replace(/\\;/g, ";")
      .replace(/\\\\/g, "\\");
}

/** Naiv lokal tid (ingen tidszonskonvertering) — speglar klientens _parseDtstart. */
function parseDtstart(value) {
  if (!value) return null;
  try {
    const clean = value.replace(/Z/g, "").trim();
    if (clean.length < 8) return null;
    const y = parseInt(clean.substring(0, 4), 10);
    const m = parseInt(clean.substring(4, 6), 10);
    const d = parseInt(clean.substring(6, 8), 10);
    let h = 0;
    let min = 0;
    if (clean.length >= 15 && clean[8] === "T") {
      h = parseInt(clean.substring(9, 11), 10);
      min = parseInt(clean.substring(11, 13), 10);
    }
    if ([y, m, d, h, min].some((n) => Number.isNaN(n))) return null;
    return {y, m, d, h, min};
  } catch (e) {
    return null;
  }
}

function dateKeyFromParts(p) {
  return `${String(p.y).padStart(4, "0")}-${String(p.m).padStart(2, "0")}-${String(p.d).padStart(2, "0")}`;
}

function hmFromParts(p) {
  return `${String(p.h).padStart(2, "0")}:${String(p.min).padStart(2, "0")}`;
}

/** Jämför två naiva datum/tid-delar kronologiskt (samma kalender antas). */
function comparePartsAfter(a, b) {
  const av = ((a.y * 12 + (a.m - 1)) * 31 + a.d) * 1440 + a.h * 60 + a.min;
  const bv = ((b.y * 12 + (b.m - 1)) * 31 + b.d) * 1440 + b.h * 60 + b.min;
  return av > bv;
}

function parseIcsDuration(raw) {
  if (!raw) return null;
  const s = String(raw).trim().toUpperCase();
  if (!s.startsWith("P")) return null;
  let days = 0;
  const dm = /(\d+)D/.exec(s);
  if (dm) days = parseInt(dm[1], 10);
  const wm = /(\d+)W/.exec(s);
  if (wm) days += parseInt(wm[1], 10) * 7;
  let tp = "";
  const tIdx = s.indexOf("T");
  if (tIdx >= 0) tp = s.substring(tIdx + 1);
  let hours = 0;
  let minutes = 0;
  let seconds = 0;
  const hm = /(\d+)H/.exec(tp);
  if (hm) hours = parseInt(hm[1], 10);
  const mm = /(\d+)M/.exec(tp);
  if (mm) minutes = parseInt(mm[1], 10);
  const sm = /(\d+)S/.exec(tp);
  if (sm) seconds = parseInt(sm[1], 10);
  const totalMinutes = days * 24 * 60 + hours * 60 + minutes + (seconds > 0 ? 1 : 0);
  return totalMinutes > 0 ? totalMinutes : null;
}

function addMinutes(p, minutes) {
  const base = new Date(Date.UTC(p.y, p.m - 1, p.d, p.h, p.min));
  base.setUTCMinutes(base.getUTCMinutes() + minutes);
  return {
    y: base.getUTCFullYear(),
    m: base.getUTCMonth() + 1,
    d: base.getUTCDate(),
    h: base.getUTCHours(),
    min: base.getUTCMinutes(),
  };
}

/** Sluttid HH:mm från DURATION eller DTEND, eller null. Speglar _icsEndTimeHm. */
function icsEndTimeHm(ev, startParts) {
  const durMinutes = parseIcsDuration(ev.DURATION);
  if (durMinutes && durMinutes > 0) {
    const end = addMinutes(startParts, durMinutes);
    if (!comparePartsAfter(end, startParts)) return null;
    return hmFromParts(end);
  }
  const endParts = parseDtstart(ev.DTEND);
  if (!endParts || !comparePartsAfter(endParts, startParts)) return null;
  return hmFromParts(endParts);
}

function truncate(text, max) {
  return text.length > max ? `${text.slice(0, max)}…` : text;
}

/** DESCRIPTION/LOCATION: ICS-avkodning, enkel HTML → radbrytningar, taggborttagning. */
function sanitizeIcsBody(raw) {
  if (!raw) return "";
  return htmlToText(decodeIcsText(raw));
}

/**
 * Enkel HTML → text: radbrytning för <br> och </p>, taggar bort, vanliga entiteter avkodade.
 * Delas med skolnyheternas RSS-synk (news_feeds.js), så samma brödtext blir samma text.
 * @param {string} raw
 * @return {string}
 */
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

function icsExtendedProps(ev) {
  const out = {};
  for (const key of Object.keys(ev)) {
    if (!key.startsWith("X-")) continue;
    const v = sanitizeIcsBody(ev[key]);
    if (!v) continue;
    out[key] = truncate(v, MAX_LOCATION_CHARS);
  }
  return out;
}

/**
 * Tolkar rå ICS-text till händelsefält, med samma filter (framtida/idag,
 * max 200) och fältform som klientens _parseAndSaveIcs.
 * @param {string} icsText
 * @param {{ todayParts: {y:number,m:number,d:number} }} [opts] för tester —
 *   annars beräknas dagens datum från servertiden.
 * @return {Array<object>} fält redo att skrivas till planner_events (utan
 *   familyId/personUids/calendarImportId/createdByUid — läggs på av anroparen).
 */
function parseIcsTextToEventDrafts(icsText, opts = {}) {
  const lines = unfoldLines(icsText);
  const vevents = extractVevents(lines);

  const today = opts.todayParts || (() => {
    const now = new Date();
    return {y: now.getFullYear(), m: now.getMonth() + 1, d: now.getDate()};
  })();
  const todayAtMidnight = {...today, h: 0, min: 0};

  const drafts = [];
  for (const ev of vevents) {
    const title = decodeIcsText(ev.SUMMARY || "").trim();
    if (!title) continue;
    const startParts = parseDtstart(ev.DTSTART);
    if (!startParts) continue;
    // isBefore(today) i kliententen — dvs strikt före midnatt idag, dagens
    // datum (oavsett klockslag) räknas som "framtida".
    if (comparePartsAfter(todayAtMidnight, startParts)) continue;
    if (drafts.length >= MAX_EVENTS) break;

    const startHm = (startParts.h === 0 && startParts.min === 0) ? "" : hmFromParts(startParts);
    const endHm = icsEndTimeHm(ev, startParts);

    const draft = {
      title,
      date: dateKeyFromParts(startParts),
      time: startHm,
    };
    if (endHm) draft.endTime = endHm;

    const desc = sanitizeIcsBody(ev.DESCRIPTION || "");
    if (desc) draft.calendarDescription = truncate(desc, MAX_DESCRIPTION_CHARS);

    const loc = sanitizeIcsBody(ev.LOCATION || "");
    if (loc) draft.location = truncate(loc, MAX_LOCATION_CHARS);

    const calUrl = decodeIcsText(ev.URL || "").trim();
    if (calUrl) draft.calendarUrl = calUrl.length > MAX_LOCATION_CHARS ? calUrl.slice(0, MAX_LOCATION_CHARS) : calUrl;

    const extras = icsExtendedProps(ev);
    if (Object.keys(extras).length) draft.calendarExtendedProps = extras;

    drafts.push(draft);
  }
  return drafts;
}

/**
 * Callable: importIcsText
 * data: { icsText: string, calendarName: string, memberUid?: string, kind: "schedule"|"activity" }
 * return: { importId: string, count: number }
 */
exports.importIcsText = onCall({
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
    throw new HttpsError("permission-denied", "Endast föräldrar kan importera kalenderfiler.");
  }
  const familyId = caller.familyId;
  if (!familyId) {
    throw new HttpsError("failed-precondition", "Ingen familj.");
  }

  const {icsText, calendarName, memberUid, kind: rawKind} = request.data || {};

  if (typeof icsText !== "string" || !icsText.trim()) {
    throw new HttpsError("invalid-argument", "ICS-innehåll saknas.");
  }
  // Byte-storlek, inte teckenlängd (UTF-8 kan vara upp till 4 byte/tecken).
  if (Buffer.byteLength(icsText, "utf8") > MAX_ICS_TEXT_BYTES) {
    throw new HttpsError("invalid-argument", "Kalenderfilen är för stor (max 5 MB).");
  }

  const kind = rawKind === "activity" ? "activity" : "schedule";
  const name = (typeof calendarName === "string" && calendarName.trim()) ?
    calendarName.trim() : "Importerad kalender";

  let personName = "";
  let personUid = "";
  if (typeof memberUid === "string" && memberUid.trim()) {
    const memberSnap = await db.collection("users").doc(memberUid.trim()).get();
    if (memberSnap.exists) {
      const memberData = memberSnap.data() || {};
      if (memberData.familyId === familyId) {
        personUid = memberSnap.id;
        personName = String(memberData.name || "").trim();
      }
    }
  }

  if (kind === "schedule" && !personUid) {
    throw new HttpsError(
        "invalid-argument",
        "Välj vem schemat gäller, annars syns det inte i kalendern.",
    );
  }

  const drafts = parseIcsTextToEventDrafts(icsText);

  const importRef = db.collection("calendar_imports").doc();
  const piktogram = kind === "activity" ? "📋" : "📚";

  const ops = [];
  for (const draft of drafts) {
    const ref = db.collection("planner_events").doc();
    const fields = {
      title: draft.title,
      piktogram,
      type: "activity",
      date: draft.date,
      time: draft.time,
      persons: personName ? [personName] : [],
      personUids: personUid ? [personUid] : [],
      checklist: [],
      source: "calendar",
      planningImportKind: kind,
      calendarName: name,
      calendarImportId: importRef.id,
      createdBy: uid,
      createdByUid: uid,
      isPending: false,
      familyId,
    };
    if (draft.endTime) fields.endTime = draft.endTime;
    if (draft.calendarDescription) fields.calendarDescription = draft.calendarDescription;
    if (draft.location) fields.location = draft.location;
    if (draft.calendarUrl) fields.calendarUrl = draft.calendarUrl;
    if (draft.calendarExtendedProps) fields.calendarExtendedProps = draft.calendarExtendedProps;
    ops.push({ref, data: fields});
  }

  if (ops.length === 0) {
    return {importId: "", count: 0};
  }

  ops.push({
    ref: importRef,
    data: {
      name,
      url: "",
      feedUrl: "",
      familyId,
      lastSync: admin.firestore.FieldValue.serverTimestamp(),
      eventCount: ops.length,
      source: "file",
      autoSync: false,
      planningImportKind: kind,
      targetType: kind,
      assignedMember: personName || null,
      person: personName || null,
      personUid: personUid || null,
      createdByUid: uid,
    },
  });

  await commitInChunks(db, ops);

  return {importId: importRef.id, count: ops.length - 1};
});

exports.htmlToText = htmlToText;

exports._test = {
  unfoldLines,
  extractVevents,
  parseDtstart,
  parseIcsDuration,
  icsEndTimeHm,
  sanitizeIcsBody,
  htmlToText,
  icsExtendedProps,
  parseIcsTextToEventDrafts,
};
