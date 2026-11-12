/* eslint-disable max-len, require-jsdoc */
const test = require("node:test");
const assert = require("node:assert/strict");
const {createSyncService} = require("../calendar_sync/sync_service");
const {FirestoreOAuthStore} = require("../calendar_sync/firestore_store");
const mapping = require("../calendar_sync/event_mapping");
class FakeDb {
  constructor(seed = {}) {
    this.rows = new Map(Object.entries(seed)); this.versions = new Map(); this.sequence = 0;
  }
  write(path, value, merge = false) {
    this.rows.set(path, structuredClone(merge ? {...this.rows.get(path), ...value} : value)); this.versions.set(path, ++this.sequence);
  }
  snapshot(path) {
    return {id: path.split("/").at(-1), exists: this.rows.has(path), updateTime: {seconds: this.versions.get(path) || 0, nanoseconds: 0}, data: () => structuredClone(this.rows.get(path))};
  }
  collection(name) {
    const db = this;
    const query = (filters = [], max = Infinity) => ({
      where(field, op, value) {
        assert.equal(op, "=="); return query([...filters, [field, value]], max);
      },
      limit(value) {
        return query(filters, value);
      },
      async get() {
        const docs = [...db.rows].filter(([path, value]) => path.startsWith(`${name}/`) && path.split("/").length === name.split("/").length + 1 && filters.every(([f, v]) => value[f] === v)).slice(0, max).map(([path]) => db.snapshot(path)); return {docs, size: docs.length};
      },
      doc(id) {
        const path = `${name}/${id}`; return {path, id, collection: (child) => db.collection(`${path}/${child}`), get: async () => db.snapshot(path), update: async (value) => db.write(path, value, true)};
      },
    });
    return query();
  }
  async runTransaction(fn) {
    const writes = [];
    const tx = {get: async (ref) => ref.path ? this.snapshot(ref.path) : ref.get(), set: (ref, value, options) => writes.push([ref.path, value, options?.merge]),
      update: (ref, value) => writes.push([ref.path, value, true]), delete: (ref) => writes.push([ref.path, null]), create: (ref, value) => {
        assert(!this.rows.has(ref.path)); writes.push([ref.path, value]);
      }};
    const result = await fn(tx);
    for (const [path, value, merge] of writes) {
      if (value === null) {
        this.rows.delete(path); this.versions.set(path, ++this.sequence);
      } else this.write(path, value, merge);
    }
    return result;
  }
  batch() {
    const writes = []; return {set: (ref, value) => writes.push([ref.path, value]), delete: (ref) => writes.push([ref.path, null]), commit: async () => {
      for (const [path, value] of writes) {
        if (value === null) this.rows.delete(path); else this.write(path, value);
      }
    }};
  }
}
const base = {title: "Familjeträning", date: "2026-10-26", time: "07:30", endTime: "08:30", source: "manual", createdByUid: "owner", createdBy: "owner", familyId: "family", personUids: ["owner"], persons: ["Oscar"], checklist: [{item: "Vatten", isDone: true}]};
const raw = (title = "External private title", extra = {}) => ({id: "remote", summary: title, start: {dateTime: "2026-10-26T07:30:00+01:00", timeZone: "Europe/Stockholm"}, end: {dateTime: "2026-10-26T08:30:00+01:00", timeZone: "Europe/Stockholm"}, visibility: "default", organizer: {self: true}, etag: "v1", ...extra});
function harness({events = [], locals = {}} = {}) {
  let time = 1000000;
  const connection = {id: "c", uid: "owner", familyId: "family", provider: "google", status: "connected", enabled: true, generation: 1, calendarId: "calendar"};
  const db = new FakeDb({"calendar_sync_connections/c": connection, "users/owner": {name: "Oscar", role: "parent", familyId: "family"}, "families/family": {}, "config/privateCalendarPilot20261030": {enabled: true, contract: "private-v1-20261030"}, ...locals});
  const remotes = new Map(events.map((e) => [e.id, e]));
  const calls = [];
  const lists = [];
  const provider = {
    listCalendars: async () => [{id: "calendar", name: "My calendar", writable: true}],
    listEvents: async () => lists.length ? lists.shift() : {items: [...remotes.values()].map((r) => ({id: r.id, etag: r.etag, raw: r})), syncToken: `token${time}`, full: true},
    getEvent: async (_, id) => {
      const r = remotes.get(id); if (!r) throw Object.assign(new Error("missing"), {code: "not-found"}); return {id, etag: r.etag, raw: r};
    },
    createEvent: async (_, {operationId, event}) => {
      calls.push(["create", event]); const id = `created-${operationId}`; const r = remotes.get(id) || {...event, id, etag: `v${calls.length}`, organizer: {self: true}}; remotes.set(id, r); return {id, etag: r.etag, raw: r};
    },
    updateEvent: async (_, id, event, {etag}) => {
      calls.push(["update", event]); assert.equal(remotes.get(id).etag, etag); const r = {...remotes.get(id), ...event, etag: `v${calls.length + 1}`}; remotes.set(id, r); return {id, etag: r.etag, raw: r};
    },
    deleteEvent: async (_, id) => {
      calls.push(["delete", id]); remotes.delete(id); return {id, deleted: true};
    },
  };
  const store = new FirestoreOAuthStore({db, now: () => time});
  const runtime = {store, authorize: async (uid, familyId) => {
    const u = db.rows.get(`users/${uid}`); return u && ["parent", "admin", "youth"].includes(u.role) && u.familyId === familyId;
  }, getProvider: async () => provider};
  const service = createSyncService({db, runtime, now: () => time});
  return {db, store, runtime, service, provider, calls, lists, remotes, connection, tick: () => {
    time += 1000;
  }, rows: (collection) => [...db.rows].filter(([path]) => path.startsWith(collection)).map(([path, data]) => ({path, data}))};
}
const sync = (h) => h.service.syncNow({uid: "owner", connectionId: "c"});

test("incoming public source becomes private marker+detail atomically with separate semantic baselines", async () => {
  const h = harness({events: [raw()]});
  await sync(h);
  const marker = h.rows("planner_events/")[0];
  assert.equal(marker.data.title, "Privat");
  assert.equal(marker.data.visibility, "private");
  assert.equal(marker.data.source, "manual");
  assert(!JSON.stringify(marker.data).includes("External private title"));
  assert.equal(h.db.rows.get(`private_activities/owner/events/${marker.path.split("/").at(-1)}`).title, "External private title");
  const link = h.rows("calendar_sync_connections/c/links/")[0].data;
  assert.equal(link.privacyPolicy, "local-private");
  assert.notEqual(link.localHash, link.remoteHash);
  h.tick(); await sync(h);
  assert.equal(h.calls.length, 0);
});

test("local edit of imported private activity preserves provider visibility and checklists", async () => {
  const h = harness({events: [raw()]}); await sync(h);
  const detail = h.rows("private_activities/owner/events/")[0];
  h.db.write(detail.path, {...detail.data, title: "Changed at home", checklist: [{item: "Bag", isDone: true}], lessonPrep: {text: "Bring book"}});
  h.tick(); await sync(h);
  assert.equal(h.remotes.get("remote").summary, "Changed at home");
  assert.equal(h.remotes.get("remote").visibility, "default");
  assert.equal(h.rows("calendar_sync_connections/c/conflicts/").length, 0);
  h.remotes.set("remote", {...h.remotes.get("remote"), summary: "External update", etag: "v9"}); h.tick(); await sync(h);
  const updated = h.db.rows.get(detail.path);
  assert.equal(updated.title, "External update"); assert.equal(updated.checklist[0].isDone, true); assert.equal(updated.lessonPrep.text, "Bring book");
});

test("only own manually created self/common activities are pushed; unrelated family data is excluded", async () => {
  const h = harness({locals: {"planner_events/own": base, "planner_events/other": {...base, createdByUid: "child", personUids: ["child"]}, "planner_events/import": {...base, source: "calendar"}, "planner_events/for-child": {...base, personUids: ["child"]}, "planner_events/secret": {...base, visibility: "private", privateOwnerUid: "child"}}});
  await sync(h); assert.equal(h.calls.filter((c) => c[0] === "create").length, 1); assert.equal(h.calls[0][1].summary, base.title);
});

test("missing local row is a conflict; only explicit tombstone leads to remote delete", async () => {
  const h = harness({locals: {"planner_events/own": base}}); await sync(h);
  h.db.rows.delete("planner_events/own"); h.tick(); await sync(h);
  assert.equal(h.calls.filter((c) => c[0] === "delete").length, 0);
  assert(h.rows("calendar_sync_connections/c/conflicts/").some((c) => c.data.reason === "local-row-missing"));
  await h.service.captureEventDeletion({id: "own", data: base, eventId: "explicit-firestore-delete"});
  h.tick(); await sync(h);
  assert.equal(h.calls.filter((c) => c[0] === "delete").length, 1);
});

test("new local edit during provider write remains dirty after ack", async () => {
  const h = harness({locals: {"planner_events/own": base}});
  const original = h.provider.createEvent;
  h.provider.createEvent = async (...args) => {
    const result = await original(...args); h.db.write("planner_events/own", {...base, title: "Edited while saving"}); return result;
  };
  await sync(h); const first = [...h.remotes.values()][0]; assert.equal(first.summary, base.title);
  h.tick(); await sync(h); assert.equal([...h.remotes.values()][0].summary, "Edited while saving");
});

test("Google override blocks master both in initial full listing and in later delta", async () => {
  for (const delta of [false, true]) {
    const master = raw("Series", {id: "master", recurrence: ["RRULE:FREQ=WEEKLY"]});
    const override = {id: "override", etag: "x1", deleted: true, raw: {id: "override", status: "cancelled", recurringEventId: "master", originalStartTime: {dateTime: "2026-11-02T07:30:00+01:00"}}};
    const h = harness({events: [master]});
    if (!delta) h.lists.push({items: [{id: "master", etag: "v1", raw: master}, override], full: true, syncToken: "t1"});
    await sync(h);
    if (delta) {
      h.lists.push({items: [override], full: false, syncToken: "t2"}); h.tick(); await sync(h);
    }
    assert(h.rows("calendar_sync_connections/c/conflicts/").length > 0);
    assert.equal(h.calls.length, 0);
    if (!delta) assert.equal(h.rows("planner_events/").length, 0);
  }
});

test("failed provider page cannot advance token or write calendar data", async () => {
  const h = harness(); h.provider.listEvents = async () => {
    throw Object.assign(new Error("partial read"), {code: "provider-unavailable"});
  };
  await assert.rejects(sync(h)); assert.equal(h.rows("planner_events/").length, 0); assert.equal(h.db.rows.get("calendar_sync_connections/c").syncToken, undefined);
});

test("family/role change blocks synchronization, private details are never read through another user", async () => {
  const h = harness({events: [raw()]}); h.db.write("users/owner", {name: "Oscar", familyId: "new-family", role: "parent"});
  await assert.rejects(sync(h)); assert.equal(h.rows("planner_events/").length, 0); assert.equal(h.calls.length, 0);
});

test("iCloud create IDs are stable for retry and different for different operations", () => {
  const input = mapping.canonical(base);
  const first = mapping.fromCanonical("icloud", input, {operationId: "one"}).payload.ics;
  const retry = mapping.fromCanonical("icloud", input, {operationId: "one"}).payload.ics;
  const second = mapping.fromCanonical("icloud", input, {operationId: "two"}).payload.ics;
  const uid = (ics) => /^UID:(.+)$/m.exec(ics)[1];
  assert.equal(uid(first), uid(retry)); assert.notEqual(uid(first), uid(second));
});

test("full refresh without a removed event followed by empty delta never resurrects old cached data", async () => {
  const h = harness({events: [raw()]}); await sync(h);
  h.remotes.delete("remote"); h.tick(); await sync(h);
  assert.equal(h.rows("planner_events/").length, 0);
  h.lists.push({items: [], full: false, syncToken: "empty-delta"}); h.tick(); await sync(h);
  assert.equal(h.rows("planner_events/").length, 0);
  assert.equal(h.calls.length, 0);
});

test("private detail cannot shadow marker dates, owners or recurrence", async () => {
  const h = harness({events: [raw()]}); await sync(h);
  const marker = h.rows("planner_events/")[0];
  const detail = h.rows("private_activities/owner/events/")[0];
  h.db.write(detail.path, {...detail.data, date: "2040-01-01", time: "20:00", endTime: "21:00", source: "calendar", recurrence: {type: "daily"}, familyId: "family", createdByUid: "someone-else", title: "Legitimate title edit"});
  h.tick(); await sync(h);
  const result = h.remotes.get("remote");
  assert.equal(result.start.dateTime.slice(0, 10), marker.data.date);
  assert.equal(result.start.dateTime.slice(11, 16), marker.data.time);
  assert.equal(result.recurrence.length, 0);
  assert.equal(result.summary, "Legitimate title edit");
});

test("master with detached local occurrences is explicitly unsupported", async () => {
  const h = harness({locals: {"planner_events/own": {...base, recurrence: {type: "weekly", startDate: base.date}, detachedOccurrences: {"2026-11-02": "moved_child"}}}});
  await sync(h); assert.equal(h.calls.length, 0); assert(h.rows("calendar_sync_connections/c/conflicts/").length > 0);
});

test("local change between snapshot and outbox prepare prevents first network write", async () => {
  const h = harness({locals: {"planner_events/own": base}});
  const run = h.db.runTransaction.bind(h.db); let race = true;
  h.db.runTransaction = async (fn) => {
    const result = await run(fn); if (race && Array.isArray(result) && result[0]?.id === "own") {
      race = false; h.db.write("planner_events/own", {...base, title: "Newer intent"});
    } return result;
  };
  await sync(h); assert.equal(h.calls.length, 0); assert(h.rows("calendar_sync_connections/c/conflicts/").length);
  h.tick(); await sync(h); assert.equal(h.calls.length, 1); assert.equal([...h.remotes.values()][0].summary, "Newer intent");
});

test("another connection cannot activate the same user/provider/calendar combination", async () => {
  const h = harness(); h.db.write("calendar_sync_connections/second", {...h.connection, id: "second", status: "authorized", enabled: false, calendarId: null});
  await assert.rejects(h.service.selectCalendar({uid: "owner", connectionId: "second", calendarId: "calendar"}), (error) => error.code === "calendar-already-connected");
  assert.equal(h.db.rows.get("calendar_sync_connections/second").status, "authorized");
});

test("conflict list declares truncation rather than hiding additional rows", async () => {
  const h = harness();
  for (let i = 0; i < 201; i++) h.db.write(`calendar_sync_connections/c/conflicts/${i}`, {status: "open", reason: "unsupported-event", createdAt: i, action: {remote: {supported: false}}});
  const result = await h.service.getConflicts({uid: "owner", connectionId: "c"});
  assert.equal(result.conflicts.length, 200); assert.equal(result.truncated, true);
});

async function crashedCreateThenLocalDelete(provider) {
  const {createdEventIdentity} = require("../calendar_sync/providers");
  const h = harness({locals: {"planner_events/own": base}});
  const calendarId = provider === "icloud" ? "https://p01-caldav.icloud.com/123/calendars/test/" : "calendar";
  h.db.write("calendar_sync_connections/c", {...h.connection, provider, calendarId});
  let reads = 0;
  const list = h.provider.listEvents;
  h.provider.listEvents = async (...args) => {
    reads++; return list(...args);
  };
  h.provider.createEvent = async (calendar, {operationId, event}) => {
    h.calls.push(["create", event]);
    const identity = createdEventIdentity(provider, calendar, operationId);
    const id = identity.id || "outlook-server-assigned-id";
    h.remotes.set(id, {...event, id, etag: "v-created", ...identity});
    throw new Error("Process died after provider commit, before acknowledgement");
  };
  await assert.rejects(sync(h));
  assert.equal(h.rows("calendar_sync_connections/c/outbox/")[0].data.status, "pending");
  h.db.rows.delete("planner_events/own");
  const captured = await h.service.captureEventDeletion({id: "own", data: base, eventId: "delete-after-crash"});
  assert.equal(captured.captured, 0); // The missing link is the dangerous crash window.
  for (let i = 0; i < 61; i++) h.tick();
  const beforeReplayReads = reads;
  await assert.rejects(sync(h), (error) => error.code === "ambiguous-create-outcome");
  assert.equal(reads, beforeReplayReads, "quarantined replay must stop before provider listing/import");
  assert.equal(h.rows("planner_events/").length, 0);
  assert.equal(h.rows("calendar_sync_connections/c/outbox/")[0].data.status, "quarantined");
  assert.equal(h.calls.length, 1);
  for (let i = 0; i < 61; i++) h.tick();
  await assert.rejects(sync(h), (error) => error.code === "ambiguous-create-outcome");
  assert.equal(reads, beforeReplayReads, "quarantine persists across later workers");
  const conflicts = await h.service.getConflicts({uid: "owner", connectionId: "c"});
  assert.equal(conflicts.conflicts[0].reason, "ambiguous-create-outcome");
  assert.equal(h.db.rows.get("calendar_sync_connections/c").conflictCount, 1);
  return {h, conflictId: conflicts.conflicts[0].id};
}

test("crashed create then local deletion cannot resurrect an activity; explicit skip excludes exact provider identity", async () => {
  for (const provider of ["google", "icloud", "outlook"]) {
    const {h, conflictId} = await crashedCreateThenLocalDelete(provider);
    const result = await h.service.resolveConflict({uid: "owner", connectionId: "c", conflictId, choice: "skip"});
    assert.equal(result.status, "resolved", provider);
    assert.equal(h.rows("calendar_sync_connections/c/outbox/")[0].data.status, "ignored");
    const ignored = h.rows("calendar_sync_connections/c/ignored/")[0].data;
    assert.equal(ignored.remoteId, [...h.remotes.keys()][0]);
    h.tick(); await sync(h);
    assert.equal(h.rows("planner_events/").length, 0, provider);
    assert.equal(h.calls.length, 1, "skip must not create, update or delete remotely");
    assert.equal(h.remotes.size, 1, "the external copy is left untouched");
  }
});

test("Outlook quarantine is not cleared without exactly one positive immutable transaction identity", async () => {
  const {h, conflictId} = await crashedCreateThenLocalDelete("outlook");
  h.lists.push({items: [], full: true, syncToken: null});
  await assert.rejects(h.service.resolveConflict({uid: "owner", connectionId: "c", conflictId, choice: "skip"}), (error) => error.code === "ambiguous-create-outcome");
  const remote = [...h.remotes.values()][0];
  h.lists.push({items: [{id: "first", raw: remote}, {id: "second", raw: remote}], full: true, syncToken: null});
  await assert.rejects(h.service.resolveConflict({uid: "owner", connectionId: "c", conflictId, choice: "skip"}), (error) => error.code === "ambiguous-create-outcome");
  assert.equal(h.rows("calendar_sync_connections/c/outbox/")[0].data.status, "quarantined");
  assert.equal(h.rows("calendar_sync_connections/c/ignored/").length, 0);
  assert.equal(h.rows("planner_events/").length, 0);
});
