/* eslint-disable max-len, require-jsdoc, valid-jsdoc */
"use strict";

const {randomUUID} = require("node:crypto");
const {AsyncLocalStorage} = require("node:async_hooks");
const {CalendarProviderError} = require("./providers");

function fail(code) {
  throw new CalendarProviderError(code);
}
class FirestoreOAuthStore {
  constructor({db, now = Date.now, leaseMs = 90000, setIntervalImpl = setInterval, clearIntervalImpl = clearInterval}) {
    this.db = db; this.now = now; this.leaseMs = leaseMs;
    this.setInterval = setIntervalImpl; this.clearInterval = clearIntervalImpl;
    this.context = new AsyncLocalStorage();
  }
  ref(id) {
    if (typeof id !== "string" || !id || id.includes("/")) fail("invalid-connection-id");
    return this.db.collection("calendar_sync_connections").doc(id);
  }
  stateRef(id) {
    if (typeof id !== "string" || !/^(?:(?:handoff|completion)_)?[a-f0-9]{64}$/.test(id)) fail("invalid-oauth-state");
    return this.db.collection("calendar_sync_states").doc(id);
  }
  async createState(id, record) {
    await this.stateRef(id).create({...record, consumed: false, ttlAt: new Date(record.expiresAt)});
  }
  async consumeState(id) {
    return this.db.runTransaction(async (tx) => {
      const ref = this.stateRef(id); const snapshot = await tx.get(ref);
      const row = snapshot.exists ? snapshot.data() : null;
      if (!row || row.consumed || row.expiresAt <= this.now()) return null;
      tx.update(ref, {consumed: true, secret: null, consumedAt: this.now()});
      return row;
    });
  }
  async getConnection(id) {
    const snapshot = await this.ref(id).get();
    return snapshot.exists ? snapshot.data() : null;
  }
  async putConnection(id, record) {
    const held = this.context.getStore();
    await this.db.runTransaction(async (tx) => {
      const ref = this.ref(id); const snapshot = await tx.get(ref);
      if (!snapshot.exists) {
        tx.create(ref, {...record, generation: 1, status: record.provider === "icloud" ? record.status : "awaiting_confirmation",
          pendingExpiresAt: record.provider === "icloud" ? null : this.now() + 15 * 60 * 1000});
        return;
      }
      const current = snapshot.data();
      this.checkLease(current, id, held);
      if (["disconnected", "revoked"].includes(current.status)) fail("reauthorization-required");
      if (record.uid !== current.uid || record.familyId !== current.familyId || record.provider !== current.provider) fail("forbidden");
      // Preserve live lease and authoritative generation even when caller's
      // snapshot predates a periodic lease renewal.
      tx.set(ref, {...record, generation: current.generation, _lease: current._lease});
    });
  }
  checkLease(record, id, held = this.context.getStore()) {
    if (!held || held.id !== id || held.lost || !record || record._lease?.owner !== held.owner ||
      record._lease.expiresAt <= this.now() || record.generation !== held.generation) fail("connection-lease-lost");
  }
  async assertLease(id, generation) {
    const current = await this.getConnection(id);
    this.checkLease(current, id);
    if (generation !== undefined && current.generation !== generation) fail("connection-generation-changed");
    return current;
  }
  async updateConnection(id, fields) {
    const current = await this.assertLease(id);
    await this.putConnection(id, {...current, ...fields, updatedAt: this.now()});
  }
  async disconnect(id, uid, familyId) {
    return this.withConnectionLock(id, async () => {
      const held = this.context.getStore();
      await this.db.runTransaction(async (tx) => {
        const ref = this.ref(id); const snapshot = await tx.get(ref);
        const row = snapshot.exists ? snapshot.data() : null;
        this.checkLease(row, id, held);
        if (row.uid !== uid || row.familyId !== familyId) fail("forbidden");
        tx.update(ref, {status: "disconnected", enabled: false, secret: null,
          generation: row.generation + 1, syncToken: null, pendingExpiresAt: null, updatedAt: this.now()});
      });
      held.generation++;
      return {status: "disconnected"};
    });
  }
  async expirePending() {
    const snapshot = await this.db.collection("calendar_sync_connections").where("pendingExpiresAt", ">", 0).where("pendingExpiresAt", "<=", this.now()).limit(200).get();
    let expired = 0;
    for (const doc of snapshot.docs) {
      // Missing/null fields never represent an expiring authorization.
      const candidate = doc.data();
      if (candidate.status !== "awaiting_confirmation" || typeof candidate.pendingExpiresAt !== "number") continue;
      try {
        await this.withConnectionLock(doc.id, async () => {
          const row = await this.assertLease(doc.id);
          if (row.status === "awaiting_confirmation" && row.pendingExpiresAt <= this.now()) {
            await this.disconnect(doc.id, row.uid, row.familyId);
            expired++;
          }
        });
      } catch (error) {
        if (error.code !== "connection-busy" && error.code !== "connection-lease-lost") throw error;
      }
    }
    return {expired};
  }
  async withConnectionLock(id, fn) {
    const existing = this.context.getStore();
    if (existing?.id === id) {
      await this.assertLease(id); return fn();
    }
    const owner = randomUUID();
    const held = await this.db.runTransaction(async (tx) => {
      const ref = this.ref(id); const snapshot = await tx.get(ref);
      if (!snapshot.exists) fail("connection-not-found");
      const row = snapshot.data();
      if (row._lease?.owner && row._lease.expiresAt > this.now()) fail("connection-busy");
      const generation = Number.isInteger(row.generation) ? row.generation : 1;
      tx.update(ref, {generation, _lease: {owner, expiresAt: this.now() + this.leaseMs}});
      return {id, owner, generation, lost: false};
    });
    let renewal = Promise.resolve();
    const timer = this.setInterval(() => {
      renewal = renewal.then(async () => {
        await this.db.runTransaction(async (tx) => {
          const ref = this.ref(id); const snapshot = await tx.get(ref);
          const row = snapshot.exists ? snapshot.data() : null;
          this.checkLease(row, id, held);
          tx.update(ref, {_lease: {owner, expiresAt: this.now() + this.leaseMs}});
        });
      }).catch(() => {
        held.lost = true;
      });
    }, Math.floor(this.leaseMs / 3));
    timer?.unref?.();
    try {
      return await this.context.run(held, async () => {
        const result = await fn();
        await renewal;
        await this.assertLease(id);
        return result;
      });
    } finally {
      this.clearInterval(timer);
      await renewal;
      await this.db.runTransaction(async (tx) => {
        const ref = this.ref(id); const snapshot = await tx.get(ref);
        if (snapshot.exists && snapshot.data()._lease?.owner === owner) tx.update(ref, {_lease: null});
      });
    }
  }
}

module.exports = {FirestoreOAuthStore};
