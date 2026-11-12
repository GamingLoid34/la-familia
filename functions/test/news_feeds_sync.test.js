/* eslint-disable max-len */
const test = require("node:test");
const assert = require("node:assert");
const {_test} = require("../news_feeds");

const {syncOneFeed, drainQueue} = _test;

/**
 * Det synken och dräneringen använder av Firestore, i minnet. Dokumenten är vanliga objekt;
 * serverTimestamp och increment lagras som de är, eftersom inget test läser dem.
 * @return {Object}
 */
function fakeDb() {
  const store = new Map();
  const clone = (v) => (v === undefined ? undefined : structuredCloneSafe(v));
  const snapOf = (ref) => {
    const data = store.get(ref.path);
    return {id: ref.id, ref, exists: data !== undefined, data: () => clone(data)};
  };
  const refOf = (collection, id) => {
    const ref = {
      id,
      path: `${collection}/${id}`,
      get: async () => snapOf(ref),
      create: async (data) => {
        if (store.has(ref.path)) throw Object.assign(new Error("ALREADY_EXISTS"), {code: 6});
        store.set(ref.path, clone(data));
      },
      set: async (data) => store.set(ref.path, clone(data)),
      update: async (patch) => {
        if (!store.has(ref.path)) throw Object.assign(new Error("NOT_FOUND"), {code: 5});
        store.set(ref.path, {...store.get(ref.path), ...clone(patch)});
      },
    };
    return ref;
  };
  const query = (collection, filters) => ({
    where: (field, op, value) => {
      assert.equal(op, "==");
      return query(collection, [...filters, [field, value]]);
    },
    get: async () => {
      const docs = [];
      for (const [path, data] of store) {
        const [col, id] = path.split("/");
        if (col !== collection) continue;
        if (filters.every(([f, v]) => data[f] === v)) docs.push(snapOf(refOf(col, id)));
      }
      return {docs};
    },
  });
  return {
    store,
    collection: (name) => ({doc: (id) => refOf(name, id), ...query(name, [])}),
    getAll: async (...refs) => refs.map(snapOf),
    runTransaction: async (fn) => fn({get: (ref) => ref.get(), update: (ref, patch) => ref.update(patch)}),
  };
}

/**
 * Djupkopia som behåller Timestamp och FieldValue-objekt som de är.
 * @param {unknown} v
 * @return {unknown}
 */
function structuredCloneSafe(v) {
  if (Array.isArray(v)) return v.map(structuredCloneSafe);
  if (v && typeof v === "object" && Object.getPrototypeOf(v) === Object.prototype) {
    return Object.fromEntries(Object.entries(v).map(([k, x]) => [k, structuredCloneSafe(x)]));
  }
  return v;
}

const FAMILY = "fam1";
const FEED = "feed1";

/**
 * Ett SchoolSoft-likt flöde. `body` är brödtexten i det första inlägget som HTML.
 * @param {{title: (string|undefined), body: (string|undefined)}} first
 * @return {string}
 */
function rss({title = "Nyhet: Veckobrev v.42", body} = {}) {
  const firstBody = body ?? "<p>Hej! Torsdag &auml;r det bad, ta med badkl&auml;der.</p><p>Fredag &aring;ker vi till skogen &amp; grillar.<br>Matsäck behövs.</p>";
  return `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"><channel><title>SchoolSoft</title>
<item>
  <title>${title}</title>
  <guid isPermaLink="false">news-42</guid>
  <pubDate>Fri, 16 Oct 2026 14:05:00 +0200</pubDate>
  <description><![CDATA[${firstBody}]]></description>
</item>
<item>
  <title>Studiedag</title>
  <guid isPermaLink="false">news-43</guid>
  <pubDate>Thu, 15 Oct 2026 09:00:00 +0200</pubDate>
  <description><![CDATA[<div>Måndag 26/10 är det studiedag.</div><div>Fritids är öppet.</div>]]></description>
</item>
</channel></rss>`;
}

const NOW = new Date("2026-10-17T08:00:00+02:00");

/**
 * @return {Promise<Object>} en databas med en källa
 */
async function setup() {
  const db = fakeDb();
  await db.collection("news_feeds").doc(FEED).set({familyId: FAMILY, ownerUid: "u1", visibility: "family", aboutUids: []});
  return db;
}

/**
 * En körning som den schemalagda: synk av källan, sedan dränering.
 * @param {Object} db
 * @param {string} text flödet
 * @param {string} runId
 * @return {Promise<Object>}
 */
async function sync(db, text, runId) {
  const feedSnap = await db.collection("news_feeds").doc(FEED).get();
  const synced = await syncOneFeed(db, feedSnap, {runId, now: NOW, prefetched: {text, notModified: false}});
  const drained = await drainQueue(db, FAMILY, {runId, now: NOW});
  return {...synced, ...drained};
}

/**
 * @param {Object} db
 * @return {Object[]} alla anteckningar
 */
function notes(db) {
  return [...db.store].filter(([p]) => p.startsWith("notes/")).map(([, d]) => d);
}

/**
 * Som triggern: tar varje utdelad begäran och lämnar en tolkning att granska.
 * @param {Object} db
 */
function interpretAll(db) {
  for (const [path, d] of db.store) {
    if (!path.startsWith("notes/") || d.status !== "saved" || !d.requestId) continue;
    db.store.set(path, {...d, status: "needs_review", claimedRequestId: d.requestId, interpretation: {requestId: d.requestId}});
  }
}

test("samma flöde två gånger i rad ger noll ändringar och inga nya begärans-id", async () => {
  const db = await setup();
  const first = await sync(db, rss(), "run1");
  assert.equal(first.newItems, 2);
  assert.equal(first.queued, 2);
  interpretAll(db);
  const before = JSON.stringify(notes(db));

  const second = await sync(db, rss(), "run2");
  assert.deepEqual({newItems: second.newItems, changed: second.changed, queued: second.queued}, {newItems: 0, changed: 0, queued: 0});
  assert.equal(JSON.stringify(notes(db)), before);
});

test("annan radbrytnings-HTML för samma brev räknas inte som ändring", async () => {
  const db = await setup();
  await sync(db, rss(), "run1");
  interpretAll(db);
  const before = JSON.stringify(notes(db));

  // <br/> i stället för <p>, extra blanktecken och radbrytningar i källan, &#228; i stället för &auml;.
  const sameLetter = "Hej!  Torsdag &#228;r det bad, ta med badkl&auml;der.<br/>\n\n  Fredag &aring;ker vi till skogen &amp; grillar.<br />Matsäck behövs.  ";
  const second = await sync(db, rss({body: sameLetter}), "run2");
  assert.equal(second.changed, 0);
  assert.equal(second.queued, 0);
  assert.equal(JSON.stringify(notes(db)), before);
});

test("ändrad brödtext köas och får begärans-id först i dräneringen, inom kvoten", async () => {
  const db = await setup();
  await sync(db, rss(), "run1");
  interpretAll(db);
  // Dagens kvot är slut: dräneringen får inte dela ut något.
  await db.collection("ai_usage").doc(FAMILY).set({noteDate: "2026-10-17", noteCount: 20});

  const second = await sync(db, rss({body: "<p>Badet är inställt.</p>"}), "run2");
  assert.equal(second.changed, 1);
  assert.equal(second.queued, 0);
  const changedNote = notes(db).find((n) => n.sourceKey === "news-42");
  assert.equal(changedNote.status, "saved");
  assert.equal(changedNote.requestId, null);

  // En tolkning kvar i dag.
  await db.collection("ai_usage").doc(FAMILY).set({noteDate: "2026-10-17", noteCount: 19});
  const third = await sync(db, rss({body: "<p>Badet är inställt.</p>"}), "run3");
  assert.equal(third.changed, 0);
  assert.equal(third.queued, 1);
  assert.equal(notes(db).find((n) => n.sourceKey === "news-42").requestId, "sync-run3-1");
});

test("ny rubrik med samma brödtext uppdaterar texten men tolkas inte om", async () => {
  const db = await setup();
  await sync(db, rss(), "run1");
  interpretAll(db);
  const second = await sync(db, rss({title: "Nyhet: Veckobrev vecka 42"}), "run2");
  assert.equal(second.changed, 1);
  assert.equal(second.queued, 0);
  const note = notes(db).find((n) => n.sourceKey === "news-42");
  assert.equal(note.status, "needs_review");
  assert.equal(note.title, "Nyhet: Veckobrev vecka 42");
  assert.ok(note.text.startsWith("Nyhet: Veckobrev vecka 42\n"));
});

test("dräneringen räknar med samma räknare och tak som triggern", async () => {
  const db = await setup();
  await db.collection("ai_usage").doc(FAMILY).set({noteDate: "2026-10-17", noteCount: 19});
  const first = await sync(db, rss(), "run1");
  assert.equal(first.newItems, 2);
  // 20 - 19 = 1 kvar, så bara den nyaste får ett id.
  assert.equal(first.queued, 1);
  assert.equal(first.waiting, 1);
  assert.equal(notes(db).find((n) => n.requestId).sourceKey, "news-42");
});
