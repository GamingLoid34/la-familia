'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {createHash} = require('node:crypto');
const {createOAuthService, createSecretBox, SCOPES} = require('../calendar_sync/oauth');
const digest = (s) => createHash('sha256').update(s).digest('hex');
const redirectUri = 'https://us-central1-la-familia-5d9f5.cloudfunctions.net/calendarOAuthCallback';
const token = (provider = 'google') => ({access_token: 'access-placeholder', refresh_token: 'refresh-placeholder', expires_in: 3600, token_type: 'Bearer', scope: SCOPES[provider].join(' ')});
const codeIs = (code) => (error) => {assert.equal(error.code, code); return true;};
function harness() {
  const states = new Map();
  const connections = new Map();
  const locks = new Map();
  const responses = [];
  const calls = [];
  let time = 1000000000;
  let canAuthorize = true;
  const encryptionKey = Buffer.alloc(32, 7);
  const store = {
    async createState(id, record) {assert.equal(states.has(id), false); states.set(id, structuredClone(record));},
    async consumeState(id) {const row = states.get(id); states.delete(id); return row;},
    async putConnection(id, record) {connections.set(id, structuredClone(record));},
    async getConnection(id) {return structuredClone(connections.get(id));},
    async withConnectionLock(id, fn) {
      const previous = locks.get(id) || Promise.resolve();
      let release;
      const gate = new Promise((resolve) => {release = resolve;});
      locks.set(id, previous.then(() => gate));
      await previous;
      try {return await fn();} finally {release();}
    },
  };
  const configs = {google: {clientId: 'client-placeholder', clientSecret: 'client-secret-placeholder', redirectUri},
    outlook: {clientId: 'client-placeholder', clientSecret: 'client-secret-placeholder', redirectUri}};
  const service = createOAuthService({providers: configs, encryptionKey, store,
    authorize: async (uid, familyId) => canAuthorize && uid === 'user' && familyId === 'family', now: () => time,
    fetchImpl: async (url, options) => {
      calls.push({url, ...options}); assert.ok(responses.length, 'unexpected token request');
      const response = responses.shift();
      if (response instanceof Error) throw response;
      return new Response(JSON.stringify(response.body), {status: response.status || 200, headers: response.headers || {}});
    },
  });
  async function begin(provider = 'google') {
    const started = await service.begin({uid: 'user', familyId: 'family', provider});
    return {...started, state: new URL(started.authorizationUrl).searchParams.get('state')};
  }
  async function connected(provider = 'google') {
    const started = await begin(provider);
    responses.push({body: token(provider)});
    return service.complete({...started, code: 'authorization-placeholder'});
  }
  return {service, begin, connected, store, states, connections, responses, calls, encryptionKey, configs,
    advance: (ms) => {time += ms;}, revokeMembership: () => {canAuthorize = false;}};
}

test('AES-GCM envelopes are randomized and cryptographically bound to identity', () => {
  const box = createSecretBox(Buffer.alloc(32, 1));
  const first = box.seal({token: 'private-placeholder'}, 'family:user:1');
  const second = box.seal({token: 'private-placeholder'}, 'family:user:1');
  assert.notEqual(first.ciphertext, second.ciphertext);
  assert.doesNotMatch(JSON.stringify(first), /private-placeholder/);
  assert.deepEqual(box.open(first, 'family:user:1'), {token: 'private-placeholder'});
  assert.throws(() => box.open(first, 'family:user:2'), codeIs('secret-decryption-failed'));
  assert.throws(() => createSecretBox(Buffer.alloc(31)), codeIs('invalid-encryption-key'));
  const corrupt = {...first, tag: Buffer.alloc(16).toString('base64url')};
  assert.throws(() => box.open(corrupt, 'family:user:1'), codeIs('secret-decryption-failed'));
});
test('OAuth start binds family, user, browser and S256 without storing raw state or verifier', async () => {
  const h = harness(); const start = await h.begin();
  const query = new URL(start.authorizationUrl).searchParams;
  assert.equal(query.get('redirect_uri'), redirectUri);
  assert.equal(query.get('code_challenge_method'), 'S256');
  assert.equal(query.get('access_type'), 'offline');
  assert.equal(query.get('prompt'), 'consent');
  const stored = h.states.get(digest(start.state));
  assert.equal(stored.uid, 'user'); assert.equal(stored.familyId, 'family');
  const secret = createSecretBox(h.encryptionKey).open(stored.secret, JSON.stringify(['vardag-calendar-v1', 'state', digest(start.state), 'google', 'user', 'family']));
  assert.equal(query.get('code_challenge'), createHash('sha256').update(secret.verifier).digest('base64url'));
  const serialized = JSON.stringify([...h.states]);
  assert.doesNotMatch(serialized, new RegExp(start.state));
  assert.doesNotMatch(serialized, new RegExp(start.browserBinding));
  assert.doesNotMatch(serialized, new RegExp(secret.verifier));
});
test('complete exchanges code with matching verifier and stores only encrypted tokens', async () => {
  const h = harness(); const start = await h.begin();
  h.responses.push({body: token()});
  const result = await h.service.complete({...start, code: 'code-placeholder'});
  assert.equal(result.status, 'authorized');
  assert.equal(h.states.size, 0); assert.equal(h.connections.size, 1);
  assert.doesNotMatch(JSON.stringify([...h.connections]), /access-placeholder|refresh-placeholder/);
  assert.doesNotMatch(JSON.stringify(result), /secret|token/i);
  const body = new URLSearchParams(h.calls[0].body);
  assert.equal(body.get('grant_type'), 'authorization_code');
  assert.equal(body.get('code'), 'code-placeholder');
  assert.equal(body.get('redirect_uri'), redirectUri);
  assert.equal(body.get('code_verifier').length, 43);
  assert.equal(h.calls[0].redirect, 'manual');
  assert.equal(await h.service.getAccessToken({...result}), 'access-placeholder');
  assert.equal(h.calls.length, 1);
});
test('atomic state consume allows one callback under concurrent replay', async () => {
  const h = harness(); const start = await h.begin(); h.responses.push({body: token()});
  const results = await Promise.allSettled([h.service.complete({...start, code: 'code'}), h.service.complete({...start, code: 'code'})]);
  assert.equal(results.filter((r) => r.status === 'fulfilled').length, 1);
  assert.equal(results.find((r) => r.status === 'rejected').reason.code, 'invalid-oauth-state');
  assert.equal(h.calls.length, 1); assert.equal(h.connections.size, 1);
});
test('wrong browser binding stops account-linking CSRF before token exchange', async () => {
  const h = harness(); const start = await h.begin();
  await assert.rejects(h.service.complete({...start, browserBinding: 'a'.repeat(43), code: 'code'}), codeIs('invalid-oauth-browser'));
  assert.equal(h.calls.length, 0); assert.equal(h.connections.size, 0);
});
test('expired state and removed family membership cannot link an account', async () => {
  const h = harness(); const start = await h.begin(); h.advance(11 * 60 * 1000);
  await assert.rejects(h.service.complete({...start, code: 'code'}), codeIs('invalid-oauth-state'));
  const second = await h.begin(); h.revokeMembership();
  await assert.rejects(h.service.complete({...second, code: 'code'}), codeIs('forbidden'));
  assert.equal(h.calls.length, 0);
});
test('consent rejection consumes state and never creates a misleading connection', async () => {
  const h = harness(); const start = await h.begin();
  await assert.rejects(h.service.complete({...start, error: 'access_denied'}), codeIs('consent-denied'));
  assert.equal(h.states.size, 0); assert.equal(h.connections.size, 0); assert.equal(h.calls.length, 0);
});
test('partial calendar consent and missing refresh token cannot enable background sync', async () => {
  for (const data of [{...token(), scope: SCOPES.google[0]}, {...token(), refresh_token: undefined}]) {
    const h = harness(); const start = await h.begin(); h.responses.push({body: data});
    await assert.rejects(h.service.complete({...start, code: 'code'}), codeIs(data.refresh_token ? 'insufficient-calendar-permission' : 'offline-consent-required'));
    assert.equal(h.connections.size, 0);
  }
});
test('Microsoft code flow uses common tenant, delegated scope and PKCE', async () => {
  const h = harness(); const start = await h.begin('outlook');
  assert.match(start.authorizationUrl, /^https:\/\/login.microsoftonline.com\/common\/oauth2\/v2.0\/authorize\?/);
  const query = new URL(start.authorizationUrl).searchParams;
  assert.match(query.get('scope'), /offline_access/); assert.match(query.get('scope'), /Calendars.ReadWrite/);
  h.responses.push({body: {...token('outlook'), scope: 'Calendars.ReadWrite'}});
  const result = await h.service.complete({...start, code: 'code'});
  assert.equal(result.provider, 'outlook');
  assert.equal(h.calls[0].url, 'https://login.microsoftonline.com/common/oauth2/v2.0/token');
});
test('refresh rotation is atomic and concurrent callers reuse the refreshed token', async () => {
  const h = harness(); const connection = await h.connected('outlook'); h.advance(3600 * 1000);
  h.responses.push({body: {...token('outlook'), access_token: 'new-access', refresh_token: 'new-refresh'}});
  const results = await Promise.all([h.service.getAccessToken(connection), h.service.getAccessToken(connection)]);
  assert.deepEqual(results, ['new-access', 'new-access']); assert.equal(h.calls.length, 2);
  const refreshBody = new URLSearchParams(h.calls[1].body);
  assert.equal(refreshBody.get('grant_type'), 'refresh_token'); assert.equal(refreshBody.get('refresh_token'), 'refresh-placeholder');
  h.advance(3600 * 1000); h.responses.push({body: {...token('outlook'), access_token: 'third-access', refresh_token: 'third-refresh'}});
  assert.equal(await h.service.getAccessToken(connection), 'third-access');
  assert.equal(new URLSearchParams(h.calls[2].body).get('refresh_token'), 'new-refresh');
});
test('Google refresh response may omit scope and refresh token without losing either', async () => {
  const h = harness(); const connection = await h.connected(); h.advance(3600 * 1000);
  h.responses.push({body: {access_token: 'next-access', token_type: 'Bearer', expires_in: 3600}});
  await h.service.getAccessToken(connection); h.advance(3600 * 1000);
  h.responses.push({body: {access_token: 'again-access', token_type: 'Bearer', expires_in: 3600}});
  await h.service.getAccessToken(connection);
  assert.equal(new URLSearchParams(h.calls[2].body).get('refresh_token'), 'refresh-placeholder');
  assert.equal(h.connections.get(connection.connectionId).scope, SCOPES.google.join(' '));
});
test('token access is denied across user/family and membership revocation', async () => {
  const h = harness(); const connection = await h.connected();
  await assert.rejects(h.service.getAccessToken({...connection, uid: 'other'}), codeIs('forbidden'));
  await assert.rejects(h.service.getAccessToken({...connection, familyId: 'other'}), codeIs('forbidden'));
  h.revokeMembership(); await assert.rejects(h.service.getAccessToken(connection), codeIs('forbidden'));
  assert.equal(h.calls.length, 1);
});
test('invalid_grant is explicit reauthorization and never includes provider diagnostics', async () => {
  const h = harness(); const connection = await h.connected(); h.advance(3600 * 1000);
  h.responses.push({status: 400, body: {error: 'invalid_grant', error_description: 'private secret details'}});
  await assert.rejects(h.service.getAccessToken(connection), (error) => {assert.equal(error.code, 'reauthorization-required'); assert.doesNotMatch(error.message, /private secret/); return true;});
});
test('OAuth endpoints never follow redirects and malformed response is sanitized', async () => {
  for (const response of [{status: 302, body: {}, headers: {Location: 'https://evil.example/'}}, {body: null}]) {
    const h = harness(); const start = await h.begin(); h.responses.push(response);
    await assert.rejects(h.service.complete({...start, code: 'code'}), codeIs(response.status === 302 ? 'unsafe-oauth-redirect' : 'invalid-token-response'));
    assert.equal(h.calls.length, 1); assert.equal(h.connections.size, 0);
  }
});
test('missing configuration/unsafe tenant/redirect are rejected before authorization', async () => {
  const h = harness(); delete h.configs.google.clientSecret;
  await assert.rejects(h.begin(), codeIs('provider-not-configured'));
  h.configs.outlook.tenant = 'evil.example/path';
  await assert.rejects(h.begin('outlook'), codeIs('invalid-microsoft-tenant'));
  h.configs.outlook.tenant = 'common'; h.configs.outlook.redirectUri = 'http://localhost/callback';
  await assert.rejects(h.begin('outlook'), codeIs('invalid-redirect-uri'));
  assert.equal(h.states.size, 0);
});
