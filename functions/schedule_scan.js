/* eslint-disable valid-jsdoc, max-len */
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const {commitInChunks} = require("./calendar_feeds");

const ANTHROPIC_MODEL = "claude-sonnet-5";

const PARSE_SCHEDULE_IMAGE_SYSTEM =
  "Du läser ett foto av ett veckoschema (rehab, skola eller aktivitet).\n" +
  "Svara ENDAST med giltig JSON, ingen annan text:\n" +
  "{\"scheduleTitle\":\"...\",\"personHint\":\"...\"|null,\n" +
  "\"events\":[{\"date\":\"YYYY-MM-DD\",\"time\":\"HH:mm\",\n" +
  "\"endTime\":\"HH:mm\"|null,\"title\":\"...\",\"location\":null|\"...\"}]}.\n" +
  "Regler: Kolumnrubriker kan innehålla datum som YYMMDD (260824 =\n" +
  "2026-08-24) — använd dem i första hand. Saknas datum: använd angiven\n" +
  "veckostart (måndag) + veckodagen i rubriken. Tider skrivna med punkt\n" +
  "(07.30) blir 07:30. Ta med ALLA läsbara poster inklusive Lunch.\n" +
  "STARTTID (time): tryckt tid i rutan gäller alltid. Saknar rutan tryckt\n" +
  "tid men schemat är ett tidsrutnät med timaxel: läs av rutans ÖVERKANT\n" +
  "mot timaxeln, avrundat till närmaste kvart (:00/:15/:30/:45).\n" +
  "SLUTTID (endTime), i prioritetsordning:\n" +
  "1) En sluttid som står i texten (t.ex. '13.30-14.45') gäller alltid.\n" +
  "2) I ett tidsrutnät: läs av rutans NEDERKANT mot timaxeln, avrundat\n" +
  "till närmaste kvart. Rutans höjd = aktivitetens längd.\n" +
  "3) Annars endTime = null. Gissa ALDRIG en sluttid som varken står i\n" +
  "text eller går att läsa ur rutnätet.\n" +
  "Hitta aldrig på händelser — hoppa över oläsliga rader. Titlar exakt\n" +
  "som de står (behåll namn som 'Fysioterapi Maria').";

/** @return {string} YYYY-MM-DD i Europe/Stockholm */
function stockholmDateKey(d = new Date()) {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "Europe/Stockholm",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(d);
}

/** @param {FirebaseFirestore.Firestore} db @param {string} familyId @param {string} todayKey */
async function consumeAiQuota(db, familyId, todayKey) {
  const ref = db.collection("ai_usage").doc(familyId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.data() || {};
    const count = data.date === todayKey ? (data.count || 0) : 0;
    if (count >= 10) {
      throw new HttpsError("resource-exhausted", "Dagens AI-kvot är slut.");
    }
    tx.set(ref, {date: todayKey, count: count + 1}, {merge: true});
  });
}

function parseScheduleJson(raw) {
  let text = String(raw || "").trim();
  if (text.startsWith("```")) {
    text = text.replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/m, "").trim();
  }
  const parsed = JSON.parse(text);
  if (!parsed || typeof parsed !== "object") {
    throw new Error("Ogiltigt svar från AI.");
  }
  const rawEvents = Array.isArray(parsed.events) ? parsed.events : [];
  const events = [];

  for (const item of rawEvents) {
    if (!item || typeof item !== "object") continue;
    const date = typeof item.date === "string" ? item.date.trim() : "";
    const time = typeof item.time === "string" ? item.time.trim() : "";
    const title = typeof item.title === "string" ? item.title.trim() : "";
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) continue;
    if (!/^\d{2}:\d{2}$/.test(time)) continue;
    if (!title) continue;

    let endTime = null;
    if (typeof item.endTime === "string" && /^\d{2}:\d{2}$/.test(item.endTime.trim())) {
      endTime = item.endTime.trim();
    }

    let location = null;
    if (typeof item.location === "string" && item.location.trim()) {
      location = item.location.trim();
    }

    events.push({
      date,
      time,
      endTime,
      title,
      location,
    });
    if (events.length >= 60) break;
  }

  const scheduleTitle = typeof parsed.scheduleTitle === "string" && parsed.scheduleTitle.trim() ?
    parsed.scheduleTitle.trim() :
    null;
  const personHint = typeof parsed.personHint === "string" && parsed.personHint.trim() ?
    parsed.personHint.trim() :
    null;

  return {
    scheduleTitle,
    personHint,
    events,
  };
}

/**
 * 1a. Callable: tolkar foto av veckoschema via Anthropic Vision.
 * Indata: { imageBase64, mediaType, weekStartHint }
 */
exports.parseScheduleImage = onCall({
  region: "us-central1",
  secrets: ["LAFAMILIA_ANTHROPIC_KEY"],
  timeoutSeconds: 120,
  memory: "512MiB",
}, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Inloggning krävs.");
  }

  const apiKey = process.env.LAFAMILIA_ANTHROPIC_KEY;
  if (!apiKey) {
    throw new HttpsError("failed-precondition", "AI-nyckel saknas.");
  }

  const db = admin.firestore();
  const callerSnap = await db.collection("users").doc(request.auth.uid).get();
  if (!callerSnap.exists) {
    throw new HttpsError("permission-denied", "Användare saknas.");
  }
  const caller = callerSnap.data() || {};
  const role = caller.role || "";
  if (role !== "parent" && role !== "admin") {
    throw new HttpsError("permission-denied", "Endast föräldrar kan använda schemascanning.");
  }
  const familyId = caller.familyId;
  if (!familyId) {
    throw new HttpsError("failed-precondition", "Ingen familj kopplad.");
  }

  const data = request.data || {};
  const {imageBase64, mediaType, weekStartHint} = data;
  const validMediaTypes = ["image/jpeg", "image/png", "image/webp"];

  if (!mediaType || !validMediaTypes.includes(mediaType)) {
    throw new HttpsError(
        "invalid-argument",
        "Ogiltig bildtyp (måste vara JPEG, PNG eller WebP).",
    );
  }

  if (!imageBase64 || typeof imageBase64 !== "string" || imageBase64.length > 6000000) {
    throw new HttpsError(
        "invalid-argument",
        "Bilden är för stor — ta om fotot.",
    );
  }

  const todayKey = stockholmDateKey();
  await consumeAiQuota(db, familyId, todayKey);

  const requestBody = JSON.stringify({
    model: ANTHROPIC_MODEL,
    max_tokens: 3000,
    system: PARSE_SCHEDULE_IMAGE_SYSTEM,
    messages: [{
      role: "user",
      content: [
        {
          type: "image",
          source: {
            type: "base64",
            media_type: mediaType,
            data: imageBase64,
          },
        },
        {
          type: "text",
          text: "Veckostart om datum saknas: " + (weekStartHint || ""),
        },
      ],
    }],
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
    const timer = setTimeout(() => controller.abort(), 55000);

    try {
      response = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        signal: controller.signal,
        headers,
        body: requestBody,
      });
    } catch (err) {
      console.warn(`parseScheduleImage: Nätverksfel vid försök ${attempt}:`, err.message || err);
      if (attempt === 1) {
        await sleep(1500);
        continue;
      }
      if (err.name === "AbortError") {
        throw new HttpsError("unavailable", "AI-tjänsten svarade inte i tid.");
      }
      throw new HttpsError("unavailable", "Kunde inte nå AI-tjänsten (nätverksfel).");
    } finally {
      clearTimeout(timer);
    }

    if (response.ok) {
      break;
    }

    const errBodyText = await response.text();
    console.error(
        `parseScheduleImage: Anthropic HTTP ${response.status} (försök ${attempt}): ` +
        `${errBodyText.slice(0, 500)}`,
    );

    const isRetryable = response.status === 429 ||
      response.status === 529 ||
      (response.status >= 500 && response.status <= 599);

    if (attempt === 1 && isRetryable) {
      await sleep(1500);
      continue;
    }

    const status = response.status;
    if (status === 400) {
      throw new HttpsError(
          "invalid-argument",
          "Ogiltig begäran till AI-tjänsten (HTTP 400).",
      );
    } else if (status === 401 || status === 403) {
      throw new HttpsError(
          "permission-denied",
          `Åtkomst nekad till AI-tjänsten (HTTP ${status}).`,
      );
    } else if (status === 429) {
      throw new HttpsError(
          "resource-exhausted",
          "AI-tjänsten är överbelastad (HTTP 429). Försök igen om en stund.",
      );
    } else if (status === 529) {
      throw new HttpsError(
          "unavailable",
          "AI-tjänsten är överbelastad (HTTP 529). Försök igen om en stund.",
      );
    } else if (status >= 500 && status <= 599) {
      throw new HttpsError(
          "unavailable",
          `AI-tjänsten stötte på ett internt fel (HTTP ${status}). Försök igen.`,
      );
    } else {
      throw new HttpsError(
          "unavailable",
          `AI-tjänsten svarade med fel (HTTP ${status}).`,
      );
    }
  }

  if (!response || !response.ok) {
    throw new HttpsError("unavailable", "AI-tjänsten är tillfälligt otillgänglig.");
  }

  let body;
  try {
    body = await response.json();
  } catch (_) {
    throw new HttpsError("unavailable", "Ogiltigt svar från AI-tjänsten.");
  }

  const stopReason = body.stop_reason || null;
  if (stopReason === "max_tokens") {
    throw new HttpsError(
        "unavailable",
        "AI-svaret blev för långt — försök med ett mer avgränsat foto.",
    );
  }

  const textBlock = (body.content || []).find((b) => b.type === "text");
  if (!textBlock || !textBlock.text) {
    throw new HttpsError("unavailable", "Tomt svar från AI-tjänsten.");
  }

  try {
    return parseScheduleJson(textBlock.text);
  } catch (_) {
    throw new HttpsError(
        "unavailable",
        "Kunde inte tolka schemat — försök med ett skarpare foto.",
    );
  }
});

/**
 * 1b. Callable: sparar tolkade schemahändelser till Firestore under calendar_imports + planner_events.
 * Indata: { name, personName, personUid, events }
 */
exports.saveScheduleImport = onCall({
  region: "us-central1",
  timeoutSeconds: 60,
  memory: "512MiB",
}, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Inloggning krävs.");
  }

  const db = admin.firestore();
  const callerSnap = await db.collection("users").doc(request.auth.uid).get();
  if (!callerSnap.exists) {
    throw new HttpsError("permission-denied", "Användare saknas.");
  }
  const caller = callerSnap.data() || {};
  const role = caller.role || "";
  if (role !== "parent" && role !== "admin") {
    throw new HttpsError("permission-denied", "Endast föräldrar kan importera schema.");
  }
  const familyId = caller.familyId;
  if (!familyId) {
    throw new HttpsError("failed-precondition", "Ingen familj kopplad.");
  }

  const data = request.data || {};
  const name = typeof data.name === "string" && data.name.trim() ?
    data.name.trim() :
    "Skannat schema";
  const personName = typeof data.personName === "string" && data.personName.trim() ?
    data.personName.trim() :
    "";
  const personUid = typeof data.personUid === "string" && data.personUid.trim() ?
    data.personUid.trim() :
    "";
  const rawEvents = Array.isArray(data.events) ? data.events : [];

  if (rawEvents.length === 0) {
    throw new HttpsError("invalid-argument", "Inga händelser att spara.");
  }
  if (rawEvents.length > 100) {
    throw new HttpsError("invalid-argument", "Max 100 händelser per import.");
  }

  const validEvents = [];
  for (const item of rawEvents) {
    if (!item || typeof item !== "object") continue;
    const date = typeof item.date === "string" ? item.date.trim() : "";
    const time = typeof item.time === "string" ? item.time.trim() : "";
    const title = typeof item.title === "string" ? item.title.trim() : "";
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) continue;
    if (!/^\d{2}:\d{2}$/.test(time)) continue;
    if (!title) continue;

    let endTime = null;
    if (typeof item.endTime === "string" && /^\d{2}:\d{2}$/.test(item.endTime.trim())) {
      endTime = item.endTime.trim();
    }
    let location = null;
    if (typeof item.location === "string" && item.location.trim()) {
      location = item.location.trim();
    }

    validEvents.push({date, time, endTime, title, location});
  }

  // Reservregel: aktivitet pågår tills nästa börjar samma dag. Rör aldrig
  // sluttider AI:n läst ur text/rutnät. Spegling finns i
  // lib/screens/schedule_scan_page.dart (_inferBlockEndTimes).
  const inferBlockEndTimes = (events) => {
    const byDate = new Map();
    for (const ev of events) {
      if (!ev.date) continue;
      if (!byDate.has(ev.date)) {
        byDate.set(ev.date, []);
      }
      byDate.get(ev.date).push(ev);
    }
    for (const dayEvents of byDate.values()) {
      dayEvents.sort((a, b) => a.time.localeCompare(b.time));
      for (let i = 0; i < dayEvents.length - 1; i++) {
        const cur = dayEvents[i];
        const next = dayEvents[i + 1];
        if (!cur.endTime && next.time > cur.time) {
          cur.endTime = next.time;
        }
      }
    }
  };
  inferBlockEndTimes(validEvents);

  if (validEvents.length === 0) {
    throw new HttpsError("invalid-argument", "Inga giltiga händelser att spara.");
  }

  const rawLabel = typeof data.schemaLabel === "string" ? data.schemaLabel.trim() : "";
  let schemaLabel = "Skola";
  let piktogram = "🏫";
  if (rawLabel === "Rehab") {
    schemaLabel = "Rehab";
    piktogram = "🏥";
  } else if (rawLabel === "Jobb") {
    schemaLabel = "Jobb";
    piktogram = "💼";
  } else if (rawLabel === "Schema" || rawLabel === "Annat") {
    schemaLabel = "Schema";
    piktogram = "📋";
  } else if (rawLabel === "Skola") {
    schemaLabel = "Skola";
    piktogram = "🏫";
  } else {
    const low = name.toLowerCase();
    if (low.includes("rehab") || low.includes("klinik")) {
      schemaLabel = "Rehab";
      piktogram = "🏥";
    }
  }
  if (typeof data.piktogram === "string" && data.piktogram.trim()) {
    piktogram = data.piktogram.trim();
  }

  const importRef = db.collection("calendar_imports").doc();
  await importRef.set({
    familyId,
    name,
    importKind: "photo",
    targetType: "schedule",
    planningImportKind: "schedule",
    schemaLabel,
    piktogram,
    person: personName || null,
    personUid: personUid || null,
    assignedMember: personName || null,
    eventCount: validEvents.length,
    lastSync: admin.firestore.FieldValue.serverTimestamp(),
    createdByUid: request.auth.uid,
    source: "photo",
    autoSync: false,
  });

  const slug = (str) => String(str || "").toLowerCase().replace(/[^a-z0-9åäö]/g, "").slice(0, 30);
  const ops = [];

  for (const ev of validEvents) {
    const eventRef = db.collection("planner_events").doc();
    const icsKey = `photo|${ev.date}|${ev.time}|${slug(ev.title)}`;
    const eventData = {
      title: ev.title,
      piktogram,
      schemaLabel,
      type: "activity",
      date: ev.date,
      time: ev.time,
      persons: personName ? [personName] : [],
      personUids: personUid ? [personUid] : [],
      checklist: [],
      source: "calendar",
      planningImportKind: "schedule",
      calendarName: name,
      calendarImportId: importRef.id,
      createdBy: request.auth.uid,
      createdByUid: request.auth.uid,
      isPending: false,
      familyId,
      icsKey,
    };
    if (ev.endTime) eventData.endTime = ev.endTime;
    if (ev.location) eventData.location = ev.location;

    ops.push({ref: eventRef, data: eventData});
  }

  await commitInChunks(db, ops);

  return {
    importId: importRef.id,
    eventCount: validEvents.length,
  };
});
