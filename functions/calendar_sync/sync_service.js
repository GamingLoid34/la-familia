/* eslint-disable max-len, require-jsdoc */
"use strict";
const {createHash, randomUUID} = require("node:crypto");
const {planReconciliation, executeAction} = require("./reconcile");
const defaultMapping = require("./event_mapping");
const {CalendarProviderError, createdEventIdentity} = require("./providers");
const LIMIT = 2000;
const key = (...parts) => createHash("sha256").update(JSON.stringify(parts)).digest("hex");
const clean = (value) => JSON.parse(JSON.stringify(value));
const fail = (code) => {
  throw new CalendarProviderError(code);
};
const stamp = (doc) => doc?.updateTime ? `${doc.updateTime.seconds}:${doc.updateTime.nanoseconds}` : key(doc?.exists ? doc.data() : null);
const version = (marker, detail) => key(stamp(marker), detail ? stamp(detail) : "");
const brief = (row) => row ? {...(row.event ? {title: row.event.title, date: row.event.date, time: row.event.time, endTime: row.event.endTime} : {}), deleted: row.deleted === true} : null;
function ownsLocal(data, connection, name) {
  if (data.familyId !== connection.familyId || data.isPending || data.source && data.source !== "manual") return false;
  if (data.visibility === "private") return data.privateOwnerUid === connection.uid && data.createdByUid === connection.uid;
  if ((data.createdByUid || data.createdBy) !== connection.uid) return false;
  if (Array.isArray(data.personUids) && data.personUids.length) return data.personUids.includes(connection.uid);
  if (Array.isArray(data.persons) && data.persons.length) return data.persons.includes(name);
  return true;
}
function createSyncService({db, runtime, now = Date.now, mapping = defaultMapping}) {
  const connRef = (id) => runtime.store.ref(id);
  const sub = (connection, collection) => connRef(connection.id).collection(collection);
  const linkRef = (connection, localId) => sub(connection, "links").doc(key(localId));
  const privateRef = (uid, id) => db.collection("private_activities").doc(uid).collection("events").doc(id);
  const markerRef = (id) => db.collection("planner_events").doc(id);
  function decode(connection, raw) {
    const result = mapping.toCanonical(connection.provider, raw);
    return result.supported ? {...result, hash: mapping.fingerprint(result.event)} : result;
  }
  function codec(connection, operationId) {
    return {
      decode: (raw) => decode(connection, raw),
      encode: (event, originalRaw, link) => {
        let remoteEvent = event;
        if (link?.privacyPolicy === "local-private" && originalRaw) {
          const existing = decode(connection, originalRaw);
          if (!existing.supported) return existing;
          remoteEvent = {...event, private: existing.event.private};
        }
        const result = mapping.fromCanonical(connection.provider, remoteEvent, {originalRaw, operationId});
        return result.supported ? {...result, expectedHash: mapping.fingerprint(remoteEvent)} : result;
      },
    };
  }
  async function assertActive(connection) {
    const fresh = await runtime.store.assertLease(connection.id, connection.generation);
    if (fresh.uid !== connection.uid || fresh.familyId !== connection.familyId || fresh.status !== "connected" || fresh.enabled !== true || fresh.calendarId !== connection.calendarId) fail("connection-not-active");
    if (!(await runtime.authorize(fresh.uid, fresh.familyId))) fail("forbidden");
    return fresh;
  }
  async function txAuthorize(tx, connection, selection = false) {
    const freshSnap = await tx.get(connRef(connection.id));
    const fresh = freshSnap.exists ? freshSnap.data() : null;
    runtime.store.checkLease(fresh, connection.id);
    if (!fresh || fresh.generation !== connection.generation || fresh.uid !== connection.uid || fresh.familyId !== connection.familyId || (selection ? !["authorized", "connected"].includes(fresh.status) : fresh.status !== "connected" || !fresh.enabled || fresh.calendarId !== connection.calendarId)) fail("connection-not-active");
    const userSnap = await tx.get(db.collection("users").doc(connection.uid));
    const user = userSnap.exists ? userSnap.data() : null;
    if (!user || !["parent", "admin", "youth"].includes(user.role) || user.familyId !== connection.familyId) fail("forbidden");
    const family = await tx.get(db.collection("families").doc(connection.familyId));
    const pilot = await tx.get(db.collection("config").doc("privateCalendarPilot20261030"));
    if (!family.exists || !pilot.exists || pilot.data().enabled !== true || pilot.data().contract !== "private-v1-20261030") fail("private-calendar-unavailable");
    return user;
  }
  function makeLocal(connection, marker, detail, user) {
    if (!marker?.exists) return null;
    const data = marker.data();
    const id = marker.id;
    const revision = version(marker, detail);
    if (!ownsLocal(data, connection, user.name || "")) return {id, revision, supported: false, reason: "local-no-longer-owned"};
    let merged = data;
    if (data.visibility === "private") {
      const privateData = detail?.exists ? detail.data() : null;
      if (!privateData || privateData.ownerUid !== connection.uid || privateData.familyId !== connection.familyId) return {id, revision, supported: false, reason: "private-details-missing"};
      merged = {...data, private: true};
      for (const field of ["title", "piktogram", "checklist", "lessonPrep", "description", "calendarDescription", "location"]) {
        delete merged[field];
        if (Object.hasOwn(privateData, field)) merged[field] = privateData[field];
      }
    }
    try {
      const event = mapping.canonical(merged);
      return {id, revision, supported: true, event, hash: mapping.fingerprint(event), deleted: false};
    } catch (_) {
      return {id, revision, supported: false, reason: "unsupported-local-event"};
    }
  }
  async function txLocal(tx, connection, id, user) {
    const marker = await tx.get(markerRef(id));
    const detail = marker.exists && marker.data().visibility === "private" ? await tx.get(privateRef(connection.uid, id)) : null;
    return {marker, detail, row: makeLocal(connection, marker, detail, user)};
  }
  async function readLocal(connection, links) {
    return db.runTransaction(async (tx) => {
      const user = await txAuthorize(tx, connection);
      const all = await tx.get(db.collection("planner_events").where("familyId", "==", connection.familyId).limit(LIMIT + 1));
      if (all.size > LIMIT) fail("too-many-local-events");
      const linked = new Set(links.map((l) => l.localId));
      const rows = [];
      for (const doc of all.docs) {
        if (!linked.has(doc.id) && (doc.id.startsWith("sync_") || !ownsLocal(doc.data(), connection, user.name || ""))) continue;
        const detail = doc.data().visibility === "private" ? await tx.get(privateRef(connection.uid, doc.id)) : null;
        rows.push(makeLocal(connection, doc, detail, user));
      }
      const tombstones = await tx.get(sub(connection, "tombstones").limit(LIMIT + 1));
      if (tombstones.size > LIMIT) fail("too-many-local-events");
      const present = new Set(rows.map((row) => row.id));
      for (const doc of tombstones.docs) {
        const data = doc.data();
        if (!present.has(data.localId)) rows.push({id: data.localId, deleted: true, supported: true, hash: "deleted", revision: data.revision});
      }
      return rows;
    });
  }
  function linkData(connection, action, local, remote, extra = {}) {
    return clean({...action.link, localId: local.id, remoteId: remote.id, localHash: local.hash || null, remoteHash: remote.hash || null,
      localDeleted: !!local.deleted, remoteDeleted: !!remote.deleted, remoteEtag: remote.etag || null,
      localRevision: local.revision || null, updatedAt: now(), ...extra});
  }
  async function conflict(connection, action, reason) {
    const id = key(action.link?.localId || action.local?.id || null, action.link?.remoteId || action.remote?.id || null);
    await db.runTransaction(async (tx) => {
      await txAuthorize(tx, connection);
      const ref = sub(connection, "conflicts").doc(id);
      const existing = await tx.get(ref);
      tx.set(ref, clean({id, status: "open", reason, createdAt: existing.exists ? existing.data().createdAt : now(), updatedAt: now(), action}));
      if (action.operationId) tx.set(sub(connection, "outbox").doc(action.operationId), {status: "conflict", updatedAt: now()}, {merge: true});
      if (!action.link && action.local?.id && action.remote?.id) {
        tx.set(linkRef(connection, action.local.id), {localId: action.local.id, remoteId: action.remote.id, localHash: null, remoteHash: null, localDeleted: false, remoteDeleted: false, remoteEtag: action.remote.etag || null, updatedAt: now()});
      }
    });
    return {status: "conflict", id, reason};
  }
  async function ack(connection, action, remote) {
    return db.runTransaction(async (tx) => {
      const user = await txAuthorize(tx, connection);
      const localId = action.link?.localId || action.local?.id;
      const current = await txLocal(tx, connection, localId, user);
      const expected = action.local;
      // Store the acknowledged old revision, never silently acknowledge a newer
      // user edit made while the external request was in flight.
      const local = expected || current.row;
      if (!local) fail("local-row-missing");
      const conflictRef = sub(connection, "conflicts").doc(key(localId, remote.id));
      const oldConflict = await tx.get(conflictRef);
      if (oldConflict.exists) tx.update(conflictRef, {status: "resolved", resolution: "reconciled", updatedAt: now()});
      tx.set(linkRef(connection, localId), linkData(connection, action, {...local, id: localId}, remote));
      if (action.operationId) tx.set(sub(connection, "outbox").doc(action.operationId), {status: "done", updatedAt: now()}, {merge: true});
      return {status: current.row && current.row.revision !== expected?.revision ? "acknowledged-newer-local-pending" : "acknowledged"};
    });
  }
  async function applyIncoming(connection, action) {
    return db.runTransaction(async (tx) => {
      const user = await txAuthorize(tx, connection);
      const id = action.link?.localId || `sync_${key(connection.id, action.remote.id)}`;
      const current = await txLocal(tx, connection, id, user);
      const previousLink = await tx.get(linkRef(connection, id));
      const tomb = await tx.get(sub(connection, "tombstones").doc(key(id)));
      if (action.type === "pullCreate" && previousLink.exists) return {status: "already-applied"};
      const matches = action.local?.deleted ? !current.marker.exists && tomb.exists && tomb.data().revision === action.local.revision :
        action.local ? current.row?.revision === action.local.revision : !current.marker.exists;
      if (!matches || current.row?.supported === false) {
        const conflictId = key(id, action.remote.id);
        tx.set(sub(connection, "conflicts").doc(conflictId), clean({id: conflictId, status: "open", reason: "local-changed-during-write", createdAt: now(), updatedAt: now(), action}));
        return {status: "conflict", id: conflictId};
      }
      if (action.type === "pullDelete") {
        if (current.marker.exists) tx.delete(markerRef(id));
        if (current.detail?.exists) tx.delete(privateRef(connection.uid, id));
        tx.set(linkRef(connection, id), linkData(connection, action, {id, deleted: true, hash: "deleted", revision: action.local?.revision}, action.remote));
        tx.set(sub(connection, "tombstones").doc(key(id)), {localId: id, revision: `remote_${key(action.remote.id, action.remote.etag || "deleted")}`, source: "remote", createdAt: now()});
        return {status: "deleted-locally"};
      }
      const remoteEvent = mapping.canonical(action.remote.event);
      const privacyPolicy = action.link?.privacyPolicy || (action.type === "pullCreate" ? "local-private" : null);
      const forcePrivate = privacyPolicy === "local-private" || remoteEvent.private;
      const localEvent = {...remoteEvent, private: forcePrivate};
      const times = {date: localEvent.date, time: localEvent.time, endTime: localEvent.endTime,
        ...(localEvent.timeMode === "allDay" ? {timeMode: "allDay"} : {}), isRecurring: !!localEvent.recurrence,
        ...(localEvent.recurrence ? {recurrence: localEvent.recurrence} : {})};
      if (forcePrivate) {
        const oldDetail = current.detail?.exists ? current.detail.data() : {};
        tx.set(markerRef(id), {familyId: connection.familyId, createdByUid: connection.uid, createdBy: connection.uid,
          visibility: "private", privateOwnerUid: connection.uid, title: "Privat", piktogram: "🔒", type: "activity", source: "manual", isPending: false,
          personUids: [connection.uid], persons: [user.name || ""], ...times});
        // Preserve checklist/preparation and other owner-only fields on edits.
        tx.set(privateRef(connection.uid, id), {...oldDetail, ownerUid: connection.uid, familyId: connection.familyId,
          title: localEvent.title, description: localEvent.description, calendarDescription: localEvent.description, location: localEvent.location,
          piktogram: oldDetail.piktogram || "📅", checklist: oldDetail.checklist || current.marker.data()?.checklist || [],
          ...(oldDetail.lessonPrep || current.marker.data()?.lessonPrep ? {lessonPrep: oldDetail.lessonPrep || current.marker.data().lessonPrep} : {})});
      } else {
        // A pull cannot declassify an existing private activity implicitly.
        if (current.marker.exists && current.marker.data().visibility === "private") fail("private-to-family-requires-confirmation");
        const old = current.marker.exists ? current.marker.data() : {};
        const updated = {...old, ...times, title: localEvent.title, description: localEvent.description, calendarDescription: localEvent.description, location: localEvent.location};
        if (!localEvent.recurrence) delete updated.recurrence;
        if (localEvent.timeMode !== "allDay") delete updated.timeMode;
        tx.set(markerRef(id), updated);
      }
      // Revision is intentionally absent until the next read; hashes define the
      // baseline. Local/private and remote/public use separate semantic hashes.
      tx.set(linkRef(connection, id), linkData(connection, action, {id, hash: mapping.fingerprint(localEvent)}, action.remote, {privacyPolicy}));
      return {status: "applied"};
    });
  }
  const actionStore = {
    assertActive, ack, conflict, applyIncoming,
    prepare: async (connection, action) => db.runTransaction(async (tx) => {
      const user = await txAuthorize(tx, connection);
      const ref = sub(connection, "outbox").doc(action.operationId);
      const existing = await tx.get(ref);
      const intended = existing.exists && existing.data().action ? existing.data().action : action;
      const localId = intended.link?.localId || intended.local?.id;
      const current = await txLocal(tx, connection, localId, user);
      const tomb = await tx.get(sub(connection, "tombstones").doc(key(localId)));
      const deletionMatches = intended.local?.deleted && !current.marker.exists && tomb.exists && tomb.data().revision === intended.local.revision;
      const validCurrent = deletionMatches || current.row?.supported === true;
      const revisionMatches = deletionMatches || current.row?.revision === intended.local?.revision;
      if (!validCurrent || (!existing.exists && !revisionMatches)) {
        const conflictId = key(localId, intended.link?.remoteId || intended.remote?.id || null);
        const ambiguousCreate = existing.exists && intended.type === "pushCreate" && !validCurrent;
        tx.set(sub(connection, "conflicts").doc(conflictId), clean({id: conflictId, status: "open", reason: ambiguousCreate ? "ambiguous-create-outcome" : "local-changed-before-write", createdAt: now(), updatedAt: now(), action: intended}));
        // A new create has a stable operation ID; don't poison it before any
        // remote request was sent. A future fresh local edit can use that ID.
        if (existing.exists) tx.update(ref, {status: ambiguousCreate ? "quarantined" : "conflict", updatedAt: now()});
        return {done: true, action: intended};
      }
      if (existing.exists) return {done: existing.data().status !== "pending", action: intended};
      tx.set(ref, clean({status: "pending", action, createdAt: now(), updatedAt: now()}));
      return {action, done: false};
    }),
  };
  async function owned(connectionId, uid) {
    const raw = await runtime.store.getConnection(connectionId);
    if (!raw || raw.uid !== uid || !(await runtime.authorize(uid, raw.familyId))) fail("forbidden");
    return {...raw, id: connectionId};
  }
  async function execute(connection, action, provider) {
    return executeAction({connection, action, provider, store: actionStore, codec: codec(connection, action.operationId)});
  }
  async function syncPass(connectionId) {
    return runtime.store.withConnectionLock(connectionId, async () => {
      const connection = {...await runtime.store.assertLease(connectionId), id: connectionId};
      await assertActive(connection);
      if (connection.retryAfterAt && connection.retryAfterAt > now()) fail("retry-later");
      const provider = await runtime.getProvider(connection);
      try {
        const assertNoQuarantine = async () => {
          const blocked = await sub(connection, "outbox").where("status", "==", "quarantined").limit(1).get();
          if (blocked.size) fail("ambiguous-create-outcome");
        };
        await assertNoQuarantine();
        const pending = await sub(connection, "outbox").where("status", "==", "pending").limit(100).get();
        for (const doc of pending.docs) {
          await execute(connection, doc.data().action, provider);
          // A remote create might have succeeded before a process died. If the
          // local event was then deleted, never import that unlinked result as
          // a new private activity. Quarantine survives all later worker runs.
          await assertNoQuarantine();
        }
        let listed;
        try {
          listed = await provider.listEvents(connection.calendarId, {syncToken: connection.remoteCacheGeneration ? connection.syncToken || null : null});
        } catch (error) {
          if (error.code !== "sync-reset-required") throw error;
          listed = await provider.listEvents(connection.calendarId, {syncToken: null});
        }
        if (!listed || !Array.isArray(listed.items) || listed.items.length > 10000 || new Set(listed.items.map((item) => item.id)).size !== listed.items.length) fail("invalid-provider-list");
        const linksSnap = await sub(connection, "links").limit(LIMIT + 1).get();
        if (linksSnap.size > LIMIT) fail("too-many-linked-events");
        const links = linksSnap.docs.map((d) => d.data());
        const previousCache = connection.remoteCacheGeneration ? await sub(connection, "remotes").where("generation", "==", connection.remoteCacheGeneration).limit(10001).get() : null;
        if (previousCache?.size > 10000) fail("too-many-events");
        if (!listed.full && !connection.remoteCacheGeneration) fail("incomplete-provider-snapshot");
        const cacheGeneration = listed.full ? randomUUID() : connection.remoteCacheGeneration;
        const changed = listed.items.map((item) => ({...item, ...(item.deleted ? {deleted: true, hash: "deleted", supported: true} : decode(connection, item.raw))}));
        const oldRows = (previousCache?.docs || []).map((d) => d.data().row);
        const complete = new Map((listed.full ? [] : oldRows).map((row) => [row.id, row]));
        for (const row of changed) complete.set(row.id, row);
        // A master that has ever had unsupported exceptions stays read-only;
        // a later full feed can omit a cancelled child, which is not proof that
        // the exception was removed from the actual series.
        const exceptionalMasters = new Set([...complete.values(), ...oldRows].flatMap((row) => [
          ...(row.raw?.recurringEventId ? [row.raw.recurringEventId] : []),
          ...(row.seriesHasExceptions ? [row.id] : []),
        ]));
        const toPersist = new Map(changed.map((row) => [row.id, row]));
        for (const id of exceptionalMasters) {
          const master = complete.get(id);
          if (master) {
            const blocked = {...master, supported: false, reason: "series-has-exceptions", seriesHasExceptions: true};
            complete.set(id, blocked);
            toPersist.set(id, blocked);
          }
        }
        const records = [...toPersist.values()];
        for (let start = 0; start < records.length; start += 300) {
          await assertActive(connection);
          const batch = db.batch();
          for (const row of records.slice(start, start + 300)) batch.set(sub(connection, "remotes").doc(key(cacheGeneration, row.id)), clean({row, generation: cacheGeneration}));
          await batch.commit();
        }
        const ignoredSnap = await sub(connection, "ignored").get();
        const ignored = ignoredSnap.docs.map((d) => d.data());
        const ignoredLocals = new Set(ignored.map((r) => r.localId).filter(Boolean));
        const ignoredRemotes = new Set(ignored.map((r) => r.remoteId).filter(Boolean));
        const localRows = (await readLocal(connection, links)).filter((r) => !ignoredLocals.has(r.id));
        const remoteRows = [...complete.values()].filter((r) => !ignoredRemotes.has(r.id));
        const plan = planReconciliation({connectionId, links: links.filter((l) => !ignoredLocals.has(l.localId) && !ignoredRemotes.has(l.remoteId)), localRows, remoteRows, remoteComplete: listed.full === true || !!connection.fullSnapshotAt});
        const counts = {applied: 0, conflicts: 0};
        for (const action of plan) {
          const result = await execute(connection, action, provider);
          if (result.status === "conflict") counts.conflicts++; else counts.applied++;
        }
        await assertActive(connection);
        const conflicts = await sub(connection, "conflicts").where("status", "==", "open").get();
        await runtime.store.updateConnection(connectionId, {syncToken: listed.syncToken || null, remoteCacheGeneration: cacheGeneration, fullSnapshotAt: listed.full ? now() : connection.fullSnapshotAt || null,
          lastSyncAt: now(), lastError: null, retryAfterAt: null, conflictCount: conflicts.size});
        // Only after the new generation is committed may superseded cached
        // snapshots be removed. A crash before this cleanup cannot resurrect them.
        if (listed.full && previousCache?.size) {
          for (let start = 0; start < previousCache.docs.length; start += 300) {
            const batch = db.batch();
            for (const old of previousCache.docs.slice(start, start + 300)) batch.delete(sub(connection, "remotes").doc(old.id));
            await batch.commit();
          }
        }
        return {...counts, conflictCount: conflicts.size, lastSyncAt: now()};
      } catch (error) {
        const safeCode = typeof error.code === "string" && /^[a-z-]{1,60}$/.test(error.code) ? error.code : "sync-failed";
        try {
          const conflicts = await sub(connection, "conflicts").where("status", "==", "open").get();
          await runtime.store.updateConnection(connectionId, {lastError: safeCode, conflictCount: conflicts.size, retryAfterAt: now() + Math.max(error.retryAfter || 60, 60) * 1000});
        } catch (_) {/* Lease loss must not be masked by status reporting. */}
        throw error;
      }
    });
  }
  async function selectCalendar({uid, connectionId, calendarId}) {
    await owned(connectionId, uid);
    return runtime.store.withConnectionLock(connectionId, async () => {
      const connection = {...await runtime.store.assertLease(connectionId), id: connectionId};
      if (!["authorized", "connected"].includes(connection.status)) fail("reauthorization-required");
      if (connection.calendarId && connection.calendarId !== calendarId) fail("disconnect-before-changing-calendar");
      const provider = await runtime.getProvider(connection);
      const calendars = await provider.listCalendars();
      const selected = calendars.find((c) => c.id === calendarId);
      if (!selected?.writable) fail("calendar-not-writable");
      // Read probe before enabling: no calendar data is written during selection.
      await provider.listEvents(calendarId, {syncToken: null});
      await db.runTransaction(async (tx) => {
        await txAuthorize(tx, connection, true);
        const others = await tx.get(db.collection("calendar_sync_connections").where("uid", "==", connection.uid).limit(101));
        if (others.size > 100) fail("too-many-connections");
        if (others.docs.some((doc) => doc.id !== connectionId && doc.data().familyId === connection.familyId && doc.data().provider === connection.provider && doc.data().calendarId === calendarId && doc.data().status === "connected" && doc.data().enabled === true)) fail("calendar-already-connected");
        tx.update(connRef(connectionId), {calendarId, calendarName: selected.name || "Kalender", status: "connected", enabled: true, syncToken: null, fullSnapshotAt: null, lastError: null, retryAfterAt: null, updatedAt: now()});
      });
      return {status: "connected", calendarId, calendarName: selected.name || "Kalender"};
    });
  }
  async function syncNow({uid, connectionId}) {
    await owned(connectionId, uid);
    return syncPass(connectionId);
  }
  async function getConflicts({uid, connectionId}) {
    const connection = await owned(connectionId, uid);
    const snapshot = await sub(connection, "conflicts").where("status", "==", "open").limit(201).get();
    return {truncated: snapshot.size > 200, conflicts: snapshot.docs.slice(0, 200).map((doc) => {
      const value = doc.data();
      return {id: doc.id, reason: value.reason, createdAt: value.createdAt, local: brief(value.action.local), remote: brief(value.action.remote),
        resolvable: value.action.local?.supported !== false && value.action.remote?.supported !== false && !!value.action.link};
    })};
  }
  async function resolveConflict({uid, connectionId, conflictId, choice}) {
    await owned(connectionId, uid);
    if (!["keepLocal", "keepRemote", "skip"].includes(choice)) fail("invalid-conflict-choice");
    return runtime.store.withConnectionLock(connectionId, async () => {
      const connection = {...await runtime.store.assertLease(connectionId), id: connectionId};
      await assertActive(connection);
      const ref = sub(connection, "conflicts").doc(conflictId);
      const doc = await ref.get();
      if (!doc.exists || doc.data().status !== "open") fail("conflict-not-found");
      const action = doc.data().action;
      if (choice === "skip") {
        let remoteId = action.link?.remoteId || action.remote?.id || null;
        const quarantined = doc.data().reason === "ambiguous-create-outcome";
        if (quarantined) {
          const identity = createdEventIdentity(connection.provider, connection.calendarId, action.operationId);
          if (identity.id) remoteId = identity.id;
          else {
            // Outlook's ID is assigned remotely. A complete read must locate
            // the immutable create transaction ID; absence does not prove that
            // a timed-out create cannot still appear later.
            const provider = await runtime.getProvider(connection);
            const listed = await provider.listEvents(connection.calendarId, {syncToken: null});
            if (!listed?.full || !Array.isArray(listed.items)) fail("ambiguous-create-outcome");
            const matches = listed.items.filter((item) => item.raw?.transactionId === identity.transactionId);
            if (matches.length !== 1 || !matches[0].id) fail("ambiguous-create-outcome");
            remoteId = matches[0].id;
          }
        }
        await db.runTransaction(async (tx) => {
          await txAuthorize(tx, connection);
          const fresh = await tx.get(ref);
          if (!fresh.exists || fresh.data().status !== "open" || fresh.data().action.operationId !== action.operationId) fail("conflict-changed-refresh-required");
          const blockedRef = sub(connection, "outbox").doc(action.operationId);
          const blocked = quarantined ? await tx.get(blockedRef) : null;
          if (quarantined && (!blocked.exists || blocked.data().status !== "quarantined")) fail("conflict-changed-refresh-required");
          tx.set(sub(connection, "ignored").doc(conflictId), clean({localId: action.link?.localId || action.local?.id || null, remoteId,
            ...(quarantined ? {operationId: action.operationId, quarantinedOutcome: true} : {}), createdAt: now()}));
          if (quarantined) tx.update(blockedRef, {status: "ignored", updatedAt: now()});
          tx.update(ref, {status: "resolved", resolution: choice, updatedAt: now()});
          tx.update(connRef(connectionId), {retryAfterAt: null, lastError: null});
        });
        return {status: "resolved"};
      }
      if (!action.link || action.local?.supported === false || action.remote?.supported === false) fail("unsupported-conflict-resolution");
      const provider = await runtime.getProvider(connection);
      const locals = await readLocal(connection, [action.link]);
      const local = locals.find((r) => r.id === action.link.localId);
      let remote;
      try {
        const item = await provider.getEvent(connection.calendarId, action.link.remoteId);
        remote = {...item, ...decode(connection, item.raw)};
      } catch (error) {
        if (error.code !== "not-found") throw error;
        remote = {id: action.link.remoteId, deleted: true, supported: true, hash: "deleted"};
      }
      if (!local || local.revision !== action.local?.revision || remote.etag !== action.remote?.etag || remote.hash !== action.remote?.hash) fail("conflict-changed-refresh-required");
      const type = choice === "keepLocal" ? local.deleted ? "pushDelete" : "pushUpdate" : remote.deleted ? "pullDelete" : "pullUpdate";
      const chosen = {...action, type, local, remote, operationId: key(connectionId, "resolve", conflictId, choice, local.revision, remote.etag || remote.hash)};
      const result = await execute(connection, chosen, provider);
      if (result.status !== "conflict") await ref.update({status: "resolved", resolution: choice, updatedAt: now()});
      return result;
    });
  }
  async function captureEventDeletion({id, data, eventId}) {
    if (!id || !data?.familyId) return {captured: 0};
    const connections = await db.collection("calendar_sync_connections").where("familyId", "==", data.familyId).limit(101).get();
    if (connections.size > 100) fail("too-many-connections");
    let captured = 0;
    for (const doc of connections.docs) {
      const connection = {...doc.data(), id: doc.id};
      if (!connection.enabled || connection.status !== "connected") continue;
      await db.runTransaction(async (tx) => {
        const link = await tx.get(linkRef(connection, id));
        const current = await tx.get(markerRef(id));
        if (!link.exists || link.data().localDeleted || link.data().remoteDeleted || current.exists) return;
        if (data.visibility === "private" && data.privateOwnerUid !== connection.uid) return;
        // The Firestore deletion event is the explicit durable signal; missing
        // rows discovered by a sync read never cause this write.
        tx.set(sub(connection, "tombstones").doc(key(id)), {localId: id, revision: key(eventId || "delete", id, stamp(doc)), source: "user-delete", createdAt: now()});
        captured++;
      });
    }
    return {captured};
  }
  async function scheduled() {
    const connections = await db.collection("calendar_sync_connections").where("status", "==", "connected").limit(100).get();
    const results = [];
    for (const doc of connections.docs) {
      if (!doc.data().enabled || doc.data().retryAfterAt > now()) continue;
      try {
        results.push({id: doc.id, ...await syncPass(doc.id)});
      } catch (error) {
        results.push({id: doc.id, status: "failed", code: typeof error.code === "string" ? error.code : "sync-failed"});
      }
    }
    return results;
  }
  return {selectCalendar, syncNow, getConflicts, resolveConflict, scheduled, captureEventDeletion, syncPass,
    _test: {actionStore, readLocal, codec, ownsLocal, makeLocal, version}};
}
module.exports = {createSyncService, _test: {ownsLocal, version}};
