/* eslint-disable max-len, require-jsdoc */
const test = require("node:test");
const assert = require("node:assert/strict");
const ical = require("node-ical");
const {buildIcalendar, CalendarExportError, _test: format} = require("../calendar_ical");
const {buildCalendarExport, MAX_DOCUMENTS, MAX_RESPONSE_BYTES} = require("../calendar_export")._test;
const NOW = new Date("2026-10-30T10:00:00Z");

function activity(id, data = {}) {
  return {id, data: {familyId: "f", date: "2026-10-30", time: "09:00", title: id, ...data}};
}

function exportEvents(events, extra = {}) {
  return buildIcalendar({familyId: "f", scope: "family", now: NOW, events, ...extra});
}

function parsedEvents(ics) {
  return Object.values(ical.sync.parseICS(ics)).filter((event) => event.type === "VEVENT");
}

function expanded(event, from = "2026-10-01", to = "2026-12-31") {
  return ical.expandRecurringEvent(event, {from: new Date(`${from}T00:00:00Z`), to: new Date(`${to}T23:59:59Z`)});
}

test("export uses CRLF, folds at 75 UTF-8 octets and prevents calendar injection", () => {
  const title = "🌸 Åäö ".repeat(50) + ",;\\\r\nBEGIN:VEVENT\nUID:injected";
  const description = "Rad 1\nRad 2; komma, slash\\";
  const output = exportEvents([activity("a", {title, description, location: "Hallen\nEND:VEVENT"})]);
  assert.ok(output.ics.endsWith("\r\n"));
  assert.equal(output.ics.replaceAll("\r\n", "").includes("\n"), false);
  assert.ok(output.ics.split("\r\n").every((line) => Buffer.byteLength(line) <= 75));
  const parsed = parsedEvents(output.ics);
  assert.equal(parsed.length, 1);
  assert.equal(parsed[0].summary, title.replaceAll("\r\n", "\n"));
  assert.equal(parsed[0].description, description);
  assert.equal(parsed[0].location, "Hallen\nEND:VEVENT");
});

test("UID remains stable after edits and between personal/family exports; families and collections cannot collide", () => {
  const a = parsedEvents(exportEvents([activity("a")]).ics)[0];
  const b = parsedEvents(exportEvents([activity("a", {title: "Ändrad", date: "2026-11-01"})], {scope: "personal"}).ics)[0];
  assert.equal(a.uid, b.uid);
  assert.notEqual(format.uidFor("f", "planner_events", "a"), format.uidFor("other", "planner_events", "a"));
  assert.notEqual(format.uidFor("f", "planner_events", "a"), format.uidFor("f", "work_shifts", "a"));
});

test("weekly 07:30 stays 07:30 across autumn DST; end date is inclusive and EXDATE is respected", () => {
  const output = exportEvents([activity("series", {date: "2026-10-19", time: "07:30", endTime: "08:00", recurrence: {type: "weekly", startDate: "2026-10-19", endDate: "2026-11-09", exceptions: ["2026-11-02"]}})]);
  const event = parsedEvents(output.ics)[0];
  assert.deepEqual(expanded(event).map((item) => item.start.toISOString()), ["2026-10-19T05:30:00.000Z", "2026-10-26T06:30:00.000Z", "2026-11-09T06:30:00.000Z"]);
  assert.match(output.ics, /BEGIN:VTIMEZONE/);
  assert.match(output.ics, /UNTIL=20261109T225959Z/);
});

test("daily, biweekly and monthly rules preserve their occurrence sets", () => {
  const cases = [
    ["daily", "2026-10-29", "2026-11-02", ["2026-10-29", "2026-10-30", "2026-10-31", "2026-11-01", "2026-11-02"]],
    ["biweekly", "2026-10-19", "2026-11-17", ["2026-10-19", "2026-11-02", "2026-11-16"]],
    ["monthly", "2026-10-31", "2026-12-31", ["2026-10-31", "2026-12-31"]],
  ];
  for (const [type, startDate, endDate, expected] of cases) {
    const event = parsedEvents(exportEvents([activity(type, {date: startDate, time: "07:30", recurrence: {type, startDate, endDate}})]).ics)[0];
    assert.deepEqual(expanded(event).map((item) => item.start.toISOString().slice(0, 10)), expected, type);
  }
});

test("moving an occurrence preserves UID and RECURRENCE-ID without duplicating or suppressing the move", () => {
  const output = exportEvents([
    activity("series", {date: "2026-10-19", time: "07:30", recurrence: {type: "weekly", startDate: "2026-10-19", endDate: "2026-11-02", exceptions: ["2026-10-26", "2026-11-02"]}}),
    activity("moved", {date: "2026-12-02", time: "11:00", originalSeriesId: "series", originalOccurrenceDate: "2026-10-26"}),
  ]);
  assert.equal(output.eventCount, 2);
  const events = parsedEvents(output.ics);
  assert.equal(events.length, 1, "parser groups override into its original series");
  assert.equal(events[0].recurrences["2026-10-26"].recurrenceid.toISOString(), "2026-10-26T06:30:00.000Z");
  assert.deepEqual(expanded(events[0]).map((item) => item.start.toISOString()), ["2026-10-19T05:30:00.000Z", "2026-12-02T10:00:00.000Z"]);
  assert.equal(expanded(events[0], "2026-12-01", "2026-12-03").length, 1, "a move is found even outside the original series interval");
  assert.equal(events[0].exdate["2026-10-26"], undefined);
  assert.ok(events[0].exdate["2026-11-02"]);
});

test("all-day recurrence and moved all-day occurrence use DATE values and exclusive end", () => {
  const output = exportEvents([
    activity("s", {time: "", timeMode: "allDay", date: "2026-10-30", recurrence: {type: "daily", startDate: "2026-10-30", endDate: "2026-10-31", exceptions: ["2026-10-31"]}}),
    activity("m", {date: "2026-11-03", time: "", timeMode: "allDay", originalSeriesId: "s", originalOccurrenceDate: "2026-10-31"}),
  ]);
  const event = parsedEvents(output.ics)[0];
  assert.equal(event.datetype, "date");
  assert.equal(event.end.toISOString().slice(0, 10), "2026-10-31");
  assert.match(output.ics, /RECURRENCE-ID;VALUE=DATE:20261031/);
  assert.match(output.ics, /RRULE:FREQ=DAILY;UNTIL=20261031/);
  assert.deepEqual(expanded(event).map((item) => item.start.toISOString().slice(0, 10)), ["2026-10-30", "2026-11-03"]);
});

test("night work shifts finish on next day and keep actual DST duration", () => {
  const output = exportEvents([], {shifts: [{id: "w", data: {who: "Oscar", date: "2026-10-24", startTime: "22:00", endTime: "06:00"}}]});
  const event = parsedEvents(output.ics)[0];
  assert.equal(event.start.toISOString(), "2026-10-24T20:00:00.000Z");
  assert.equal(event.end.toISOString(), "2026-10-25T05:00:00.000Z");
  assert.equal(event.summary, "Arbetspass · Oscar");
});

test("packlist and preparation text preserve checked state and moved completed dates", () => {
  const output = exportEvents([activity("a", {checklist: [{item: "Gympapåse", isDone: true}, {item: "Vatten", isDone: false}], lessonPrep: {text: "Läs sidan 12", doneDates: ["2026-10-30"]}, transport: {lamnar: "Oscar", hamtar: "Noomi"}})]);
  const desc = parsedEvents(output.ics)[0].description;
  assert.match(desc, /\[x\] Gympapåse/);
  assert.match(desc, /\[ \] Vatten/);
  assert.match(desc, /Förberedelse klar: 2026-10-30/);
  assert.match(desc, /Hämtar: Noomi/);
  assert.ok(output.warnings.some((w) => w.includes("Avbockningar")));
});

test("unscheduled events and undecided times generate visible warnings; detached events remain usable", () => {
  const output = exportEvents([activity("undated", {date: ""}), activity("undecided", {time: "", timeMode: "undecided"}), activity("m", {originalSeriesId: "unselected", originalOccurrenceDate: "2026-10-29"})]);
  assert.equal(output.eventCount, 2);
  assert.equal(output.warnings.length, 3);
  assert.match(parsedEvents(output.ics).find((e) => e.summary === "undecided").description, /Tid ej bestämd/);
});

test("unknown recurrence, impossible dates and DST-gap starts fail explicitly rather than losing data", () => {
  const cases = [
    {recurrence: {type: "yearly"}},
    {recurrence: {type: "weekly", startDate: "2026-10-30", byDay: "MO"}},
    {isRecurring: true},
    {date: "2026-02-30"},
    {date: "2026-03-29", time: "02:30"},
    {time: "09:00\r\nEND:VEVENT"},
    {recurrence: {type: "daily", startDate: "2026-10-30", endDate: "2026-10-01"}},
  ];
  for (const data of cases) assert.throws(() => exportEvents([activity("bad", data)]), CalendarExportError);
});

test("malformed, duplicate and cross-privacy move links fail explicitly", () => {
  const series = activity("s", {date: "2026-10-30", recurrence: {type: "daily", startDate: "2026-10-30", exceptions: ["2026-10-31"]}});
  const moved = activity("m", {originalSeriesId: "s", originalOccurrenceDate: "2026-10-31"});
  assert.throws(() => exportEvents([series, moved, {...moved, id: "another"}]), /samma ursprungsdatum/);
  assert.throws(() => exportEvents([series, {...moved, data: {...moved.data, visibility: "private"}}]), /ogiltig serielänk/);
  assert.throws(() => exportEvents([activity("m", {originalSeriesId: "s"})]), /ofullständig serielänk/);
});

function fakeDb(seed, options = {}) {
  const reads = [];
  const makeRef = (path, filters = [], limit = Infinity) => ({
    path, filters, max: limit,
    doc: (id) => makeRef(`${path}/${id}`),
    collection: (name) => makeRef(`${path}/${name}`),
    where: (field, op, value) => makeRef(path, [...filters, [field, value]], limit),
    limit: (max) => makeRef(path, filters, max),
  });
  const snap = (path, data) => ({id: path.split("/").at(-1), exists: data != null, data: () => data});
  const read = async (ref) => {
    reads.push(ref.path);
    if (ref.path.split("/").length % 2 === 0) return snap(ref.path, seed[ref.path]);
    const docs = Object.entries(seed).filter(([path, data]) => path.startsWith(`${ref.path}/`) && path.split("/").length === ref.path.split("/").length + 1 && (options.ignoreFamilyFilter || ref.filters.every(([key, value]) => data[key] === value)))
        .slice(0, ref.max).map(([path, data]) => snap(path, data));
    return {docs, size: options.querySize ?? docs.length};
  };
  return {reads, collection: (name) => makeRef(name), runTransaction: async (callback, settings) => {
    assert.deepEqual(settings, {readOnly: true});
    return callback({get: read, getAll: async (...refs) => Promise.all(refs.map(read))});
  }};
}

function fixture() {
  const marker = (owner) => ({visibility: "private", privateOwnerUid: owner, title: "Privat", persons: [owner], personUids: [owner]});
  const detail = (owner, title) => ({ownerUid: owner, familyId: "f", title, checklist: [{item: "Hemlig packning", isDone: true}]});
  return {
    "users/p": {familyId: "f", role: "parent", name: "Parent"},
    "users/y": {familyId: "f", role: "youth", name: "Youth"},
    "users/c": {familyId: "f", role: "child", name: "Child"},
    "families/f": {},
    "families/other": {},
    "planner_events/shared": activity("shared", {persons: []}).data,
    "planner_events/parent": activity("parent", {personUids: ["p"]}).data,
    "planner_events/youth": activity("youth", {personUids: ["y"], persons: ["Parent"]}).data,
    "planner_events/legacy": activity("legacy", {persons: ["Parent"]}).data,
    "planner_events/private-parent": activity("private-parent", marker("p")).data,
    "planner_events/private-youth": activity("private-youth", marker("y")).data,
    "planner_events/other": activity("CROSS-FAMILY", {familyId: "other"}).data,
    "planner_events/pending": activity("pending", {isPending: true}).data,
    "planner_events/imported": activity("imported", {source: "calendar", calendarImportId: "i"}).data,
    "work_shifts/parent": {familyId: "f", date: "2026-10-30", who: "Parent", whoUid: "p", startTime: "08:00", endTime: "16:00"},
    "work_shifts/youth": {familyId: "f", date: "2026-10-30", who: "Youth", whoUid: "y", startTime: "08:00", endTime: "16:00"},
    "work_shifts/other": {familyId: "other", date: "2026-10-30", who: "Parent", whoUid: "p", startTime: "08:00", endTime: "16:00"},
    "private_activities/p/events/private-parent": detail("p", "Parent secret"),
    "private_activities/y/events/private-youth": detail("y", "Youth secret"),
  };
}

test("family export contains family activities/work but no private markers, private details, foreign family, pending or imported events", async () => {
  const db = fakeDb(fixture(), {ignoreFamilyFilter: true});
  const output = await buildCalendarExport({db, uid: "p", data: {scope: "family"}, now: NOW});
  assert.deepEqual(parsedEvents(output.ics).map((e) => e.summary).sort(), ["Arbetspass · Parent", "Arbetspass · Youth", "legacy", "parent", "shared", "youth"].sort());
  assert.equal(output.eventCount, 6);
  assert.equal(db.reads.some((path) => path.startsWith("private_activities")), false);
  assert.doesNotMatch(output.ics, /Parent secret|Youth secret|Privat|CROSS-FAMILY|pending|imported/);
  assert.equal(output.warnings.length, 2);
});

test("personal export includes own and common, respects UID over name, and never reads child's private details for parent", async () => {
  const db = fakeDb(fixture());
  const output = await buildCalendarExport({db, uid: "p", data: {scope: "personal"}, now: NOW});
  assert.deepEqual(parsedEvents(output.ics).map((e) => e.summary).sort(), ["Arbetspass · Parent", "Parent secret", "legacy", "parent", "shared"].sort());
  assert.deepEqual(db.reads.filter((path) => path.startsWith("private_activities")), ["private_activities/p/events/private-parent"]);
  assert.match(output.ics, /CLASS:PRIVATE/);
  assert.doesNotMatch(output.ics, /Youth secret/);
});

test("youth can export their own private events but cannot export whole family or parent private details", async () => {
  const db = fakeDb(fixture());
  const output = await buildCalendarExport({db, uid: "y", data: {scope: "personal"}, now: NOW});
  assert.deepEqual(parsedEvents(output.ics).map((e) => e.summary).sort(), ["Arbetspass · Youth", "Youth secret", "shared", "youth"].sort());
  assert.equal(db.reads.some((path) => path.startsWith("private_activities/p")), false);
  await assert.rejects(buildCalendarExport({db, uid: "y", data: {scope: "family"}}), {code: "permission-denied"});
  await assert.rejects(buildCalendarExport({db, uid: "c", data: {scope: "family"}}), {code: "permission-denied"});
});

test("auth, trusted profile and family membership cannot be overridden by request", async () => {
  const db = fakeDb(fixture());
  await assert.rejects(buildCalendarExport({db, data: {scope: "personal"}}), {code: "unauthenticated"});
  await assert.rejects(buildCalendarExport({db, uid: "missing", data: {scope: "personal"}}), {code: "permission-denied"});
  await assert.rejects(buildCalendarExport({db, uid: "p", data: {scope: "family", familyId: "other"}}), {code: "invalid-argument"});
  await assert.rejects(buildCalendarExport({db, uid: "p", data: {scope: "personal", includeImported: "true"}}), {code: "invalid-argument"});
  const seed = fixture();
  delete seed["families/f"];
  await assert.rejects(buildCalendarExport({db: fakeDb(seed), uid: "p", data: {scope: "personal"}}), {code: "failed-precondition"});
});

test("missing or foreign-family private detail stops export; private overlays cannot replace trusted timing or membership", async () => {
  for (const detail of [null, {title: "Wrong", ownerUid: "y", familyId: "f"}, {title: "Wrong", ownerUid: "p", familyId: "other"}]) {
    const seed = fixture();
    if (detail) seed["private_activities/p/events/private-parent"] = detail;
    else delete seed["private_activities/p/events/private-parent"];
    await assert.rejects(buildCalendarExport({db: fakeDb(seed), uid: "p", data: {scope: "personal"}}), {code: "failed-precondition"});
  }
  const seed = fixture();
  Object.assign(seed["private_activities/p/events/private-parent"], {date: "2040-01-01", time: "23:00", personUids: ["y"], description: "Owner-only description", location: "Owner-only place"});
  const output = await buildCalendarExport({db: fakeDb(seed), uid: "p", data: {scope: "personal"}, now: NOW});
  const privateEvent = parsedEvents(output.ics).find((e) => e.summary === "Parent secret");
  assert.equal(privateEvent.start.toISOString(), "2026-10-30T08:00:00.000Z");
  assert.doesNotMatch(output.ics, /20400101/);
  assert.match(privateEvent.description, /Owner-only description/);
  assert.equal(privateEvent.location, "Owner-only place");
  const family = await buildCalendarExport({db: fakeDb(seed), uid: "p", data: {scope: "family"}, now: NOW});
  assert.doesNotMatch(family.ics, /Owner-only/);
});

test("explicit includeImported preserves visible imported activities with a duplicate-risk warning", async () => {
  const output = await buildCalendarExport({db: fakeDb(fixture()), uid: "p", data: {scope: "family", includeImported: true}, now: NOW});
  assert.equal(output.eventCount, 7);
  assert.ok(parsedEvents(output.ics).some((e) => e.summary === "imported"));
  assert.ok(output.warnings.some((w) => w.includes("ursprungskalendern kan ge dubletter")));
});

test("oversized datasets and responses fail rather than silently truncating", async () => {
  await assert.rejects(buildCalendarExport({db: fakeDb(fixture(), {querySize: MAX_DOCUMENTS + 1}), uid: "p", data: {scope: "family"}}), {code: "resource-exhausted"});
  const seed = fixture();
  seed["planner_events/shared"].description = "a".repeat(MAX_RESPONSE_BYTES);
  await assert.rejects(buildCalendarExport({db: fakeDb(seed), uid: "p", data: {scope: "family"}}), {code: "resource-exhausted"});
});
