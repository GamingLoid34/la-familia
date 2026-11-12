const test = require("node:test");
const assert = require("node:assert");
const {_test} = require("../ics_text_import");

// Fast "idag" så testet inte flagnar med tiden: 2026-09-16.
const TODAY = {y: 2026, m: 9, d: 16};

const FIXTURE_ICS = [
  "BEGIN:VCALENDAR",
  "VERSION:2.0",
  "BEGIN:VEVENT",
  "UID:past-1@example.com",
  "SUMMARY:Gammal lektion (i går)",
  "DTSTART:20260915T090000",
  "DTEND:20260915T100000",
  "END:VEVENT",
  "BEGIN:VEVENT",
  "UID:today-1@example.com",
  "SUMMARY:Matematik",
  "DTSTART:20260916T080000",
  "DTEND:20260916T085000",
  "LOCATION:Sal 4",
  "DESCRIPTION:Ta med miniräknare",
  "END:VEVENT",
  "BEGIN:VEVENT",
  "UID:future-1@example.com",
  "SUMMARY:Idrott",
  "DTSTART:20260918T130000",
  "DURATION:PT1H",
  "X-SPORTADMIN-GROUP:Innebandy",
  "END:VEVENT",
  "BEGIN:VEVENT",
  "UID:no-title@example.com",
  "SUMMARY:",
  "DTSTART:20260919T100000",
  "END:VEVENT",
  "BEGIN:VEVENT",
  "UID:allday@example.com",
  "SUMMARY:Studiedag",
  "DTSTART;VALUE=DATE:20260920",
  "END:VEVENT",
  "END:VCALENDAR",
].join("\r\n");

test("unfoldLines vecklar upp fortsättningsrader", () => {
  // RFC 5545: fortsättningsradens EGET inledande tecken (space/tab) tas
  // bort vid ihopslagning — vill man ha ett mellanslag i resultatet
  // måste det ligga kvar EFTER det borttagna prefixet, som här: "  f...".
  const raw =
    "BEGIN:VEVENT\r\nSUMMARY:Lång rad som\r\n  fortsätter här\r\nEND:VEVENT";
  const lines = _test.unfoldLines(raw);
  assert.strictEqual(lines.length, 3);
  assert.strictEqual(lines[1], "SUMMARY:Lång rad som fortsätter här");
});

test("parseDtstart tolkar naiv lokal tid, ingen tz-konvertering", () => {
  const expected = {y: 2026, m: 9, d: 20, h: 9, min: 0};
  assert.deepStrictEqual(_test.parseDtstart("20260920T090000"), expected);
  assert.deepStrictEqual(_test.parseDtstart("20260920T090000Z"), expected);
  assert.deepStrictEqual(
      _test.parseDtstart("20260920"),
      {y: 2026, m: 9, d: 20, h: 0, min: 0},
  );
  assert.strictEqual(_test.parseDtstart(""), null);
  assert.strictEqual(_test.parseDtstart(null), null);
});

test("parseIcsDuration tolkar ISO-8601-varaktighet till minuter", () => {
  assert.strictEqual(_test.parseIcsDuration("PT1H30M"), 90);
  assert.strictEqual(_test.parseIcsDuration("P1D"), 1440);
  assert.strictEqual(_test.parseIcsDuration("PT45M"), 45);
  assert.strictEqual(_test.parseIcsDuration("ogiltigt"), null);
  assert.strictEqual(_test.parseIcsDuration(""), null);
});

test("icsEndTimeHm: DURATION före DTEND, kräver sluttid efter start", () => {
  const start = _test.parseDtstart("20260916T090000");
  const withEnd = {DTEND: "20260916T103000"};
  const withBoth = {DURATION: "PT1H30M", DTEND: "20260916T170000"};
  const beforeStart = {DTEND: "20260916T080000"};
  assert.strictEqual(_test.icsEndTimeHm(withEnd, start), "10:30");
  assert.strictEqual(_test.icsEndTimeHm(withBoth, start), "10:30");
  assert.strictEqual(_test.icsEndTimeHm(beforeStart, start), null);
  assert.strictEqual(_test.icsEndTimeHm({}, start), null);
});

test("sanitizeIcsBody avkodar ICS-escape och tar bort HTML", () => {
  assert.strictEqual(
      _test.sanitizeIcsBody("Rad ett\\nRad två"),
      "Rad ett\nRad två",
  );
  assert.strictEqual(
      _test.sanitizeIcsBody("<p>Hej<br>då</p>"),
      "Hej\ndå",
  );
  assert.strictEqual(_test.sanitizeIcsBody(""), "");
});

test("icsExtendedProps: bara X-fält, trunkerar långa värden", () => {
  const ev = {"X-FOO": "bar", "SUMMARY": "ignoreras", "X-EMPTY": ""};
  assert.deepStrictEqual(_test.icsExtendedProps(ev), {"X-FOO": "bar"});
});

test("parseIcsTextToEventDrafts: filtrerar förflutet/tom titel/heldag", () => {
  const drafts = _test.parseIcsTextToEventDrafts(
      FIXTURE_ICS,
      {todayParts: TODAY},
  );

  // Gammal lektion (igår) bortfiltrerad, tom SUMMARY bortfiltrerad.
  assert.strictEqual(drafts.length, 3);

  const titles = drafts.map((d) => d.title);
  assert.deepStrictEqual(titles, ["Matematik", "Idrott", "Studiedag"]);

  const matte = drafts[0];
  assert.strictEqual(matte.date, "2026-09-16");
  assert.strictEqual(matte.time, "08:00");
  assert.strictEqual(matte.endTime, "08:50");
  assert.strictEqual(matte.location, "Sal 4");
  assert.strictEqual(matte.calendarDescription, "Ta med miniräknare");

  const idrott = drafts[1];
  assert.strictEqual(idrott.date, "2026-09-18");
  assert.strictEqual(idrott.time, "13:00");
  assert.strictEqual(idrott.endTime, "14:00");
  assert.deepStrictEqual(
      idrott.calendarExtendedProps,
      {"X-SPORTADMIN-GROUP": "Innebandy"},
  );

  // Heldagshändelse (VALUE=DATE, midnatt) -> tom starttid, ingen sluttid.
  const studiedag = drafts[2];
  assert.strictEqual(studiedag.date, "2026-09-20");
  assert.strictEqual(studiedag.time, "");
  assert.strictEqual(studiedag.endTime, undefined);
});

test("parseIcsTextToEventDrafts: dagens datum räknas som framtida", () => {
  const icsToday = [
    "BEGIN:VCALENDAR",
    "BEGIN:VEVENT",
    "SUMMARY:Precis idag, sen kväll",
    "DTSTART:20260916T235900",
    "END:VEVENT",
    "END:VCALENDAR",
  ].join("\n");
  const drafts = _test.parseIcsTextToEventDrafts(
      icsToday,
      {todayParts: TODAY},
  );
  assert.strictEqual(drafts.length, 1);
});

test("parseIcsTextToEventDrafts: beskrivning trunkeras vid 15000", () => {
  const longDesc = "x".repeat(15005);
  const ics = [
    "BEGIN:VCALENDAR",
    "BEGIN:VEVENT",
    "SUMMARY:Lång beskrivning",
    "DTSTART:20260916T100000",
    `DESCRIPTION:${longDesc}`,
    "END:VEVENT",
    "END:VCALENDAR",
  ].join("\n");
  const drafts = _test.parseIcsTextToEventDrafts(ics, {todayParts: TODAY});
  assert.strictEqual(drafts.length, 1);
  // 15000 tecken + "…"
  assert.strictEqual(drafts[0].calendarDescription.length, 15001);
  assert.ok(drafts[0].calendarDescription.endsWith("…"));
});

test("parseIcsTextToEventDrafts: tak på 200 händelser", () => {
  const lines = ["BEGIN:VCALENDAR"];
  for (let i = 0; i < 250; i++) {
    const day = String(17 + (i % 10)).padStart(2, "0");
    lines.push("BEGIN:VEVENT");
    lines.push(`SUMMARY:Händelse ${i}`);
    lines.push(`DTSTART:202609${day}T090000`);
    lines.push("END:VEVENT");
  }
  lines.push("END:VCALENDAR");
  const drafts = _test.parseIcsTextToEventDrafts(
      lines.join("\n"),
      {todayParts: TODAY},
  );
  assert.strictEqual(drafts.length, 200);
});
