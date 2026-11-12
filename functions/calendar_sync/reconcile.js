/* eslint-disable max-len, require-jsdoc, valid-jsdoc */
"use strict";

const {createHash} = require("node:crypto");

const key = (...parts) => createHash("sha256").update(JSON.stringify(parts)).digest("hex");
const same = (a, b) => a != null && b != null && a === b;

/**
 * Three-way comparison against the last acknowledged state on BOTH sides.
 * No timestamp-based last-writer-wins. An absent local row is never a deletion:
 * deletion requires an explicit durable tombstone from the authorized writer.
 * Rows contain {id,hash,revision,deleted,supported,event,raw,etag}; remote absence
 * is meaningful only after a full, successfully completed, unfiltered read.
 */
function planReconciliation({connectionId, links, localRows, remoteRows, remoteComplete = false}) {
  const locals = new Map(localRows.map((row) => [row.id, row]));
  const remotes = new Map(remoteRows.map((row) => [row.id, row]));
  if (locals.size !== localRows.length || remotes.size !== remoteRows.length) throw new Error("duplicate-row-id");
  const actions = [];
  const linkedLocal = new Set();
  const linkedRemote = new Set();
  const add = (type, link, local, remote, reason) => actions.push({
    type, link, local, remote, ...(reason ? {reason} : {}),
    operationId: key(connectionId, type, link?.localId || local?.id, link?.remoteId || remote?.id,
        // Create IDs remain stable across edits and retries; all other operations
        // identify their exact immutable intended change.
        type === "pushCreate" ? null : local?.revision || local?.hash || remote?.etag || remote?.hash),
  });
  for (const link of links) {
    if (linkedLocal.has(link.localId) || linkedRemote.has(link.remoteId)) throw new Error("duplicate-link");
    linkedLocal.add(link.localId);
    linkedRemote.add(link.remoteId);
    const local = locals.get(link.localId);
    const remote = remotes.get(link.remoteId);
    if (!local) {
      add("conflict", link, local, remote, "local-row-missing"); continue;
    }
    if (link.localDeleted && link.remoteDeleted && local.deleted && (!remote || remote.deleted)) continue;
    if (!remote && !remoteComplete) continue; // No delta for this linked event.
    if (!remote) {
      add("verifyRemoteMissing", link, local, remote); continue;
    }
    if (local.supported === false || remote.supported === false) {
      add("conflict", link, local, remote, "unsupported-event"); continue;
    }
    const localChanged = !!local.deleted !== !!link.localDeleted || !same(local.hash, link.localHash);
    const remoteChanged = !!remote.deleted !== !!link.remoteDeleted || !same(remote.hash, link.remoteHash);
    if (local.deleted && remote.deleted) {
      add("ack", link, local, remote); continue;
    }
    if (!local.deleted && !remote.deleted && same(local.hash, remote.hash)) {
      if (localChanged || remoteChanged || link.remoteEtag !== remote.etag) add("ack", link, local, remote);
      continue;
    }
    if (localChanged && remoteChanged) {
      add("conflict", link, local, remote, "changed-on-both-sides");
    } else if (localChanged) {
      add(local.deleted ? "pushDelete" : "pushUpdate", link, local, remote);
    } else if (remoteChanged) {
      add(remote.deleted ? "pullDelete" : "pullUpdate", link, local, remote);
    }
  }
  for (const local of localRows) {
    if (linkedLocal.has(local.id) || local.deleted) continue;
    add(local.supported === false ? "conflict" : "pushCreate", null, local, null,
        local.supported === false ? "unsupported-event" : null);
  }
  for (const remote of remoteRows) {
    if (linkedRemote.has(remote.id) || remote.deleted) continue;
    add(remote.supported === false ? "conflict" : "pullCreate", null, null, remote,
        remote.supported === false ? "unsupported-event" : null);
  }
  return actions;
}

/**
 * Executes one durable outbox operation. Store must atomically persist the
 * complete action BEFORE any remote write and CAS the local revision when
 * applying incoming changes/acknowledging outgoing ones. Tokens, event payloads
 * and conflict contents must remain server-only. Never log them.
 *
 * store.assertActive checks lease, UID/family/role, connection generation and
 * enabled status. store.prepare returns the persisted operation (same contents
 * on a retry), not a new snapshot. store.ack must retain a newer local revision
 * as dirty; it may not mark that newer revision as synchronized.
 */
async function executeAction({connection, action, provider, store, codec}) {
  await store.assertActive(connection);
  if (action.type === "conflict") return store.conflict(connection, action, action.reason);
  if (action.type === "ack") return store.ack(connection, action, action.remote);
  if (action.type === "verifyRemoteMissing") {
    let remote;
    try {
      remote = await provider.getEvent(connection.calendarId, action.link.remoteId);
      return {status: "retry-read"}; // It exists; a fresh coherent pass is required.
    } catch (error) {
      if (error.code !== "not-found") throw error;
      remote = {id: action.link.remoteId, deleted: true, hash: "deleted", supported: true};
    }
    const next = planReconciliation({connectionId: connection.id, links: [action.link],
      localRows: [action.local], remoteRows: [remote]});
    return executeAction({connection, action: next[0], provider, store, codec});
  }
  if (action.type.startsWith("pull")) {
    await store.assertActive(connection);
    // applyIncoming must include marker + owner-only private detail + link in
    // one transaction, with revision/auth/lease rechecked within the transaction.
    return store.applyIncoming(connection, action);
  }
  const operation = await store.prepare(connection, action);
  if (operation.done) return {status: "already-acknowledged"};
  action = operation.action;
  await store.assertActive(connection);
  const remoteId = action.link?.remoteId;
  let current = action.remote;
  let encoded;
  if (action.type !== "pushCreate") {
    try {
      const read = await provider.getEvent(connection.calendarId, remoteId);
      current = {...read, ...codec.decode(read.raw)};
    } catch (error) {
      if (error.code !== "not-found") throw error;
      if (action.type === "pushDelete") return store.ack(connection, action, {id: remoteId, deleted: true, hash: "deleted"});
      return store.conflict(connection, action, "remote-deleted-during-write");
    }
    if (current.supported === false) return store.conflict(connection, action, "unsupported-event");
    if (action.type === "pushUpdate") {
      encoded = codec.encode(action.local.event, current.raw, action.link, action.operationId);
      if (!encoded.supported) return store.conflict(connection, action, encoded.reason || "unsupported-event");
    }
    // A retry after remote success + process death can acknowledge the exact
    // applied content without overwriting anything or duplicating an event.
    if (action.type === "pushUpdate" && same(current.hash, encoded.expectedHash || action.local.hash)) {
      return store.ack(connection, action, current);
    }
    if (current.etag !== action.remote?.etag) return store.conflict(connection, action, "remote-changed-during-write");
  }
  await store.assertActive(connection);
  let result;
  try {
    if (action.type === "pushDelete") {
      result = await provider.deleteEvent(connection.calendarId, remoteId, {etag: current.etag});
      result.hash = "deleted";
    } else {
      encoded ||= codec.encode(action.local.event, current?.raw, action.link, action.operationId);
      if (!encoded.supported) return store.conflict(connection, action, encoded.reason || "unsupported-event");
      result = action.type === "pushCreate" ?
        await provider.createEvent(connection.calendarId, {operationId: action.operationId, event: encoded.payload}) :
        await provider.updateEvent(connection.calendarId, remoteId, encoded.payload, {etag: current.etag});
      result = {...result, ...codec.decode(result.raw)};
      // Provider idempotent create may return a record edited elsewhere since
      // the first attempt. Keep that version for explicit reconciliation.
      if (result.supported === false || !same(result.hash, encoded.expectedHash || action.local.hash)) {
        return store.conflict(connection, {...action, remote: result}, "remote-result-differs");
      }
    }
  } catch (error) {
    if (error.code === "conflict") return store.conflict(connection, action, "remote-changed-during-write");
    throw error; // Outbox remains pending. Scheduler must honor Retry-After.
  }
  return store.ack(connection, action, result);
}

exports.planReconciliation = planReconciliation;
exports.executeAction = executeAction;
