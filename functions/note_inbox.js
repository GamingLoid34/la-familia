/* eslint-disable max-len */
/**
 * Assistentens inkorg (steg 3 i assistent-plan.md).
 *
 * En anteckning sparas först och ändras aldrig. Triggern tolkar den och skriver förslag.
 * Familjen granskar och bekräftar via callable; först då skapas kalenderposter och uppgifter.
 *
 * Tre saker styr designen:
 * - Originalet är heligt. Servern skriver aldrig över `text`.
 * - Begärans-id styr allt. Triggern reagerar bara på en ny begäran, aldrig på sitt eget svar.
 * - Bekräftelsen är idempotent på `(noteId, revision, actionId)`, så en upprepad bekräftelse
 *   ger samma resultat utan dubbletter.
 */
const {HttpsError} = require("firebase-functions/v2/https");
const {onDocumentWritten} = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

const ANTHROPIC_MODEL = "claude-sonnet-5";

/** Egen kvot, skild från de tio anrop som planeraren och matsedeln delar. */
const NOTE_QUOTA_PER_DAY = 20;

/**
 * Felet en anteckning får när kvoten är slut. Skolnyheternas synk (news_feeds.js) känner igen
 * det och köar om sådana anteckningar nästa körning, så texten måste vara densamma på båda ställena.
 */
const QUOTA_EXHAUSTED_MESSAGE = "Dagens tolkningskvot är slut.";

const INTERPRET_SYSTEM =
  "Du läser en anteckning från en familj: ett veckobrev, ett meddelande från skolan eller " +
  "en påminnelse någon skrivit till sig själv.\n" +
  "Svara ENDAST med giltig JSON, ingen annan text:\n" +
  "{\"actions\":[{\"type\":\"...\",\"title\":\"...\",\"summary\":\"...\",\"payload\":{...}," +
  "\"blockedReason\":null|\"...\"}],\"question\":null|\"...\"}\n" +
  "Tillåtna type-värden och deras payload:\n" +
  "- create_event: {\"date\":\"YYYY-MM-DD\",\"time\":\"HH:MM\"|null,\"endTime\":\"HH:MM\"|null," +
  "\"title\":\"...\",\"persons\":[\"Förnamn\"]}\n" +
  "- create_task: {\"title\":\"...\",\"dueDate\":\"YYYY-MM-DD\"|null,\"dueTime\":\"HH:MM\"|null," +
  "\"showFromDate\":\"YYYY-MM-DD\"|null,\"about\":[\"Förnamn\"]}\n" +
  "- add_checklist_item: {\"eventTitle\":\"...\",\"date\":\"YYYY-MM-DD\",\"item\":\"...\"}\n" +
  "- add_exception: {\"eventTitle\":\"...\",\"date\":\"YYYY-MM-DD\",\"reason\":\"...\"}\n" +
  "- info: {\"validFrom\":\"YYYY-MM-DD\"|null,\"validTo\":\"YYYY-MM-DD\"|null}\n" +
  "Regler:\n" +
  "Skapa INTE en ny aktivitet när det redan finns en aktivitet med samma titel och datum i " +
  "underlaget — föreslå add_exception eller add_checklist_item på den befintliga i stället.\n" +
  "Förberedelser till en ÅTERKOMMANDE aktivitet blir create_task, aldrig add_checklist_item.\n" +
  "add_checklist_item och add_exception får BARA användas när aktiviteten redan finns i " +
  "underlaget ovan. Finns den inte: föreslå create_event för aktiviteten och lägg " +
  "förberedelserna som create_task. En packlistrad på en aktivitet som inte finns går " +
  "inte att spara.\n" +
  "Står det 'Anteckningen gäller' ovan: använd de personerna i alla förslag, och fråga " +
  "aldrig vem det gäller. Det är redan besvarat.\n" +
  "Blockera BARA när dagen eller personen saknas. Allt annat som saknas är i sin ordning.\n" +
  "En aktivitet UTAN klockslag är ett komplett förslag: sätt time till null och blockera " +
  "inte. Föräldern behöver veta ATT barnet ska bada på torsdag för att skicka med " +
  "badkläder, inte exakt när. Samma sak för plats, längd och andra detaljer.\n" +
  "En uppgift utan sista datum är också komplett: sätt dueDate till null och blockera inte.\n" +
  "Blockerar du ändå: ta med förslaget, sätt blockedReason till en kort mening om vad som " +
  "saknas, och ställ en fråga i question.\n" +
  "Hitta aldrig på datum, tider eller personer som inte går att härleda ur texten.\n" +
  "Ren information utan något att göra blir ett enda info-förslag.\n" +
  "Svara som EN kompakt JSON-rad utan radbrytningar eller extra blanksteg.\n";

/**
 * @param {Date} d
 * @return {string} YYYY-MM-DD i Europe/Stockholm
 */
function stockholmDateKey(d = new Date()) {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "Europe/Stockholm",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(d);
}

/**
 * Egen kvoträknare för tolkning. Ligger i samma dokument som övriga AI-anrop men i ett eget
 * fält, så att en inklistrad text aldrig äter upp planerarens anrop.
 * Loggar aldrig texten, bara datum och antal.
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} familyId
 * @param {string} todayKey
 */
async function consumeNoteQuota(db, familyId, todayKey) {
  const ref = db.collection("ai_usage").doc(familyId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.data() || {};
    const count = data.noteDate === todayKey ? (data.noteCount || 0) : 0;
    if (count >= NOTE_QUOTA_PER_DAY) {
      throw new HttpsError("resource-exhausted", QUOTA_EXHAUSTED_MESSAGE);
    }
    tx.set(ref, {noteDate: todayKey, noteCount: count + 1}, {merge: true});
  });
}

/**
 * Ska den här skrivningen tolkas?
 *
 * Samma tabell som `util/NoteStatusMachine.kt` i Android-repot. Kontrollen stänger tre hål på
 * en gång: serverns egna resultatskrivningar (status är då inte `saved`), upprepad leverans av
 * samma händelse (begärans-id är oförändrat) och text som ändrats utan att någon begärt en ny
 * tolkning.
 *
 * @param {Object|null} before dokumentet före skrivningen, null när det just skapats
 * @param {Object|null} after dokumentet efter skrivningen
 * @return {boolean}
 */
function shouldInterpret(before, after) {
  if (!after) return false;
  if (after.deletedAt) return false;
  if (after.status !== "saved") return false;
  if (typeof after.requestId !== "string" || !after.requestId.trim()) return false;
  if (typeof after.text !== "string" || !after.text.trim()) return false;
  return !before || before.requestId !== after.requestId;
}

/**
 * Tolkar AI:ns svar defensivt. Allt som inte går att lita på faller bort i stället för att
 * bli ett förslag familjen tror på.
 *
 * @param {string} raw
 * @return {Object} med `actions` (lista) och `question` (sträng eller null)
 */
function parseInterpretation(raw) {
  let text = String(raw || "").trim();
  if (text.startsWith("```")) {
    text = text.replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/m, "").trim();
  }
  const parsed = JSON.parse(text);
  if (!parsed || typeof parsed !== "object") {
    throw new Error("Ogiltigt svar från AI.");
  }

  const known = ["create_event", "create_task", "add_checklist_item", "add_exception", "info"];
  const actions = [];
  const rawActions = Array.isArray(parsed.actions) ? parsed.actions : [];

  for (const item of rawActions) {
    if (!item || typeof item !== "object") continue;
    const type = typeof item.type === "string" ? item.type.trim() : "";
    if (!known.includes(type)) continue;
    const title = typeof item.title === "string" ? item.title.trim() : "";
    if (!title) continue;

    const payload = item.payload && typeof item.payload === "object" ? item.payload : {};
    const blocked = typeof item.blockedReason === "string" && item.blockedReason.trim() ?
      item.blockedReason.trim() :
      validationProblem(type, payload);

    actions.push({
      // Stabilt id ur innehållet: samma förslag vid en omtolkning behåller sitt id, så
      // bekräftelsen blir idempotent och diffen kan peka på rätt rad.
      id: actionId(type, title, payload),
      type,
      title: title.slice(0, 200),
      summary: typeof item.summary === "string" ? item.summary.trim().slice(0, 300) : null,
      payload,
      status: "pending",
      blockedReason: blocked,
    });
  }

  const question = typeof parsed.question === "string" && parsed.question.trim() ?
    parsed.question.trim().slice(0, 300) :
    null;

  return {actions, question};
}

/**
 * Stabilt åtgärds-id ur innehållet. Måste ge samma id för samma sakförslag över omtolkningar,
 * annars går idempotensen förlorad.
 * @param {string} type
 * @param {string} title
 * @param {Object} payload
 * @return {string}
 */
function actionId(type, title, payload) {
  const parts = [
    type,
    title.toLowerCase(),
    payload.date || payload.dueDate || "",
    payload.time || payload.dueTime || "",
    payload.item || "",
    payload.eventTitle || "",
  ].join("|");
  let hash = 0;
  for (let i = 0; i < parts.length; i++) {
    hash = (hash * 31 + parts.charCodeAt(i)) | 0;
  }
  return `${type}_${(hash >>> 0).toString(36)}`;
}

/**
 * Är förslaget så konkret att det går att utföra? Returnerar en mening när något saknas,
 * annars null. Planen: oklart datum eller person ger kort utan bekräftelseknapp och en fråga.
 * @param {string} type
 * @param {Object} payload
 * @return {string|null}
 */
function validationProblem(type, payload) {
  const isDate = (v) => typeof v === "string" && /^\d{4}-\d{2}-\d{2}$/.test(v);
  const isTime = (v) => typeof v === "string" && /^([01][0-9]|2[0-3]):[0-5][0-9]$/.test(v);

  if (type === "create_event") {
    if (!isDate(payload.date)) return "Vilken dag gäller det?";
    if (payload.time != null && !isTime(payload.time)) return "Vilken tid gäller det?";
    if (!Array.isArray(payload.persons) || payload.persons.length === 0) return "Vem gäller det?";
    return null;
  }
  if (type === "create_task") {
    if (payload.dueDate != null && !isDate(payload.dueDate)) return "Vilket datum ska det vara klart?";
    if (payload.dueTime != null && !isTime(payload.dueTime)) return "Vilken tid gäller det?";
    return null;
  }
  if (type === "add_checklist_item") {
    if (!isDate(payload.date)) return "Vilken dag gäller det?";
    if (typeof payload.item !== "string" || !payload.item.trim()) return "Vad ska packas?";
    if (typeof payload.eventTitle !== "string" || !payload.eventTitle.trim()) return "Vilken aktivitet gäller det?";
    return null;
  }
  if (type === "add_exception") {
    if (!isDate(payload.date)) return "Vilken dag ställs in?";
    if (typeof payload.eventTitle !== "string" || !payload.eventTitle.trim()) return "Vilken aktivitet gäller det?";
    return null;
  }
  if (type === "info") {
    if (payload.validFrom != null && !isDate(payload.validFrom)) return "Från vilket datum gäller det?";
    if (payload.validTo != null && !isDate(payload.validTo)) return "Till vilket datum gäller det?";
    return null;
  }
  return "Okänd åtgärd.";
}

/**
 * Underlag till tolkningen: familjens medlemmar och kommande aktiviteter, så AI:n föreslår ett
 * undantag i stället för en dubblett.
 *
 * Privata anteckningar ingår aldrig i någon annans underlag, och originaltexten från andra
 * anteckningar skickas inte alls — bara strukturerade poster.
 *
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} familyId
 * @param {string} todayKey
 * @return {Promise<Object>}
 */
async function buildContext(db, familyId, todayKey) {
  const [membersSnap, eventsSnap] = await Promise.all([
    db.collection("users").where("familyId", "==", familyId).get(),
    db.collection("planner_events")
        .where("familyId", "==", familyId)
        .where("date", ">=", todayKey)
        .orderBy("date")
        .limit(60)
        .get(),
  ]);

  const members = membersSnap.docs.map((d) => {
    const data = d.data() || {};
    return {uid: d.id, name: data.name || "", role: data.role || ""};
  });

  const events = eventsSnap.docs.map((d) => {
    const data = d.data() || {};
    return {
      id: d.id,
      title: data.title || "",
      date: data.date || "",
      time: data.time || "",
      isRecurring: data.isRecurring === true || !!data.recurrence,
      persons: Array.isArray(data.persons) ? data.persons : [],
    };
  });

  return {members, events};
}

/**
 * Anropar Anthropic. Ett omförsök vid nätverksfel, som resten av servern.
 * @param {string} apiKey
 * @param {string} userContent
 * @return {Promise<string>}
 */
async function callAnthropic(apiKey, userContent) {
  const body = JSON.stringify({
    model: ANTHROPIC_MODEL,
    // 4000 räckte inte. Modellen tänker först, och på ett riktigt veckobrev åt
    // tankeblocket hela budgeten: svaret kapades mitt i en sträng och gick inte att tolka.
    // Beställarens brev på 882 tecken behövde 3206 token. 8000 ger god marginal och är
    // samma tak som schemaskanningen redan använder.
    max_tokens: 8000,
    system: INTERPRET_SYSTEM,
    messages: [{role: "user", content: userContent}],
  });
  const headers = {
    "x-api-key": apiKey,
    "anthropic-version": "2023-06-01",
    "content-type": "application/json",
  };
  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

  let response;
  for (let attempt = 1; attempt <= 2; attempt++) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 60000);
    try {
      response = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST", signal: controller.signal, headers, body,
      });
    } catch (err) {
      // Loggar aldrig prompten, bara felet.
      console.warn(`interpretNote: nätverksfel försök ${attempt}: ${err.message || err}`);
      if (attempt === 1) {
        await sleep(1500);
        continue;
      }
      throw new Error("Kunde inte nå AI-tjänsten.");
    } finally {
      clearTimeout(timer);
    }
    if (response.ok) break;
    console.error(`interpretNote: Anthropic HTTP ${response.status} (försök ${attempt})`);
    if (attempt === 1 && response.status >= 500) {
      await sleep(1500);
      continue;
    }
    throw new Error("AI-tjänsten svarade med fel.");
  }

  const json = await response.json();
  const block = Array.isArray(json.content) ? json.content.find((c) => c.type === "text") : null;
  if (!block || typeof block.text !== "string") {
    // Loggar svarets form, aldrig prompten eller anteckningens text. Utan det här gick det
    // inte att se skillnad på ett avbrutet svar, ett fel från API:t och ett tomt svar.
    const shape = {
      stopReason: json.stop_reason || null,
      types: Array.isArray(json.content) ? json.content.map((c) => c && c.type) : null,
      errorType: json.error ? json.error.type : null,
      errorMessage: json.error ? String(json.error.message || "").slice(0, 200) : null,
    };
    console.error(`interpretNote: inget textblock. ${JSON.stringify(shape)}`);
    throw new Error("Tomt svar från AI.");
  }
  // Ett svar som kapats av token-gränsen är trunkerad JSON och går inte att tolka. Bättre att
  // säga det rakt ut än att låta JSON.parse kasta ett obegripligt fel.
  if (json.stop_reason === "max_tokens") {
    console.error("interpretNote: svaret kapades av token-gränsen.");
    throw new Error("Texten var för lång för att tolkas i ett svep.");
  }
  return block.text;
}

/**
 * Trigger: tolkar en anteckning när en ny begäran dyker upp.
 *
 * Begäran tas i anspråk atomiskt, så en upprepad leverans av samma händelse inte ger två
 * parallella tolkningar. Resultatet skrivs bara om anspråket fortfarande gäller, så ett sent
 * svar från en äldre tolkning aldrig skriver över en nyare revision.
 */
exports.onNoteWritten = onDocumentWritten({
  document: "notes/{noteId}",
  region: "us-central1",
  secrets: ["LAFAMILIA_ANTHROPIC_KEY"],
  timeoutSeconds: 120,
  memory: "512MiB",
}, async (event) => {
  const before = event.data?.before?.exists ? event.data.before.data() : null;
  const after = event.data?.after?.exists ? event.data.after.data() : null;
  if (!shouldInterpret(before, after)) return;

  const db = admin.firestore();
  const ref = event.data.after.ref;
  const requestId = after.requestId;
  const familyId = after.familyId;
  if (!familyId) return;

  // Ta begäran i anspråk atomiskt. Misslyckas det arbetar någon annan redan på den.
  let claimedRevision = 0;
  const claimed = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.data();
    if (!data || data.deletedAt) return false;
    claimedRevision = (data.interpretation && data.interpretation.revision) || 0;
    if (data.status !== "saved" || data.requestId !== requestId) return false;
    if (data.claimedRequestId === requestId) return false;
    // Tidsstämpeln gör att en körning som dör mitt i kan släppas. Utan den fastnade
    // anteckningen i "interpreting" för alltid, utan väg ut i gränssnittet.
    tx.update(ref, {
      status: "interpreting",
      claimedRequestId: requestId,
      interpretingSince: admin.firestore.FieldValue.serverTimestamp(),
    });
    return true;
  });
  if (!claimed) return;

  const todayKey = stockholmDateKey();
  // Revisionen räknas ur dokumentet som det såg ut vid anspråket, inte ur triggerns
  // ögonblicksbild. Det tar bort hela klassen av fel där två körningar räknar från samma tal.
  const nextRevision = (claimedRevision || 0) + 1;

  /**
   * Skriver resultatet, men bara om anspråket fortfarande gäller.
   * @param {Object} patch
   * @return {Promise<void>}
   */
  const finish = async (patch) => {
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const data = snap.data();
      if (!data) return;
      // Mjukradering tar anteckningen ur allt aktivt underlag, oavsett status.
      if (data.deletedAt) return;
      // Någon har hunnit begära en nyare tolkning: låt den vinna.
      if (data.claimedRequestId !== requestId) return;
      if (data.status !== "interpreting") return;
      tx.update(ref, patch);
    });
  };

  try {
    const apiKey = process.env.LAFAMILIA_ANTHROPIC_KEY;
    if (!apiKey) throw new Error("AI-nyckel saknas.");

    await consumeNoteQuota(db, familyId, todayKey);
    const context = await buildContext(db, familyId, todayKey);
    // Vem anteckningen gäller, valt när den klistrades in. Ett veckobrev kommer alltid från
    // ett visst barns klass, men texten säger sällan vems. Utan det här blockerades varje
    // förslag med "vilket barn gäller det?", och inkorgen blev en lista över frågor.
    const aboutUids = Array.isArray(after.aboutUids) ? after.aboutUids : [];
    const aboutNames = context.members
        .filter((m) => aboutUids.includes(m.uid))
        .map((m) => m.name)
        .filter(Boolean);

    const userContent =
      `Idag är ${todayKey}.\n` +
      `Familjens medlemmar: ${JSON.stringify(context.members.map((m) => m.name))}\n` +
      (aboutNames.length ?
        `Anteckningen gäller: ${JSON.stringify(aboutNames)}. ` +
          "Använd dessa personer i alla förslag utan att fråga vem det gäller.\n" :
        "") +
      `Kommande aktiviteter: ${JSON.stringify(context.events)}\n\n` +
      `Anteckningen:\n${after.text}`;

    const raw = await callAnthropic(apiKey, userContent);
    const {actions, question} = parseInterpretation(raw);

    await finish({
      status: "needs_review",
      interpretation: {
        revision: nextRevision,
        requestId,
        model: ANTHROPIC_MODEL,
        actions,
        question,
        interpretedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
    });
  } catch (err) {
    const message = err instanceof HttpsError ? err.message : (err.message || "Tolkningen misslyckades.");
    console.error(`interpretNote: ${message}`);
    // Originalet är orört; anteckningen kan köras om med en ny begäran.
    await finish({status: "failed", interpretationError: message});
  }
});

exports.NOTE_QUOTA_PER_DAY = NOTE_QUOTA_PER_DAY;
exports.QUOTA_EXHAUSTED_MESSAGE = QUOTA_EXHAUSTED_MESSAGE;
exports.stockholmDateKey = stockholmDateKey;

exports._test = {
  shouldInterpret,
  parseInterpretation,
  validationProblem,
  actionId,
  stockholmDateKey,
};
