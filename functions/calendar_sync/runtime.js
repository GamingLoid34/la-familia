/* global globalThis */
/* eslint-disable max-len, require-jsdoc, valid-jsdoc */
"use strict";

const {randomBytes, randomUUID, createHash} = require("node:crypto");
const {onCall, onRequest, HttpsError} = require("firebase-functions/v2/https");
const {defineSecret} = require("firebase-functions/params");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");
const {createOAuthService, createSecretBox} = require("./oauth");
const {FirestoreOAuthStore} = require("./firestore_store");
const {GoogleCalendarProvider, OutlookCalendarProvider, ICloudCalendarProvider, CalendarProviderError} = require("./providers");

const CALLBACK_ORIGIN = "https://us-central1-la-familia-5d9f5.cloudfunctions.net";
const CALLBACK_URL = `${CALLBACK_ORIGIN}/calendarOAuthCallback`;
const APP_URL = "https://la-familia-5d9f5.web.app";
const COOKIE = "__Host-vardag_calendar_oauth";
const SECRET_NAMES = ["CALENDAR_PROVIDER_CONFIG", "CALENDAR_TOKEN_ENCRYPTION_KEY"];
const SECRETS = SECRET_NAMES.map((name) => defineSecret(name));
const digest = (value) => createHash("sha256").update(value).digest("hex");
function fail(code) {
  throw new CalendarProviderError(code);
}
function opaque(value) {
  if (typeof value !== "string" || !/^[A-Za-z0-9_-]{43}$/.test(value)) fail("invalid-oauth-state");
  return value;
}
function connectionId(value) {
  if (typeof value !== "string" || !/^[A-Za-z0-9_-]{1,128}$/.test(value)) fail("invalid-connection-id");
  return value;
}
const icloudContext = (id, record) => JSON.stringify(["vardag-calendar-icloud-v1", id, record.uid, record.familyId]);
const handoffContext = (id, record) => JSON.stringify(["vardag-calendar-handoff-v1", id, record.uid, record.familyId]);
function publicConnection(id, row) {
  return {id, provider: row.provider, status: row.status, calendarId: row.calendarId || null,
    calendarName: row.calendarName || null, calendars: Array.isArray(row.calendars) ? row.calendars.map(({id, name, writable}) => ({id, name, writable: writable === true})) : [], lastSyncAt: row.lastSyncAt || null,
    lastError: typeof row.lastError === "string" && /^[a-z-]{1,60}$/.test(row.lastError) ? row.lastError : null,
    updatedAt: row.updatedAt || null, conflictCount: Number.isSafeInteger(row.conflictCount) && row.conflictCount >= 0 ? row.conflictCount : 0};
}
function createCalendarRuntime({db, config = {}, fetchImpl = globalThis.fetch, now = Date.now, store: givenStore}) {
  const store = givenStore || new FirestoreOAuthStore({db, now});
  const key = config.encryptionKey;
  const providers = config.providers || {};
  function box() {
    if (!Buffer.isBuffer(key) || key.length !== 32) fail("provider-not-configured");
    return createSecretBox(key);
  }
  async function profile(uid) {
    if (typeof uid !== "string" || !uid || uid.includes("/")) fail("unauthenticated");
    return db.runTransaction(async (tx) => {
      const user = await tx.get(db.collection("users").doc(uid));
      const row = user.exists ? user.data() : null;
      if (!row || !["parent", "admin", "youth"].includes(row.role) || typeof row.familyId !== "string" || !row.familyId || row.familyId.includes("/")) fail("forbidden");
      const family = await tx.get(db.collection("families").doc(row.familyId));
      if (!family.exists) fail("forbidden");
      return {uid, familyId: row.familyId, role: row.role, name: row.name || ""};
    }, {readOnly: true});
  }
  async function authorize(uid, familyId) {
    const member = await profile(uid);
    if (member.familyId !== familyId) return false;
    const capability = await db.collection("config").doc("privateCalendarPilot20261030").get();
    return capability.exists && capability.data().enabled === true && capability.data().contract === "private-v1-20261030";
  }
  function oauth() {
    box();
    return createOAuthService({providers, encryptionKey: key, store, authorize, fetchImpl, now});
  }
  function configured(provider) {
    if (!Buffer.isBuffer(key) || key.length !== 32) return false;
    if (provider === "icloud") return true;
    return !!providers[provider]?.clientId && !!providers[provider]?.clientSecret && providers[provider]?.redirectUri === CALLBACK_URL;
  }
  async function getProvider(connection) {
    const id = connectionId(connection.id);
    if (!(await authorize(connection.uid, connection.familyId))) fail("forbidden");
    const fresh = await store.getConnection(id);
    if (!fresh || fresh.uid !== connection.uid || fresh.familyId !== connection.familyId ||
      !["authorized", "connected"].includes(fresh.status) || !fresh.secret) fail("reauthorization-required");
    if (connection.generation !== undefined && fresh.generation !== connection.generation) fail("connection-generation-changed");
    if (fresh.provider === "icloud") {
      const credentials = box().open(fresh.secret, icloudContext(id, fresh));
      return new ICloudCalendarProvider({...credentials, fetchImpl});
    }
    const accessToken = await oauth().getAccessToken({connectionId: id, uid: fresh.uid, familyId: fresh.familyId});
    if (fresh.provider === "google") return new GoogleCalendarProvider({accessToken, fetchImpl});
    if (fresh.provider === "outlook") return new OutlookCalendarProvider({accessToken, fetchImpl});
    fail("unsupported-provider");
  }
  async function list(uid) {
    const member = await profile(uid);
    const snapshot = await db.collection("calendar_sync_connections").where("uid", "==", uid).limit(100).get();
    const connections = snapshot.docs.filter((doc) => doc.data().familyId === member.familyId && doc.data().status !== "awaiting_confirmation")
        .map((doc) => publicConnection(doc.id, doc.data()));
    // Public readiness flags are enabled only after secret configuration and
    // provider deployment/probes. Listing itself needs no secret bindings.
    return {connections, providers: ["google", "outlook", "icloud"].map((provider) => ({provider, configured: config.availability?.[provider] === true}))};
  }
  async function start(uid, data) {
    const member = await profile(uid); const provider = data?.provider;
    if (!["google", "outlook"].includes(provider)) fail("unsupported-provider");
    if (!configured(provider)) fail("provider-not-configured");
    const begun = await oauth().begin({...member, provider});
    const ticket = randomBytes(32).toString("base64url"); const id = `handoff_${digest(ticket)}`;
    const record = {uid, familyId: member.familyId, provider, expiresAt: begun.expiresAt};
    record.secret = box().seal({authorizationUrl: begun.authorizationUrl, browserBinding: begun.browserBinding}, handoffContext(id, record));
    await store.createState(id, record);
    return {url: `${CALLBACK_ORIGIN}/calendarOAuthStart?ticket=${ticket}`, expiresAt: record.expiresAt};
  }
  async function openHandoff(ticket) {
    const id = `handoff_${digest(opaque(ticket))}`;
    const record = await store.consumeState(id);
    if (!record || record.expiresAt <= now() || !(await authorize(record.uid, record.familyId))) fail("invalid-oauth-state");
    return box().open(record.secret, handoffContext(id, record));
  }
  async function callback(query, browserBinding) {
    const result = await oauth().complete({state: query.state, code: query.code, error: query.error, browserBinding});
    // This extra authenticated completion is necessary because the handoff URL
    // is shareable. An OAuth callback alone must not attach a victim's external
    // account to the initiating (possibly malicious) Vardag account.
    const ticket = randomBytes(32).toString("base64url");
    await store.createState(`completion_${digest(ticket)}`, {uid: result.uid, familyId: result.familyId,
      connectionId: result.connectionId, expiresAt: now() + 10 * 60 * 1000});
    return {url: `${APP_URL}/#/calendar-connect?ticket=${ticket}`};
  }
  async function finish(uid, data) {
    const member = await profile(uid);
    const record = await store.consumeState(`completion_${digest(opaque(data?.ticket))}`);
    if (!record || record.uid !== uid || record.familyId !== member.familyId || !(await authorize(uid, member.familyId))) fail("forbidden");
    const id = connectionId(record.connectionId);
    return store.withConnectionLock(id, async () => {
      const connection = await store.assertLease(id);
      if (connection.uid !== uid || connection.familyId !== member.familyId || connection.status !== "awaiting_confirmation") fail("forbidden");
      await store.updateConnection(id, {status: "authorized", pendingExpiresAt: null});
      const provider = await getProvider({...connection, id, status: "authorized"});
      const calendars = (await provider.listCalendars()).map(({id: calendarId, name, writable}) => ({id: calendarId, name, writable}));
      await store.updateConnection(id, {calendars, lastError: null});
      return {connectionId: id, provider: connection.provider, status: "authorized", calendars};
    });
  }
  async function connectICloud(uid, data) {
    const member = await profile(uid);
    if (!configured("icloud")) fail("provider-not-configured");
    if (!(await authorize(uid, member.familyId))) fail("forbidden");
    if (typeof data?.username !== "string" || typeof data?.appPassword !== "string") fail("invalid-credentials");
    const provider = new ICloudCalendarProvider({username: data.username, appPassword: data.appPassword, fetchImpl});
    const calendars = (await provider.listCalendars()).map(({id, name, writable}) => ({id, name, writable}));
    const id = randomUUID();
    const record = {uid, familyId: member.familyId, provider: "icloud", status: "authorized", createdAt: now(), updatedAt: now(), calendars};
    record.secret = box().seal({username: data.username, appPassword: data.appPassword}, icloudContext(id, record));
    // Re-check account membership after network discovery before persisting.
    if (!(await authorize(uid, member.familyId))) fail("forbidden");
    await store.putConnection(id, record);
    return {connectionId: id, provider: "icloud", status: "authorized", calendars};
  }
  async function disconnect(uid, data) {
    const member = await profile(uid);
    return store.disconnect(connectionId(data?.connectionId), uid, member.familyId);
  }
  return {store, authorize, profile, getProvider, list, start, openHandoff, callback, finish, connectICloud, disconnect};
}

function safeError(error) {
  const code = error?.code || "";
  if (code === "provider-not-configured") return new HttpsError("unavailable", "Kalenderkopplingen är inte aktiverad ännu. Appregistrering och serverkonfiguration återstår.");
  if (code === "unauthenticated") return new HttpsError("unauthenticated", "Logga in i Vardag först.");
  if (["forbidden", "invalid-oauth-browser"].includes(code)) return new HttpsError("permission-denied", "Kalenderkopplingen hör inte till ditt konto eller är inte tillåten.");
  if (code === "connection-busy") return new HttpsError("aborted", "Kalendern uppdateras just nu. Försök igen om en liten stund.");
  if (["reauthorization-required", "offline-consent-required", "insufficient-calendar-permission", "unauthenticated"].includes(code)) return new HttpsError("failed-precondition", "Anslut kalenderkontot igen och godkänn kalenderåtkomst.");
  if (code.startsWith("invalid-") || code === "consent-denied") return new HttpsError("invalid-argument", "Anslutningen kunde inte slutföras. Starta den igen från Vardag.");
  return new HttpsError("unavailable", "Kalendertjänsten svarade inte som väntat. Försök igen senare.");
}
function parseProviderConfig(value) {
  if (!value) return {};
  try {
    if (typeof value !== "string" || value.length > 32768) fail("provider-not-configured");
    const parsed = JSON.parse(value);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed) || Object.keys(parsed).some((name) => !["google", "outlook"].includes(name))) fail("provider-not-configured");
    const result = {};
    for (const provider of ["google", "outlook"]) {
      if (parsed[provider] === undefined) continue;
      const cfg = parsed[provider];
      if (!cfg || typeof cfg !== "object" || Array.isArray(cfg) || Object.keys(cfg).some((name) => !["clientId", "clientSecret"].includes(name)) ||
          typeof cfg.clientId !== "string" || typeof cfg.clientSecret !== "string" || !cfg.clientId || !cfg.clientSecret ||
          cfg.clientId.length > 8192 || cfg.clientSecret.length > 8192 || /[\r\n]/.test(cfg.clientId + cfg.clientSecret)) fail("provider-not-configured");
      result[provider] = {...cfg, redirectUri: CALLBACK_URL, ...(provider === "outlook" ? {tenant: "common"} : {})};
    }
    return result;
  } catch (_) {
    fail("provider-not-configured");
  }
}
function configuredRuntime() {
  const env = process.env;
  const key = env.CALENDAR_TOKEN_ENCRYPTION_KEY ? Buffer.from(env.CALENDAR_TOKEN_ENCRYPTION_KEY, "base64") : null;
  return createCalendarRuntime({db: admin.firestore(), config: {encryptionKey: key,
    availability: {google: env.CALENDAR_GOOGLE_READY === "true", outlook: env.CALENDAR_MICROSOFT_READY === "true", icloud: env.CALENDAR_ICLOUD_READY === "true"},
    providers: parseProviderConfig(env.CALENDAR_PROVIDER_CONFIG)}});
}
function call(method, secrets = SECRETS) {
  return onCall({region: "us-central1", timeoutSeconds: 120, ...(secrets.length ? {secrets} : {})}, async (request) => {
    try {
      return await configuredRuntime()[method](request.auth?.uid, request.data);
    } catch (error) {
      throw safeError(error);
    }
  });
}
function headers(res) {
  res.set("Cache-Control", "no-store"); res.set("Referrer-Policy", "no-referrer");
  res.set("Content-Security-Policy", "default-src 'none'; frame-ancestors 'none'; base-uri 'none'");
  res.set("X-Content-Type-Options", "nosniff");
}
function cookie(req) {
  const entries = String(req.headers.cookie || "").split(";").map((s) => s.trim());
  const entry = entries.find((s) => s.startsWith(`${COOKIE}=`));
  return entry ? entry.slice(COOKIE.length + 1) : "";
}
const HTTP_OPTIONS = {region: "us-central1", timeoutSeconds: 120, secrets: SECRETS};
const calendarOAuthStart = onRequest(HTTP_OPTIONS, async (req, res) => {
  headers(res);
  if (req.method !== "GET") {
    res.status(405).send("Använd anslutningslänken från Vardag."); return;
  }
  try {
    const result = await configuredRuntime().openHandoff(req.query.ticket);
    res.set("Set-Cookie", `${COOKIE}=${opaque(result.browserBinding)}; Secure; HttpOnly; SameSite=Lax; Path=/; Max-Age=600`);
    res.redirect(303, result.authorizationUrl);
  } catch (_) {
    res.status(400).send("Länken har gått ut. Starta kalenderkopplingen igen från Vardag.");
  }
});
const calendarOAuthCallback = onRequest(HTTP_OPTIONS, async (req, res) => {
  headers(res);
  res.set("Set-Cookie", `${COOKIE}=; Secure; HttpOnly; SameSite=Lax; Path=/; Max-Age=0`);
  if (req.method !== "GET") {
    res.status(405).send("Anslutningen kunde inte slutföras."); return;
  }
  try {
    const result = await configuredRuntime().callback(req.query, cookie(req));
    res.redirect(303, result.url);
  } catch (_) {
    res.status(400).send("Kalenderkopplingen kunde inte slutföras. Öppna Vardag och försök igen.");
  }
});

module.exports = {createCalendarRuntime, configuredRuntime, safeError, CALLBACK_URL, parseProviderConfig, SECRETS, TOKEN_SECRET: SECRETS[1],
  getCalendarConnections: call("list", []), startCalendarConnection: call("start"),
  finishCalendarConnection: call("finish"), connectICloudCalendar: call("connectICloud", [SECRETS[1]]),
  disconnectCalendarConnection: call("disconnect", []), calendarOAuthStart, calendarOAuthCallback,
  expirePendingCalendarConnections: onSchedule({region: "us-central1", schedule: "every 15 minutes"}, () => configuredRuntime().store.expirePending())};
