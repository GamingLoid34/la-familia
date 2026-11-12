/* eslint-disable max-len */
const test = require("node:test");
const assert = require("node:assert");
const {_test} = require("../news_feeds");

const {
  FeedError, safeMessage, parseFeedUrl, isPrivateAddress, fetchFeed, decodeFeed, parseFeed,
  sourceKeyFor, noteIdFor, normalizeForHash, contentHashOf, noteContentFor, changeAction, isQueued,
} = _test;

const SECRET = "https://skola.example/rss/abc123TOKEN";
const publicLookup = async () => [{address: "93.184.216.34", family: 4}];

/**
 * Ett svar som liknar fetch-API:ts, utan nätverk.
 * @param {number} status
 * @param {string} body
 * @param {Object} headers
 * @return {Object}
 */
function response(status, body = "", headers = {}) {
  const lower = Object.fromEntries(Object.entries(headers).map(([k, v]) => [k.toLowerCase(), v]));
  const bytes = Buffer.from(body, "utf8");
  return {
    status,
    ok: status >= 200 && status < 300,
    headers: {get: (k) => lower[k.toLowerCase()] ?? null},
    body: null,
    arrayBuffer: async () => bytes,
  };
}

const RSS = `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"><channel><title>SchoolSoft</title>
<item>
  <title>Nyhet: Veckobrev v.42</title>
  <link>https://sms.schoolsoft.se/skola/jsp/news.jsp?id=42</link>
  <guid isPermaLink="false">news-42</guid>
  <pubDate>Fri, 16 Oct 2026 14:05:00 +0200</pubDate>
  <description><![CDATA[<p>Hej! Torsdag &auml;r det bad, ta med badkl&auml;der.</p><p>Fredag &aring;ker vi till skogen &amp; grillar.</p>]]></description>
</item>
<item>
  <title>Utan guid</title>
  <link>https://sms.schoolsoft.se/skola/jsp/news.jsp?id=43</link>
  <description>Bara text</description>
</item>
</channel></rss>`;

// --- Adressen ---

test("bara https godtas, och adressen syns aldrig i felet", () => {
  for (const bad of ["http://skola.example/rss?token=hemligt", "ftp://x/rss", "inte en länk", ""]) {
    assert.throws(() => parseFeedUrl(bad), (err) => {
      assert.ok(err instanceof FeedError);
      assert.ok(!err.message.includes("hemligt"));
      return true;
    });
  }
  assert.equal(parseFeedUrl(SECRET).hostname, "skola.example");
});

test("inloggningsuppgifter och egna portar i adressen nekas", () => {
  assert.throws(() => parseFeedUrl("https://a:b@skola.example/rss"), FeedError);
  assert.throws(() => parseFeedUrl("https://skola.example:8443/rss"), FeedError);
  assert.doesNotThrow(() => parseFeedUrl("https://skola.example:443/rss"));
});

test("privata och lokala adresser känns igen", () => {
  for (const ip of ["127.0.0.1", "10.1.2.3", "172.16.0.1", "172.31.255.255", "192.168.1.1",
    "169.254.169.254", "100.64.0.1", "0.0.0.0", "224.0.0.1", "::1", "::", "fd00::1",
    "fe80::1", "::ffff:127.0.0.1", "::ffff:10.0.0.1"]) {
    assert.equal(isPrivateAddress(ip), true, ip);
  }
  for (const ip of ["93.184.216.34", "172.32.0.1", "8.8.8.8", "2606:4700::1111"]) {
    assert.equal(isPrivateAddress(ip), false, ip);
  }
});

// --- Hämtningen ---

test("hämtningen skickar villkoren och tar emot 304", async () => {
  let seen;
  const fake = async (url, init) => {
    seen = init.headers;
    return response(304);
  };
  const res = await fetchFeed(SECRET, {etag: "\"v1\"", lastModified: "Fri, 16 Oct 2026 12:00:00 GMT"}, {fetch: fake, lookup: publicLookup});
  assert.equal(res.notModified, true);
  assert.equal(seen["if-none-match"], "\"v1\"");
  assert.equal(seen["if-modified-since"], "Fri, 16 Oct 2026 12:00:00 GMT");
});

test("en omdirigering till en privat adress stoppas", async () => {
  const fake = async () => response(302, "", {location: "https://169.254.169.254/latest/meta-data"});
  await assert.rejects(fetchFeed(SECRET, {}, {fetch: fake, lookup: publicLookup}), (err) => {
    assert.ok(err instanceof FeedError);
    assert.match(err.message, /publik server/);
    return true;
  });
});

test("ett namn som pekar på en intern adress stoppas före hämtningen", async () => {
  let fetched = false;
  const fake = async () => {
    fetched = true;
    return response(200, RSS);
  };
  const lookup = async () => [{address: "93.184.216.34"}, {address: "10.0.0.5"}];
  await assert.rejects(fetchFeed(SECRET, {}, {fetch: fake, lookup}), FeedError);
  assert.equal(fetched, false);
});

test("högst tre omdirigeringar följs", async () => {
  let calls = 0;
  const fake = async () => {
    calls++;
    return response(301, "", {location: `https://skola.example/steg${calls}`});
  };
  await assert.rejects(fetchFeed(SECRET, {}, {fetch: fake, lookup: publicLookup}), /för många omdirigeringar/);
  assert.equal(calls, 4);
});

test("en omdirigering till http nekas", async () => {
  const fake = async () => response(301, "", {location: "http://skola.example/rss"});
  await assert.rejects(fetchFeed(SECRET, {}, {fetch: fake, lookup: publicLookup}), /https/);
});

test("ett HTTP-fel ger statuskoden men inte adressen", async () => {
  const fake = async () => response(403, "nej");
  await assert.rejects(fetchFeed(SECRET, {}, {fetch: fake, lookup: publicLookup}), (err) => {
    assert.equal(err.message, "Kunde inte hämta skolnyheter (HTTP 403).");
    assert.ok(!err.message.includes("abc123TOKEN"));
    return true;
  });
});

test("ett nätverksfel som nämner värden blir ett neutralt fel", async () => {
  const fake = async () => {
    throw new TypeError(`fetch failed: getaddrinfo ENOTFOUND ${SECRET}`);
  };
  await assert.rejects(fetchFeed(SECRET, {}, {fetch: fake, lookup: publicLookup}), (err) => {
    assert.equal(err.message, "Kunde inte hämta skolnyheter.");
    return true;
  });
  assert.equal(safeMessage(new Error(SECRET)), "Kunde inte hämta skolnyheter.");
});

test("ett flöde över 2 MB avvisas", async () => {
  const big = response(200, "x".repeat(10), {"content-length": String(3 * 1024 * 1024)});
  await assert.rejects(fetchFeed(SECRET, {}, {fetch: async () => big, lookup: publicLookup}), /för stort/);
  const undeclared = response(200, "x".repeat(2 * 1024 * 1024 + 1));
  await assert.rejects(fetchFeed(SECRET, {}, {fetch: async () => undeclared, lookup: publicLookup}), /för stort/);
});

test("etag och last-modified följer med svaret", async () => {
  const fake = async () => response(200, RSS, {"etag": "\"v2\"", "last-modified": "Sat, 17 Oct 2026 04:00:00 GMT"});
  const res = await fetchFeed(SECRET, {}, {fetch: fake, lookup: publicLookup});
  assert.equal(res.notModified, false);
  assert.equal(res.etag, "\"v2\"");
  assert.match(res.text, /Veckobrev/);
});

test("ett flöde i ISO-8859-1 avkodas rätt", () => {
  const latin = Buffer.from("<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?><rss><channel><item><title>Bad på torsdag</title></item></channel></rss>", "latin1");
  assert.match(decodeFeed(latin, "text/xml"), /Bad på torsdag/);
});

// --- Tolkningen av flödet ---

test("RSS 2.0 tolkas med guid, länk, datum och brödtext", () => {
  const items = parseFeed(RSS);
  assert.equal(items.length, 2);
  assert.equal(items[0].guid, "news-42");
  assert.equal(items[0].link, "https://sms.schoolsoft.se/skola/jsp/news.jsp?id=42");
  assert.equal(items[0].publishedAt.toISOString(), "2026-10-16T12:05:00.000Z");
  assert.match(items[0].description, /badkl&auml;der/);
  assert.equal(items[1].publishedAt, null);
});

test("Atom tolkas", () => {
  const atom = `<?xml version="1.0"?><feed xmlns="http://www.w3.org/2005/Atom">
    <entry><id>tag:skola,2026:1</id><title>Utflykt</title>
      <link rel="alternate" href="https://skola.example/n/1"/><link rel="edit" href="https://skola.example/e/1"/>
      <updated>2026-10-15T08:00:00Z</updated><summary>Matsäck på fredag</summary></entry></feed>`;
  const [item] = parseFeed(atom);
  assert.equal(item.guid, "tag:skola,2026:1");
  assert.equal(item.link, "https://skola.example/n/1");
  assert.equal(item.description, "Matsäck på fredag");
  assert.equal(item.publishedAt.toISOString(), "2026-10-15T08:00:00.000Z");
});

test("RSS 1.0 tolkas", () => {
  const rdf = `<?xml version="1.0"?><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns="http://purl.org/rss/1.0/" xmlns:dc="http://purl.org/dc/elements/1.1/">
    <item rdf:about="https://skola.example/n/7"><title>Lov</title><link>https://skola.example/n/7</link><dc:date>2026-10-14T10:00:00+02:00</dc:date></item></rdf:RDF>`;
  const [item] = parseFeed(rdf);
  assert.equal(item.guid, "https://skola.example/n/7");
  assert.equal(item.title, "Lov");
});

test("egna entiteter i ett DOCTYPE expanderas aldrig", () => {
  const bomb = `<?xml version="1.0"?><!DOCTYPE rss [<!ENTITY a "aaaaaaaaaa"><!ENTITY b "&a;&a;&a;&a;&a;&a;&a;&a;&a;&a;">]>
    <rss><channel><item><title>&b;</title><guid>1</guid></item></channel></rss>`;
  const items = parseFeed(bomb);
  assert.ok(!items[0].title.includes("aaaaaaaaaa"));
});

test("något som inte är ett flöde ger ett begripligt fel", () => {
  assert.throws(() => parseFeed("<html><body>Logga in</body></html>"), /inget RSS-flöde/);
});

test("högst 200 poster läses", () => {
  const many = `<rss><channel>${Array.from({length: 250}, (_, i) => `<item><guid>${i}</guid><title>T${i}</title></item>`).join("")}</channel></rss>`;
  assert.equal(parseFeed(many).length, 200);
});

// --- Nycklar och innehåll ---

test("dedupnyckeln är guid, annars länk, annars hash av rubrik och datum", () => {
  assert.equal(sourceKeyFor({guid: "g", link: "l", title: "t", pubDateRaw: "d"}), "g");
  assert.equal(sourceKeyFor({guid: "", link: "l", title: "t", pubDateRaw: "d"}), "l");
  const hashed = sourceKeyFor({guid: "", link: "", title: "t", pubDateRaw: "d"});
  assert.match(hashed, /^sha256:[0-9a-f]{64}$/);
  assert.equal(hashed, sourceKeyFor({guid: "", link: "", title: "t", pubDateRaw: "d"}));
  assert.equal(sourceKeyFor({guid: "", link: "", title: "", pubDateRaw: ""}), "");
});

test("dokument-id är stabilt per källa och nyckel och giltigt i Firestore", () => {
  const id = noteIdFor("feedA", "https://x/y?id=1");
  assert.equal(id, noteIdFor("feedA", "https://x/y?id=1"));
  assert.notEqual(id, noteIdFor("feedB", "https://x/y?id=1"));
  assert.ok(!id.includes("/"));
});

test("normaliseringen är densamma som NoteContentHash i Android", () => {
  // Samma fall som Kotlin-koden hanterar: radslut, tomma rader, blanksteg och skiftläge.
  assert.equal(normalizeForHash("  Hej  DÅ \r\n\r\n\trad   två\r"), "hej då\nrad två");
  assert.equal(normalizeForHash("ÅÄÖ"), "åäö");
  // Hårt mellanslag mitt i en rad slås inte ihop av Javas \s, men trimmas i kanterna.
  const nbsp = String.fromCharCode(160);
  assert.equal(normalizeForHash(`${nbsp}a${nbsp}${nbsp}b${nbsp}`), `a${nbsp}${nbsp}b`);
  assert.equal(contentHashOf("   \n  "), null);
  // Samma vektor finns i Android-testet NoteContentHashTest, så de två hålls i takt.
  assert.equal(contentHashOf("  Hej!\r\n\r\nTorsdag är  det BAD."), "60f440c653af4852301ad61215f5ce7ff32344482ae44664d59a8ad2b6725e90");
});

test("anteckningens text har rubriken först och hashen räknas på brödtexten", () => {
  const [item] = parseFeed(RSS);
  const content = noteContentFor(item);
  assert.equal(content.title, "Nyhet: Veckobrev v.42");
  assert.equal(content.text, "Nyhet: Veckobrev v.42\nHej! Torsdag är det bad, ta med badkläder.\n\nFredag åker vi till skogen & grillar.");
  // Den som klistrar in brevet utan rubriken får samma hash.
  assert.equal(content.contentHash, contentHashOf("Hej! Torsdag är det bad, ta med badkläder.\nFredag åker vi till skogen & grillar."));
});

test("en post utan brödtext får rubriken som text", () => {
  const content = noteContentFor({title: "Studiedag måndag", description: ""});
  assert.equal(content.text, "Studiedag måndag");
  assert.equal(content.contentHash, contentHashOf("Studiedag måndag"));
  assert.equal(noteContentFor({title: "", description: ""}), null);
});

test("texten kapas vid reglernas tak", () => {
  const content = noteContentFor({title: "Lång", description: "a".repeat(20000)});
  assert.equal(content.text.length, 10000);
  assert.ok(content.text.endsWith("…"));
});

// --- Övergångar ---

test("synken rör aldrig en not som tolkas, är köad eller mjukraderad", () => {
  assert.equal(changeAction({status: "interpreting", requestId: "r"}), "skip");
  assert.equal(changeAction({status: "saved", requestId: "r"}), "skip");
  assert.equal(changeAction({status: "needs_review", requestId: "r", deletedAt: new Date()}), "skip");
});

test("en oköad not får bara ny text, en granskad eller bekräftad tolkas om", () => {
  assert.equal(changeAction({status: "saved", requestId: null}), "text_only");
  for (const status of ["needs_review", "confirmed", "dismissed", "failed"]) {
    assert.equal(changeAction({status, requestId: "r"}), "reinterpret", status);
  }
});

test("kön tar oköade skolnyheter och kvotfel, inget annat", () => {
  assert.equal(isQueued({source: "rss", status: "saved", requestId: null}), true);
  assert.equal(isQueued({source: "rss", status: "saved", requestId: "r"}), false);
  assert.equal(isQueued({source: "rss", status: "failed", interpretationError: "Dagens tolkningskvot är slut."}), true);
  assert.equal(isQueued({source: "rss", status: "failed", interpretationError: "AI-tjänsten svarade med fel."}), false);
  assert.equal(isQueued({status: "saved", requestId: null}), false);
  assert.equal(isQueued({source: "rss", status: "saved", requestId: null, deletedAt: new Date()}), false);
});
