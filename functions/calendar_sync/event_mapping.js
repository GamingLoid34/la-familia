/* eslint-disable max-len, require-jsdoc */
"use strict";
const {createHash} = require("node:crypto");
const ical = require("node-ical");
const {buildIcalendar, _test: exportUtils} = require("../calendar_ical");
const {htmlToText} = require("../ics_text_import");
const {normalizeIcs, localParts, unfoldLines} = require("../ics_file_parser");
const ZONE = "Europe/Stockholm";
const DAY = 86400000;
const DAYS = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"];
const GRAPH_DAYS = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"];
class Unsupported extends Error {}
const fail = (reason) => {
  throw new Unsupported(reason);
};
const nextDay = (date, offset = 1) => new Date(Date.parse(`${date}T12:00:00Z`) + offset * DAY).toISOString().slice(0, 10);
const weekday = (date) => new Date(`${date}T12:00:00Z`).getUTCDay();
const stamp = (date, time = "") => `${date.replaceAll("-", "")}${time ? `T${time.replace(":", "")}00` : ""}`;
const utcStamp = (date) => date.toISOString().replace(/[-:]/g, "").replace(/\.\d+Z$/, "Z");
function dateKey(value) {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value) || !Number.isFinite(Date.parse(value)) || new Date(value).toISOString().slice(0, 10) !== value) fail("invalid-date");
  return value;
}
function timeValue(value) {
  if (typeof value !== "string" || !/^([01]\d|2[0-3]):[0-5]\d$/.test(value)) fail("invalid-time");
  return value;
}
function recurrence(input, date) {
  if (input == null) return null;
  if (typeof input !== "object" || Array.isArray(input) || !["daily", "weekly", "biweekly", "monthly"].includes(input.type) ||
      Object.keys(input).some((key) => !["type", "startDate", "endDate", "exceptions"].includes(key))) fail("unsupported-recurrence");
  const startDate = dateKey(input.startDate || date);
  if (startDate !== date) fail("recurrence-start-mismatch");
  const endDate = input.endDate ? dateKey(input.endDate) : null;
  if (endDate && endDate < startDate) fail("invalid-recurrence-range");
  if (input.exceptions && !Array.isArray(input.exceptions)) fail("invalid-exceptions");
  return {type: input.type, startDate, endDate, exceptions: [...new Set((input.exceptions || []).map(dateKey))].sort()};
}
function canonical(input) {
  if (!input || typeof input !== "object") fail("invalid-event");
  if (input.originalSeriesId || input.originalOccurrenceDate || (input.detachedOccurrences && Object.keys(input.detachedOccurrences).length)) fail("detached-occurrence");
  const date = dateKey(input.date);
  const mode = input.timeMode || (input.time ? "timed" : "allDay");
  if (!["timed", "allDay", "time"].includes(mode)) fail("undecided-time");
  const timed = mode !== "allDay";
  const time = timed ? timeValue(input.time) : "";
  const endTime = timed ? timeValue(input.endTime) : "";
  if (timed && endTime <= time) fail("overnight-or-empty-duration");
  if (timed) {
    exportUtils.localToUtc(date, time); exportUtils.localToUtc(date, endTime);
  }
  if (input.isRecurring && !input.recurrence) fail("missing-recurrence");
  return {title: String(input.title || "Aktivitet"), date, time, endTime, timeMode: timed ? "timed" : "allDay",
    recurrence: recurrence(input.recurrence, date), description: String(input.description ?? input.calendarDescription ?? ""),
    location: String(input.location || ""), private: input.private === true || input.visibility === "private"};
}
function stable(value) {
  if (Array.isArray(value)) return value.map(stable);
  if (value && typeof value === "object") return Object.fromEntries(Object.keys(value).sort().map((key) => [key, stable(value[key])]));
  return value;
}
function fingerprint(event) {
  return createHash("sha256").update(JSON.stringify(stable(canonical(event)))).digest("hex");
}
function supported(fn) {
  try {
    return {supported: true, ...fn()};
  } catch (error) {
    return {supported: false, reason: error instanceof Unsupported ? error.message : "uninterpretable-event"};
  }
}
function invitations(provider, raw) {
  if (raw.attendees?.length || raw.attendeesOmitted || raw.conferenceData || raw.isOnlineMeeting || raw.onlineMeeting) fail("unsupported-invitations");
  if (raw.organizer && !(provider === "google" ? raw.organizer.self === true : raw.isOrganizer === true)) fail("external-organizer");
}
function ruleFromIcs(lines, event, date, time, allDay) {
  const rules = lines.filter((l) => /^RRULE:/i.test(l));
  if (!rules.length) {
    if (Object.keys(event.exdate || {}).length) fail("orphan-exceptions");
    return null;
  }
  if (rules.length !== 1) fail("multiple-recurrence-rules");
  const entries = rules[0].slice(6).split(";").map((v) => v.split("="));
  const fields = Object.fromEntries(entries);
  if (entries.length !== Object.keys(fields).length || Object.keys(fields).some((k) => !["FREQ", "INTERVAL", "BYDAY", "BYMONTHDAY", "WKST", "UNTIL"].includes(k))) fail("unsupported-recurrence");
  const interval = fields.INTERVAL === undefined ? 1 : Number(fields.INTERVAL);
  let type;
  if (fields.FREQ === "DAILY" && interval === 1) type = "daily";
  else if (fields.FREQ === "WEEKLY" && [1, 2].includes(interval)) type = interval === 2 ? "biweekly" : "weekly";
  else if (fields.FREQ === "MONTHLY" && interval === 1) type = "monthly";
  else fail("unsupported-recurrence");
  if (fields.BYDAY && (fields.FREQ !== "WEEKLY" || fields.BYDAY !== DAYS[weekday(date)])) fail("multiple-or-relative-weekdays");
  if (fields.BYMONTHDAY && (type !== "monthly" || Number(fields.BYMONTHDAY) !== Number(date.slice(-2)))) fail("relative-monthday");
  let endDate = null;
  if (fields.UNTIL) {
    const value = fields.UNTIL;
    if (allDay && /^\d{8}$/.test(value)) endDate = `${value.slice(0, 4)}-${value.slice(4, 6)}-${value.slice(6)}`;
    else if (/^\d{8}T\d{6}Z$/.test(value)) {
      const end = localParts(new Date(`${value.slice(0, 4)}-${value.slice(4, 6)}-${value.slice(6, 8)}T${value.slice(9, 11)}:${value.slice(11, 13)}:${value.slice(13, 15)}Z`));
      endDate = !allDay && end.time < time ? nextDay(end.date, -1) : end.date;
    } else fail("unsupported-until");
  }
  const exceptions = Object.values(event.exdate || {}).map((value) => {
    if (allDay) return dateKey(`${value.getFullYear()}-${String(value.getMonth() + 1).padStart(2, "0")}-${String(value.getDate()).padStart(2, "0")}`);
    const parts = localParts(value);
    if (parts.time !== time) fail("exception-time-mismatch");
    return parts.date;
  });
  return recurrence({type, startDate: date, endDate, exceptions}, date);
}
function icsCanonical(text) {
  const normalized = normalizeIcs(text);
  const lines = unfoldLines(normalized);
  const startIndex = lines.indexOf("BEGIN:VEVENT");
  const endIndex = lines.indexOf("END:VEVENT", startIndex);
  if (lines.filter((l) => l === "BEGIN:VEVENT").length !== 1 || startIndex < 0 || endIndex < startIndex) fail("exception-or-multiple-events");
  const eventLines = lines.slice(startIndex + 1, endIndex);
  if (eventLines.some((line) => /^(ATTENDEE|ORGANIZER|RECURRENCE-ID)[;:]/.test(line))) fail("unsupported-invitations-or-override");
  if (eventLines.some((line) => /^(DTSTART|DTEND)[;:]/.test(line) && /T\d{4}(?!00)\d{2}Z?$/.test(line))) fail("subminute-times");
  const events = Object.values(ical.sync.parseICS(normalized)).filter((e) => e.type === "VEVENT");
  if (events.length !== 1) fail("invalid-calendar");
  const e = events[0];
  if (e.status === "CANCELLED") fail("cancelled-event");
  if (!(e.start instanceof Date) || !(e.end instanceof Date)) fail("missing-start-or-end");
  if (e.start.getUTCSeconds() || e.end.getUTCSeconds() || e.start.getUTCMilliseconds() || e.end.getUTCMilliseconds()) fail("subminute-times");
  if (e.rrule && !e.start.dateOnly && e.start.tz !== ZONE && e.start.tz !== "Europe/Berlin") fail("recurrence-timezone");
  const allDay = e.datetype === "date" || !!e.start.dateOnly;
  const key = (date) => `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
  const start = allDay ? {date: key(e.start), time: ""} : localParts(e.start);
  const end = allDay ? {date: key(e.end), time: ""} : localParts(e.end);
  if (allDay ? end.date !== nextDay(start.date) : end.date !== start.date) fail("multiday-event");
  return canonical({title: e.summary?.val ?? e.summary, date: start.date, time: start.time, endTime: end.time,
    timeMode: allDay ? "allDay" : "timed", description: htmlToText(e.description?.val ?? e.description ?? ""),
    location: e.location?.val ?? e.location ?? "", private: e.class === "PRIVATE" || e.class === "CONFIDENTIAL",
    recurrence: ruleFromIcs(eventLines, e, start.date, start.time, allDay)});
}
function googleIcs(raw) {
  const property = (key, value) => {
    if (value?.date) return `${key};VALUE=DATE:${stamp(dateKey(value.date))}`;
    if (!value?.dateTime) fail("missing-start-or-end");
    const zone = value.timeZone;
    const hasOffset = /(?:Z|[+-]\d\d:\d\d)$/.test(value.dateTime);
    const instant = !hasOffset && [ZONE, "Europe/Berlin"].includes(zone) ? exportUtils.localToUtc(value.dateTime.slice(0, 10), value.dateTime.slice(11, 16)) : new Date(value.dateTime);
    if (!Number.isFinite(instant.getTime())) fail("invalid-date-time");
    if (instant.getUTCSeconds() || instant.getUTCMilliseconds()) fail("subminute-times");
    if (zone === ZONE || zone === "Europe/Berlin") {
      const parts = localParts(instant);
      return `${key};TZID=${ZONE}:${stamp(parts.date, parts.time)}`;
    }
    return `${key}:${utcStamp(instant)}`;
  };
  return ["BEGIN:VCALENDAR", "VERSION:2.0", "BEGIN:VEVENT", "UID:external", property("DTSTART", raw.start), property("DTEND", raw.end), ...(raw.recurrence || []), "END:VEVENT", "END:VCALENDAR"].join("\r\n");
}
function graphInstant(value) {
  if (!value?.dateTime) fail("missing-start-or-end");
  const zone = value.timeZone || "UTC";
  const dt = value.dateTime.replace(/\.0+$/, "");
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:00(?:Z|[+-]\d\d:\d\d)?$/.test(dt)) fail("subminute-or-invalid-times");
  if (zone === "UTC" || zone === "Etc/UTC") return new Date(/[Z]|[+-]\d\d:\d\d$/.test(dt) ? dt : `${dt}Z`);
  if (![ZONE, "W. Europe Standard Time", "Europe/Berlin"].includes(zone)) fail("unsupported-timezone");
  return exportUtils.localToUtc(dateKey(dt.slice(0, 10)), dt.slice(11, 16));
}
function outlookCanonical(raw) {
  if (raw.isCancelled || raw["@removed"]) fail("cancelled-event");
  if (raw.type === "exception" || raw.type === "occurrence" || raw.exceptionOccurrences?.length || raw.cancelledOccurrences?.length) fail("outlook-series-exceptions");
  const start = localParts(graphInstant(raw.start));
  const end = localParts(graphInstant(raw.end));
  if (raw.isAllDay) {
    const originalZone = raw.originalStartTimeZone || raw.start.timeZone;
    if (["UTC", "Etc/UTC"].includes(originalZone)) {
      start.date = graphInstant(raw.start).toISOString().slice(0, 10);
      end.date = graphInstant(raw.end).toISOString().slice(0, 10);
    } else if (![ZONE, "W. Europe Standard Time", "Europe/Berlin"].includes(originalZone)) fail("unsupported-timezone");
    if (end.date !== nextDay(start.date)) fail("multiday-event");
  } else if (start.date !== end.date) fail("multiday-event");
  let rec = null;
  if (raw.recurrence) {
    const {pattern: p, range: r} = raw.recurrence;
    if (!p || !r || !["noEnd", "endDate"].includes(r.type)) fail("unsupported-recurrence");
    if (![ZONE, "W. Europe Standard Time", "Europe/Berlin"].includes(r.recurrenceTimeZone || raw.originalStartTimeZone)) fail("recurrence-timezone");
    let type;
    if (p.type === "daily" && p.interval === 1) type = "daily";
    else if (p.type === "weekly" && [1, 2].includes(p.interval) && p.daysOfWeek?.length === 1 && p.daysOfWeek[0] === GRAPH_DAYS[weekday(start.date)]) type = p.interval === 2 ? "biweekly" : "weekly";
    else if (p.type === "absoluteMonthly" && p.interval === 1 && p.dayOfMonth === Number(start.date.slice(-2))) type = "monthly";
    else fail("unsupported-recurrence");
    rec = recurrence({type, startDate: r.startDate, endDate: r.type === "endDate" ? r.endDate : null}, start.date);
  }
  return canonical({title: raw.subject, date: start.date, time: raw.isAllDay ? "" : start.time, endTime: raw.isAllDay ? "" : end.time,
    timeMode: raw.isAllDay ? "allDay" : "timed", recurrence: rec, description: raw.body?.contentType?.toLowerCase() === "html" ? htmlToText(raw.body.content) : raw.body?.content || "",
    location: raw.location?.displayName || "", private: ["private", "personal", "confidential"].includes(raw.sensitivity)});
}
function toCanonical(provider, raw) {
  return supported(() => {
    if (provider === "icloud") return {event: icsCanonical(raw.ics)};
    invitations(provider, raw);
    if (provider === "google") {
      if (raw.vardagSeriesHasExceptions === true) fail("series-has-exceptions");
      if (raw.status === "cancelled") fail("cancelled-event");
      if (raw.recurringEventId || raw.originalStartTime || (raw.eventType && raw.eventType !== "default")) fail("unsupported-event-type");
      const e = icsCanonical(googleIcs(raw));
      return {event: canonical({...e, title: raw.summary, description: htmlToText(raw.description || ""), location: raw.location || "", private: raw.visibility === "private" || raw.visibility === "confidential"})};
    }
    if (provider === "outlook") return {event: outlookCanonical(raw)};
    fail("unsupported-provider");
  });
}
function recurrenceLines(e) {
  if (!e.recurrence) return [];
  const r = e.recurrence;
  let rule = `RRULE:FREQ=${{daily: "DAILY", weekly: "WEEKLY", biweekly: "WEEKLY;INTERVAL=2", monthly: "MONTHLY"}[r.type]}`;
  if (r.type === "monthly") rule += `;BYMONTHDAY=${Number(e.date.slice(-2))}`;
  if (r.endDate) rule += `;UNTIL=${e.timeMode === "allDay" ? stamp(r.endDate) : utcStamp(exportUtils.localToUtc(r.endDate, "23:59")).replace(/00Z$/, "59Z")}`;
  return [rule, ...r.exceptions.map((date) => e.timeMode === "allDay" ? `EXDATE;VALUE=DATE:${stamp(date)}` : `EXDATE;TZID=${ZONE}:${stamp(date, e.time)}`)];
}
function icsPayload(e, original, operationId, old) {
  const generated = buildIcalendar({familyId: "sync", events: [{id: operationId || "event", data: {...e, visibility: e.private ? "private" : "family"}}], scope: "self", now: new Date()}).ics;
  if (!original?.ics) return {ics: generated};
  const oldLines = unfoldLines(original.ics);
  const newLines = unfoldLines(generated);
  const managed = new Set(["SUMMARY", "DTSTART", "DTEND", "DURATION", "DESCRIPTION", "LOCATION", "CLASS", "RRULE", "EXDATE", "DTSTAMP", "SEQUENCE"]);
  if (old) {
    if (old.description === e.description) managed.delete("DESCRIPTION");
    if (old.location === e.location) managed.delete("LOCATION");
    if (old.private === e.private) managed.delete("CLASS");
    if (JSON.stringify(old.recurrence) === JSON.stringify(e.recurrence)) {
      managed.delete("RRULE"); managed.delete("EXDATE");
    }
  }
  const insert = newLines.slice(newLines.indexOf("BEGIN:VEVENT") + 1, newLines.indexOf("END:VEVENT")).filter((line) => managed.has(line.split(/[;:]/, 1)[0]) && !line.startsWith("SEQUENCE:"));
  if (!oldLines.includes(`TZID:${ZONE}`)) {
    const zoneStart = newLines.indexOf("BEGIN:VTIMEZONE");
    const zoneEnd = newLines.indexOf("END:VTIMEZONE");
    if (zoneStart >= 0 && zoneEnd > zoneStart) oldLines.splice(oldLines.indexOf("BEGIN:VEVENT"), 0, ...newLines.slice(zoneStart, zoneEnd + 1));
  }
  let depth = 0;
  let sequence = 0;
  const out = [];
  for (const line of oldLines) {
    if (line === "BEGIN:VEVENT") {
      depth = 1; out.push(line); continue;
    }
    if (depth > 0 && line.startsWith("BEGIN:")) depth++;
    if (depth === 1 && line.startsWith("SEQUENCE:")) sequence = Number(line.slice(9)) || 0;
    if (depth === 1 && line === "END:VEVENT") out.push(...insert, `SEQUENCE:${sequence + 1}`);
    if (!(depth === 1 && managed.has(line.split(/[;:]/, 1)[0]))) out.push(line);
    if (depth > 0 && line.startsWith("END:")) depth--;
  }
  return {ics: out.filter((line, i) => line || i < out.length - 1).map(exportUtils.foldLine).join("\r\n") + "\r\n"};
}
function fromCanonical(provider, input, options = {}) {
  return supported(() => {
    const e = canonical(input);
    const original = options.originalRaw || options.original;
    let old = null;
    if (original) {
      const result = toCanonical(provider, original);
      if (!result.supported) fail(result.reason);
      old = result.event;
    }
    const allDay = e.timeMode === "allDay";
    if (provider === "icloud") return {payload: icsPayload(e, original, options.operationId, old)};
    if (provider === "google") {
      const time = (end) => allDay ? {date: end ? nextDay(e.date) : e.date} : {dateTime: `${e.date}T${end ? e.endTime : e.time}:00`, timeZone: ZONE};
      return {payload: {summary: e.title, description: old && e.description === old.description ? original.description || "" : e.description,
        location: e.location, start: time(false), end: time(true),
        recurrence: old && JSON.stringify(e.recurrence) === JSON.stringify(old.recurrence) ? original.recurrence || [] : recurrenceLines(e),
        visibility: old && e.private === old.private ? original.visibility || "default" : e.private ? "private" : "default"}};
    }
    if (provider === "outlook") {
      if (e.recurrence?.exceptions.length) fail("outlook-exceptions-require-instance-writes");
      let r = null;
      if (e.recurrence) {
        const rec = e.recurrence;
        const pattern = {type: rec.type === "monthly" ? "absoluteMonthly" : rec.type === "biweekly" ? "weekly" : rec.type, interval: rec.type === "biweekly" ? 2 : 1};
        if (["weekly", "biweekly"].includes(rec.type)) Object.assign(pattern, {daysOfWeek: [GRAPH_DAYS[weekday(e.date)]], firstDayOfWeek: "monday"});
        if (rec.type === "monthly") pattern.dayOfMonth = Number(e.date.slice(-2));
        r = {pattern, range: {type: rec.endDate ? "endDate" : "noEnd", startDate: e.date, ...(rec.endDate ? {endDate: rec.endDate} : {}), recurrenceTimeZone: ZONE}};
      }
      return {payload: {subject: e.title, body: old && e.description === old.description ? original.body || {contentType: "text", content: ""} : {contentType: "text", content: e.description},
        location: {...original?.location, displayName: e.location}, isAllDay: allDay,
        start: {dateTime: `${e.date}T${allDay ? "00:00" : e.time}:00`, timeZone: ZONE},
        end: {dateTime: `${allDay ? nextDay(e.date) : e.date}T${allDay ? "00:00" : e.endTime}:00`, timeZone: ZONE},
        recurrence: old && JSON.stringify(e.recurrence) === JSON.stringify(old.recurrence) ? original.recurrence || null : r,
        sensitivity: old && e.private === old.private ? original.sensitivity || "normal" : e.private ? "private" : "normal"}};
    }
    fail("unsupported-provider");
  });
}
module.exports = {toCanonical, fromCanonical, fingerprint, canonical, _test: {icsCanonical, recurrenceLines}};
