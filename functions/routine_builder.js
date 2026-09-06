/* eslint-disable valid-jsdoc, max-len */
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

const ANTHROPIC_MODEL = "claude-sonnet-5";

const ROUTINE_BUILDER_SYSTEM =
  "Du är en expert på NPF-anpassad vardagsstruktur och baklängesplanering av morgon- och kvällsrutiner för barn och familjer.\n" +
  "Svara ENDAST med giltig JSON, ingen annan text eller markdown:\n" +
  "{\n" +
  "  \"malTid\": \"HH:mm\",\n" +
  "  \"malEtikett\": \"...\",\n" +
  "  \"antaganden\": [\"...\", \"...\"],\n" +
  "  \"steps\": [\n" +
  "    {\"tid\": \"HH:mm\", \"piktogram\": \"emoji\", \"titel\": \"...\"}\n" +
  "  ]\n" +
  "}\n" +
  "REGLER FÖR BAKLÄNGESPLANERING & STRUKTUR:\n" +
  "1. Baklängesplanera från fasta ankare i beskrivningen (t.ex. tåg-, buss- eller skoltider, 'måste vara ute', restider). Räkna exakt: tågtid minus gångtid minus körning/lämning = tid ut genom dörren. Lägg alltid 3–5 min buffert före avfärd.\n" +
  "2. Realistiska schablontider när inget annat anges:\n" +
  "   - Dusch: 10 min\n" +
  "   - Frukost: 15 min\n" +
  "   - Påklädning: 5 min\n" +
  "   - Tandborstning: 3 min\n" +
  "   - Packa väska: 3 min\n" +
  "   - Skor & ytterkläder: 3–5 min\n" +
  "   Lista VARJE antagande som gjorts i fältet 'antaganden' (t.ex. 'Dusch 10 min', 'Frukost 15 min', '4 min buffert före avfärd').\n" +
  "3. Logisk ordning:\n" +
  "   - Morgonrutin: hygien och påklädning FÖRE frukost om inget annat sägs i texten.\n" +
  "   - Kvällsrutin: planeras framåt från angiven läggtid eller starttid.\n" +
  "4. Antal steg: 5–10 steg, i strikt kronologiskt stigande tidsordning ('tid'), alla i formatet 'HH:mm' (24-timmars).\n" +
  "5. Piktogram: välj en passande, tydlig emoji för varje steg.\n" +
  "6. Titlar: svenska, korta, konkreta NPF-vänliga titlar UTAN tider i titeln (tiden ska endast ligga i 'tid'-fältet).\n" +
  "7. Om befintliga steg skickas med: utgå från dem, bevara relevanta steg och justera tider och ordning istället för att börja om helt.\n" +
  "8. Hitta ALDRIG på ankare eller tider som inte står eller kan härledas från beskrivningen.";

/**
 * Tolkar och validerar JSON-svar från AI.
 * @param {string} raw Rå sträng från AI-svaret.
 * @return {object} Parsat och sanerat rutinsvar.
 */
function parseRoutineJson(raw) {
  let text = String(raw || "").trim();
  if (text.startsWith("```")) {
    text = text.replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/m, "").trim();
  } else {
    const match = text.match(/```(?:json)?\s*([\s\S]*?)\s*```/i);
    if (match && match[1]) {
      text = match[1].trim();
    }
  }

  if (!text.startsWith("{")) {
    const firstBrace = text.indexOf("{");
    const lastBrace = text.lastIndexOf("}");
    if (firstBrace !== -1 && lastBrace > firstBrace) {
      text = text.substring(firstBrace, lastBrace + 1);
    }
  }

  const parsed = JSON.parse(text);
  if (!parsed || typeof parsed !== "object") {
    throw new Error("Ogiltigt svar från AI.");
  }
  const malTid = typeof parsed.malTid === "string" ? parsed.malTid.trim() : "";
  const malEtikett = typeof parsed.malEtikett === "string" ? parsed.malEtikett.trim() : "";
  const antaganden = Array.isArray(parsed.antaganden) ?
    parsed.antaganden.map(String).map((s) => s.trim()).filter(Boolean) :
    [];
  const rawSteps = Array.isArray(parsed.steps) ? parsed.steps : [];
  const steps = [];

  for (const s of rawSteps) {
    if (!s || typeof s !== "object") continue;
    const tid = typeof s.tid === "string" ? s.tid.trim() : "";
    const piktogram = typeof s.piktogram === "string" && s.piktogram.trim() ?
      s.piktogram.trim() :
      "✅";
    const titel = typeof s.titel === "string" && s.titel.trim() ?
      s.titel.trim() :
      (typeof s.title === "string" && s.title.trim() ? s.title.trim() : "");
    if (!titel) continue;

    steps.push({
      tid: /^\d{2}:\d{2}$/.test(tid) ? tid : null,
      piktogram,
      title: titel,
    });
    if (steps.length >= 15) break;
  }

  return {
    malTid: /^\d{2}:\d{2}$/.test(malTid) ? malTid : "",
    malEtikett,
    antaganden,
    steps,
  };
}

/**
 * Callable: genererar en baklängesplanerad rutin via Anthropic Claude Sonnet 5.
 * Indata: { type: 'morning'|'evening', ownerName: string, beskrivning: string, befintligaSteg?: [{titel, tid?}] }
 */
exports.generateRoutine = onCall({
  region: "us-central1",
  secrets: ["LAFAMILIA_ANTHROPIC_KEY"],
  timeoutSeconds: 60,
  memory: "256MiB",
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
  const familyId = caller.familyId;
  if (!familyId) {
    throw new HttpsError("failed-precondition", "Ingen familj kopplad.");
  }

  const data = request.data || {};
  const {type = "morning", ownerName = "", beskrivning = "", befintligaSteg = []} = data;

  if (!beskrivning || typeof beskrivning !== "string" || !beskrivning.trim()) {
    throw new HttpsError("invalid-argument", "Beskrivning saknas.");
  }

  const userPrompt =
    `Typ: ${type === "evening" ? "Kvällsrutin" : "Morgonrutin"}\n` +
    `För: ${ownerName || "Familjemedlem"}\n` +
    `Beskrivning: ${beskrivning.trim()}\n` +
    (Array.isArray(befintligaSteg) && befintligaSteg.length > 0 ?
      `Befintliga steg som underlag:\n${JSON.stringify(befintligaSteg, null, 2)}` :
      "");

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 55000);

  let response;
  try {
    response = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      signal: controller.signal,
      headers: {
        "x-api-key": apiKey,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
      },
      body: JSON.stringify({
        model: ANTHROPIC_MODEL,
        max_tokens: 4000,
        thinking: {type: "disabled"},
        system: ROUTINE_BUILDER_SYSTEM,
        messages: [{
          role: "user",
          content: userPrompt,
        }],
      }),
    });
  } catch (err) {
    if (err.name === "AbortError") {
      throw new HttpsError("unavailable", "AI-tjänsten svarade inte i tid.");
    }
    throw new HttpsError("unavailable", "Kunde inte nå AI-tjänsten.");
  } finally {
    clearTimeout(timer);
  }

  if (!response.ok) {
    const errorText = await response.text().catch(() => "");
    console.error("Anthropic error:", response.status, errorText);
    throw new HttpsError("internal", "AI-tjänsten returnerade ett fel.");
  }

  const json = await response.json();
  const textBlock = (json.content || []).find((b) => b && b.type === "text");
  const content = textBlock && typeof textBlock.text === "string" ? textBlock.text : "";

  if (!content) {
    console.error("Inget textblock i Anthropic-svaret:", JSON.stringify(json));
    throw new HttpsError("internal", "Inget svar från AI.");
  }

  try {
    return parseRoutineJson(content);
  } catch (e) {
    console.error("Kunde inte parsa JSON från AI:", content, e);
    throw new HttpsError("internal", "Kunde inte tolka svaret från AI.");
  }
});
