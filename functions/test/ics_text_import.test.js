/* eslint-disable max-len, require-jsdoc */
const test = require("node:test");
const assert = require("node:assert/strict");
const {gunzipSync} = require("node:zlib");
const {_test: api} = require("../ics_text_import");
const WINDOW = {fromDate: "2026-10-23", toDate: "2026-10-30"};
const calendar = (...events) => ["BEGIN:VCALENDAR", "VERSION:2.0", ...events.map((lines) => ["BEGIN:VEVENT", ...lines, "END:VEVENT"].join("\r\n")), "END:VCALENDAR"].join("\r\n");
const event = (uid, ...lines) => [`UID:${uid}`, "SUMMARY:Träning", ...lines];
const parse = (text, window = WINDOW) => api.parseIcsTextToEventDrafts(text, window, api.htmlToText).drafts;

test("UTC, TZID and floating values use Swedish local time; midnight remains timed", () => {
  const rows = parse(calendar(
      event("utc", "DTSTART:20261026T073000Z", "DTEND:20261026T083000Z"),
      event("zone", "DTSTART;TZID=Europe/Stockholm:20261026T083000", "DURATION:PT1H"),
      event("float", "DTSTART:20261026T083000", "DTEND:20261026T093000"),
      event("midnight", "DTSTART:20261026T000000", "DURATION:PT1H"),
  ));
  assert.equal(rows.length, 4);
  assert.equal(rows[0].time, "00:00");
  assert.equal(rows[0].icsAllDay, false);
  for (const row of rows.slice(1)) {
    assert.equal(row.time, "08:30"); assert.equal(row.endTime, "09:30");
  }
});

test("old weekly series expands over DST and respects EXDATE and cancellation", () => {
  const rows = parse(calendar(
      event("weekly", "DTSTART;TZID=Europe/Stockholm:20260102T073000", "DURATION:PT1H", "RRULE:FREQ=DAILY", "EXDATE;TZID=Europe/Stockholm:20261024T073000"),
      event("weekly", "RECURRENCE-ID;TZID=Europe/Stockholm:20261025T073000", "DTSTART;TZID=Europe/Stockholm:20261025T073000", "STATUS:CANCELLED"),
  ));
  assert.deepEqual(rows.map((r) => r.date), ["2026-10-23", "2026-10-26", "2026-10-27", "2026-10-28", "2026-10-29", "2026-10-30"]);
  assert(rows.every((r) => r.time === "07:30"));
  assert.equal(rows[0].icsOriginalStart, "2026-10-23T05:30:00.000Z");
  assert.equal(rows[1].icsOriginalStart, "2026-10-26T06:30:00.000Z");
});

test("moved occurrence enters window from original date outside it, with no old duplicate", () => {
  const rows = parse(calendar(
      event("moved", "DTSTART;TZID=Europe/Stockholm:20261001T090000", "DURATION:PT1H", "RRULE:FREQ=WEEKLY;COUNT=5"),
      event("moved", "RECURRENCE-ID;TZID=Europe/Stockholm:20261008T090000", "DTSTART;TZID=Europe/Stockholm:20261026T140000", "DTEND;TZID=Europe/Stockholm:20261026T150000"),
      event("moved", "RECURRENCE-ID;TZID=Europe/Stockholm:20261029T090000", "DTSTART;TZID=Europe/Stockholm:20261110T140000", "DTEND;TZID=Europe/Stockholm:20261110T150000"),
  ));
  assert.equal(rows.length, 1);
  assert.equal(rows[0].date, "2026-10-26");
  assert.equal(rows[0].time, "14:00");
  assert.match(rows[0].icsInstanceKey, /2026-10-08T07:00:00/);
});

test("all-day DTEND is exclusive, including ongoing spans entering the window", () => {
  const rows = parse(calendar(event("allday", "DTSTART;VALUE=DATE:20261001", "DTEND;VALUE=DATE:20261026")));
  assert.deepEqual(rows.map((r) => [r.date, r.time, r.endTime]), [
    ["2026-10-23", "", undefined], ["2026-10-24", "", undefined], ["2026-10-25", "", undefined],
  ]);
  assert.equal(rows[0].icsInstanceKey, rows[2].icsInstanceKey);
  assert.equal(rows[0].icsOriginalEnd, rows[2].icsOriginalEnd);
});

test("overnight is explicitly refused before writes until clients support end dates", () => {
  assert.throws(() => parse(calendar(event("night", "DTSTART:20261026T220000", "DTEND:20261027T010000"))), /nattpass.*Ing(e|en)nting|nattpass/);
});

test("private source events cannot silently become family-visible, including private overrides", () => {
  for (const privacy of ["PRIVATE", "CONFIDENTIAL"]) {
    assert.throws(() => parse(calendar(event("private", "DTSTART:20261026T090000", `CLASS:${privacy}`))), /privata eller konfidentiella/);
    assert.throws(() => parse(calendar(
      event("series", "DTSTART:20261026T090000", "RRULE:FREQ=DAILY;COUNT=2"),
      event("series", "RECURRENCE-ID:20261027T090000", "DTSTART:20261027T100000", `CLASS:${privacy}`),
    )), /privata eller konfidentiella/);
  }
});

test("never truncates occurrence count; unsupported rules and unknown timezone reject before writes", () => {
  const many = Array.from({length: 401}, (_, n) => event(`uid-${n}`, "DTSTART:20261026T090000"));
  assert.throws(() => parse(calendar(...many)), /fler än 400/);
  for (const rule of ["RRULE:FREQ=MINUTELY", "RRULE:FREQ=DAILY;BYSECOND=1,2", "RDATE:20261026T120000"]) {
    assert.throws(() => parse(calendar(event("x", "DTSTART:20261026T090000", rule))), /upprepningar|RDATE/);
  }
  assert.throws(() => parse(calendar(event("x", "DTSTART;TZID=Mars/Olympus:20261026T090000"))), /tidszon/);
});

test("history window, leap dates, order and full 366-day cap are validated", () => {
  assert.deepEqual(api.importWindow({fromDate: "2024-01-01", toDate: "2024-12-31"}), {fromDate: "2024-01-01", toDate: "2024-12-31", timeZone: "Europe/Stockholm"});
  for (const data of [{fromDate: "2026-02-30"}, {fromDate: "2026-10-26", toDate: "2026-10-25"}, {fromDate: "2026-01-01", toDate: "2027-01-02"}]) {
    assert.throws(() => api.importWindow(data), /datum|366 dagar/);
  }
  assert.equal(api.importWindow({}, new Date("2026-10-29T23:30Z")).fromDate, "2026-10-30");
});

test("HTML decoding still supports school-news RSS", () => {
  assert.equal(api.htmlToText("<p>Hej &aring; &auml; &#246;<br>Tv&aring;</p>"), "Hej å ä ö\nTvå");
  assert.equal(api.htmlToText("&amp;lt;"), "&lt;");
});

function fakeDb(initial = {}) {
  const records = new Map(Object.entries(initial));
  const calls = {writes: 0, transactions: 0};
  const ref = (path) => ({id: path.split("/").pop(), path, collection: (name) => collection(`${path}/${name}`), get: async () => ({exists: records.has(path), data: () => records.get(path)})});
  const collection = (path) => ({doc: (id) => ref(`${path}/${id}`)});
  return {records, calls, collection, runTransaction: async (fn) => {
    calls.transactions++;
    const writes = [];
    const result = await fn({get: (r) => r.get(), set: (r, value) => writes.push([r.path, value])});
    for (const [path, value] of writes) {
      records.set(path, value); calls.writes++;
    }
    return result;
  }};
}
const sample = calendar(event("sample", "DTSTART:20261026T090000", "DURATION:PT1H", "DESCRIPTION:Originalet finns kvar"));
const request = (data = {}, uid = "parent") => ({auth: {uid}, data: {icsText: sample, kind: "activity", ...WINDOW, ...data}});
const handler = (db) => api.makeImportHandler({getDb: () => db, timestamp: () => "server-time"});

test("preview writes nothing; confirmed identical file is atomic and idempotent with original preserved", async () => {
  const db = fakeDb({"users/parent": {role: "parent", familyId: "f1"}});
  const call = handler(db);
  const preview = await call(request({preview: true}));
  assert.equal(preview.count, 1);
  assert.equal(db.calls.writes, 0);
  const saved = await call(request());
  assert.equal(saved.alreadyImported, false);
  const writes = db.calls.writes;
  const again = await call(request({icsText: sample.replace(/\r\n/g, "\n"), fromDate: "2026-01-01", toDate: "2026-12-31"}));
  assert.equal(again.alreadyImported, true);
  assert.equal(again.fromDate, WINDOW.fromDate);
  assert.equal(db.calls.writes, writes);
  assert.equal([...db.records.keys()].filter((k) => k.startsWith("planner_events/")).length, 1);
  const source = db.records.get(`calendar_import_sources/${saved.importId}/chunks/000`);
  assert.equal(gunzipSync(Buffer.from(source.data, "base64")).toString("utf8"), sample);
});

test("rejects anonymous, child, missing/foreign family and foreign selected member without writes", async () => {
  const db = fakeDb({"users/parent": {role: "parent", familyId: "f1"}, "users/child": {role: "child", familyId: "f1"}, "users/nofamily": {role: "admin"}, "users/foreign": {role: "child", familyId: "f2"}});
  for (const req of [{data: {}}, request({}, "child"), request({}, "missing"), request({}, "nofamily"), request({familyId: "f2"}), request({memberUid: "foreign"}), request({memberUid: "not-found"}), request({kind: "schedule"})]) {
    await assert.rejects(handler(db)(req));
  }
  assert.equal(db.calls.writes, 0);
});

test("transaction revalidates permission and keeps imports atomic after family switch", async () => {
  const db = fakeDb({"users/parent": {role: "parent", familyId: "f1"}});
  const run = db.runTransaction;
  db.runTransaction = async (fn) => {
    db.records.set("users/parent", {role: "parent", familyId: "f2"});
    return run(fn);
  };
  await assert.rejects(handler(db)(request()), /egen familj/);
  assert.equal(db.calls.writes, 0);
});


test("monthly implicit day 31 does not drift to day 30", () => {
  const rows = parse(calendar(event("month-end", "DTSTART;TZID=Europe/Stockholm:20260131T090000", "DTEND;TZID=Europe/Stockholm:20260131T100000", "RRULE:FREQ=MONTHLY;COUNT=4")), {fromDate: "2026-01-01", toDate: "2026-06-30"});
  assert.deepEqual(rows.map((r) => r.date), ["2026-01-31", "2026-03-31", "2026-05-31"]);
});
