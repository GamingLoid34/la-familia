/* eslint-disable max-len, require-jsdoc */
"use strict";

// RFC 5545: local DTSTART + TZID keeps recurring activities at the same wall
// time across daylight saving. Export is read-only; no user data is rewritten.
const {createHash} = require("node:crypto");
const ZONE = "Europe/Stockholm";
const DAY = 86400000;
const formatter = new Intl.DateTimeFormat("en-GB", {
  timeZone: ZONE, year: "numeric", month: "2-digit", day: "2-digit",
  hour: "2-digit", minute: "2-digit", second: "2-digit", hourCycle: "h23",
});

class CalendarExportError extends Error {
  constructor(message) {
    super(message);
    this.name = "CalendarExportError";
  }
}

function fail(message) {
  throw new CalendarExportError(message);
}

function dateValue(value, label = "Datum") {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) fail(`${label} är ogiltigt. Rätta aktiviteten och försök igen.`);
  const millis = Date.parse(`${value}T00:00:00Z`);
  if (!Number.isFinite(millis) || new Date(millis).toISOString().slice(0, 10) !== value || Number(value.slice(0, 4)) < 1900) {
    fail(`${label} måste vara ett giltigt datum från år 1900.`);
  }
  return value;
}

function addDay(value) {
  return dateValue(new Date(Date.parse(`${value}T00:00:00Z`) + DAY).toISOString().slice(0, 10));
}

function timeValue(value, allowMidnightEnd = false) {
  if (allowMidnightEnd && value === "24:00") return value;
  if (typeof value !== "string" || !/^([01]\d|2[0-3]):[0-5]\d$/.test(value)) fail("En aktivitet har ett ogiltigt klockslag. Rätta tiden och försök igen.");
  return value;
}

function localStamp(date, time) {
  return `${date.replaceAll("-", "")}T${time.replace(":", "")}00`;
}

function utcStamp(date) {
  return date.toISOString().replace(/[-:]/g, "").replace(/\.\d{3}Z$/, "Z");
}

function offsetAt(millis) {
  const p = Object.fromEntries(formatter.formatToParts(new Date(millis)).map((part) => [part.type, part.value]));
  return Date.UTC(+p.year, +p.month - 1, +p.day, +p.hour, +p.minute, +p.second) - Math.floor(millis / 1000) * 1000;
}

function localToUtc(date, time) {
  const naive = Date.parse(`${date}T${time}:00Z`);
  const offsets = new Set([offsetAt(naive - 2 * DAY), offsetAt(naive), offsetAt(naive + 2 * DAY)]);
  const candidates = [...offsets].map((offset) => naive - offset).filter((instant) => instant + offsetAt(instant) === naive).sort((a, b) => a - b);
  if (!candidates.length) fail(`Klockslaget ${time} den ${date} finns inte vid övergången till sommartid. Rätta aktiviteten före export.`);
  // RFC 5545 chooses the first occurrence of an ambiguous local time.
  return new Date(candidates[0]);
}

function textValue(value) {
  // eslint-disable-next-line no-control-regex -- iCalendar TEXT forbids these control bytes.
  return String(value ?? "").replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/g, "")
      .replaceAll("\\", "\\\\").replace(/\r\n|\r|\n/g, "\\n").replaceAll(";", "\\;").replaceAll(",", "\\,");
}

// Continuation whitespace counts towards the 75-octet physical line limit.
// Iterating code points, rather than bytes, never splits a UTF-8 character.
function foldLine(line) {
  const lines = [];
  let current = "";
  let bytes = 0;
  for (const char of line) {
    const size = Buffer.byteLength(char, "utf8");
    if (bytes + size > 75) {
      lines.push(current);
      current = " ";
      bytes = 1;
    }
    current += char;
    bytes += size;
  }
  lines.push(current);
  return lines.join("\r\n");
}

function uidFor(familyId, collection, id) {
  return `${createHash("sha256").update(JSON.stringify([familyId, collection, id])).digest("hex")}@vardag.app`;
}

function offsetText(offset) {
  const minutes = Math.abs(offset / 60000);
  return `${offset < 0 ? "-" : "+"}${String(Math.floor(minutes / 60)).padStart(2, "0")}${String(minutes % 60).padStart(2, "0")}`;
}

function timezoneLines(earliestYear) {
  const lines = ["BEGIN:VTIMEZONE", `TZID:${ZONE}`, `X-LIC-LOCATION:${ZONE}`];
  // Modern EU rules are stable since 1996. For older stored activities, derive
  // historical observances from the Node runtime's IANA timezone database.
  if (earliestYear < 1996) {
    let cursor = Date.UTC(earliestYear, 0, 1);
    let previous = offsetAt(cursor);
    lines.push("BEGIN:STANDARD", `DTSTART:${earliestYear}0101T000000`, `TZOFFSETFROM:${offsetText(previous)}`, `TZOFFSETTO:${offsetText(previous)}`, "END:STANDARD");
    const end = Date.UTC(1996, 0, 1);
    while (cursor < end) {
      const next = Math.min(cursor + DAY, end);
      const offset = offsetAt(next);
      if (offset !== previous) {
        let low = cursor;
        let high = next;
        while (high - low > 1000) {
          const mid = Math.floor((low + high) / 2000) * 1000;
          if (offsetAt(mid) === previous) low = mid;
          else high = mid;
        }
        const kind = offset > previous ? "DAYLIGHT" : "STANDARD";
        lines.push(`BEGIN:${kind}`, `DTSTART:${utcStamp(new Date(high + previous)).slice(0, -1)}`, `TZOFFSETFROM:${offsetText(previous)}`, `TZOFFSETTO:${offsetText(offset)}`, `END:${kind}`);
        previous = offset;
      }
      cursor = next;
    }
  }
  lines.push(
      "BEGIN:DAYLIGHT", "DTSTART:19960331T020000", "TZOFFSETFROM:+0100", "TZOFFSETTO:+0200", "TZNAME:CEST", "RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=-1SU", "END:DAYLIGHT",
      "BEGIN:STANDARD", "DTSTART:19961027T030000", "TZOFFSETFROM:+0200", "TZOFFSETTO:+0100", "TZNAME:CET", "RRULE:FREQ=YEARLY;BYMONTH=10;BYDAY=-1SU", "END:STANDARD", "END:VTIMEZONE",
  );
  return lines;
}

function recurrenceFor(data) {
  const rec = data.recurrence;
  if (rec == null) {
    if (data.isRecurring === true) fail("En återkommande aktivitet saknar sin upprepningsregel. Rätta aktiviteten före export.");
    return null;
  }
  if (typeof rec !== "object" || Array.isArray(rec) || !["daily", "weekly", "biweekly", "monthly"].includes(rec.type)) {
    fail("En aktivitet har en upprepningsregel som exporten inte stöder. Ingen fil skapades, så att tillfällen inte försvinner.");
  }
  if (Object.keys(rec).some((key) => !["type", "startDate", "endDate", "exceptions"].includes(key))) fail("En aktivitet använder extra upprepningsvillkor som exporten inte stöder. Ingen fil skapades.");
  const start = dateValue(rec.startDate || data.date);
  const end = rec.endDate ? dateValue(rec.endDate, "Slutdatum") : null;
  if (end && end < start) fail("En upprepningsregel slutar före sitt startdatum. Rätta aktiviteten före export.");
  if (rec.exceptions != null && !Array.isArray(rec.exceptions)) fail("En aktivitets undantagsdatum är ogiltiga. Rätta aktiviteten före export.");
  const exceptions = [...new Set((rec.exceptions || []).map((d) => dateValue(d, "Undantagsdatum")))];
  return {type: rec.type, start, end, exceptions};
}

function occursOn(rec, date) {
  if (date < rec.start || (rec.end && date > rec.end)) return false;
  const days = (Date.parse(`${date}T00:00:00Z`) - Date.parse(`${rec.start}T00:00:00Z`)) / DAY;
  if (rec.type === "daily") return true;
  if (rec.type === "weekly") return days % 7 === 0;
  if (rec.type === "biweekly") return days % 14 === 0;
  return date.slice(-2) === rec.start.slice(-2);
}

function normalizeEvent(record, counters) {
  const data = record.data;
  const rec = recurrenceFor(data);
  const rawDate = rec?.start || data.date;
  if (rawDate == null || rawDate === "") {
    counters.undated++;
    return null;
  }
  const date = dateValue(rawDate);
  if (data.timeMode && !["allDay", "undecided", "timed", "time"].includes(data.timeMode)) fail("En aktivitet har ett tidsläge som exporten inte stöder. Ingen fil skapades.");
  const time = data.time ?? "";
  const allDay = data.timeMode === "allDay" || data.timeMode === "undecided" || data.icsAllDay === true || time === "";
  const undecided = data.timeMode === "undecided" || (allDay && data.timeMode !== "allDay" && data.icsAllDay !== true);
  if (undecided) counters.undecided++;
  if (!allDay) timeValue(time);
  let endDate = date;
  let endTime = data.endTime || "";
  if (!allDay) {
    localToUtc(date, time);
    if (endTime) {
      timeValue(endTime, true);
      if (endTime === "24:00" || endTime <= time) {
        endDate = addDay(date);
        if (endTime === "24:00") endTime = "00:00";
      }
      localToUtc(endDate, endTime);
    }
  }
  if (data.checklist?.length || data.lessonPrep?.text) counters.checklists++;
  if (rec && !allDay && time.startsWith("02:")) counters.dst++;
  return {...record, date, time, allDay, undecided, endDate, endTime, rec};
}

function descriptionFor(event) {
  const d = event.data;
  const parts = [];
  const descriptions = [...new Set([d.description, d.calendarDescription, d.note].filter((v) => typeof v === "string" && v.trim()))];
  parts.push(...descriptions);
  if (Array.isArray(d.persons) && d.persons.length) parts.push(`Gäller: ${d.persons.filter((p) => typeof p === "string").join(", ")}`);
  if (event.undecided) parts.push("Tid ej bestämd i Vardag. Visas som heldag i denna kalender.");
  if (d.transport && typeof d.transport === "object") {
    for (const [key, label] of [["lamnar", "Lämnar"], ["hamtar", "Hämtar"]]) {
      if (typeof d.transport[key] === "string" && d.transport[key]) parts.push(`${label}: ${d.transport[key]}`);
    }
  }
  if (Array.isArray(d.checklist) && d.checklist.length) {
    parts.push("Packlista:\n" + d.checklist.map((i) => typeof i === "string" ? `[ ] ${i}` : `[${i?.isDone ? "x" : " "}] ${i?.item ?? i?.text ?? ""}`).join("\n"));
  }
  if (typeof d.lessonPrep?.text === "string" && d.lessonPrep.text) {
    parts.push(`Förberedelse: ${d.lessonPrep.text}`);
    if (Array.isArray(d.lessonPrep.doneDates) && d.lessonPrep.doneDates.length) parts.push(`Förberedelse klar: ${d.lessonPrep.doneDates.join(", ")}`);
  }
  if (d.originalOccurrenceDate) parts.push(`Flyttad från ${d.originalOccurrenceDate}.`);
  return parts.join("\n\n");
}

function startLine(property, event, date = event.date) {
  return event.allDay ? `${property};VALUE=DATE:${date.replaceAll("-", "")}` : `${property};TZID=${ZONE}:${localStamp(date, event.time)}`;
}

function eventLines(event, uid, stamp, master, movedDates) {
  const d = event.data;
  const lines = ["BEGIN:VEVENT", `UID:${uid}`, `DTSTAMP:${stamp}`, "SEQUENCE:0", `SUMMARY:${textValue(d.title || "Aktivitet")}`];
  lines.push(startLine("DTSTART", event));
  if (event.allDay) lines.push(`DTEND;VALUE=DATE:${addDay(event.date).replaceAll("-", "")}`);
  else if (event.endTime) lines.push(`DTEND;TZID=${ZONE}:${localStamp(event.endDate, event.endTime)}`);
  if (d.visibility === "private") lines.push("CLASS:PRIVATE");
  if (master) lines.push(startLine("RECURRENCE-ID", master, d.originalOccurrenceDate));
  if (event.rec) {
    const r = event.rec;
    const frequency = {daily: "DAILY", weekly: "WEEKLY", biweekly: "WEEKLY;INTERVAL=2", monthly: "MONTHLY"}[r.type];
    let rule = `RRULE:FREQ=${frequency}`;
    // Explicit BYMONTHDAY also avoids importers clamping a 31st to the 30th
    // and then drifting subsequent occurrences away from Vardag's rule.
    if (r.type === "monthly") rule += `;BYMONTHDAY=${Number(r.start.slice(-2))}`;
    if (r.end) rule += `;UNTIL=${event.allDay ? r.end.replaceAll("-", "") : utcStamp(localToUtc(r.end, "23:59")).replace(/00Z$/, "59Z")}`;
    lines.push(rule);
    for (const date of r.exceptions) {
      if (!movedDates?.has(date)) lines.push(startLine("EXDATE", event, date));
    }
  }
  const description = descriptionFor(event);
  if (description) lines.push(`DESCRIPTION:${textValue(description)}`);
  if (typeof d.location === "string" && d.location) lines.push(`LOCATION:${textValue(d.location)}`);
  lines.push("END:VEVENT");
  return lines;
}

function buildIcalendar({familyId, events, shifts = [], scope, now = new Date(), warnings = []}) {
  const counters = {undated: 0, undecided: 0, checklists: 0, detached: 0, dst: 0};
  const records = [...events.map((e) => ({...e, collection: "planner_events"})), ...shifts.map((s) => ({
    ...s, collection: "work_shifts", data: {...s.data, title: s.data.title || (s.data.who ? `Arbetspass · ${s.data.who}` : "Arbetspass"),
      time: s.data.startTime ?? s.data.start ?? "", endTime: s.data.endTime ?? s.data.end ?? "", persons: s.data.who ? [s.data.who] : []},
  }))];
  const normalized = records.map((r) => normalizeEvent(r, counters)).filter(Boolean);
  const masters = new Map(normalized.filter((e) => e.collection === "planner_events" && e.rec).map((e) => [e.id, e]));
  const overrides = new Map();
  const movedDates = new Map();
  for (const event of normalized) {
    const d = event.data;
    if (!d.originalSeriesId && !d.originalOccurrenceDate) continue;
    if (!d.originalSeriesId || !d.originalOccurrenceDate || event.rec) fail("Ett flyttat tillfälle har en ofullständig serielänk. Rätta aktiviteten före export.");
    dateValue(d.originalOccurrenceDate, "Ursprungsdatum");
    const master = masters.get(d.originalSeriesId);
    if (!master) {
      counters.detached++;
      continue;
    }
    // Never merge public and private series, even if malformed stored data links them.
    if ((master.data.visibility === "private") !== (d.visibility === "private") || master.data.privateOwnerUid !== d.privateOwnerUid) fail("Ett flyttat tillfälle har en ogiltig serielänk. Ingen fil skapades.");
    if (!occursOn(master.rec, d.originalOccurrenceDate) || !master.rec.exceptions.includes(d.originalOccurrenceDate)) fail("Ett flyttat tillfälle stämmer inte med seriens undantagsdatum. Rätta aktiviteten före export.");
    const dates = movedDates.get(master.id) || new Set();
    if (dates.has(d.originalOccurrenceDate)) fail("Två flyttade tillfällen har samma ursprungsdatum. Rätta dubletten före export.");
    dates.add(d.originalOccurrenceDate);
    movedDates.set(master.id, dates);
    overrides.set(event.id, master);
  }
  const resultWarnings = [...warnings];
  if (counters.undated) resultWarnings.push(`${counters.undated} aktiviteter saknar datum och kunde inte tas med.`);
  if (counters.undecided) resultWarnings.push(`${counters.undecided} aktiviteter utan bestämt klockslag visas som heldag.`);
  if (counters.checklists) resultWarnings.push("Packlistor och förberedelser följer med som text. Avbockningar synkroniseras inte i en exporterad kalenderfil.");
  if (counters.detached) resultWarnings.push(`${counters.detached} flyttade tillfällen exporteras som egna aktiviteter eftersom deras serier inte ingår i urvalet.`);
  if (counters.dst) resultWarnings.push("Återkommande aktiviteter klockan 02–03 kan hoppas över av andra kalenderappar den dag klockan ställs fram till sommartid.");
  const lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Vardag//Kalenderexport 1.0//SV", "CALSCALE:GREGORIAN", `X-WR-CALNAME:${scope === "family" ? "Vardag – familj" : "Vardag – min kalender"}`, `X-WR-TIMEZONE:${ZONE}`];
  if (normalized.some((e) => !e.allDay)) lines.push(...timezoneLines(Math.min(1996, ...normalized.map((e) => Number(e.date.slice(0, 4))))));
  // Masters precede overrides for less capable importers.
  normalized.sort((a, b) => Number(!!b.rec) - Number(!!a.rec) || a.collection.localeCompare(b.collection) || a.id.localeCompare(b.id));
  for (const event of normalized) {
    const master = event.collection === "planner_events" ? overrides.get(event.id) : null;
    const uid = uidFor(familyId, event.collection, master?.id || event.id);
    lines.push(...eventLines(event, uid, utcStamp(now), master, movedDates.get(event.id)));
  }
  lines.push("END:VCALENDAR");
  return {ics: lines.map(foldLine).join("\r\n") + "\r\n", eventCount: normalized.length, warnings: resultWarnings};
}

module.exports = {buildIcalendar, CalendarExportError, _test: {textValue, foldLine, uidFor, localToUtc, timezoneLines, recurrenceFor, occursOn}};
