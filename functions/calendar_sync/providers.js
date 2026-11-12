/* global globalThis */
/* eslint-disable max-len, require-jsdoc, valid-jsdoc */
"use strict";

const {createHash} = require("node:crypto");
const {XMLParser, XMLValidator} = require("fast-xml-parser");
const ical = require("node-ical");

const MAX_BYTES = 8 * 1024 * 1024;
const MAX_ITEMS = 10000;
const MAX_PAGES = 100;
const GOOGLE = "https://www.googleapis.com/calendar/v3/";
const GRAPH = "https://graph.microsoft.com/v1.0/";

class CalendarProviderError extends Error {
  constructor(code, status = 0, retryAfter = null) {
    super(`Calendar provider: ${code}`);
    this.name = "CalendarProviderError";
    this.code = code;
    this.status = status;
    this.retryAfter = retryAfter;
  }
}
const fail = (code) => {
  throw new CalendarProviderError(code);
};
function required(value, name) {
  if (typeof value !== "string" || !value.trim() || value.length > 16384 || /[\r\n]/.test(value)) fail(`invalid-${name}`);
  return value;
}
const hash = (value) => createHash("sha256").update(required(value, "operation-id")).digest("hex");
function etagHeaders(etag) {
  required(etag, "etag");
  if (etag === "*") fail("invalid-etag");
  return {"If-Match": etag};
}
function errorFor(response) {
  const status = response.status;
  const code = ({401: "unauthenticated", 403: "forbidden", 404: "not-found", 409: "conflict",
    410: "sync-reset-required", 412: "conflict", 429: "rate-limited"})[status] ||
    (status >= 500 ? "provider-unavailable" : "provider-rejected");
  const rawRetry = response.headers.get("retry-after");
  let retryAfter = null;
  if (rawRetry && /^\d+$/.test(rawRetry)) retryAfter = Math.min(Number(rawRetry), 86400);
  else if (rawRetry) {
    const seconds = Math.ceil((Date.parse(rawRetry) - Date.now()) / 1000);
    if (Number.isFinite(seconds)) retryAfter = Math.min(Math.max(seconds, 0), 86400);
  }
  return new CalendarProviderError(code, status, retryAfter);
}
async function textBody(response) {
  const length = Number(response.headers.get("content-length"));
  if (length > MAX_BYTES) fail("response-too-large");
  if (!response.body) return "";
  const chunks = [];
  let size = 0;
  try {
    for await (const chunk of response.body) {
      size += chunk.length;
      if (size > MAX_BYTES) fail("response-too-large");
      chunks.push(Buffer.from(chunk));
    }
  } catch (error) {
    if (error instanceof CalendarProviderError) throw error;
    fail("network-error");
  }
  return Buffer.concat(chunks).toString("utf8");
}
async function request(fetchImpl, url, options = {}, accepted = []) {
  let response;
  try {
    response = await fetchImpl(url, {...options, redirect: "manual", signal: AbortSignal.timeout(25000)});
  } catch (_) {
    throw new CalendarProviderError("network-error");
  }
  if (!response.ok && !accepted.includes(response.status)) throw errorFor(response);
  return response;
}
async function jsonBody(response) {
  try {
    return JSON.parse(await textBody(response));
  } catch (error) {
    if (error instanceof CalendarProviderError) throw error;
    fail("invalid-response");
  }
}
function checkObject(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) fail("invalid-response");
  return value;
}
function append(items, rows) {
  if (!Array.isArray(rows)) fail("invalid-response");
  items.push(...rows);
  if (items.length > MAX_ITEMS) fail("too-many-events");
}
function wrapped(raw) {
  checkObject(raw);
  required(raw.id, "event-id");
  return {id: raw.id, etag: raw.etag || raw["@odata.etag"] || null,
    deleted: raw.status === "cancelled" || !!raw["@removed"], raw};
}
function payload(event) {
  checkObject(event);
  // Invitations need a separate user-approved product flow. Never send them as a side effect of sync.
  if (event.attendees?.length || event.organizer) fail("unsupported-invitations");
  return event;
}

class GoogleCalendarProvider {
  constructor({accessToken, fetchImpl = globalThis.fetch}) {
    this.headers = {Authorization: `Bearer ${required(accessToken, "access-token")}`};
    this.fetch = fetchImpl;
  }
  async call(path, {method = "GET", body, headers = {}, accepted = []} = {}) {
    const response = await request(this.fetch, `${GOOGLE}${path}`, {
      method, headers: {...this.headers, ...headers, ...(body ? {"Content-Type": "application/json"} : {})},
      ...(body ? {body: JSON.stringify(body)} : {}),
    }, accepted);
    return {response, data: response.status === 204 ? null : await jsonBody(response)};
  }
  path(calendarId, eventId = "") {
    return `calendars/${encodeURIComponent(required(calendarId, "calendar-id"))}/events${eventId ? `/${encodeURIComponent(required(eventId, "event-id"))}` : ""}`;
  }
  async listCalendars() {
    const items = [];
    let token = "";
    const seen = new Set();
    for (let page = 0; page < MAX_PAGES; page++) {
      const query = new URLSearchParams({maxResults: "250", ...(token ? {pageToken: token} : {})});
      const {data} = await this.call(`users/me/calendarList?${query}`);
      append(items, (data.items || []).map((raw) => ({id: raw.id, name: raw.summary || "",
        writable: ["owner", "writer"].includes(raw.accessRole), timeZone: raw.timeZone || null, raw})));
      if (!data.nextPageToken) return items;
      token = required(data.nextPageToken, "page-token");
      if (seen.has(token)) fail("invalid-pagination");
      seen.add(token);
    }
    fail("too-many-pages");
  }
  async listEvents(calendarId, {syncToken = null} = {}) {
    const items = [];
    let pageToken = "";
    const seen = new Set();
    for (let page = 0; page < MAX_PAGES; page++) {
      const query = new URLSearchParams({maxResults: "250", singleEvents: "false", showDeleted: "true",
        ...(syncToken ? {syncToken: required(syncToken, "sync-token")} : {}), ...(pageToken ? {pageToken} : {})});
      const {data} = await this.call(`${this.path(calendarId)}?${query}`);
      append(items, (data.items || []).map(wrapped));
      if (!data.nextPageToken) return {items, syncToken: required(data.nextSyncToken, "sync-token"), full: !syncToken};
      pageToken = required(data.nextPageToken, "page-token");
      if (seen.has(pageToken)) fail("invalid-pagination");
      seen.add(pageToken);
    }
    fail("too-many-pages");
  }
  async getEvent(calendarId, id) {
    const {data} = await this.call(this.path(calendarId, id));
    const item = wrapped(data);
    if (!item.deleted && Array.isArray(data.recurrence) && data.recurrence.length) {
      // A master GET omits detached/cancelled instance records. Probe the same
      // iCalUID before a pending write is replayed, not just on normal list sync.
      item.raw = {...data, vardagSeriesHasExceptions: await this.hasSeriesExceptions(calendarId, data)};
    }
    return item;
  }
  async hasSeriesExceptions(calendarId, master) {
    if (typeof master.iCalUID !== "string" || !master.iCalUID) return true; // Fail closed: incomplete identity.
    let pageToken = "";
    const seen = new Set();
    for (let page = 0; page < MAX_PAGES; page++) {
      const query = new URLSearchParams({iCalUID: master.iCalUID, maxResults: "250", singleEvents: "false", showDeleted: "true",
        ...(pageToken ? {pageToken} : {})});
      const {data} = await this.call(`${this.path(calendarId)}?${query}`);
      if (data.items !== undefined && !Array.isArray(data.items)) fail("invalid-response");
      for (const row of data.items || []) {
        if (row.recurringEventId === master.id) return true;
        if (row.id === master.id && master.etag && row.etag !== master.etag) fail("provider-changed-during-sync");
      }
      if (!data.nextPageToken) return false;
      pageToken = required(data.nextPageToken, "page-token");
      if (seen.has(pageToken)) fail("invalid-pagination");
      seen.add(pageToken);
    }
    fail("too-many-pages");
  }
  async createEvent(calendarId, {operationId, event}) {
    payload(event);
    if (event.id || event.iCalUID || event.recurringEventId || event.originalStartTime) fail("unsupported-create-identity");
    const key = hash(operationId);
    const {id} = createdEventIdentity("google", calendarId, operationId);
    const body = {...event, id, extendedProperties: {...event.extendedProperties,
      private: {...event.extendedProperties?.private, vardagOperationId: key}}};
    try {
      const {data} = await this.call(this.path(calendarId), {method: "POST", body});
      return wrapped(data);
    } catch (error) {
      if (error.status !== 409) throw error;
      const existing = await this.getEvent(calendarId, id);
      if (existing.raw.extendedProperties?.private?.vardagOperationId !== key) throw error;
      return {...existing, alreadyExists: true};
    }
  }
  async updateEvent(calendarId, id, event, {etag} = {}) {
    payload(event);
    const {data} = await this.call(this.path(calendarId, id), {method: "PATCH", body: event, headers: etagHeaders(etag)});
    return wrapped(data);
  }
  async deleteEvent(calendarId, id, {etag} = {}) {
    try {
      await this.call(this.path(calendarId, id), {method: "DELETE", headers: etagHeaders(etag)});
    } catch (error) {
      if (error.status !== 404 && error.status !== 410) throw error;
    }
    return {id, deleted: true};
  }
}

function graphUrl(value, expectedPath) {
  let url;
  try {
    url = new URL(value);
  } catch (_) {
    fail("unsafe-url");
  }
  if (url.origin !== "https://graph.microsoft.com" || url.username || url.password || url.hash ||
    !url.pathname.startsWith("/v1.0/") || (expectedPath && url.pathname !== expectedPath)) fail("unsafe-url");
  return url.href;
}
class OutlookCalendarProvider {
  constructor({accessToken, fetchImpl = globalThis.fetch}) {
    this.headers = {Authorization: `Bearer ${required(accessToken, "access-token")}`,
      Prefer: "IdType=\"ImmutableId\", outlook.timezone=\"UTC\""};
    this.fetch = fetchImpl;
  }
  path(calendarId, eventId = "") {
    return `me/calendars/${encodeURIComponent(required(calendarId, "calendar-id"))}/events${eventId ? `/${encodeURIComponent(required(eventId, "event-id"))}` : ""}`;
  }
  async call(url, {method = "GET", body, headers = {}} = {}) {
    const response = await request(this.fetch, graphUrl(url), {method,
      headers: {...this.headers, ...headers, ...(body ? {"Content-Type": "application/json"} : {})},
      ...(body ? {body: JSON.stringify(body)} : {}),
    });
    return response.status === 204 ? null : await jsonBody(response);
  }
  async collect(path) {
    let url = `${GRAPH}${path}`;
    const expectedPath = new URL(url).pathname;
    const items = [];
    const seen = new Set();
    for (let page = 0; page < MAX_PAGES; page++) {
      const data = await this.call(url);
      append(items, data.value);
      if (!data["@odata.nextLink"]) return items;
      url = graphUrl(data["@odata.nextLink"], expectedPath);
      if (seen.has(url)) fail("invalid-pagination");
      seen.add(url);
    }
    fail("too-many-pages");
  }
  async listCalendars() {
    return (await this.collect("me/calendars")).map((raw) => ({id: raw.id,
      name: raw.name || "", writable: raw.canEdit === true, raw}));
  }
  async listEvents(calendarId, {syncToken = null} = {}) {
    // The stable delta endpoint expands a primary-calendar date window. Listing raw
    // masters for ANY selected calendar avoids losing recurrence/exception semantics.
    if (syncToken) fail("unsupported-sync-token");
    const items = (await this.collect(this.path(calendarId))).map(wrapped);
    for (let index = 0; index < items.length; index++) items[index] = await this.enrichSeries(calendarId, items[index]);
    return {items, syncToken: null, full: true};
  }
  async enrichSeries(calendarId, item) {
    if (item.raw.type !== "seriesMaster") return item;
    // Graph omits cancelled and changed occurrences from /events. They must
    // be requested explicitly on the master; otherwise a cancelled Monday
    // would silently reappear after an import or export.
    const select = ["id", "subject", "start", "end", "body", "location", "locations",
      "isAllDay", "recurrence", "originalStart", "originalStartTimeZone",
      "originalEndTimeZone", "seriesMasterId", "type", "occurrenceId", "sensitivity",
      "showAs", "lastModifiedDateTime", "attendees", "organizer",
      "exceptionOccurrences", "cancelledOccurrences"].join(",");
    const query = new URLSearchParams({"$select": select, "$expand": "exceptionOccurrences"});
    const detail = await this.call(`${GRAPH}${this.path(calendarId, item.id)}?${query}`);
    if (detail.id !== item.id) fail("invalid-response");
    if (item.etag && detail["@odata.etag"] !== item.etag) fail("provider-changed-during-sync");
    if (detail["exceptionOccurrences@odata.nextLink"]) fail("unsupported-exception-pagination");
    item.raw = {...item.raw, ...detail};
    item.etag = detail["@odata.etag"] || item.etag;
    return item;
  }
  async getEvent(calendarId, id) {
    return this.enrichSeries(calendarId, wrapped(await this.call(`${GRAPH}${this.path(calendarId, id)}`)));
  }
  async createEvent(calendarId, {operationId, event}) {
    payload(event);
    if (event.id || event.seriesMasterId || event.type === "exception" || event.type === "occurrence") fail("unsupported-create-identity");
    const {transactionId} = createdEventIdentity("outlook", calendarId, operationId);
    return wrapped(await this.call(`${GRAPH}${this.path(calendarId)}`, {method: "POST", body: {...event, transactionId}}));
  }
  async updateEvent(calendarId, id, event, {etag} = {}) {
    payload(event);
    return wrapped(await this.call(`${GRAPH}${this.path(calendarId, id)}`, {method: "PATCH", body: event, headers: etagHeaders(etag)}));
  }
  async deleteEvent(calendarId, id, {etag} = {}) {
    try {
      await this.call(`${GRAPH}${this.path(calendarId, id)}`, {method: "DELETE", headers: etagHeaders(etag)});
    } catch (error) {
      if (error.status !== 404) throw error;
    }
    return {id, deleted: true};
  }
}

function icloudUrl(value, base = "https://caldav.icloud.com/") {
  let url;
  try {
    url = new URL(value, base);
  } catch (_) {
    fail("unsafe-url");
  }
  if (url.protocol !== "https:" || url.port || url.username || url.password || url.hash || url.search ||
    !/^(?:caldav|p\d+-caldav)\.icloud\.com$/.test(url.hostname)) fail("unsafe-url");
  if (/%2f|%5c|%00/i.test(url.pathname)) fail("unsafe-url");
  return url.href;
}
function resourceUrl(calendarId, id) {
  const calendar = icloudUrl(calendarId);
  if (!calendar.endsWith("/")) fail("invalid-calendar-id");
  const url = icloudUrl(id, calendar);
  if (!url.startsWith(calendar) || url === calendar || new URL(url).pathname.slice(new URL(calendar).pathname.length).includes("/")) fail("unsafe-url");
  return url;
}
const array = (value) => value === undefined || value === null ? [] : Array.isArray(value) ? value : [value];
function xmlText(value) {
  return typeof value === "string" ? value : typeof value === "object" && value ? value["#text"] || "" : "";
}
const escapeXml = (value) => String(value).replace(/[&<>"']/g, (char) => ({"&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&apos;"})[char]);
function xml(body) {
  if (/<!DOCTYPE|<!ENTITY/i.test(body) || XMLValidator.validate(body) !== true) fail("invalid-xml");
  try {
    return new XMLParser({ignoreAttributes: false, removeNSPrefix: true, parseTagValue: false}).parse(body);
  } catch (_) {
    fail("invalid-xml");
  }
}
function multistatus(body) {
  const root = xml(body).multistatus;
  if (!root) fail("invalid-response");
  return {token: xmlText(root["sync-token"]), rows: array(root.response).map((row) => {
    let props = {};
    for (const stat of array(row.propstat)) {
      if (/\s200(?:\s|$)/.test(xmlText(stat.status))) props = {...props, ...stat.prop};
    }
    return {href: xmlText(row.href), status: xmlText(row.status), props};
  })};
}
function propfindBody(props) {
  return `<?xml version="1.0" encoding="utf-8"?><d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav"><d:prop>${props}</d:prop></d:propfind>`;
}
function checkedIcs(event) {
  const text = event?.ics;
  if (typeof text !== "string" || Buffer.byteLength(text) > MAX_BYTES || !/^BEGIN:VCALENDAR\r?\n/.test(text) || !/\r?\nEND:VCALENDAR\s*$/.test(text)) fail("invalid-ics");
  // The adapter passes the full calendar resource through: RRULE, EXDATE,
  // RECURRENCE-ID and VTIMEZONE must survive a read/modify/write round trip.
  const unfolded = text.replace(/\r?\n[ \t]/g, "");
  if (/^ATTENDEE[;:]/mi.test(unfolded) || /^ORGANIZER[;:]/mi.test(unfolded) || /^METHOD[;:]/mi.test(unfolded)) fail("unsupported-invitations");
  let entries;
  try {
    entries = Object.values(ical.sync.parseICS(text)).filter((item) => item.type === "VEVENT");
  } catch (_) {
    fail("invalid-ics");
  }
  if (entries.length !== 1 || !entries[0].uid) fail("unsupported-multiple-uids");
  return {text, uid: entries[0].uid};
}
class ICloudCalendarProvider {
  constructor({username, appPassword, fetchImpl = globalThis.fetch}) {
    required(username, "username");
    if (username.includes(":")) fail("invalid-username");
    this.headers = {Authorization: `Basic ${Buffer.from(`${username}:${required(appPassword, "app-password")}`).toString("base64")}`};
    this.fetch = fetchImpl;
  }
  async call(url, {method = "GET", body, headers = {}, accepted = []} = {}) {
    let target = icloudUrl(url);
    for (let redirect = 0; redirect < 4; redirect++) {
      const response = await request(this.fetch, target, {method,
        headers: {...this.headers, ...headers, ...(body ? {"Content-Type": method === "PUT" ? "text/calendar; charset=utf-8" : "application/xml; charset=utf-8"} : {})},
        ...(body ? {body} : {}),
      }, [...accepted, 301, 302, 307, 308]);
      if (![301, 302, 307, 308].includes(response.status)) return {response, url: target, text: await textBody(response)};
      const location = response.headers.get("location");
      if (!location) fail("invalid-redirect");
      target = icloudUrl(location, target);
    }
    fail("too-many-redirects");
  }
  async props(url, names, depth = "0") {
    const response = await this.call(url, {method: "PROPFIND", body: propfindBody(names), headers: {Depth: depth}});
    return {...multistatus(response.text), url: response.url};
  }
  async listCalendars() {
    const principalResult = await this.props("https://caldav.icloud.com/", "<d:current-user-principal/>");
    const principalHref = principalResult.rows.find((row) => row.props["current-user-principal"]?.href)?.props["current-user-principal"].href;
    if (!principalHref) fail("missing-principal");
    const principal = icloudUrl(xmlText(principalHref), principalResult.url);
    const homeResult = await this.props(principal, "<c:calendar-home-set/>");
    const homeHref = homeResult.rows.find((row) => row.props["calendar-home-set"]?.href)?.props["calendar-home-set"].href;
    if (!homeHref) fail("missing-calendar-home");
    const home = icloudUrl(xmlText(homeHref), homeResult.url);
    const result = await this.props(home, "<d:resourcetype/><d:displayname/><d:current-user-privilege-set/><c:supported-calendar-component-set/>", "1");
    return result.rows.filter((row) => row.props.resourcetype && Object.hasOwn(row.props.resourcetype, "calendar")).flatMap((row) => {
      const components = array(row.props["supported-calendar-component-set"]?.comp);
      if (components.length && !components.some((item) => item["@_name"] === "VEVENT")) return [];
      const privileges = array(row.props["current-user-privilege-set"]?.privilege);
      const has = (key) => privileges.some((item) => Object.hasOwn(item, key));
      return [{id: icloudUrl(row.href, result.url), name: xmlText(row.props.displayname),
        writable: has("all") || has("write") || (has("write-content") && has("bind") && has("unbind")), raw: row.props}];
    });
  }
  async getEvent(calendarId, id) {
    const target = resourceUrl(calendarId, id);
    const result = await this.call(target);
    const etag = result.response.headers.get("etag");
    if (!etag) fail("missing-etag");
    if (!/^BEGIN:VCALENDAR\r?\n/.test(result.text)) fail("invalid-ics");
    return {id: target, etag, deleted: false, raw: {ics: result.text}};
  }
  async listEvents(calendarId, {syncToken = null} = {}) {
    const target = icloudUrl(calendarId);
    if (syncToken) required(syncToken, "sync-token");
    const body = `<?xml version="1.0"?><d:sync-collection xmlns:d="DAV:"><d:sync-token>${escapeXml(syncToken || "")}</d:sync-token><d:sync-level>1</d:sync-level><d:prop><d:getetag/></d:prop></d:sync-collection>`;
    const result = await this.call(target, {method: "REPORT", body, headers: {Depth: "1"}, accepted: [400, 403, 405, 409, 501]});
    if (!result.response.ok) {
      const expiredToken = /<(?:[A-Za-z0-9_-]+:)?valid-sync-token[\s/>]/.test(result.text);
      if (syncToken && expiredToken) throw new CalendarProviderError("sync-reset-required", result.response.status);
      if (!syncToken && [400, 405, 501].includes(result.response.status)) return this.fullEvents(target);
      throw errorFor(result.response);
    }
    const parsed = multistatus(result.text);
    const token = required(parsed.token, "sync-token");
    const items = [];
    if (parsed.rows.length > MAX_ITEMS) fail("too-many-events");
    for (const row of parsed.rows) {
      if (icloudUrl(row.href, target) === target) continue;
      const id = resourceUrl(target, row.href);
      if (/\s404(?:\s|$)/.test(row.status)) items.push({id, etag: null, deleted: true, raw: {}});
      else {
        // A concurrent deletion is an explicit tombstone; other failures must
        // abort the entire sync, never masquerade as a complete empty calendar.
        try {
          items.push(await this.getEvent(target, id));
        } catch (error) {
          if (error.status === 404) items.push({id, etag: null, deleted: true, raw: {}}); else throw error;
        }
      }
    }
    return {items, syncToken: token, full: !syncToken};
  }
  async fullEvents(calendarId) {
    const body = "<?xml version=\"1.0\"?><c:calendar-query xmlns:d=\"DAV:\" xmlns:c=\"urn:ietf:params:xml:ns:caldav\"><d:prop><d:getetag/><c:calendar-data/></d:prop><c:filter><c:comp-filter name=\"VCALENDAR\"><c:comp-filter name=\"VEVENT\"/></c:comp-filter></c:filter></c:calendar-query>";
    const result = await this.call(calendarId, {method: "REPORT", body, headers: {Depth: "1"}});
    const items = multistatus(result.text).rows.map((row) => {
      const ics = xmlText(row.props["calendar-data"]);
      if (!ics.startsWith("BEGIN:VCALENDAR")) fail("invalid-ics");
      return {id: resourceUrl(calendarId, row.href), etag: required(xmlText(row.props.getetag), "etag"), deleted: false, raw: {ics}};
    });
    if (items.length > MAX_ITEMS) fail("too-many-events");
    return {items, syncToken: null, full: true};
  }
  async createEvent(calendarId, {operationId, event}) {
    const {text, uid} = checkedIcs(event);
    const {id} = createdEventIdentity("icloud", calendarId, operationId);
    try {
      await this.call(id, {method: "PUT", body: text, headers: {"If-None-Match": "*"}});
    } catch (error) {
      if (error.status !== 412) throw error;
      const existing = await this.getEvent(calendarId, id);
      if (checkedIcs(existing.raw).uid !== uid) throw error;
      return {...existing, alreadyExists: true};
    }
    return this.getEvent(calendarId, id);
  }
  async updateEvent(calendarId, id, event, {etag} = {}) {
    const body = checkedIcs(event).text;
    await this.call(resourceUrl(calendarId, id), {method: "PUT", body, headers: etagHeaders(etag)});
    return this.getEvent(calendarId, id);
  }
  async deleteEvent(calendarId, id, {etag} = {}) {
    const target = resourceUrl(calendarId, id);
    try {
      await this.call(target, {method: "DELETE", headers: etagHeaders(etag)});
    } catch (error) {
      if (error.status !== 404) throw error;
    }
    return {id: target, deleted: true};
  }
}

// Shared with quarantine recovery: never duplicate the create-id algorithm in
// the sync worker or guess an event by title/time after an ambiguous request.
function createdEventIdentity(provider, calendarId, operationId) {
  const value = hash(operationId);
  if (provider === "google") return {id: `v${value}`}; // Google base32hex alphabet.
  if (provider === "icloud") return {id: resourceUrl(calendarId, `${value}.ics`)};
  if (provider === "outlook") return {transactionId: `${value.slice(0, 8)}-${value.slice(8, 12)}-5${value.slice(13, 16)}-a${value.slice(17, 20)}-${value.slice(20, 32)}`};
  fail("unsupported-provider");
}

module.exports = {GoogleCalendarProvider, OutlookCalendarProvider, ICloudCalendarProvider, CalendarProviderError, createdEventIdentity};
