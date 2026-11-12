/* eslint-disable max-len, require-jsdoc */
const test = require("node:test");
const assert = require("node:assert/strict");
const {toCanonical, fromCanonical, fingerprint} = require("../calendar_sync/event_mapping");
const e = {title: "Träning", date: "2026-10-26", time: "07:30", endTime: "08:30", timeMode: "timed", description: "Ta med vatten", location: "Hallen", private: true};
const google = (overrides = {}) => ({id: "g", summary: "Träning", start: {dateTime: "2026-10-26T07:30:00+01:00", timeZone: "Europe/Stockholm"}, end: {dateTime: "2026-10-26T08:30:00+01:00", timeZone: "Europe/Stockholm"}, organizer: {self: true}, ...overrides});
const outlook = (overrides = {}) => ({id: "o", subject: "Träning", start: {dateTime: "2026-10-26T06:30:00.0000000", timeZone: "UTC"}, end: {dateTime: "2026-10-26T07:30:00.0000000", timeZone: "UTC"}, organizer: {emailAddress: {address: "owner@example.test"}}, isOrganizer: true, type: "singleInstance", originalStartTimeZone: "W. Europe Standard Time", ...overrides});

test("Google series preflight prevents overwriting exceptions added after the sync snapshot", () => {
  const raw = google({recurrence: ["RRULE:FREQ=WEEKLY"], vardagSeriesHasExceptions: true});
  assert.equal(toCanonical("google", raw).reason, "series-has-exceptions");
  assert.equal(fromCanonical("google", e, {originalRaw: raw}).supported, false);
});

test("same-day timed and single-day all-day round trip on all three providers", () => {
  for (const provider of ["google", "outlook", "icloud"]) {
    for (const input of [e, {...e, time: "", endTime: "", timeMode: "allDay"}]) {
      const encoded = fromCanonical(provider, input, {operationId: "op"});
      assert.equal(encoded.supported, true, `${provider}: ${encoded.reason}`);
      const decoded = toCanonical(provider, encoded.payload);
      assert.equal(decoded.supported, true, `${provider}: ${decoded.reason}`);
      assert.equal(fingerprint(decoded.event), fingerprint(input), provider);
    }
  }
});

test("weekly, fortnightly, daily and monthly keep Swedish time with finite end date", () => {
  for (const provider of ["google", "outlook", "icloud"]) {
    for (const type of ["daily", "weekly", "biweekly", "monthly"]) {
      const input = {...e, recurrence: {type, startDate: e.date, endDate: "2027-04-30", exceptions: []}};
      const encoded = fromCanonical(provider, input, {operationId: "r"});
      assert.equal(encoded.supported, true, provider);
      const decoded = toCanonical(provider, encoded.payload);
      assert.equal(decoded.supported, true, `${provider}: ${decoded.reason}`);
      assert.equal(fingerprint(decoded.event), fingerprint(input), `${provider}/${type}`);
    }
  }
});

test("Google and iCloud preserve EXDATE; Outlook refuses separate instance writes", () => {
  const input = {...e, recurrence: {type: "weekly", startDate: e.date, exceptions: ["2026-11-02"]}};
  for (const provider of ["google", "icloud"]) {
    const encoded = fromCanonical(provider, input, {operationId: "ex"});
    const decoded = toCanonical(provider, encoded.payload);
    assert.equal(decoded.supported, true, decoded.reason);
    assert.deepEqual(decoded.event.recurrence.exceptions, ["2026-11-02"]);
  }
  assert.equal(fromCanonical("outlook", input).supported, false);
});

test("Google UTC one-off converts to Swedish time but UTC recurring series stays unsupported", () => {
  const raw = google({start: {dateTime: "2026-10-26T06:30:00Z"}, end: {dateTime: "2026-10-26T07:30:00Z"}});
  assert.equal(toCanonical("google", raw).event.time, "07:30");
  assert.equal(toCanonical("google", {...raw, recurrence: ["RRULE:FREQ=WEEKLY"]}).reason, "recurrence-timezone");
});

test("Outlook UTC response derives local wall time and safe recurrence metadata", () => {
  const raw = outlook({recurrence: {pattern: {type: "weekly", interval: 1, daysOfWeek: ["monday"]}, range: {type: "noEnd", startDate: e.date, recurrenceTimeZone: "W. Europe Standard Time"}}, type: "seriesMaster"});
  const result = toCanonical("outlook", raw);
  assert.equal(result.supported, true, result.reason);
  assert.equal(result.event.time, "07:30");
  assert.equal(result.event.recurrence.type, "weekly");
  assert.equal(toCanonical("outlook", {...raw, exceptionOccurrences: [{id: "exception"}]}).supported, false);
});

test("invited meetings, cancelled, moved, overnight and complex recurrence never produce write payload", () => {
  for (const raw of [google({attendees: [{email: "other@example.test"}]}), google({organizer: {self: false}}), google({status: "cancelled"}), google({recurringEventId: "master"}), google({recurrence: ["RRULE:FREQ=WEEKLY;BYDAY=MO,FR"]})]) {
    assert.equal(toCanonical("google", raw).supported, false);
    assert.equal(fromCanonical("google", e, {originalRaw: raw}).supported, false);
  }
  assert.equal(fromCanonical("google", {...e, endTime: "01:00"}).supported, false);
  assert.equal(fromCanonical("google", {...e, endTime: ""}).supported, false);
  assert.equal(toCanonical("outlook", outlook({isOnlineMeeting: true})).supported, false);
});

test("patch payload leaves provider-only fields untouched and preserves HTML when only title changes", () => {
  const raw = google({description: "<p>Water <b>please</b></p>", colorId: "6", reminders: {useDefault: false, overrides: [{method: "popup", minutes: 17}]}, extendedProperties: {private: {otherApp: "keep"}}});
  const decoded = toCanonical("google", raw).event;
  const encoded = fromCanonical("google", {...decoded, title: "Changed"}, {originalRaw: raw});
  assert.equal(encoded.supported, true);
  assert.equal(encoded.payload.description, raw.description);
  assert.equal(encoded.payload.organizer, undefined);
  assert.equal(encoded.payload.reminders, undefined);
  assert.deepEqual({...raw, ...encoded.payload}.extendedProperties, raw.extendedProperties);
  const graph = outlook({body: {contentType: "html", content: "<p>Important</p>"}, location: {displayName: "Hall", locationEmailAddress: "hall@example.test"}});
  const graphEvent = toCanonical("outlook", graph).event;
  const graphPatch = fromCanonical("outlook", {...graphEvent, title: "Changed"}, {originalRaw: graph}).payload;
  assert.deepEqual(graphPatch.body, graph.body);
  assert.equal(graphPatch.location.locationEmailAddress, "hall@example.test");
});

test("iCloud updates preserve UID, VALARM and unknown properties while adding correct timezone", () => {
  const raw = {ics: "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nX-WR-CALNAME:Other\r\nBEGIN:VEVENT\r\nUID:source-uid\r\nSEQUENCE:3\r\nDTSTART:20261026T063000Z\r\nDTEND:20261026T073000Z\r\nSUMMARY:Old\r\nX-KEEP:unchanged\r\nBEGIN:VALARM\r\nACTION:DISPLAY\r\nDESCRIPTION:keep alarm\r\nTRIGGER:-PT15M\r\nEND:VALARM\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"};
  const old = toCanonical("icloud", raw);
  assert.equal(old.supported, true);
  const result = fromCanonical("icloud", {...old.event, title: "Changed"}, {originalRaw: raw, operationId: "update"});
  assert.equal(result.supported, true, result.reason);
  for (const line of ["UID:source-uid", "SEQUENCE:4", "X-KEEP:unchanged", "DESCRIPTION:keep alarm", "TZID:Europe/Stockholm"]) assert(result.payload.ics.includes(line), line);
  assert.equal(toCanonical("icloud", result.payload).event.title, "Changed");
});

test("fingerprint ignores linkage and field order, includes privacy/recurrence/date changes", () => {
  assert.equal(fingerprint(e), fingerprint({...e, id: "123", familyId: "family", createdAt: "today"}));
  assert.notEqual(fingerprint(e), fingerprint({...e, private: false}));
  assert.notEqual(fingerprint(e), fingerprint({...e, date: "2026-10-27"}));
});
