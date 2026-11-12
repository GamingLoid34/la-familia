/* eslint-disable max-len, require-jsdoc */
const ical = require("node-ical");
const {HttpsError} = require("firebase-functions/v2/https");
const MAX_EVENTS = 400;
const DAY_MS = 86400000;
const formatter = new Intl.DateTimeFormat("sv-SE", {
  timeZone: "Europe/Stockholm", year: "numeric", month: "2-digit", day: "2-digit",
  hour: "2-digit", minute: "2-digit", hourCycle: "h23",
});

function localParts(date) {
  const p = Object.fromEntries(formatter.formatToParts(date).map((v) => [v.type, v.value]));
  return {date: `${p.year}-${p.month}-${p.day}`, time: `${p.hour}:${p.minute}`};
}
function addDays(key, days) {
  return new Date(Date.parse(`${key}T12:00:00Z`) + days * DAY_MS).toISOString().slice(0, 10);
}
function dateOnlyKey(date) {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
}
function importWindow(data = {}, now = new Date()) {
  const fromDate = data.fromDate === undefined ? localParts(now).date : data.fromDate;
  const validateKey = (key) => {
    if (typeof key !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(key) ||
        !Number.isFinite(Date.parse(`${key}T12:00:00Z`)) || addDays(key, 0) !== key) {
      throw new HttpsError("invalid-argument", "Välj ett giltigt startdatum och slutdatum.");
    }
  };
  validateKey(fromDate);
  const toDate = data.toDate === undefined ? addDays(fromDate, 365) : data.toDate;
  validateKey(toDate);
  if (toDate < fromDate || Date.parse(toDate) - Date.parse(fromDate) > 365 * DAY_MS) {
    throw new HttpsError("invalid-argument", "Importperioden får vara högst 366 dagar, inklusive slutdagen.");
  }
  return {fromDate, toDate, timeZone: "Europe/Stockholm"};
}
function unfoldLines(text) {
  return text.replace(/^\uFEFF/, "").replace(/\r\n?/g, "\n").replace(/\n[ \t]/g, "").split("\n");
}
function invalid(message) {
  throw new HttpsError("invalid-argument", message);
}
function normalizeIcs(text) {
  const lines = unfoldLines(text);
  if (!lines.includes("BEGIN:VCALENDAR") || !lines.includes("END:VCALENDAR")) {
    invalid("Filen innehåller ingen giltig ICS-kalender.");
  }
  let depth = 0;
  let eventCount = 0;
  for (const line of lines) {
    if (line === "BEGIN:VEVENT") {
      depth++; eventCount++;
    }
    if (line === "END:VEVENT") depth--;
    if (depth < 0 || depth > 1) invalid("Kalenderfilens händelser är ofullständiga.");
    if (depth > 0 && (/^(RDATE|EXRULE)[;:]/i.test(line) || /^RECURRENCE-ID[^:]*;RANGE=/i.test(line))) {
      invalid("Filen använder RDATE, EXRULE eller ändringar av kommande tillfällen som ännu inte kan importeras säkert. Exportera tillfällena som separata händelser.");
    }
    if (depth > 0 && /^RRULE:/i.test(line) && (/(?:^|;)FREQ=(?:SECONDLY|MINUTELY|HOURLY)(?:;|$)/i.test(line.slice(6)) ||
        /(?:^|;)BY(?:SECOND|MINUTE|HOUR)=/i.test(line.slice(6)))) {
      invalid("Kalendern innehåller för täta eller avancerade tidsupprepningar. Exportera tillfällena som separata händelser.");
    }
  }
  if (depth !== 0 || eventCount > 10000) invalid("Kalenderfilen är ofullständig eller innehåller för många grundhändelser (max 10 000).");
  // Floating DATE-TIME values mean Swedish local time, even when the server runs in UTC.
  let inEvent = false;
  const normalized = lines.map((line) => {
    if (line === "BEGIN:VEVENT") inEvent = true;
    if (line === "END:VEVENT") inEvent = false;
    if (!inEvent) return line;
    return line.replace(
        /^(DTSTART|DTEND|RECURRENCE-ID|EXDATE)(;VALUE=DATE-TIME)?:([0-9]{8}T[0-9]{6}(?:,[0-9]{8}T[0-9]{6})*)$/i,
        "$1;TZID=Europe/Stockholm:$3",
    );
  }).join("\r\n");
  // node-ical/rrule-temporal currently drifts an implicit 31st to the 30th.
  // RFC 5545 inherits DTSTART's day of month and skips months without that day.
  return normalized.replace(/BEGIN:VEVENT\r\n[\s\S]*?\r\nEND:VEVENT/g, (block) => {
    const start = /^DTSTART(?:;[^:]*)?:(\d{4})(\d{2})(\d{2})/m.exec(block);
    if (!start) return block;
    return block.replace(/^RRULE:([^\r\n]+)/gm, (line, rule) =>
      /(?:^|;)FREQ=MONTHLY(?:;|$)/.test(rule) && !/(?:^|;)BY(?:MONTHDAY|DAY|SETPOS)=/.test(rule) ? `${line};BYMONTHDAY=${Number(start[3])}` : line);
  });
}
function validateDate(date) {
  if (!(date instanceof Date) || !Number.isFinite(date.getTime())) invalid("En händelse har ett ogiltigt datum. Ingen del av filen importerades.");
  if (date.tz && !/^[+-]\d\d:\d\d$/.test(date.tz)) {
    try {
      new Intl.DateTimeFormat("sv-SE", {timeZone: date.tz});
    } catch (_) {
      invalid("En händelse använder en tidszon som inte kan tolkas säkert. Exportera kalendern med en standardtidszon, till exempel Europe/Stockholm.");
    }
  }
}
function parseIcsTextToEventDrafts(text, window, htmlToText = (v) => v) {
  const normalized = normalizeIcs(text);
  let events;
  try {
    events = ical.sync.parseICS(normalized);
  } catch (_) {
    invalid("Kalenderfilen kunde inte tolkas. Kontrollera att det är en komplett ICS-export.");
  }
  const extensionKeys = [...new Set(unfoldLines(text).map((line) => /^(X-[^;:]+)[;:]/.exec(line)?.[1]).filter(Boolean))];
  const rows = [];
  const seen = new Set();
  const warnings = new Set();
  const from = new Date(`${window.fromDate}T00:00:00Z`);
  from.setUTCDate(from.getUTCDate() - 2);
  const to = new Date(`${window.toDate}T23:59:59Z`);
  to.setUTCDate(to.getUTCDate() + 2);
  const clipped = (value, max) => {
    const str = String(value?.val ?? value ?? "");
    if (str.length > max) warnings.add("Långa textfält kortas i kalenderns visning. Hela originalfilen sparas.");
    return str.length > max ? `${str.slice(0, max)}…` : str;
  };
  for (const event of Object.values(events)) {
    if (event.type !== "VEVENT" || event.status === "CANCELLED") continue;
    validateDate(event.start);
    if (event.end) validateDate(event.end);
    if (event.end && event.end < event.start) invalid("En händelse slutar före den börjar. Ingen del av filen importerades.");
    if (!event.uid) invalid("En händelse saknar UID. Exportera kalendern på nytt innan den importeras.");
    for (const override of Object.values(event.recurrences || {})) {
      if (override.status !== "CANCELLED") validateDate(override.start);
      if (override.end) validateDate(override.end);
      if (override.start && override.end && override.end < override.start) invalid("Ett flyttat tillfälle slutar före det börjar. Ingenting har importerats.");
    }
    let instances;
    try {
      instances = ical.expandRecurringEvent(event, {from, to, expandOngoing: true});
    } catch (_) {
      invalid("En upprepning i kalendern kunde inte tolkas säkert. Ingen del av filen importerades.");
    }
    for (const instance of instances) {
      const source = instance.event;
      if (source.status === "CANCELLED") continue;
      const start = instance.isFullDay ? {date: dateOnlyKey(instance.start), time: ""} : localParts(instance.start);
      const end = instance.isFullDay ? {date: dateOnlyKey(instance.end), time: ""} : localParts(instance.end);
      if (start.date > window.toDate || end.date < window.fromDate) continue;
      const privacy = String(source.class?.val ?? source.class ?? event.class?.val ?? event.class ?? "PUBLIC").toUpperCase();
      if (privacy !== "PUBLIC") {
        invalid("Filen innehåller privata eller konfidentiella aktiviteter. Den här filimporten delar innehållet med familjen och kan därför inte importera dem säkert. Exportera enbart de delade aktiviteterna från källkalendern. Ingenting har importerats.");
      }
      if (!instance.isFullDay && start.date !== end.date) {
        invalid("Filen innehåller en tidsatt aktivitet som går över midnatt. Vardag kan ännu inte importera nattpass säkert. Välj en period utan nattpass eller dela upp dem i källkalendern. Ingenting har importerats.");
      }
      const title = clipped(source.summary ?? event.summary, 1000).trim() || "Namnlös aktivitet";
      const original = source.recurrenceid || instance.start;
      const instanceKey = `${event.uid}|${original.toISOString()}`;
      const base = {
        title, icsInstanceKey: instanceKey,
        icsOriginalStart: instance.start.toISOString(), icsOriginalEnd: instance.end.toISOString(),
        icsAllDay: instance.isFullDay,
      };
      for (const [key, property, max] of [["calendarDescription", "description", 15000], ["location", "location", 2000], ["calendarUrl", "url", 2000]]) {
        const value = clipped(source[property] ?? event[property], max);
        if (value) base[key] = property === "url" ? value : htmlToText(value);
      }
      const extras = {};
      for (const key of extensionKeys) {
        const value = source[key.slice(2)] ?? event[key.slice(2)];
        if (value !== undefined) extras[key] = htmlToText(clipped(value, 2000));
      }
      if (Object.keys(extras).length) base.calendarExtendedProps = extras;
      // Current clients display one calendar day per document. Split a multi-day
      // all-day occurrence without mistaking timed midnight for all-day.
      let day = start.date < window.fromDate ? window.fromDate : start.date;
      const lastDay = (instance.isFullDay || end.time === "00:00") && end.date > start.date ? addDays(end.date, -1) : end.date;
      while (day <= lastDay && day <= window.toDate) {
        const icsKey = `${instanceKey}|day:${day}`;
        if (!seen.has(icsKey)) {
          seen.add(icsKey);
          const row = {...base, icsKey, date: day, time: instance.isFullDay ? "" : day === start.date ? start.time : "00:00"};
          if (!instance.isFullDay && instance.end > instance.start) row.endTime = end.time;
          rows.push(row);
          if (rows.length > MAX_EVENTS) invalid(`Perioden innehåller fler än ${MAX_EVENTS} kalenderposter. Välj ett kortare datumintervall. Ingenting har importerats.`);
        }
        day = addDays(day, 1);
      }
    }
  }
  return {drafts: rows.sort((a, b) => a.date.localeCompare(b.date) || a.time.localeCompare(b.time) || a.icsKey.localeCompare(b.icsKey)), warnings: [...warnings]};
}
module.exports = {MAX_EVENTS, importWindow, unfoldLines, parseIcsTextToEventDrafts, normalizeIcs, localParts};
