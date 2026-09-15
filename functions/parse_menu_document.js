/* eslint-disable linebreak-style, max-len, require-jsdoc, indent, object-curly-spacing, valid-jsdoc */
/**
 * CLOUD FUNCTION: parseMenuDocument (FAS 5.1b)
 *
 * Tolkar uppladdad matsedel (bild eller PDF) med Anthropic Messages API (claude-sonnet-5).
 * Extraherar veckodagar med datum, lunch, vegetariskt och eventuell avvikelse.
 *
 * Dokumentation och gränser (Anthropic PDF Support GA, 2026-09):
 * - docs.anthropic.com/en/docs/build-with-claude/pdf-support
 * - PDF skickas som standard 'document'-innehållsblock med media_type 'application/pdf'
 *   med anthropic-version '2023-06-01' utan betaheader.
 * - Bilder skickas som 'image'-block.
 * - Max applikationsstorlek: 8 MB (väl under API- och Cloud Run-gränser).
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

const ANTHROPIC_MODEL = "claude-sonnet-5";

const PARSE_MENU_SYSTEM =
  "Du läser ett dokument eller en bild av en skolmatsedel / veckomatsedel för en skola.\n" +
  "Svara ENDAST med giltig JSON, ingen annan text:\n" +
  "{\n" +
  "  \"weekNumber\": 38,\n" +
  "  \"year\": 2026,\n" +
  "  \"days\": [\n" +
  "    {\n" +
  "      \"date\": \"YYYY-MM-DD\",\n" +
  "      \"lunch\": \"...\",\n" +
  "      \"vegetarian\": \"...\"|null,\n" +
  "      \"note\": \"...\"|null\n" +
  "    }\n" +
  "  ],\n" +
  "  \"confidence\": \"high\" | \"needs_review\" | \"unreadable\",\n" +
  "  \"reason\": \"...\"|null\n" +
  "}\n" +
  "- Extrahera skoldagarna (måndag till fredag, eller alla angivna dagar i matsedeln).\n" +
  "- För varje dag: datum (YYYY-MM-DD), ordinarie lunch (lunch), vegetariskt alternativ (vegetarian) om angivet, samt eventuell notering (note).\n" +
  "- Vegetariskt (vegetarian) sätts ENDAST om ett separat vegetariskt alternativ uttryckligen finns angivet och skiljer sig från ordinarie lunch. Om inget separat vegetariskt alternativ finns, sätt vegetarian till null (fyll ALDRIG i ordinarie lunch som fallback).\n" +
  "- Ignorera dekorativa element, logotyper, menyer för äldreboende, etc.\n" +
  "- Om datum saknas på dagarna men veckonummer finns: härled datum från veckonumret och innevarande år i Sverige, och sätt confidence till 'needs_review'.\n" +
  "- Om dokumentet inte är en matsedel eller helt oläsbart: sätt confidence till 'unreadable' och ange en vänlig anledning i reason.\n" +
  "- Svara som EN kompakt JSON-rad utan radbrytningar eller extra formatering.";

/**
 * Returnerar dagens datum i Europe/Stockholm som YYYY-MM-DD.
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
 * Beräknar ISO-8601 veckosträng 'YYYY-Www' för ett givet datumsträng 'YYYY-MM-DD'.
 */
function getIsoWeek(dateStr) {
  if (!dateStr || typeof dateStr !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(dateStr)) {
    return null;
  }
  const [y, m, d] = dateStr.split("-").map(Number);
  const date = new Date(Date.UTC(y, m - 1, d));
  const dayNum = date.getUTCDay() || 7;
  date.setUTCDate(date.getUTCDate() + 4 - dayNum);
  const yearStart = new Date(Date.UTC(date.getUTCFullYear(), 0, 1));
  const weekNo = Math.ceil((((date - yearStart) / 86400000) + 1) / 7);
  return `${date.getUTCFullYear()}-W${String(weekNo).padStart(2, "0")}`;
}

/**
 * Returnerar måndagsdatum för en given ISO-veckosträng 'YYYY-Www'.
 */
function getMondayForIsoWeek(isoWeek) {
  if (!isoWeek || typeof isoWeek !== "string" || !/^\d{4}-W\d{2}$/.test(isoWeek)) {
    return null;
  }
  const [yearStr, weekPart] = isoWeek.split("-W");
  const year = parseInt(yearStr, 10);
  const week = parseInt(weekPart, 10);

  const jan4 = new Date(Date.UTC(year, 0, 4));
  const dayNum = jan4.getUTCDay() || 7;
  const mondayWeek1 = new Date(jan4);
  mondayWeek1.setUTCDate(jan4.getUTCDate() - dayNum + 1);

  const targetMonday = new Date(mondayWeek1);
  targetMonday.setUTCDate(mondayWeek1.getUTCDate() + (week - 1) * 7);
  return targetMonday;
}

/**
 * Genererar datum YYYY-MM-DD för måndag–fredag i en ISO-vecka.
 */
function getDatesForIsoWeek(isoWeek) {
  const monday = getMondayForIsoWeek(isoWeek);
  if (!monday) return [];

  const dates = [];
  for (let i = 0; i < 5; i++) {
    const d = new Date(monday);
    d.setUTCDate(monday.getUTCDate() + i);
    const y = d.getUTCFullYear();
    const m = String(d.getUTCMonth() + 1).padStart(2, "0");
    const day = String(d.getUTCDate()).padStart(2, "0");
    dates.push(`${y}-${m}-${day}`);
  }
  return dates;
}

/**
 * Beräknar skillnad i veckor mellan en målvecka och en referensvecka.
 */
function computeWeekDiff(targetIsoWeek, referenceIsoWeek) {
  const targetMonday = getMondayForIsoWeek(targetIsoWeek);
  const refMonday = getMondayForIsoWeek(referenceIsoWeek);
  if (!targetMonday || !refMonday) return null;
  const diffMs = targetMonday.getTime() - refMonday.getTime();
  return Math.round(diffMs / (7 * 24 * 60 * 60 * 1000));
}

/**
 * Rensar och validerar JSON-svar från AI.
 */
function parseAiJson(raw) {
  let text = String(raw || "").trim();
  if (text.startsWith("```")) {
    text = text.replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/m, "").trim();
  }
  return JSON.parse(text);
}

/**
 * Rensar och normaliserar dag-objekt.
 * Sätter vegetarian till null om den matchar ordinarie lunch (ingen dubblering/fallback).
 */
function cleanMenuDays(rawDays) {
  if (!Array.isArray(rawDays)) return [];
  return rawDays
    .filter((d) => d && typeof d === "object")
    .map((d) => {
      const lunch = typeof d.lunch === "string" && d.lunch.trim() ? d.lunch.trim() : null;
      let vegetarian = typeof d.vegetarian === "string" && d.vegetarian.trim() ? d.vegetarian.trim() : null;
      if (vegetarian && lunch && vegetarian.trim().toLowerCase() === lunch.trim().toLowerCase()) {
        vegetarian = null;
      }
      return {
        date: typeof d.date === "string" ? d.date.trim() : "",
        lunch,
        vegetarian,
        note: typeof d.note === "string" && d.note.trim() ? d.note.trim() : null,
      };
    });
}

/**
 * Pausfunktion för retries.
 */
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/**
 * Cloud Function: parseMenuDocument
 */
exports.parseMenuDocument = onCall({
  region: "us-central1",
  secrets: ["LAFAMILIA_ANTHROPIC_KEY"],
  timeoutSeconds: 120,
  memory: "512MiB",
}, async (request) => {
  const startTime = Date.now();

  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Inloggning krävs för att tolka matsedel.");
  }

  const apiKey = process.env.LAFAMILIA_ANTHROPIC_KEY;
  if (!apiKey) {
    throw new HttpsError("failed-precondition", "AI-nyckel saknas på servern.");
  }

  const data = request.data || {};
  const { schoolId, familyId, fileBase64, mimeType, fileName } = data;

  if (!schoolId || typeof schoolId !== "string" || !schoolId.trim()) {
    throw new HttpsError("invalid-argument", "schoolId saknas eller är ogiltigt.");
  }
  if (!familyId || typeof familyId !== "string" || !familyId.trim()) {
    throw new HttpsError("invalid-argument", "familyId saknas eller är ogiltigt.");
  }

  // 1. Behörighetskontroll: Anroparen måste vara förälder/admin i familjen
  const db = admin.firestore();
  const callerSnap = await db.collection("users").doc(request.auth.uid).get();
  if (!callerSnap.exists) {
    throw new HttpsError("permission-denied", "Användaren finns inte.");
  }
  const callerData = callerSnap.data() || {};
  const role = callerData.role || "";
  if (role !== "parent" && role !== "admin") {
    throw new HttpsError("permission-denied", "Endast föräldrar kan ladda upp och tolka matsedlar.");
  }
  if (callerData.familyId !== familyId) {
    throw new HttpsError("permission-denied", "Användaren tillhör inte den angivna familjen.");
  }

  // 2. Validering av filtyp och storlek
  const allowedMimeTypes = ["image/jpeg", "image/png", "image/webp", "application/pdf"];
  if (!mimeType || !allowedMimeTypes.includes(mimeType)) {
    throw new HttpsError(
      "invalid-argument",
      "Ogiltig filtyp. Tillåtna format är JPEG, PNG, WebP eller PDF.",
    );
  }

  // Max 8 MB rådata (~11.2 MB base64)
  const MAX_BASE64_LENGTH = Math.ceil((8 * 1024 * 1024 * 4) / 3);
  if (!fileBase64 || typeof fileBase64 !== "string" || fileBase64.length > MAX_BASE64_LENGTH) {
    throw new HttpsError("invalid-argument", "Dokumentet är för stort (max 8 MB).");
  }

  // 3. Skapa meddelande till Anthropic API
  const todayKey = stockholmDateKey();
  const currentIsoWeek = getIsoWeek(todayKey);

  const contentBlock = mimeType === "application/pdf"
    ? {
        type: "document",
        source: {
          type: "base64",
          media_type: "application/pdf",
          data: fileBase64,
        },
      }
    : {
        type: "image",
        source: {
          type: "base64",
          media_type: mimeType,
          data: fileBase64,
        },
      };

  const requestBody = JSON.stringify({
    model: ANTHROPIC_MODEL,
    max_tokens: 4000,
    system: PARSE_MENU_SYSTEM,
    messages: [
      {
        role: "user",
        content: [
          contentBlock,
          {
            type: "text",
            text: `Dagens datum i Sverige är ${todayKey} (innevarande vecka ${currentIsoWeek}). Tolka matsedeln.`,
          },
        ],
      },
    ],
  });

  const headers = {
    "x-api-key": apiKey,
    "anthropic-version": "2023-06-01",
    "content-type": "application/json",
  };

  // 4. Anrop till Anthropic med timeout och 2 försök
  let response;
  for (let attempt = 1; attempt <= 2; attempt++) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 90000);

    try {
      response = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        signal: controller.signal,
        headers,
        body: requestBody,
      });
    } catch (err) {
      console.warn(`[parseMenuDocument] Nätverksfel försök ${attempt}:`, err.message || err);
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

    const errText = await response.text();
    console.error(`[parseMenuDocument] Anthropic HTTP ${response.status} (försök ${attempt}): ${errText.slice(0, 300)}`);

    const isRetryable = response.status === 429 ||
      response.status === 529 ||
      (response.status >= 500 && response.status <= 599);

    if (attempt === 1 && isRetryable) {
      await sleep(2000);
      continue;
    }

    if (response.status === 429) {
      throw new HttpsError("resource-exhausted", "AI-tjänsten är hårt belastad, försök igen strax.");
    }
    throw new HttpsError("internal", `AI-tolkningen misslyckades (${response.status}).`);
  }

  const resultJson = await response.json();
  const rawText = resultJson.content?.[0]?.text;
  let parsed;
  try {
    parsed = parseAiJson(rawText);
  } catch (e) {
    console.error("[parseMenuDocument] Kunde inte parsa JSON-svar från AI:", e.message || e);
    return {
      status: "unreadable",
      message: "Kunde inte tolka formatet från AI-svaret.",
      confidence: "unreadable",
    };
  }

  // 5. Validering och förtroendebedömning
  const aiConfidence = parsed.confidence || "needs_review";
  if (aiConfidence === "unreadable" || !Array.isArray(parsed.days) || parsed.days.length === 0) {
    const elapsed = Date.now() - startTime;
    console.log(`[parseMenuDocument] schoolId=${schoolId} week=none confidence=unreadable ms=${elapsed}`);
    return {
      status: "unreadable",
      message: parsed.reason || "Kunde inte hitta någon läsbar matsedel i dokumentet.",
      confidence: "unreadable",
    };
  }

  // Rensa och normalisera dagarna
  let days = cleanMenuDays(parsed.days);

  // Härled veckokandidater baserat på innevarande datum
  const [curYearStr, curWeekNumStr] = currentIsoWeek.split("-W");
  const curYear = parseInt(curYearStr, 10);
  const curWeekNum = parseInt(curWeekNumStr, 10);

  const weekCandidates = [
    currentIsoWeek,
    `${curYear}-W${String(curWeekNum + 1).padStart(2, "0")}`,
  ];
  if (curWeekNum > 1) {
    weekCandidates.unshift(`${curYear}-W${String(curWeekNum - 1).padStart(2, "0")}`);
  }

  // Om AI:n hittade ett veckonummer, se till att det finns som kandidat
  if (parsed.weekNumber && typeof parsed.weekNumber === "number") {
    const parsedWeekKey = `${parsed.year || curYear}-W${String(parsed.weekNumber).padStart(2, "0")}`;
    if (!weekCandidates.includes(parsedWeekKey)) {
      weekCandidates.push(parsedWeekKey);
    }
  }

  // Om datumen saknas eller är ogiltiga, försök härleda från veckonummer
  const hasValidDates = days.every((d) => /^\d{4}-\d{2}-\d{2}$/.test(d.date));
  let detectedIsoWeek = null;

  if (hasValidDates && days.length > 0) {
    const isoWeeks = new Set(days.map((d) => getIsoWeek(d.date)));
    if (isoWeeks.size === 1) {
      detectedIsoWeek = Array.from(isoWeeks)[0];
    }
  }

  // Om datumen saknas men veckonummer finns: fyll på datum och flagga needs_review
  let finalConfidence = aiConfidence;
  if (!detectedIsoWeek) {
    finalConfidence = "needs_review";
    const targetWeekNumber = parsed.weekNumber || curWeekNum;
    const targetYear = parsed.year || curYear;
    detectedIsoWeek = `${targetYear}-W${String(targetWeekNumber).padStart(2, "0")}`;

    const weekDates = getDatesForIsoWeek(detectedIsoWeek);
    days = days.slice(0, 5).map((d, index) => ({
      ...d,
      date: weekDates[index] || d.date,
    }));
  }

  // Kontrollera att veckan är inom tillåtet intervall [nu - 1 vecka, nu + 3 veckor]
  const weekDiff = computeWeekDiff(detectedIsoWeek, currentIsoWeek);
  const isWithinAllowedRange = weekDiff !== null && weekDiff >= -1 && weekDiff <= 3;
  if (!isWithinAllowedRange) {
    finalConfidence = "needs_review";
  }

  // Kontrollera antal dagar (1–7 dagar)
  if (days.length < 1 || days.length > 7) {
    finalConfidence = "needs_review";
  }

  const weekNum = parseInt(detectedIsoWeek.split("-W")[1], 10);
  const weekLabel = `Vecka ${weekNum}`;
  const elapsed = Date.now() - startTime;

  // 6. Skrivning till Firestore vid HIGH confidence
  if (finalConfidence === "high") {
    const weekDocRef = db
      .collection("families")
      .doc(familyId)
      .collection("school_menus")
      .doc(schoolId)
      .collection("weeks")
      .doc(detectedIsoWeek);

    await weekDocRef.set({
      days,
      weekLabel,
      source: "manual",
      uploadedBy: request.auth.uid,
      uploadedAt: admin.firestore.FieldValue.serverTimestamp(),
      originalFileName: fileName || null,
      confidence: "high",
    });

    console.log(`[parseMenuDocument] schoolId=${schoolId} week=${detectedIsoWeek} confidence=high ms=${elapsed}`);

    return {
      status: "success",
      isoWeek: detectedIsoWeek,
      weekLabel,
      days,
      confidence: "high",
    };
  }

  // 7. Retur vid NEEDS_REVIEW — skriv INTE till Firestore
  console.log(`[parseMenuDocument] schoolId=${schoolId} week=${detectedIsoWeek} confidence=needs_review ms=${elapsed}`);
  return {
    status: "needs_review",
    isoWeek: detectedIsoWeek,
    weekLabel,
    weekCandidates,
    days,
    confidence: "needs_review",
    reason: parsed.reason || (
      !isWithinAllowedRange
        ? `Tolkad vecka (${weekLabel}) ligger utanför normalt intervall.`
        : "Vissa datum eller rätter behöver bekräftas av en förälder."
    ),
  };
});

// Exportera hjälpfunktioner för enhetstester
exports._test = {
  getIsoWeek,
  getMondayForIsoWeek,
  getDatesForIsoWeek,
  computeWeekDiff,
  parseAiJson,
  cleanMenuDays,
  stockholmDateKey,
  PARSE_MENU_SYSTEM,
};
