"use strict";
const {test} = require("node:test");
const assert = require("node:assert/strict");
const {planReconciliation, executeAction} = require("../calendar_sync/reconcile");

const link = {localId: "local", remoteId: "remote", localHash: "base", remoteHash: "base", remoteEtag: "e1"};
const local = {id: "local", hash: "base", revision: 1, event: {title: "base"}};
const remote = {id: "remote", hash: "base", etag: "e1", raw: {title: "base"}};
function plan(l = local, r = remote, options = {}) {
  return planReconciliation({connectionId: "connection", links: [link], localRows: l ? [l] : [], remoteRows: r ? [r] : [], ...options});
}
test("unchanged records do not loop; either side can change independently", () => {
  assert.deepEqual(plan(), []);
  assert.equal(plan({...local, hash: "new"})[0].type, "pushUpdate");
  assert.equal(plan(local, {...remote, hash: "new"})[0].type, "pullUpdate");
  assert.equal(plan({...local, hash: "new"}, {...remote, hash: "other"})[0].reason, "changed-on-both-sides");
  assert.equal(plan({...local, hash: "new"}, {...remote, hash: "new"})[0].type, "ack");
});
test("missing local data is never inferred as deletion, and incomplete remote reads cannot delete", () => {
  assert.equal(plan(null)[0].reason, "local-row-missing");
  assert.deepEqual(plan(local, null), []);
  assert.equal(plan(local, null, {remoteComplete: true})[0].type, "verifyRemoteMissing");
  assert.equal(plan({...local, deleted: true, hash: "deleted"})[0].type, "pushDelete");
  assert.equal(plan(local, {...remote, deleted: true, hash: "deleted"})[0].type, "pullDelete");
});
test("delete versus concurrent edit is a conflict and unsupported events stay intact", () => {
  assert.equal(plan({...local, deleted: true, hash: "deleted"}, {...remote, hash: "changed"})[0].type, "conflict");
  assert.equal(plan({...local, hash: "changed"}, {...remote, deleted: true, hash: "deleted"})[0].type, "conflict");
  assert.equal(plan(local, {...remote, supported: false})[0].reason, "unsupported-event");
});
test("new-event operation identity survives local edits before an acknowledgement", () => {
  const options = {connectionId: "connection", links: [], remoteRows: []};
  const a = planReconciliation({...options, localRows: [local]})[0];
  const b = planReconciliation({...options, localRows: [{...local, revision: 2, hash: "new"}]})[0];
  assert.equal(a.operationId, b.operationId);
  assert.equal(a.type, "pushCreate");
  assert.throws(() => plan(local, remote, {links: [link, link]}), /duplicate-link/);
});

const connection = {id: "connection", calendarId: "calendar"};
function fixture() {
  const calls = [];
  let outbox;
  const store = {
    async assertActive() { calls.push("active"); },
    async prepare(c, action) { calls.push("persist"); outbox ||= {action}; return outbox; },
    async ack(c, a, r) { calls.push("ack"); return {status: "acked", remote: r}; },
    async conflict(c, a, reason) { calls.push("conflict"); return {status: "conflict", reason}; },
    async applyIncoming() { calls.push("incoming"); return {status: "applied"}; },
  };
  const provider = {
    async getEvent() { calls.push("read"); return remote; },
    async createEvent(c, {operationId, event}) { calls.push("create"); return {id: operationId, etag: "e2", raw: event}; },
    async updateEvent(c, id, event, {etag}) { calls.push("update"); assert.equal(etag, "e1"); return {id, etag: "e2", raw: event}; },
    async deleteEvent(c, id, {etag}) { calls.push("delete"); assert.equal(etag, "e1"); return {id, deleted: true}; },
  };
  const codec = {
    decode(raw) { return {supported: true, hash: raw.title, event: raw}; },
    encode(event) { return {supported: true, payload: event}; },
  };
  return {store, provider, codec, calls};
}
test("outbox persists before external write; newer provider revision is not overwritten", async () => {
  const f = fixture();
  const action = plan({...local, hash: "new", event: {title: "new"}})[0];
  assert.equal((await executeAction({connection, action, ...f})).status, "acked");
  assert.ok(f.calls.indexOf("persist") < f.calls.indexOf("update"));
  f.provider.getEvent = async () => ({...remote, etag: "someone-else", raw: {title: "other"}});
  assert.equal((await executeAction({connection, action, ...f})).reason, "remote-changed-during-write");
  assert.equal(f.calls.filter((c) => c === "update").length, 1);
});
test("process death after provider update is recovered by comparing actual content", async () => {
  const f = fixture();
  const action = plan({...local, hash: "new", event: {title: "new"}})[0];
  let saved;
  f.provider.updateEvent = async (c, id, event) => { saved = {id, etag: "e2", raw: event}; f.calls.push("update"); return saved; };
  f.store.ack = async () => { throw new Error("process-death"); };
  await assert.rejects(executeAction({connection, action, ...f}), /process-death/);
  f.provider.getEvent = async () => saved;
  f.store.ack = async () => ({status: "acked"});
  assert.equal((await executeAction({connection, action, ...f})).status, "acked");
  assert.equal(f.calls.filter((c) => c === "update").length, 1);
});
test("retrying create uses persisted original body even if local event changed", async () => {
  const f = fixture();
  const action = planReconciliation({connectionId: connection.id, links: [], localRows: [local], remoteRows: []})[0];
  const remoteCreates = new Map();
  f.provider.createEvent = async (c, {operationId, event}) => {
    if (!remoteCreates.has(operationId)) remoteCreates.set(operationId, {id: operationId, raw: event});
    return remoteCreates.get(operationId);
  };
  f.store.ack = async () => { throw new Error("process-death"); };
  await assert.rejects(executeAction({connection, action, ...f}), /process-death/);
  f.store.ack = async (c, a) => ({status: "acked", revision: a.local.revision});
  const changed = {...action, local: {...local, revision: 2, hash: "other", event: {title: "other"}}};
  assert.equal((await executeAction({connection, action: changed, ...f})).revision, 1);
  assert.equal(remoteCreates.size, 1);
});
test("disconnect/lease expiration stops outgoing mutations", async () => {
  const f = fixture();
  f.store.assertActive = async () => { throw new Error("disabled"); };
  await assert.rejects(executeAction({connection, action: plan({...local, hash: "new"})[0], ...f}), /disabled/);
  assert.deepEqual(f.calls, []);
});
test("a missing remote event is checked individually before deleting locally", async () => {
  const f = fixture();
  const action = plan(local, null, {remoteComplete: true})[0];
  assert.equal((await executeAction({connection, action, ...f})).status, "retry-read");
  assert.ok(!f.calls.includes("incoming"));
  f.provider.getEvent = async () => { throw Object.assign(new Error("404"), {code: "not-found"}); };
  assert.equal((await executeAction({connection, action, ...f})).status, "applied");
});
test("stale conditional write conflict is preserved for the user", async () => {
  const f = fixture();
  f.provider.updateEvent = async () => { throw Object.assign(new Error("412"), {code: "conflict"}); };
  const result = await executeAction({connection, action: plan({...local, hash: "new", event: {title: "new"}})[0], ...f});
  assert.equal(result.reason, "remote-changed-during-write");
  assert.ok(!f.calls.includes("ack"));
});
