/* eslint-disable linebreak-style, max-len, require-jsdoc, indent, object-curly-spacing, valid-jsdoc */
/**
 * PROXYKONTRAKT FÖR STORSKÄRM: KOLLEKTIVTRAFIK (FAS 5)
 *
 * Denna Cloud Function agerar proxy och normaliserare mot Trafiklabs API:er.
 * För närvarande används Trafiklabs ResRobot v2.1 DepartureBoard API som underliggande
 * datakälla för att matcha den tilldelade API-nyckelns behörighet.
 *
 * PROXYKONTRAKTET ÄR LÅST:
 * Klienten (avgangar_module) förväntar sig och förlitar sig uteslutande på:
 *   Input:  { stopIds: string[], limit?: number }
 *   Output: {
 *     stops: [
 *       {
 *         stopId: string,
 *         stopName: string,
 *         departures: [
 *           {
 *             line: string,
 *             mode: "bus" | "train",
 *             destination: string,
 *             scheduled: "HH:mm",
 *             realtime: "HH:mm",
 *             delayedMin: number,
 *             cancelled: boolean
 *           }
 *         ]
 *       }
 *     ],
 *     fetchedAt: string (ISO8601),
 *     attribution: "data från Trafiklab.se"
 *   }
 *
 * Ett framtida byte tillbaka till Trafiklab Realtime APIs (t.ex. Timetables v1)
 * kan därmed ske uteslutande i denna backend-fil utan någon som helst klientändring.
 */
const { onCall, HttpsError } = require("firebase-functions/v2/https");

// In-memory cache per instans (TTL 60 sekunder)
const transitCache = new Map();
const CACHE_TTL_MS = 60 * 1000;

/**
 * Normaliserar en avgång från ResRobot v2.1 till DisplayTransit-kontraktet.
 */
function normalizeDeparture(d) {
  const product = (Array.isArray(d.Product) && d.Product[0]) || {};
  const operator = (product.operator || "").trim();
  const catOutL = (product.catOutL || "").toLowerCase();
  const name = (d.name || "").toLowerCase();
  const cls = Number(product.cls || 0);

  // Avgör färdmedel (mode): tåg eller buss
  const isTrain = cls === 1 || cls === 2 || cls === 16 ||
    catOutL.includes("tåg") || name.includes("tåg");
  const mode = isTrain ? "train" : "bus";

  // Linjebeteckning
  let line;
  if (isTrain) {
    if (operator.includes("Östgötatrafiken")) {
      line = "Östgötapendeln";
    } else if (operator.includes("Jönköpings Länstrafik")) {
      line = "Krösatåget";
    } else if (operator.includes("SJ")) {
      line = "SJ";
    } else {
      line = product.displayNumber || product.line || d.name || "Tåg";
    }
  } else {
    line = product.displayNumber || product.line || (d.name ? d.name.replace(/^[^-]+-\s*/, "") : "Buss");
  }

  // Destination (rensa bort kommun-suffix som "(Tranås kn)")
  let destination = (d.direction || "").trim();
  destination = destination.replace(/\s*\([^)]*kn\)\s*$/i, "").trim();

  // Tider i HH:mm
  const timeStr = String(d.time || "").trim();
  const scheduled = timeStr.length >= 5 ? timeStr.substring(0, 5) : timeStr;

  const rtTimeStr = String(d.rtTime || d.time || "").trim();
  const realtime = rtTimeStr.length >= 5 ? rtTimeStr.substring(0, 5) : rtTimeStr;

  // Förseningsberäkning i minuter
  let delayedMin = 0;
  if (d.rtTime && d.rtTime !== d.time && d.date) {
    try {
      const schedMs = Date.parse(`${d.date}T${d.time}`);
      const rtDate = d.rtDate || d.date;
      const rtMs = Date.parse(`${rtDate}T${d.rtTime}`);
      if (!isNaN(schedMs) && !isNaN(rtMs)) {
        const diff = Math.round((rtMs - schedMs) / 60000);
        if (diff > 0) delayedMin = diff;
      }
    } catch (e) {
      console.warn("[displayTransit] Kunde inte beräkna försening:", e.message);
    }
  }

  const cancelled = d.cancelled === true || d.cancelled === "true";

  return {
    line,
    mode,
    destination,
    scheduled,
    realtime,
    delayedMin,
    cancelled,
  };
}

/**
 * Hämtar och normaliserar avgångar för en enskild hållplats.
 */
async function fetchDeparturesForStop(stopId, apiKey, limit) {
  const now = Date.now();
  const cached = transitCache.get(stopId);
  if (cached && (now - cached.timestamp) < CACHE_TTL_MS) {
    return {
      ...cached.data,
      departures: cached.data.departures.slice(0, limit),
    };
  }

  console.log(`[displayTransit] Cache miss för stopId ${stopId}`);

  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), 5000);

  let response;
  try {
    const url = `https://api.resrobot.se/v2.1/departureBoard?id=${encodeURIComponent(stopId)}&format=json&accessId=${encodeURIComponent(apiKey)}`;
    response = await fetch(url, { signal: controller.signal });
  } catch (err) {
    if (err.name === "AbortError") {
      console.error(`[displayTransit] Timeout mot Trafiklab för stopId ${stopId}`);
      throw new HttpsError("unavailable", "Trafiklab svarade inte i tid (5s timeout).");
    }
    console.error(`[displayTransit] Nätverksfel mot Trafiklab för stopId ${stopId}:`, err);
    throw new HttpsError("unavailable", "Kunde inte ansluta till tidtabellstjänsten.");
  } finally {
    clearTimeout(timeoutId);
  }

  if (!response.ok) {
    const errorBody = await response.text().catch(() => "");
    console.error(`[displayTransit] Trafiklab fel ${response.status} för stopId ${stopId}:`, errorBody);
    throw new HttpsError("unavailable", `Trafiklab returnerade felkod ${response.status}.`);
  }

  const json = await response.json();
  const rawList = Array.isArray(json.Departure) ? json.Departure : [];

  let stopName = "";
  if (rawList.length > 0 && rawList[0].stop) {
    stopName = rawList[0].stop;
  }

  const departures = rawList.map(normalizeDeparture);

  const stopResult = {
    stopId: String(stopId),
    stopName: stopName || `Hållplats ${stopId}`,
    departures,
  };

  transitCache.set(stopId, {
    timestamp: now,
    data: stopResult,
  });

  return {
    ...stopResult,
    departures: departures.slice(0, limit),
  };
}

/**
 * Callable function: displayTransit
 * Hämtar kollektivtrafikavgångar för angivna stopIds via Trafiklab ResRobot v2.1.
 */
exports.displayTransit = onCall({
  region: "us-central1",
  secrets: ["TRAFIKLAB_API_KEY"],
  timeoutSeconds: 60,
  memory: "256MiB",
}, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Inloggning krävs.");
  }

  const apiKey = process.env.TRAFIKLAB_API_KEY;
  if (!apiKey) {
    console.error("[displayTransit] TRAFIKLAB_API_KEY saknas i Secret Manager.");
    throw new HttpsError("failed-precondition", "Kollektivtrafik-nyckel saknas på servern.");
  }

  const data = request.data || {};
  const rawStopIds = data.stopIds;
  if (!Array.isArray(rawStopIds) || rawStopIds.length === 0) {
    throw new HttpsError("invalid-argument", "stopIds måste vara en icke-tom array.");
  }

  // Max 5 hållplatser per anrop för att undvika överbelastning
  const stopIds = rawStopIds.slice(0, 5).map((id) => String(id).trim()).filter(Boolean);
  if (stopIds.length === 0) {
    throw new HttpsError("invalid-argument", "Inga giltiga stopIds angivna.");
  }

  const limit = Math.min(Math.max(Number(data.limit) || 6, 1), 10);

  const stopResults = [];
  for (const stopId of stopIds) {
    try {
      const stopData = await fetchDeparturesForStop(stopId, apiKey, limit);
      stopResults.push(stopData);
    } catch (e) {
      console.error(`[displayTransit] Fel vid hämtning av ${stopId}:`, e.message || e);
      // Om ett stopId felar lägger vi till en tom struktur så övriga hållplatser fortfarande kan visas
      stopResults.push({
        stopId,
        stopName: `Hållplats ${stopId}`,
        departures: [],
        error: "Kunde inte hämta avgångar just nu",
      });
    }
  }

  return {
    stops: stopResults,
    fetchedAt: new Date().toISOString(),
    attribution: "data från Trafiklab.se",
  };
});
