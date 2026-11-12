'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {FirestoreOAuthStore} = require('../calendar_sync/firestore_store');
const {createCalendarRuntime, CALLBACK_URL, parseProviderConfig} = require('../calendar_sync/runtime');
const {SCOPES} = require('../calendar_sync/oauth');

const codeIs = (code) => (error) => {assert.equal(error.code, code); return true;};
class FakeDb {
  constructor(seed = {}) {this.rows = new Map(Object.entries(seed)); this.queue = Promise.resolve();}
  collection(name) {
    const db = this;
    const query = (filters = [], max = Infinity) => ({
      where(field, op, value) {assert.ok(['==', '<=', '>'].includes(op)); return query([...filters, [field, value, op]], max);},
      limit(value) {return query(filters, value);},
      async get() {
        const docs = [...db.rows].filter(([path, value]) => path.startsWith(`${name}/`) && path.split('/').length === name.split('/').length + 1 && filters.every(([f, v, op]) => op === '==' ? value[f] === v : typeof value[f] === 'number' && (op === '>' ? value[f] > v : value[f] <= v)))
          .slice(0, max).map(([path]) => db.snapshot(path));
        return {docs, size: docs.length};
      },
      doc(id) {
        const path = `${name}/${id}`;
        return {path, id, get: async () => db.snapshot(path),
          create: async (value) => db.runTransaction(async (tx) => {tx.create({path}, value);})};
      },
    });
    return query();
  }
  snapshot(path) {return {id: path.split('/').at(-1), exists: this.rows.has(path), data: () => structuredClone(this.rows.get(path))};}
  async runTransaction(fn) {
    const previous = this.queue; let release; this.queue = new Promise((resolve) => {release = resolve;}); await previous;
    const writes = [];
    const tx = {get: async (ref) => this.snapshot(ref.path),
      create: (ref, value) => {assert.equal(this.rows.has(ref.path), false); writes.push([ref.path, value]);},
      update: (ref, value) => {assert.equal(this.rows.has(ref.path), true); writes.push([ref.path, {...this.rows.get(ref.path), ...value}]);},
      set: (ref, value) => writes.push([ref.path, value])};
    try {const result = await fn(tx); for (const [path, value] of writes) this.rows.set(path, structuredClone(value)); return result;} finally {release();}
  }
}
const seed = () => ({'users/user': {familyId: 'family', role: 'parent', name: 'Test'}, 'users/other': {familyId: 'family', role: 'youth'},
  'families/family': {}, 'config/privateCalendarPilot20261030': {enabled: true, contract: 'private-v1-20261030'}});
function harness() {
  const db = new FakeDb(seed()); const responses = []; const calls = [];
  const config = {encryptionKey: Buffer.alloc(32, 7), availability: {google: true, outlook: false, icloud: true},
    providers: {google: {clientId: 'placeholder', clientSecret: 'placeholder', redirectUri: CALLBACK_URL}}};
  const runtime = createCalendarRuntime({db, config, fetchImpl: async (url, options) => {
    calls.push({url, ...options}); assert.ok(responses.length);
    const r = responses.shift(); return new Response(typeof r.body === 'object' ? JSON.stringify(r.body) : r.body ?? null, {status: r.status || 200, headers: r.headers || {}});
  }});
  async function callback() {
    const start = await runtime.start('user', {provider: 'google'});
    const ticket = new URL(start.url).searchParams.get('ticket');
    const handoff = await runtime.openHandoff(ticket);
    const state = new URL(handoff.authorizationUrl).searchParams.get('state');
    responses.push({body: {token_type: 'Bearer', access_token: 'test-access', refresh_token: 'test-refresh', expires_in: 3600, scope: SCOPES.google.join(' ')}});
    const returned = await runtime.callback({state, code: 'test-code'}, handoff.browserBinding);
    return new URLSearchParams(returned.url.split('?')[1]).get('ticket');
  }
  return {db, runtime, responses, calls, config, callback};
}

test('Firestore OAuth state is consumed exactly once and expires synchronously', async () => {
  const db = new FakeDb(); let time = 1000;
  const store = new FirestoreOAuthStore({db, now: () => time}); const key = 'a'.repeat(64);
  await store.createState(key, {expiresAt: 2000, secret: {ciphertext: 'test'}});
  const result = await Promise.all([store.consumeState(key), store.consumeState(key)]);
  assert.equal(result.filter(Boolean).length, 1);
  assert.equal(db.rows.get(`calendar_sync_states/${key}`).secret, null);
  const second = 'b'.repeat(64); await store.createState(second, {expiresAt: 2000}); time = 3000;
  assert.equal(await store.consumeState(second), null);
});
test('distributed lease prevents another process, supports nested token refresh and releases', async () => {
  const db = new FakeDb({'calendar_sync_connections/c': {uid: 'u', familyId: 'f', provider: 'google', status: 'authorized', generation: 1}});
  const first = new FirestoreOAuthStore({db}); const second = new FirestoreOAuthStore({db});
  await first.withConnectionLock('c', async () => {
    await assert.rejects(second.withConnectionLock('c', async () => assert.fail()), codeIs('connection-busy'));
    await first.withConnectionLock('c', async () => {await first.updateConnection('c', {lastError: null});});
    assert.equal((await first.assertLease('c', 1)).status, 'authorized');
  });
  assert.equal(db.rows.get('calendar_sync_connections/c')._lease, null);
  await second.withConnectionLock('c', async () => {assert.equal((await second.assertLease('c')).generation, 1);});
});
test('generation change or lease loss stops credential writes', async () => {
  const db = new FakeDb({'calendar_sync_connections/c': {uid: 'u', familyId: 'f', provider: 'google', status: 'authorized', generation: 1}});
  const store = new FirestoreOAuthStore({db});
  await assert.rejects(store.withConnectionLock('c', async () => {
    const row = db.rows.get('calendar_sync_connections/c'); row.generation = 2;
    await store.updateConnection('c', {secret: 'must-not-write'});
  }), codeIs('connection-lease-lost'));
  assert.equal(db.rows.get('calendar_sync_connections/c').secret, undefined);
});
test('lease renews while held and stale worker cannot continue after expiry', async () => {
  const db = new FakeDb({'calendar_sync_connections/c': {uid: 'u', familyId: 'f', provider: 'google', status: 'authorized', generation: 1}});
  let time = 1000; let tick;
  const store = new FirestoreOAuthStore({db, now: () => time, leaseMs: 9000, setIntervalImpl: (fn) => {tick = fn; return 1;}, clearIntervalImpl: () => {}});
  await store.withConnectionLock('c', async () => {
    time = 5000; tick(); await new Promise((resolve) => setImmediate(resolve));
    assert.equal(db.rows.get('calendar_sync_connections/c')._lease.expiresAt, 14000);
  });
  await assert.rejects(store.withConnectionLock('c', async () => {time += 10000; await store.assertLease('c');}), codeIs('connection-lease-lost'));
});
test('disconnect increments generation, erases credentials and retains external mapping data', async () => {
  const db = new FakeDb({'calendar_sync_connections/c': {uid: 'u', familyId: 'f', provider: 'google', status: 'connected', generation: 4, secret: {ciphertext: 'encrypted'}, calendarId: 'remote', syncToken: 'token'}});
  const store = new FirestoreOAuthStore({db});
  await store.disconnect('c', 'u', 'f'); const row = db.rows.get('calendar_sync_connections/c');
  assert.equal(row.status, 'disconnected'); assert.equal(row.secret, null); assert.equal(row.generation, 5);
  assert.equal(row.calendarId, 'remote'); assert.equal(row.syncToken, null);
});
test('runtime refuses children, absent family, wrong member and disabled private contract', async () => {
  const h = harness(); h.db.rows.set('users/child', {familyId: 'family', role: 'child'});
  await assert.rejects(h.runtime.start('child', {provider: 'google'}), codeIs('forbidden'));
  assert.equal(await h.runtime.authorize('user', 'other-family'), false);
  h.db.rows.get('config/privateCalendarPilot20261030').enabled = false;
  await assert.rejects(h.runtime.start('user', {provider: 'google'}), codeIs('forbidden'));
  assert.equal(h.calls.length, 0);
});
test('callback leaves a shared-handoff account inaccessible until authenticated confirmation', async () => {
  const h = harness(); const ticket = await h.callback();
  const doc = [...h.db.rows].find(([path]) => path.startsWith('calendar_sync_connections/'));
  const id = doc[0].split('/').at(-1); assert.equal(doc[1].status, 'awaiting_confirmation');
  assert.equal((await h.runtime.list('user')).connections.length, 0);
  await assert.rejects(h.runtime.getProvider({id, ...doc[1]}), codeIs('reauthorization-required'));
  await assert.rejects(h.runtime.finish('other', {ticket}), codeIs('forbidden'));
  assert.equal(h.calls.length, 1); assert.equal(doc[1].status, 'awaiting_confirmation');
});
test('same authenticated account can finish once, probe calendars and then choose selection', async () => {
  const h = harness(); const ticket = await h.callback();
  h.responses.push({body: {items: [{id: 'primary', summary: 'My calendar', accessRole: 'owner'}]}});
  const result = await h.runtime.finish('user', {ticket});
  assert.equal(result.status, 'authorized'); assert.equal(result.calendars[0].writable, true);
  const list = await h.runtime.list('user'); assert.equal(list.connections.length, 1);
  assert.equal(list.connections[0].calendars[0].id, 'primary');
  assert.doesNotMatch(JSON.stringify(list), /test-access|test-refresh|ciphertext|Authorization/);
  await assert.rejects(h.runtime.finish('user', {ticket}), codeIs('forbidden'));
});
test('handoff is short-lived, one-use and contains no Firebase ID token', async () => {
  const h = harness(); const start = await h.runtime.start('user', {provider: 'google'});
  assert.match(start.url, /calendarOAuthStart\?ticket=/); assert.doesNotMatch(start.url, /id_token|access_token/);
  const ticket = new URL(start.url).searchParams.get('ticket'); await h.runtime.openHandoff(ticket);
  await assert.rejects(h.runtime.openHandoff(ticket), codeIs('invalid-oauth-state'));
});
test('public readiness works without secret bindings and is conservative by default', async () => {
  const db = new FakeDb(seed());
  const runtime = createCalendarRuntime({db});
  assert.equal((await runtime.list('user')).providers.every((p) => p.configured === false), true);
  await assert.rejects(runtime.start('user', {provider: 'google'}), codeIs('provider-not-configured'));
  const publicReady = createCalendarRuntime({db, config: {availability: {google: true}}});
  assert.equal((await publicReady.list('user')).providers.find((p) => p.provider === 'google').configured, true);
  await assert.rejects(publicReady.start('user', {provider: 'google'}), codeIs('provider-not-configured'));
});

test('abandoned OAuth confirmations erase credentials after expiry without touching active accounts', async () => {
  const db = new FakeDb({'calendar_sync_connections/pending': {uid: 'u', familyId: 'f', provider: 'google', status: 'awaiting_confirmation', generation: 1, pendingExpiresAt: 1000, secret: {ciphertext: 'encrypted'}},
    'calendar_sync_connections/active': {uid: 'u', familyId: 'f', provider: 'google', status: 'connected', generation: 1, pendingExpiresAt: null, secret: {ciphertext: 'keep'}}});
  for (let index = 0; index < 300; index++) db.rows.set(`calendar_sync_connections/a-null-${index}`, {status: 'connected', pendingExpiresAt: null});
  db.rows.set('calendar_sync_connections/zero', {status: 'connected', pendingExpiresAt: 0});
  const store = new FirestoreOAuthStore({db, now: () => 2000});
  assert.deepEqual(await store.expirePending(), {expired: 1});
  assert.equal(db.rows.get('calendar_sync_connections/pending').secret, null);
  assert.equal(db.rows.get('calendar_sync_connections/pending').status, 'disconnected');
  assert.equal(db.rows.get('calendar_sync_connections/active').secret.ciphertext, 'keep');
});

test('optional provider-config JSON allows Google first and never leaks malformed secret data', () => {
  const googleOnly = parseProviderConfig(JSON.stringify({google: {clientId: 'test-id', clientSecret: 'test-secret'}}));
  assert.equal(googleOnly.google.redirectUri, CALLBACK_URL);
  assert.equal(googleOnly.outlook, undefined);
  assert.deepEqual(parseProviderConfig('{}'), {});
  assert.deepEqual(parseProviderConfig(undefined), {});
  for (const malformed of ['private-secret-broken-json', '[1]', 'null', '{"google":{"clientId":"missing-secret"}}', '{"other":{"clientId":"x","clientSecret":"private-value"}}', '{"google":{"clientId":"x","clientSecret":"private-value","tokenUrl":"https://evil.example"}}']) {
    assert.throws(() => parseProviderConfig(malformed), (error) => {assert.equal(error.code, 'provider-not-configured'); assert.doesNotMatch(error.message, /private-value|private-secret/); return true;});
  }
});
