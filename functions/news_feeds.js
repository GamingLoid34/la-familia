/* eslint-disable valid-jsdoc, max-len */
/**
 * Skolnyheter: RSS-källor till assistentens inkorg.
 *
 * Kontraktet är `docs/assistent-rss-tillagg.md` i Android-repot, ett tillägg till steg 3.
 * Ett RSS-flöde från skolan blir en automatisk källa till `notes`; tolkning, granskning och
 * bekräftelse sker sedan exakt som för en inklistrad text (note_inbox.js, note_confirm.js).
 *
 * Fyra saker styr designen:
 * - Synken har klientens rättigheter i statusmaskinen. Varje skrivning den gör leder till
 *   `saved`; `interpreting` och allt därefter tillhör triggern och bekräftelsen.
 * - Import och tolkning skiljs åt. En ny post skapas utan `requestId`, och triggern tolkar bara
 *   anteckningar som har ett. Dräneringen sist i varje körning delar ut begärans-id inom kvoten,
 *   så 30 nya poster mot 10 i kvot aldrig ger 20 anteckningar i `failed`.
 * - Synken raderar aldrig. En post som försvinner ur flödet ligger kvar i inkorgen.
 * - Adressen är en åtkomstnyckel. Den ligger bara i `news_feed_secrets`, som ingen klient läser,
 *   och skrivs aldrig i loggar eller felmeddelanden.
 */
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");
const crypto = require("node:crypto");
const dns = require("node:dns").promises;
const net = require("node:net");
const {XMLParser} = require("fast-xml-parser");
const {htmlToText} = require("./ics_text_import");
const {NOTE_QUOTA_PER_DAY, QUOTA_EXHAUSTED_MESSAGE, stockholmDateKey} = require("./note_inbox");

const MAX_FEED_BYTES = 2 * 1024 * 1024;
const FETCH_TIMEOUT_MS = 20000;
const MAX_REDIRECTS = 3;
const MAX_ITEMS_PER_FETCH = 200;
const MAX_URL_LENGTH = 2000;

/**
 * Högst så många anteckningar per familj och körning får begärans-id. Med två körningar per
 * dygn tar skolnyheterna högst 10 av de 20 tolkningarna, och resten finns kvar för text som
 * klistras in under dagen.
 */
const QUEUE_CAP_PER_RUN = 5;

/** Samma tak som reglerna sätter på `notes.text`. */
const MAX_NOTE_TEXT = 10000;

/**
 * Hur långt bakåt den första hämtningen tar med poster. Utan marginal gav varje ny källa
 * "0 nyheter hämtade", eftersom allt i flödet var publicerat före prenumerationen, och
 * familjen kunde inte se att något fungerade förrän skolan skrev nästa gång.
 */
const FIRST_SYNC_LOOKBACK_MS = 7 * 24 * 60 * 60 * 1000;

/** En tolkning som pågått längre än så har dött; den räknas inte längre mot dagens kvot. */
const STALE_INTERPRETING_MS = 10 * 60 * 1000;

/**
 * Ett fel vars text får visas för familjen och skrivas i loggen. Innehåller aldrig adressen.
 */
class FeedError extends Error {
  /**
   * @param {string} message
   * @param {string} [code] HttpsError-kod när felet når en callable
   */
  constructor(message, code = "unavailable") {
    super(message);
    this.name = "FeedError";
    this.code = code;
  }
}

/**
 * Text som är säker att visa och logga. Okända fel kan bära adressen (nätverksfel från fetch
 * nämner värden), så de får aldrig sin egen text vidare.
 * @param {unknown} err
 * @return {string}
 */
function safeMessage(err) {
  return err instanceof FeedError ? err.message : "Kunde inte hämta skolnyheter.";
}

// --- Adressen ---

/**
 * @param {unknown} raw
 * @return {URL}
 */
function parseFeedUrl(raw) {
  if (typeof raw !== "string" || !raw.trim()) {
    throw new FeedError("Länk till flödet krävs.", "invalid-argument");
  }
  const text = raw.trim();
  if (text.length > MAX_URL_LENGTH) {
    throw new FeedError("Länken är för lång.", "invalid-argument");
  }
  let url;
  try {
    url = new URL(text);
  } catch (_) {
    throw new FeedError("Länken går inte att läsa.", "invalid-argument");
  }
  if (url.protocol !== "https:") {
    throw new FeedError("Länken måste börja med https://.", "invalid-argument");
  }
  if (url.username || url.password) {
    throw new FeedError("Länken får inte innehålla användarnamn eller lösenord.", "invalid-argument");
  }
  // Bara standardporten: funktionen ska inte kunna användas för att knacka på andra tjänster.
  if (url.port && url.port !== "443") {
    throw new FeedError("Länken får inte ange en egen port.", "invalid-argument");
  }
  return url;
}

/**
 * Är adressen privat, lokal eller på annat sätt inte en publik server?
 * @param {string} ip
 * @return {boolean}
 */
function isPrivateAddress(ip) {
  if (net.isIPv4(ip)) {
    const [a, b] = ip.split(".").map(Number);
    if (a === 0 || a === 10 || a === 127) return true;
    if (a === 100 && b >= 64 && b <= 127) return true; // CGNAT
    if (a === 169 && b === 254) return true; // länklokal, bl.a. metadata-servern
    if (a === 172 && b >= 16 && b <= 31) return true;
    if (a === 192 && b === 168) return true;
    if (a === 192 && b === 0) return true; // 192.0.0.0/24 och 192.0.2.0/24
    if (a === 198 && (b === 18 || b === 19)) return true;
    if (a >= 224) return true; // multicast och reserverat
    return false;
  }
  if (net.isIPv6(ip)) {
    const lower = ip.toLowerCase();
    const mapped = lower.match(/^::ffff:(\d+\.\d+\.\d+\.\d+)$/);
    if (mapped) return isPrivateAddress(mapped[1]);
    if (lower === "::" || lower === "::1") return true;
    const first = parseInt(lower.split(":")[0] || "0", 16);
    if ((first & 0xfe00) === 0xfc00) return true; // fc00::/7 unik lokal
    if ((first & 0xffc0) === 0xfe80) return true; // fe80::/10 länklokal
    if ((first & 0xff00) === 0xff00) return true; // multicast
    if (lower.startsWith("64:ff9b:")) return true; // NAT64, kan peka på vad som helst
    return false;
  }
  return true;
}

/**
 * Värden måste vara en publik server. Kontrolleras före varje hämtning och efter varje
 * omdirigering, så en omdirigering inte kan leda in i projektets eget nät.
 * @param {URL} url
 * @param {Function} lookup dns.lookup-kompatibel
 */
async function assertPublicHost(url, lookup) {
  const host = url.hostname.replace(/^\[|\]$/g, "");
  if (host === "localhost" || host.endsWith(".localhost") || host.endsWith(".internal")) {
    throw new FeedError("Länken pekar inte på en publik server.", "invalid-argument");
  }
  let addresses;
  if (net.isIP(host)) {
    addresses = [host];
  } else {
    try {
      const found = await lookup(host, {all: true, verbatim: true});
      addresses = found.map((a) => a.address);
    } catch (_) {
      throw new FeedError("Kunde inte hitta servern för skolnyheterna.");
    }
  }
  if (!addresses.length || addresses.some(isPrivateAddress)) {
    throw new FeedError("Länken pekar inte på en publik server.", "invalid-argument");
  }
}

/**
 * Läser svaret med ett tak, så ett jättelikt flöde inte fyller minnet innan storleken märks.
 * @param {Response} res
 * @return {Promise<Buffer>}
 */
async function readLimited(res) {
  const declared = Number(res.headers.get("content-length") || 0);
  if (declared > MAX_FEED_BYTES) {
    throw new FeedError("Flödet är för stort (max 2 MB).");
  }
  if (!res.body || typeof res.body.getReader !== "function") {
    const buf = Buffer.from(await res.arrayBuffer());
    if (buf.byteLength > MAX_FEED_BYTES) throw new FeedError("Flödet är för stort (max 2 MB).");
    return buf;
  }
  const reader = res.body.getReader();
  const chunks = [];
  let total = 0;
  for (;;) {
    const {done, value} = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > MAX_FEED_BYTES) {
      await reader.cancel().catch(() => {});
      throw new FeedError("Flödet är för stort (max 2 MB).");
    }
    chunks.push(Buffer.from(value));
  }
  return Buffer.concat(chunks);
}

/**
 * Avkodar flödet. XML-deklarationen eller content-type avgör teckenkodningen; äldre svenska
 * system skickar ibland ISO-8859-1.
 * @param {Buffer} buf
 * @param {string} contentType
 * @return {string}
 */
function decodeFeed(buf, contentType) {
  const head = buf.subarray(0, 200).toString("latin1");
  const declared = (head.match(/encoding=["']([\w-]+)["']/i) || [])[1] ||
    ((contentType || "").match(/charset=([\w-]+)/i) || [])[1] || "utf-8";
  const label = declared.toLowerCase();
  const encoding = label === "iso-8859-1" || label === "latin1" || label === "windows-1252" ?
    "windows-1252" : "utf-8";
  return new TextDecoder(encoding).decode(buf);
}

/**
 * Hämtar flödet med villkorad GET och egna omdirigeringar.
 * @param {string} urlText
 * @param {{etag?: string|null, lastModified?: string|null}} conditional
 * @param {{fetch?: Function, lookup?: Function}} deps
 * @return {Promise<{notModified: boolean, text?: string, etag?: string|null, lastModified?: string|null}>}
 */
async function fetchFeed(urlText, conditional = {}, deps = {}) {
  const doFetch = deps.fetch || fetch;
  const lookup = deps.lookup || dns.lookup;
  let current = parseFeedUrl(urlText);

  for (let hop = 0; hop <= MAX_REDIRECTS; hop++) {
    await assertPublicHost(current, lookup);
    const headers = {"user-agent": "LaFamiliaNewsSync/1.0", "accept": "application/rss+xml, application/atom+xml, application/xml, text/xml"};
    if (conditional.etag) headers["if-none-match"] = conditional.etag;
    if (conditional.lastModified) headers["if-modified-since"] = conditional.lastModified;

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);
    try {
      let res;
      try {
        res = await doFetch(current.toString(), {redirect: "manual", signal: controller.signal, headers});
      } catch (_) {
        throw new FeedError(controller.signal.aborted ?
          "Kunde inte hämta skolnyheter (tidsgränsen passerades)." :
          "Kunde inte hämta skolnyheter.");
      }
      if ([301, 302, 303, 307, 308].includes(res.status)) {
        const location = res.headers.get("location");
        if (!location) throw new FeedError(`Kunde inte hämta skolnyheter (HTTP ${res.status}).`);
        let next;
        try {
          next = new URL(location, current);
        } catch (_) {
          throw new FeedError("Kunde inte hämta skolnyheter (ogiltig omdirigering).");
        }
        current = parseFeedUrl(next.toString());
        continue;
      }
      if (res.status === 304) return {notModified: true};
      if (!res.ok) throw new FeedError(`Kunde inte hämta skolnyheter (HTTP ${res.status}).`);
      let buf;
      try {
        buf = await readLimited(res);
      } catch (err) {
        if (err instanceof FeedError) throw err;
        throw new FeedError(controller.signal.aborted ?
          "Kunde inte hämta skolnyheter (tidsgränsen passerades)." :
          "Kunde inte hämta skolnyheter.");
      }
      return {
        notModified: false,
        text: decodeFeed(buf, res.headers.get("content-type")),
        etag: res.headers.get("etag") || null,
        lastModified: res.headers.get("last-modified") || null,
      };
    } finally {
      clearTimeout(timer);
    }
  }
  throw new FeedError("Kunde inte hämta skolnyheter (för många omdirigeringar).");
}

// --- Flödet ---

/**
 * @param {unknown} value nod ur XML-parsern
 * @return {string}
 */
function textOf(value) {
  if (value == null) return "";
  if (Array.isArray(value)) return textOf(value[0]);
  if (typeof value === "string") return value.trim();
  if (typeof value === "number" || typeof value === "boolean") return String(value);
  if (typeof value === "object" && "#text" in value) return textOf(value["#text"]);
  return "";
}

/**
 * @param {string} raw
 * @return {Date|null}
 */
function parseDate(raw) {
  if (!raw) return null;
  const d = new Date(raw);
  return Number.isNaN(d.getTime()) ? null : d;
}

/**
 * Atom: länken med rel="alternate" eller utan rel.
 * @param {unknown} links
 * @return {string}
 */
function atomLink(links) {
  const list = Array.isArray(links) ? links : (links ? [links] : []);
  const pick = list.find((l) => l && typeof l === "object" && (!l["@_rel"] || l["@_rel"] === "alternate")) || list[0];
  if (!pick) return "";
  if (typeof pick === "string") return pick.trim();
  return String(pick["@_href"] || textOf(pick) || "").trim();
}

/**
 * Tolkar RSS 2.0, RSS 1.0 och Atom till en enhetlig form. Läser högst 200 poster.
 * @param {string} xml
 * @return {Array<{guid: string, link: string, title: string, description: string, pubDateRaw: string, publishedAt: Date|null}>}
 */
function parseFeed(xml) {
  // DOCTYPE tas bort före tolkningen: egna entiteter i ett flöde behövs aldrig, och de är
  // vägen in för entitetsexpansion som fyller minnet.
  const cleaned = String(xml || "").replace(/<!DOCTYPE[^[>]*(\[[\s\S]*?\])?\s*>/gi, "");
  const parser = new XMLParser({
    ignoreAttributes: false,
    attributeNamePrefix: "@_",
    textNodeName: "#text",
    parseTagValue: false,
    parseAttributeValue: false,
    trimValues: true,
    processEntities: true,
    htmlEntities: false,
  });
  let doc;
  try {
    doc = parser.parse(cleaned);
  } catch (_) {
    throw new FeedError("Flödet gick inte att läsa som RSS.");
  }
  const asList = (v) => (Array.isArray(v) ? v : (v == null ? [] : [v]));

  let items;
  if (doc && doc.rss && doc.rss.channel) {
    const channel = Array.isArray(doc.rss.channel) ? doc.rss.channel[0] : doc.rss.channel;
    items = asList(channel.item).map((it) => {
      const pubDateRaw = textOf(it.pubDate) || textOf(it["dc:date"]);
      return {
        guid: textOf(it.guid),
        link: textOf(it.link),
        title: textOf(it.title),
        description: textOf(it.description) || textOf(it["content:encoded"]),
        pubDateRaw,
        publishedAt: parseDate(pubDateRaw),
      };
    });
  } else if (doc && doc["rdf:RDF"]) {
    items = asList(doc["rdf:RDF"].item).map((it) => {
      const pubDateRaw = textOf(it["dc:date"]);
      return {
        guid: textOf(it["@_rdf:about"]),
        link: textOf(it.link),
        title: textOf(it.title),
        description: textOf(it.description),
        pubDateRaw,
        publishedAt: parseDate(pubDateRaw),
      };
    });
  } else if (doc && doc.feed) {
    items = asList(doc.feed.entry).map((it) => {
      const pubDateRaw = textOf(it.published) || textOf(it.updated);
      return {
        guid: textOf(it.id),
        link: atomLink(it.link),
        title: textOf(it.title),
        description: textOf(it.content) || textOf(it.summary),
        pubDateRaw,
        publishedAt: parseDate(pubDateRaw),
      };
    });
  } else {
    throw new FeedError("Länken ger inget RSS-flöde.");
  }
  return items.slice(0, MAX_ITEMS_PER_FETCH);
}

/**
 * @param {string} text
 * @return {string} sha-256 som gemena hexadecimaler
 */
function sha256(text) {
  return crypto.createHash("sha256").update(text, "utf8").digest("hex");
}

/**
 * Dedupnyckel inom källan: guid, annars länk, annars hash av rubrik och datum.
 * @param {{guid: string, link: string, title: string, pubDateRaw: string}} item
 * @return {string}
 */
function sourceKeyFor(item) {
  if (item.guid) return item.guid;
  if (item.link) return item.link;
  if (!item.title && !item.pubDateRaw) return "";
  return `sha256:${sha256(`${item.title}\n${item.pubDateRaw}`)}`;
}

/**
 * Dokument-id ur källa och nyckel. Gör skapandet idempotent även när två körningar möts:
 * `create` misslyckas om dokumentet redan finns, mjukraderat eller inte.
 * @param {string} feedId
 * @param {string} sourceKey
 * @return {string}
 */
function noteIdFor(feedId, sourceKey) {
  return `rss_${feedId}_${sha256(sourceKey).slice(0, 40)}`;
}

// Blanktecken som Kotlins `String.trim()` tar bort (Char.isWhitespace), och de som Javas `\s`
// matchar. Skiljer sig från JavaScripts `\s` och `trim()`: hårt mellanslag mitt i en rad slås
// inte ihop i Android, och då får det inte göra det här heller.
const KOTLIN_WHITESPACE = new Set([
  0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x1c, 0x1d, 0x1e, 0x1f, 0x20, 0xa0, 0x1680,
  0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006, 0x2007, 0x2008, 0x2009, 0x200a,
  0x2028, 0x2029, 0x202f, 0x205f, 0x3000,
]);
// Mellanslag, tab, radbrytning, vertikal tab, sidbrytning och vagnretur: Javas `\s`.
const JAVA_WHITESPACE = new RegExp(`[ ${String.fromCharCode(9, 10, 11, 12, 13)}]+`, "g");

/**
 * Kotlins `String.trim()`.
 * @param {string} line
 * @return {string}
 */
function kotlinTrim(line) {
  let start = 0;
  let end = line.length;
  while (start < end && KOTLIN_WHITESPACE.has(line.charCodeAt(start))) start++;
  while (end > start && KOTLIN_WHITESPACE.has(line.charCodeAt(end - 1))) end--;
  return line.slice(start, end);
}

/**
 * Exakt samma normalisering som `NoteContentHash.normalize` i Android. Måste hållas i takt med
 * den: ett veckobrev som både importeras och klistras in ska ge "Den här texten finns redan".
 * @param {string} text
 * @return {string}
 */
function normalizeForHash(text) {
  return String(text || "")
      .replace(/\r\n/g, "\n")
      .replace(/\r/g, "\n")
      .split("\n")
      .map((line) => kotlinTrim(line).replace(JAVA_WHITESPACE, " "))
      .filter((line) => line.length > 0)
      .join("\n")
      .toLocaleLowerCase("sv-SE");
}

/**
 * Samma som `NoteContentHash.of`: sha-256 av den normaliserade texten, tom text ger null.
 * @param {string} text
 * @return {string|null}
 */
function contentHashOf(text) {
  const normalized = normalizeForHash(text);
  return normalized ? sha256(normalized) : null;
}

/**
 * Anteckningens innehåll ur en post. Rubriken är första raden i `text`. Hashen räknas på
 * brödtexten ensam, eftersom den som klistrar in samma veckobrev kopierar brevet men sällan
 * rubriken "Nyhet: Veckobrev v.42" från flödet.
 * @param {{title: string, description: string}} item
 * @return {{title: string, text: string, contentHash: string}|null}
 */
function noteContentFor(item) {
  const title = htmlToText(item.title).replace(/\s+/g, " ").trim().slice(0, 300);
  const body = htmlToText(item.description);
  let text = body ? (title ? `${title}\n${body}` : body) : title;
  if (!text) return null;
  if (text.length > MAX_NOTE_TEXT) text = `${text.slice(0, MAX_NOTE_TEXT - 1)}…`;
  const contentHash = contentHashOf(body || title);
  if (!contentHash) return null;
  return {title, text, contentHash};
}

// --- Synken ---

/**
 * @param {Object} data anteckningens fält
 * @return {boolean}
 */
function hasRequestId(data) {
  return typeof data.requestId === "string" && data.requestId.trim().length > 0;
}

/**
 * Vad synken gör med en känd anteckning vars innehåll ändrats i flödet. Tabellen
 * "Övergångar synken får göra" i kontraktet.
 * @param {Object} data
 * @return {"skip"|"text_only"|"reinterpret"}
 */
function changeAction(data) {
  if (data.deletedAt) return "skip";
  if (data.status === "interpreting") return "skip";
  if (data.status === "saved") {
    // Köad men inte påbörjad: triggern läser texten när den tar begäran, så en ändring nu
    // skulle tolkas med fel text. Nästa körning tar den.
    return hasRequestId(data) ? "skip" : "text_only";
  }
  return "reinterpret";
}

/**
 * @return {string} kort id för körningen, del av begärans-id:n den delar ut
 */
function newRunId() {
  return `${Date.now().toString(36)}${crypto.randomBytes(3).toString("hex")}`;
}

/**
 * Synkar en källa: lägger till nya poster och köar ändrade för omtolkning. Raderar aldrig.
 *
 * @param {FirebaseFirestore.Firestore} db
 * @param {FirebaseFirestore.DocumentSnapshot} feedSnap
 * @param {{runId: string, now?: Date, prefetched?: Object, fetch?: Function, lookup?: Function}} opts
 * @return {Promise<{newItems: number, changed: number, notModified: boolean}>}
 */
async function syncOneFeed(db, feedSnap, opts) {
  const feed = feedSnap.data() || {};
  const feedId = feedSnap.id;
  const now = opts.now || new Date();
  const {FieldValue, Timestamp} = admin.firestore;

  let fetched = opts.prefetched;
  if (!fetched) {
    const secretSnap = await db.collection("news_feed_secrets").doc(feedId).get();
    const url = secretSnap.exists ? (secretSnap.data() || {}).url : null;
    if (!url) throw new FeedError("Länken till skolnyheterna saknas.");
    fetched = await fetchFeed(url, {etag: feed.httpEtag, lastModified: feed.httpLastModified}, opts);
  }

  if (fetched.notModified) {
    await feedSnap.ref.update({lastSync: FieldValue.serverTimestamp(), lastSyncStatus: "ok", lastError: null});
    return {newItems: 0, changed: 0, notModified: true};
  }

  const items = parseFeed(fetched.text);
  const subscribedMs = feed.subscribedAt && typeof feed.subscribedAt.toMillis === "function" ?
    feed.subscribedAt.toMillis() : 0;

  const candidates = new Map();
  for (const item of items) {
    const sourceKey = sourceKeyFor(item);
    if (!sourceKey) continue;
    if (item.publishedAt && item.publishedAt.getTime() < subscribedMs) continue;
    const content = noteContentFor(item);
    if (!content) continue;
    const id = noteIdFor(feedId, sourceKey);
    if (!candidates.has(id)) {
      candidates.set(id, {id, sourceKey, item, content});
    }
  }

  const notes = db.collection("notes");
  const list = [...candidates.values()];
  const snaps = [];
  for (let i = 0; i < list.length; i += 100) {
    const refs = list.slice(i, i + 100).map((c) => notes.doc(c.id));
    if (refs.length) snaps.push(...await db.getAll(...refs));
  }

  let newItems = 0;
  let changed = 0;
  for (let i = 0; i < list.length; i++) {
    const c = list[i];
    const snap = snaps[i];
    if (!snap.exists) {
      const data = {
        familyId: feed.familyId,
        ownerUid: feed.ownerUid,
        visibility: feed.visibility === "private" ? "private" : "family",
        text: c.content.text,
        contentHash: c.content.contentHash,
        aboutUids: Array.isArray(feed.aboutUids) ? feed.aboutUids.slice(0, 20) : [],
        status: "saved",
        // Fältet måste finnas (reglerna kräver det), men tomt: noten är läsbar men köad.
        requestId: null,
        linkedIds: [],
        createdByUid: feed.ownerUid,
        createdAt: FieldValue.serverTimestamp(),
        source: "rss",
        feedId,
        sourceKey: c.sourceKey,
        title: c.content.title,
        link: c.item.link || null,
        publishedAt: Timestamp.fromDate(c.item.publishedAt || now),
      };
      try {
        await notes.doc(c.id).create(data);
        newItems++;
      } catch (err) {
        // ALREADY_EXISTS: en annan körning hann före. Allt annat är ett riktigt fel.
        if (err && err.code === 6) continue;
        throw err;
      }
      continue;
    }

    const existing = snap.data() || {};
    if (existing.contentHash === c.content.contentHash && existing.title === c.content.title) continue;
    if (changeAction(existing) === "skip") continue;

    const updated = await db.runTransaction(async (tx) => {
      const fresh = await tx.get(snap.ref);
      const data = fresh.data();
      if (!data) return false;
      const action = changeAction(data);
      if (action === "skip") return false;
      const patch = {text: c.content.text, title: c.content.title, contentHash: c.content.contentHash};
      // En ny rubrik med samma brödtext tolkas inte om. Ändrad brödtext köas utan begärans-id,
      // så dräneringen delar ut det inom kvoten, precis som för en ny post.
      if (action === "reinterpret" && data.contentHash !== c.content.contentHash) {
        patch.status = "saved";
        patch.requestId = null;
      }
      tx.update(snap.ref, patch);
      return true;
    });
    if (updated) changed++;
  }

  await feedSnap.ref.update({
    lastSync: FieldValue.serverTimestamp(),
    lastSyncStatus: "ok",
    lastError: null,
    itemCount: FieldValue.increment(newItems),
    httpEtag: fetched.etag || null,
    httpLastModified: fetched.lastModified || null,
  });
  return {newItems, changed, notModified: false};
}

/**
 * Skriver felet på källan utan att låta det stoppa övriga källor.
 * @param {FirebaseFirestore.DocumentSnapshot} feedSnap
 * @param {unknown} err
 */
async function markFeedError(feedSnap, err) {
  const message = safeMessage(err);
  console.error(`newsFeeds: ${feedSnap.id}: ${message}${err instanceof FeedError ? "" : ` (${err && err.name})`}`);
  try {
    await feedSnap.ref.update({
      lastSync: admin.firestore.FieldValue.serverTimestamp(),
      lastSyncStatus: "error",
      lastError: message,
    });
  } catch (writeErr) {
    console.error(`newsFeeds: ${feedSnap.id}: kunde inte skriva felet (${writeErr && writeErr.name})`);
  }
}

/**
 * Delar ut begärans-id till köade skolnyheter, nyast först, inom dagens tolkningskvot och
 * högst fem per körning. Triggern tar över därifrån, exakt som när klienten trycker Tolka.
 *
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} familyId
 * @param {{runId: string, now?: Date, cap?: number}} opts
 * @return {Promise<{queued: number, waiting: number}>}
 */
async function drainQueue(db, familyId, opts) {
  const now = opts.now || new Date();
  const cap = opts.cap == null ? QUEUE_CAP_PER_RUN : opts.cap;
  const todayKey = stockholmDateKey(now);

  const usageSnap = await db.collection("ai_usage").doc(familyId).get();
  const usage = usageSnap.data() || {};
  const used = usage.noteDate === todayKey ? (usage.noteCount || 0) : 0;

  const snap = await db.collection("notes")
      .where("familyId", "==", familyId)
      .where("source", "==", "rss")
      .get();

  let inFlight = 0;
  const waiting = [];
  for (const doc of snap.docs) {
    const d = doc.data() || {};
    if (d.deletedAt) continue;
    if (d.status === "saved" && hasRequestId(d)) {
      inFlight++;
    } else if (d.status === "interpreting") {
      const since = d.interpretingSince && typeof d.interpretingSince.toMillis === "function" ?
        d.interpretingSince.toMillis() : now.getTime();
      if (now.getTime() - since < STALE_INTERPRETING_MS) inFlight++;
    } else if (isQueued(d)) {
      waiting.push(doc);
    }
  }

  const budget = Math.max(0, Math.min(cap, NOTE_QUOTA_PER_DAY - used - inFlight));
  const millis = (d) => {
    const t = d.publishedAt || d.createdAt;
    return t && typeof t.toMillis === "function" ? t.toMillis() : 0;
  };
  waiting.sort((a, b) => millis(b.data()) - millis(a.data()));

  let queued = 0;
  for (const doc of waiting.slice(0, budget)) {
    const requestId = `sync-${opts.runId}-${queued + 1}`;
    const ok = await db.runTransaction(async (tx) => {
      const fresh = await tx.get(doc.ref);
      const data = fresh.data();
      // Familjen kan ha hunnit trycka Tolka eller ta bort noten sedan listan lästes.
      if (!data || !isQueued(data)) return false;
      tx.update(doc.ref, {status: "saved", requestId});
      return true;
    });
    if (ok) queued++;
  }
  return {queued, waiting: waiting.length - queued};
}

/**
 * Väntar noten på en tolkning som dräneringen får dela ut? Ny och oköad, eller fallen på
 * kvoten. Andra fel lämnas åt familjen.
 * @param {Object} d
 * @return {boolean}
 */
function isQueued(d) {
  if (d.deletedAt || d.source !== "rss") return false;
  if (d.status === "saved") return !hasRequestId(d);
  return d.status === "failed" && d.interpretationError === QUOTA_EXHAUSTED_MESSAGE;
}

/**
 * Den schemalagda körningen: alla källor med automatisk synk, familj för familj. Ett fel i en
 * källa isoleras till den, och dräneringen körs för varje familj även när flödena var oförändrade,
 * eftersom kvoten räknas om vid midnatt.
 * @param {FirebaseFirestore.Firestore} db
 * @param {{now?: Date, fetch?: Function, lookup?: Function}} deps
 * @return {Promise<{ok: number, failed: number, newItems: number, queued: number}>}
 */
async function runScheduledSync(db, deps = {}) {
  const runId = newRunId();
  const snap = await db.collection("news_feeds").where("autoSync", "==", true).get();
  const byFamily = new Map();
  for (const doc of snap.docs) {
    const familyId = (doc.data() || {}).familyId;
    if (!familyId) continue;
    if (!byFamily.has(familyId)) byFamily.set(familyId, []);
    byFamily.get(familyId).push(doc);
  }

  const totals = {ok: 0, failed: 0, newItems: 0, queued: 0};
  for (const [familyId, feeds] of byFamily) {
    for (const feedSnap of feeds) {
      try {
        const result = await syncOneFeed(db, feedSnap, {...deps, runId});
        totals.ok++;
        totals.newItems += result.newItems;
      } catch (err) {
        totals.failed++;
        await markFeedError(feedSnap, err);
      }
    }
    try {
      const drained = await drainQueue(db, familyId, {...deps, runId});
      totals.queued += drained.queued;
    } catch (err) {
      console.error(`newsFeeds: dränering misslyckades för en familj (${err && err.name})`);
    }
  }
  console.log(`syncNewsFeeds: klar ok=${totals.ok} fail=${totals.failed} nya=${totals.newItems} köade=${totals.queued}`);
  return totals;
}

/**
 * Barnkopplingen är ett tips till tolkningen. Bara familjens egna medlemmar godtas.
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} familyId
 * @param {unknown} raw
 * @return {Promise<string[]>}
 */
async function validAboutUids(db, familyId, raw) {
  if (!Array.isArray(raw) || raw.length === 0) return [];
  const wanted = [...new Set(raw.filter((v) => typeof v === "string" && v))].slice(0, 20);
  if (!wanted.length) return [];
  const members = await db.collection("users").where("familyId", "==", familyId).get();
  const ids = new Set(members.docs.map((d) => d.id));
  return wanted.filter((uid) => ids.has(uid));
}

/**
 * Det klienten får se av adressen: domänen och de fyra sista tecknen.
 * @param {URL} url
 * @return {{urlHost: string, urlHint: string}}
 */
function urlDisplay(url) {
  const text = url.toString();
  return {urlHost: url.hostname, urlHint: text.slice(-4)};
}

/**
 * Callable: lägg till en källa, synka om den ("Synka nu") eller byt adress.
 * data: {url, name, aboutUids?, visibility?, feedId?} → {feedId, newItems, queued}
 */
async function handleSubscribe(request, deps = {}) {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Inloggning krävs.");
  }
  const uid = request.auth.uid;
  const db = admin.firestore();

  const callerSnap = await db.collection("users").doc(uid).get();
  const caller = callerSnap.exists ? (callerSnap.data() || {}) : null;
  if (!caller || (caller.role !== "parent" && caller.role !== "admin")) {
    throw new HttpsError("permission-denied", "Endast föräldrar.");
  }
  const familyId = caller.familyId;
  if (!familyId) {
    throw new HttpsError("failed-precondition", "Ingen familj.");
  }

  const {url, name, aboutUids, visibility, feedId} = request.data || {};
  const runId = newRunId();
  const {FieldValue, Timestamp} = admin.firestore;

  try {
    let feedRef;
    let prefetched = null;
    if (feedId != null) {
      if (typeof feedId !== "string" || !feedId || feedId.includes("/")) {
        throw new HttpsError("invalid-argument", "Ogiltig källa.");
      }
      feedRef = db.collection("news_feeds").doc(feedId);
      const snap = await feedRef.get();
      const existing = snap.exists ? (snap.data() || {}) : null;
      // En privat källa som tillhör någon annan finns inte, sett från anroparen.
      if (!existing || existing.familyId !== familyId ||
          (existing.visibility === "private" && existing.ownerUid !== uid)) {
        throw new HttpsError("not-found", "Källan finns inte.");
      }
      if (typeof url === "string" && url.trim()) {
        const parsed = parseFeedUrl(url);
        prefetched = await fetchFeed(parsed.toString(), {}, deps);
        parseFeed(prefetched.text);
        await db.collection("news_feed_secrets").doc(feedId).set({
          url: parsed.toString(), familyId, updatedAt: FieldValue.serverTimestamp(),
        });
        await feedRef.update({...urlDisplay(parsed), httpEtag: null, httpLastModified: null});
      }
    } else {
      const parsed = parseFeedUrl(url);
      // Första hämtningen validerar adressen innan något skrivs: en felaktig länk ger ett
      // fel i dialogen, inte en trasig källa i listan.
      prefetched = await fetchFeed(parsed.toString(), {}, deps);
      parseFeed(prefetched.text);

      const displayName = typeof name === "string" && name.trim() ?
        name.trim().slice(0, 80) : "Skolnyheter";
      const now = deps.now || new Date();
      feedRef = db.collection("news_feeds").doc();
      const batch = db.batch();
      batch.set(feedRef, {
        familyId,
        name: displayName,
        ...urlDisplay(parsed),
        ownerUid: uid,
        visibility: visibility === "private" ? "private" : "family",
        aboutUids: await validAboutUids(db, familyId, aboutUids),
        subscribedAt: Timestamp.fromMillis(now.getTime() - FIRST_SYNC_LOOKBACK_MS),
        autoSync: true,
        lastSync: null,
        lastSyncStatus: null,
        lastError: null,
        itemCount: 0,
        httpEtag: null,
        httpLastModified: null,
        createdByUid: uid,
        createdAt: FieldValue.serverTimestamp(),
      });
      batch.set(db.collection("news_feed_secrets").doc(feedRef.id), {
        url: parsed.toString(), familyId, createdAt: FieldValue.serverTimestamp(),
      });
      await batch.commit();
    }

    const feedSnap = await feedRef.get();
    let result;
    try {
      result = await syncOneFeed(db, feedSnap, {...deps, runId, prefetched: prefetched || undefined});
    } catch (err) {
      await markFeedError(feedSnap, err);
      throw err;
    }
    const drained = await drainQueue(db, familyId, {...deps, runId});
    return {feedId: feedRef.id, newItems: result.newItems, queued: drained.queued};
  } catch (err) {
    if (err instanceof HttpsError) throw err;
    if (!(err instanceof FeedError)) {
      console.error(`subscribeNewsFeed: ${err && err.name}`);
    }
    throw new HttpsError(err instanceof FeedError ? err.code : "unavailable", safeMessage(err));
  }
}

exports.subscribeNewsFeed = onCall({
  region: "us-central1",
  timeoutSeconds: 120,
  memory: "512MiB",
}, (request) => handleSubscribe(request));

/**
 * 04:30 som kalendersynken, och 16:30 så att dagens skolnyheter hinner tolkas före
 * kvällsöverblicken.
 */
exports.syncNewsFeeds = onSchedule({
  schedule: "30 4,16 * * *",
  timeZone: "Europe/Stockholm",
  region: "us-central1",
  timeoutSeconds: 540,
  memory: "512MiB",
}, async () => {
  await runScheduledSync(admin.firestore());
  return null;
});

exports._test = {
  FeedError,
  safeMessage,
  parseFeedUrl,
  isPrivateAddress,
  assertPublicHost,
  fetchFeed,
  decodeFeed,
  parseFeed,
  sourceKeyFor,
  noteIdFor,
  normalizeForHash,
  contentHashOf,
  noteContentFor,
  changeAction,
  isQueued,
  syncOneFeed,
  drainQueue,
  runScheduledSync,
  handleSubscribe,
  QUEUE_CAP_PER_RUN,
  FIRST_SYNC_LOOKBACK_MS,
};
