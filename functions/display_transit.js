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

// In-memory cache för searchStops (TTL 10 minuter)
const searchStopsCache = new Map();
const SEARCH_CACHE_TTL_MS = 10 * 60 * 1000;

/**
 * Klassificerar färdmedel (modes) för både avgångar och hållplatser.
 *
 * Officiell källa för bitmask och produktkoder:
 * Trafiklab ResRobot v2.1 Common Data Types
 * https://www.trafiklab.se/api/our-apis/resrobot-v21/common/
 *
 * Request product class bitmask (används i StopLocation.products):
 *   1   = Air traffic
 *   2   = High speed trains, Snabbtåg, Arlanda Express
 *   4   = Regional trains, InterCity trains
 *   8   = Express buses, Flygbussar
 *   16  = Local trains (Tåg, PågaTåg, Öresundståg, Östgötapendeln)
 *   32  = Metro, such as tunnelbanan
 *   64  = Tram such as Spårvagn, Tvärbanan
 *   128 = Buses
 *   256 = Ferries and international ferries
 *   512 = Taxi
 *
 * Response product class categories (används i Departure.Product.cls / catCode):
 *   1 = High speed trains
 *   2 = Regional trains
 *   3 = Express buses
 *   4 = Local trains (även bitmask-värdet 16 förekommer i API-svar som cls)
 *   5 = Metro
 *   6 = Tram
 *   7 = Buses
 *   8 = Ferries (notera: i request-bitmasken är 8 expressbuss)
 *   9 = Taxi
 *
 * @param {object} params
 * @param {number} [params.products] Bitmask från StopLocation.products
 * @param {number|string} [params.cls] Produktklass från Departure.Product.cls
 * @param {string} [params.catOutL] Kategori i klartext (t.ex. "Tåg", "Buss")
 * @param {string} [params.name] Linje- eller hållplatsnamn
 * @returns {string[]} Array med identifierade modes: t.ex. ["train"], ["bus"], ["train", "bus"] eller ["unknown"]
 */
function classifyModes({ products = 0, cls = 0, catOutL = "", name = "" } = {}) {
  const modes = [];
  const prodNum = Number(products) || 0;
  const clsNum = Number(cls) || 0;
  const cat = String(catOutL || "").toLowerCase();
  const n = String(name || "").toLowerCase();

  // Tåg: bitmask 2 (high speed), 4 (regional), 16 (lokaltåg)
  // eller cls 1, 2, 4, 16
  // eller textuellt matchande "tåg" i kategori eller namn
  const isTrain = Boolean(prodNum & (2 | 4 | 16)) ||
    clsNum === 1 || clsNum === 2 || clsNum === 4 || clsNum === 16 ||
    cat.includes("tåg") || n.includes("tåg");

  // Buss: bitmask 8 (expressbuss), 128 (buss)
  // eller cls 3, 7, 8, 128
  // eller textuellt matchande "buss" i kategori eller namn.
  // Motivering för cls 8: Värdet 8 är tvetydigt (expressbuss i bitmasken, färja i svarskategorilistan).
  // Koden väljer expressbuss eftersom Trafiklab i praktiken observerats returnera bitmaskvärden som cls
  // i API-svar (jämför cls 16 för Östgötapendeln).
  const isBus = Boolean(prodNum & (8 | 128)) ||
    clsNum === 3 || clsNum === 7 || clsNum === 8 || clsNum === 128 ||
    cat.includes("buss") || n.includes("buss");

  if (isTrain) modes.push("train");
  if (isBus) modes.push("bus");

  // BACKLOG: Spårvagn (bitmask 64, cls 6) och Tunnelbana (bitmask 32, cls 5) klassas idag som "unknown"
  // och visas med neutral ikon. Relevant att lägga till dedikerat färdmedel om t.ex. en hållplats
  // i Norrköping (spårvagn) eller Stockholm läggs till i framtiden.

  // Okänd/ny produktklass -> neutral "unknown" (visas ändå med neutral ikon, aldrig gömd)
  if (modes.length === 0 && (prodNum > 0 || clsNum > 0)) {
    modes.push("unknown");
  }

  return modes;
}

/**
 * Söker hållplatser via ResRobot v2.1 location.name med 10 minuters cache.
 */
async function searchStops(query, apiKey) {
  const q = (query || "").trim();
  if (q.length < 2) {
    throw new HttpsError("invalid-argument", "Söksträngen måste innehålla minst 2 tecken.");
  }

  const cacheKey = q.toLowerCase();
  const now = Date.now();
  const cached = searchStopsCache.get(cacheKey);
  if (cached && (now - cached.timestamp) < SEARCH_CACHE_TTL_MS) {
    return cached.data;
  }

  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), 5000);

  let response;
  try {
    const url = `https://api.resrobot.se/v2.1/location.name?input=${encodeURIComponent(q)}&format=json&accessId=${encodeURIComponent(apiKey)}`;
    response = await fetch(url, { signal: controller.signal });
  } catch (err) {
    if (err.name === "AbortError") {
      console.error(`[displayTransit.searchStops] Timeout mot Trafiklab för "${q}"`);
      throw new HttpsError("unavailable", "Trafiklab svarade inte i tid (5s timeout).");
    }
    console.error(`[displayTransit.searchStops] Nätverksfel mot Trafiklab för "${q}":`, err);
    throw new HttpsError("unavailable", "Kunde inte ansluta till hållplatssökningen.");
  } finally {
    clearTimeout(timeoutId);
  }

  if (!response.ok) {
    const errorBody = await response.text().catch(() => "");
    console.error(`[displayTransit.searchStops] Trafiklab fel ${response.status} för "${q}":`, errorBody);
    throw new HttpsError("unavailable", `Trafiklab returnerade felkod ${response.status}.`);
  }

  const json = await response.json();
  let rawStops = [];
  if (Array.isArray(json.stopLocationOrCoordLocation)) {
    rawStops = json.stopLocationOrCoordLocation
      .map((item) => item.StopLocation)
      .filter(Boolean);
  } else if (Array.isArray(json.StopLocation)) {
    rawStops = json.StopLocation;
  }

  const stops = rawStops.slice(0, 20).map((stop) => {
    const rawName = String(stop.name || "").trim();
    const cleanName = rawName.replace(/\s*\([^)]*kn\)\s*$/i, "").trim() || rawName;
    const stopId = String(stop.extId || stop.id || "").trim();
    const modes = classifyModes({
      products: stop.products,
      name: rawName,
    });

    return {
      stopId,
      name: cleanName,
      modes: modes.length > 0 ? modes : ["unknown"],
    };
  }).filter((s) => s.stopId.length > 0);

  const result = {
    stops,
    fetchedAt: new Date().toISOString(),
    attribution: "data från Trafiklab.se",
  };

  searchStopsCache.set(cacheKey, {
    timestamp: now,
    data: result,
  });

  return result;
}

/**
 * Normaliserar en avgång från ResRobot v2.1 till DisplayTransit-kontraktet.
 */
function normalizeDeparture(d) {
  const product = (Array.isArray(d.Product) && d.Product[0]) || {};
  const operator = (product.operator || "").trim();
  const catOutL = (product.catOutL || "").toLowerCase();
  const name = (d.name || "").toLowerCase();
  const cls = Number(product.cls || 0);

  // Avgör färdmedel (mode) via delad klassificerare
  const modes = classifyModes({ cls, catOutL, name });
  const isTrain = modes.includes("train");
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
    const url = `https://api.resrobot.se/v2.1/departureBoard?id=${encodeURIComponent(stopId)}&format=json&duration=240&accessId=${encodeURIComponent(apiKey)}`;
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

  // Om anropet är en hållplatssökning
  if (data.action === "searchStops") {
    return await searchStops(data.query, apiKey);
  }

  const rawStopIds = data.stopIds;
  if (!Array.isArray(rawStopIds) || rawStopIds.length === 0) {
    throw new HttpsError("invalid-argument", "stopIds måste vara en icke-tom array.");
  }

  // Max 5 hållplatser per anrop för att undvika överbelastning
  const stopIds = rawStopIds.slice(0, 5).map((id) => String(id).trim()).filter(Boolean);
  if (stopIds.length === 0) {
    throw new HttpsError("invalid-argument", "Inga giltiga stopIds angivna.");
  }

  const limit = Math.min(Math.max(Number(data.limit) || 10, 1), 30);

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

// Exporter för testning och modulär användning
exports.classifyModes = classifyModes;
exports.normalizeDeparture = normalizeDeparture;
exports.searchStops = searchStops;
exports._test = {
  searchStopsCache,
  transitCache,
};
