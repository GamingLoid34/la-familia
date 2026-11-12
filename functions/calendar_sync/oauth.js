/* global globalThis */
/* eslint-disable max-len, require-jsdoc, valid-jsdoc */
"use strict";

const {createHash, randomBytes, randomUUID, createCipheriv, createDecipheriv, timingSafeEqual} = require("node:crypto");
const {CalendarProviderError} = require("./providers");

const SCOPES = Object.freeze({
  google: ["https://www.googleapis.com/auth/calendar.events", "https://www.googleapis.com/auth/calendar.calendarlist.readonly"],
  outlook: ["https://graph.microsoft.com/Calendars.ReadWrite", "offline_access"],
});
const STATE_TTL_MS = 10 * 60 * 1000;
const digest = (value) => createHash("sha256").update(value).digest("hex");
function fail(code) {
  throw new CalendarProviderError(code);
}
function input(value, name, max = 8192) {
  if (typeof value !== "string" || !value || value.length > max || /[\r\n]/.test(value)) fail(`invalid-${name}`);
  return value;
}
function opaque(value) {
  if (typeof value !== "string" || !/^[A-Za-z0-9_-]{43}$/.test(value)) fail("invalid-oauth-state");
  return value;
}
function secureEqual(left, right) {
  const a = Buffer.from(left || "", "utf8");
  const b = Buffer.from(right || "", "utf8");
  return a.length === b.length && timingSafeEqual(a, b);
}
function createSecretBox(encryptionKey) {
  if (!Buffer.isBuffer(encryptionKey) || encryptionKey.length !== 32) fail("invalid-encryption-key");
  const key = Buffer.from(encryptionKey);
  return {
    seal(value, context) {
      const iv = randomBytes(12);
      const cipher = createCipheriv("aes-256-gcm", key, iv);
      cipher.setAAD(Buffer.from(input(context, "encryption-context")));
      const ciphertext = Buffer.concat([cipher.update(JSON.stringify(value), "utf8"), cipher.final()]);
      return {version: 1, iv: iv.toString("base64url"), ciphertext: ciphertext.toString("base64url"), tag: cipher.getAuthTag().toString("base64url")};
    },
    open(value, context) {
      try {
        if (value?.version !== 1 || typeof value.ciphertext !== "string" || value.ciphertext.length > 128 * 1024) fail("invalid-secret-envelope");
        const iv = Buffer.from(value.iv, "base64url");
        const tag = Buffer.from(value.tag, "base64url");
        if (iv.length !== 12 || tag.length !== 16) fail("invalid-secret-envelope");
        const decipher = createDecipheriv("aes-256-gcm", key, iv);
        decipher.setAAD(Buffer.from(input(context, "encryption-context")));
        decipher.setAuthTag(tag);
        return JSON.parse(Buffer.concat([decipher.update(Buffer.from(value.ciphertext, "base64url")), decipher.final()]).toString("utf8"));
      } catch (_) {
        fail("secret-decryption-failed");
      }
    },
  };
}
function configuration(provider, configs) {
  if (!Object.hasOwn(SCOPES, provider)) fail("unsupported-provider");
  const cfg = configs[provider];
  if (!cfg?.clientId || !cfg?.clientSecret || !cfg?.redirectUri) fail("provider-not-configured");
  input(cfg.clientId, "client-id"); input(cfg.clientSecret, "client-secret");
  let redirect;
  try {
    redirect = new URL(cfg.redirectUri);
  } catch (_) {
    fail("invalid-redirect-uri");
  }
  if (redirect.protocol !== "https:" || redirect.username || redirect.password || redirect.search || redirect.hash || redirect.port) fail("invalid-redirect-uri");
  if (provider === "google") return {...cfg, authorizeUrl: "https://accounts.google.com/o/oauth2/v2/auth", tokenUrl: "https://oauth2.googleapis.com/token"};
  const tenant = cfg.tenant || "common";
  if (!/^(common|organizations|consumers|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$/i.test(tenant)) fail("invalid-microsoft-tenant");
  return {...cfg, authorizeUrl: `https://login.microsoftonline.com/${tenant}/oauth2/v2.0/authorize`, tokenUrl: `https://login.microsoftonline.com/${tenant}/oauth2/v2.0/token`};
}
async function readTokenResponse(response) {
  if (Number(response.headers.get("content-length")) > 65536) fail("invalid-token-response");
  let size = 0;
  const chunks = [];
  try {
    if (response.body) {
      for await (const chunk of response.body) {
        size += chunk.length;
        if (size > 65536) fail("invalid-token-response");
        chunks.push(Buffer.from(chunk));
      }
    }
    return JSON.parse(Buffer.concat(chunks).toString("utf8"));
  } catch (_) {
    fail("invalid-token-response");
  }
}
async function tokenRequest(fetchImpl, cfg, fields) {
  let response;
  try {
    response = await fetchImpl(cfg.tokenUrl, {method: "POST", redirect: "manual", signal: AbortSignal.timeout(25000),
      headers: {"Content-Type": "application/x-www-form-urlencoded", "Accept": "application/json"},
      body: new URLSearchParams({client_id: cfg.clientId, client_secret: cfg.clientSecret, ...fields}).toString(),
    });
  } catch (_) {
    fail("oauth-network-error");
  }
  // Never follow token-endpoint redirects or include raw error text in logs/UI.
  if (response.status >= 300 && response.status < 400) fail("unsafe-oauth-redirect");
  const data = await readTokenResponse(response);
  if (!data || typeof data !== "object" || Array.isArray(data)) fail("invalid-token-response");
  if (!response.ok || data.error) {
    if (data.error === "invalid_grant" || data.error === "interaction_required") fail("reauthorization-required");
    if (response.status === 429) fail("rate-limited");
    if (response.status >= 500) fail("provider-unavailable");
    fail("oauth-token-rejected");
  }
  if (typeof data !== "object" || !data || String(data.token_type).toLowerCase() !== "bearer") fail("invalid-token-response");
  input(data.access_token, "access-token", 32768);
  if (data.refresh_token) input(data.refresh_token, "refresh-token", 32768);
  if (!Number.isFinite(Number(data.expires_in)) || Number(data.expires_in) <= 0 || Number(data.expires_in) > 366 * 86400) fail("invalid-token-response");
  return data;
}
function permittedScopes(provider, scope) {
  if (typeof scope !== "string") return false;
  const granted = new Set(scope.split(/\s+/).filter(Boolean));
  if (provider === "google") return granted.has("https://www.googleapis.com/auth/calendar") || SCOPES.google.every((s) => granted.has(s));
  return [...granted].some((s) => s.toLowerCase().replace("https://graph.microsoft.com/", "") === "calendars.readwrite");
}
function context(record, id, kind) {
  // Length-prefix via JSON prevents ambiguous identities or delimiter injection.
  return JSON.stringify(["vardag-calendar-v1", kind, id, record.provider, record.uid, record.familyId]);
}
function createOAuthService({providers = {}, encryptionKey, store, authorize, fetchImpl = globalThis.fetch, now = Date.now}) {
  for (const method of ["createState", "consumeState", "putConnection", "getConnection", "withConnectionLock"]) {
    if (typeof store?.[method] !== "function") fail("invalid-oauth-store");
  }
  if (typeof authorize !== "function") fail("missing-authorize");
  const box = createSecretBox(encryptionKey);
  async function allowed(uid, familyId) {
    input(uid, "uid", 256); input(familyId, "family-id", 256);
    if (await authorize(uid, familyId) !== true) fail("forbidden");
  }
  return {
    async begin({uid, familyId, provider}) {
      await allowed(uid, familyId);
      const cfg = configuration(provider, providers);
      const state = randomBytes(32).toString("base64url");
      const browserBinding = randomBytes(32).toString("base64url");
      const verifier = randomBytes(32).toString("base64url");
      const stateId = digest(state);
      const record = {uid, familyId, provider, createdAt: now(), expiresAt: now() + STATE_TTL_MS,
        browserBindingHash: digest(browserBinding), redirectUri: cfg.redirectUri};
      record.secret = box.seal({verifier}, context(record, stateId, "state"));
      await store.createState(stateId, record);
      const query = new URLSearchParams({client_id: cfg.clientId, redirect_uri: cfg.redirectUri,
        response_type: "code", scope: SCOPES[provider].join(" "), state,
        code_challenge: createHash("sha256").update(verifier).digest("base64url"), code_challenge_method: "S256",
        ...(provider === "google" ? {access_type: "offline", prompt: "consent", include_granted_scopes: "true"} : {response_mode: "query", prompt: "select_account"}),
      });
      // HTTP caller must set browserBinding as Secure/HttpOnly/SameSite=Lax cookie
      // on the callback host. Do not include it in authorizationUrl or app logs.
      return {authorizationUrl: `${cfg.authorizeUrl}?${query}`, browserBinding, expiresAt: record.expiresAt};
    },
    async complete({state, code, error, browserBinding}) {
      const stateId = digest(opaque(state));
      opaque(browserBinding);
      // consumeState MUST atomically remove/mark the state used, including races.
      const record = await store.consumeState(stateId);
      if (!record || record.expiresAt <= now() || record.createdAt > now()) fail("invalid-oauth-state");
      if (!secureEqual(record.browserBindingHash, digest(browserBinding))) fail("invalid-oauth-browser");
      await allowed(record.uid, record.familyId);
      if (error) fail(error === "access_denied" ? "consent-denied" : "oauth-authorization-failed");
      input(code, "authorization-code");
      const cfg = configuration(record.provider, providers);
      if (cfg.redirectUri !== record.redirectUri) fail("oauth-configuration-changed");
      const {verifier} = box.open(record.secret, context(record, stateId, "state"));
      const token = await tokenRequest(fetchImpl, cfg, {grant_type: "authorization_code", code,
        redirect_uri: cfg.redirectUri, code_verifier: verifier});
      if (!permittedScopes(record.provider, token.scope)) fail("insufficient-calendar-permission");
      if (!token.refresh_token) fail("offline-consent-required");
      const connectionId = randomUUID();
      const connection = {uid: record.uid, familyId: record.familyId, provider: record.provider,
        createdAt: now(), updatedAt: now(), expiresAt: now() + Number(token.expires_in) * 1000,
        scope: token.scope, status: "authorized"};
      connection.secret = box.seal({accessToken: token.access_token, refreshToken: token.refresh_token}, context(connection, connectionId, "connection"));
      await store.putConnection(connectionId, connection);
      // authorized is deliberately distinct from connected: first listCalendars
      // and selected-calendar probe must succeed before sync is activated.
      return {connectionId, uid: record.uid, familyId: record.familyId, provider: record.provider, status: "authorized"};
    },
    async getAccessToken({connectionId, uid, familyId, forceRefresh = false}) {
      input(connectionId, "connection-id", 256);
      await allowed(uid, familyId);
      // Distributed lock prevents refresh-token rotation races across instances.
      return store.withConnectionLock(connectionId, async () => {
        const record = await store.getConnection(connectionId);
        if (!record || record.uid !== uid || record.familyId !== familyId) fail("forbidden");
        if (!["authorized", "connected"].includes(record.status)) fail("reauthorization-required");
        const secrets = box.open(record.secret, context(record, connectionId, "connection"));
        if (!forceRefresh && record.expiresAt > now() + 60000) return secrets.accessToken;
        const cfg = configuration(record.provider, providers);
        const token = await tokenRequest(fetchImpl, cfg, {grant_type: "refresh_token", refresh_token: secrets.refreshToken,
          ...(record.provider === "outlook" ? {scope: SCOPES.outlook.join(" ")} : {})});
        if (token.scope && !permittedScopes(record.provider, token.scope)) fail("insufficient-calendar-permission");
        const updated = {...record, updatedAt: now(), expiresAt: now() + Number(token.expires_in) * 1000,
          scope: token.scope || record.scope};
        updated.secret = box.seal({accessToken: token.access_token, refreshToken: token.refresh_token || secrets.refreshToken}, context(updated, connectionId, "connection"));
        await store.putConnection(connectionId, updated);
        return token.access_token;
      });
    },
  };
}

module.exports = {createOAuthService, createSecretBox, SCOPES};
