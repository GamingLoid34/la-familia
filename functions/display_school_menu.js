/* eslint-disable linebreak-style, max-len, require-jsdoc, indent, object-curly-spacing, valid-jsdoc */
/**
 * PROXYKONTRAKT FÖR STORSKÄRM: SKOLMATSEDEL (FAS 5.1 & TILLÄGG)
 *
 * ARKITEKTURBESLUT & MOTIVERING:
 * Även om meny.mateo.se har ett publikt REST-API med öppna CORS-headers används
 * Cloud Function-proxyn av tre avgörande skäl:
 * 1. Schema- och leverantörsändringar utan klientuppdatering:
 *    Mateo Meny har ett odokumenterat och icke-versionshanterat API (/api/v1/days/{id}).
 *    Om deras datastruktur eller fältnamn förändras kan vi omedelbart distribuera en
 *    patchad Cloud Function på under en minut med 'firebase deploy --only functions:displaySchoolMenu',
 *    utan att behöva kompilera om och rulla ut nya versioner av Flutter webb- eller Android-appar.
 * 2. Delad instanscache (Shared In-Memory Cache):
 *    Alla enheter i hemmet (storskärm på väggen, föräldrars mobiler och surfplattor)
 *    delar samma servercache (24 h för skolligor, 6 h för menyer). Detta minimerar
 *    onödiga anrop och är hövligt mot kommunens/Mateos servrar.
 * 3. Normalisering och felisolering:
 *    Mateo har skiftande strukturer mellan kommuner och skolformer (grundskola vs gymnasium,
 *    separata lunchrader vs fritextfält). Cloud Function normaliserar all data till enhetliga
 *    kontrakt och isolerar eventuella serverfel per skola så att resten av skärmen fungerar.
 *
 * TVÅ LÄGEN I SAMMA CALLABLE:
 * A) action: "list"
 *    Input:  { action: "list", municipality?: "tranas" | "linkoping" }
 *    Output: { municipality: "tranas", schools: [ { id: "318", name: "Junkaremålsskolan", type: "school" }, ... ] }
 *    Cache:  24 timmar
 *    Vitlista: tranas, linkoping (normaliseras: tranås -> tranas, etc.)
 *    Okänd kommun: returnerar tom lista { municipality, schools: [] } och loggar varning, ALDRIG fel.
 *
 * B) action: "menu" (standard om action saknas)
 *    Input:  { action: "menu", schools?: [{ id, name, municipality }], schoolIds?: string[], weekOffset?: 0 | 1 }
 *    Output: { schools: [ { schoolId, schoolName, days: [...] } ], menus: [...], fetchedAt, source: "meny.mateo.se" }
 *    Cache:  6 timmar per skola
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { parseMateoDays } = require("./mateo_parser");

// In-memory cache per instans (TTL 6 timmar för menyer, 24 timmar för skolligor)
const schoolMenuCache = new Map();
const CACHE_TTL_MS = 6 * 60 * 60 * 1000;

const municipalityCache = new Map();
const MUNICIPALITY_CACHE_TTL_MS = 24 * 60 * 60 * 1000;

// Vitlista över godkända kommun-sluggar i Mateo
const MUNICIPALITY_WHITELIST = new Set(["tranas", "linkoping"]);

// Kända standardnamn för skolor i Tranås (används som omedelbar fallback)
const DEFAULT_SCHOOL_NAMES = {
  "318": "Junkaremålsskolan",
  "323": "Fröafallsskolan",
  "354": "Granelundsskolan",
  "330": "Gripenbergs skola",
  "343": "Hubbarpsskolan",
  "335": "Linderås skola",
  "352": "Restaurang Parkhallen",
  "338": "Sommens skola",
  "346": "Ängarydsskolan",
};

/**
 * Normaliserar kommunsträng så att "Tranås", "tranås", "TRANAS" blir "tranas"
 * och "Linköping", "linköping" blir "linkoping".
 */
function normalizeMunicipality(input) {
  if (!input || typeof input !== "string") return "tranas";
  const cleaned = input
    .trim()
    .toLowerCase()
    .replace(/å/g, "a")
    .replace(/ä/g, "a")
    .replace(/ö/g, "o");
  return cleaned || "tranas";
}

/**
 * Beräknar start (måndag) och slut (söndag) för angiven vecka i svensk tidszon.
 */
function getWeekRange(weekOffset = 0) {
  const swedishDateStr = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Europe/Stockholm",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date());

  const [year, month, dayNum] = swedishDateStr.split("-").map(Number);
  const localDate = new Date(year, month - 1, dayNum);

  const dayOfWeek = localDate.getDay(); // 0 = sön, 1 = mån ...
  const diffToMonday = dayOfWeek === 0 ? -6 : 1 - dayOfWeek;

  const monday = new Date(localDate);
  monday.setDate(localDate.getDate() + diffToMonday + (weekOffset * 7));

  const sunday = new Date(monday);
  sunday.setDate(monday.getDate() + 6);

  const fmt = (d) => {
    const y = d.getFullYear();
    const m = String(d.getMonth() + 1).padStart(2, "0");
    const dNum = String(d.getDate()).padStart(2, "0");
    return `${y}-${m}-${dNum}`;
  };

  return {
    from: fmt(monday),
    to: fmt(sunday),
  };
}

/**
 * Hämtar och cachar skolor/kök för en kommun från Mateo organisationsendpoint.
 * Returnerar aldrig fel — vid okänd kommun eller externt fel returneras tom lista.
 */
async function fetchMunicipalitySchools(municipality) {
  const normalized = normalizeMunicipality(municipality);

  if (!MUNICIPALITY_WHITELIST.has(normalized)) {
    console.warn(`[displaySchoolMenu] Kommun '${municipality}' (${normalized}) ingår inte i vitlistan.`);
    return { municipality: normalized, schools: [] };
  }

  const now = Date.now();
  const cached = municipalityCache.get(normalized);
  if (cached && (now - cached.timestamp < MUNICIPALITY_CACHE_TTL_MS)) {
    return cached.data;
  }

  const url = `https://meny-api.mateo.se/api/v1/organizations/${normalized}`;
  try {
    const response = await fetch(url, {
      method: "GET",
      headers: {
        "User-Agent": "LaFamilia-Storskarm/1.0 (familjeanvändning)",
      },
      signal: AbortSignal.timeout(8000),
    });

    if (!response.ok) {
      console.warn(`[displaySchoolMenu] HTTP ${response.status} vid hämtning av organisation ${normalized}`);
      return cached ? cached.data : { municipality: normalized, schools: [] };
    }

    const orgData = await response.json();
    const rawUnits = Array.isArray(orgData?.units) ? orgData.units : [];

    // Sortera och filtrera: exkludera äldreboenden och vårdboenden
    const schools = rawUnits
      .filter((u) => {
        if (!u || !u.id || !u.name) return false;
        const type = String(u.type || "").toLowerCase();
        const name = String(u.name).toLowerCase();
        if (type === "retirementhome" || type === "nursinghome") return false;
        if (name.includes("äldreboende") || name.includes("vårdboende")) return false;
        return true;
      })
      .map((u) => ({
        id: String(u.id).trim(),
        name: String(u.name).trim(),
        type: u.type ? String(u.type).trim() : "school",
      }))
      .sort((a, b) => a.name.localeCompare(b.name, "sv"));

    const result = {
      municipality: normalized,
      schools,
    };

    municipalityCache.set(normalized, {
      timestamp: now,
      data: result,
    });

    // Registrera kända namn i DEFAULT_SCHOOL_NAMES för meny-uppslag
    for (const s of schools) {
      DEFAULT_SCHOOL_NAMES[s.id] = s.name;
    }

    return result;
  } catch (err) {
    console.warn(`[displaySchoolMenu] Fel vid anrop mot organisations-API (${normalized}):`, err.message || err);
    if (cached) return cached.data;
    return { municipality: normalized, schools: [] };
  }
}

/**
 * Hämtar meny för en enskild skola med in-memory cache och timeout.
 */
async function fetchSchoolMenu(schoolId, fromDate, toDate, fallbackName) {
  const cacheKey = `${schoolId}_${fromDate}_${toDate}`;
  const now = Date.now();

  const cached = schoolMenuCache.get(cacheKey);
  if (cached && (now - cached.timestamp < CACHE_TTL_MS)) {
    return cached.data;
  }

  const schoolName = fallbackName || DEFAULT_SCHOOL_NAMES[schoolId] || `Skola ${schoolId}`;
  const url = `https://meny-api.mateo.se/api/v1/days/${schoolId}?from=${fromDate}&to=${toDate}`;

  try {
    const response = await fetch(url, {
      method: "GET",
      headers: {
        "User-Agent": "LaFamilia-Storskarm/1.0 (familjeanvändning)",
      },
      signal: AbortSignal.timeout(8000),
    });

    if (!response.ok) {
      throw new Error(`HTTP ${response.status} ${response.statusText}`);
    }

    const rawDays = await response.json();
    const normalizedDays = parseMateoDays(rawDays);

    const result = {
      schoolId: String(schoolId),
      schoolName: schoolName,
      days: normalizedDays,
    };

    schoolMenuCache.set(cacheKey, {
      timestamp: now,
      data: result,
    });

    return result;
  } catch (error) {
    console.error(`[displaySchoolMenu] Fel vid hämtning av skola ${schoolId}:`, error.message || error);
    // Om cache finns sedan tidigare men har gått ut, använd stale cache vid nätverksfel
    if (cached) {
      console.warn(`[displaySchoolMenu] Använder utgången cache för skola ${schoolId}`);
      return cached.data;
    }
    throw error;
  }
}

/**
 * Pausar exekvering under angivet antal millisekunder (för att undvika parallella anrop).
 */
function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * Cloud Function: displaySchoolMenu
 * Anropas av mobilappen (inställningar) och storskärmsklienten.
 */
exports.displaySchoolMenu = onCall({
  region: "us-central1",
  timeoutSeconds: 30,
  memory: "256MiB",
}, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Inloggning krävs för att anropa displaySchoolMenu.");
  }

  const data = request.data || {};
  const action = (data.action || "menu").toString().trim().toLowerCase();

  // ── LÄGE 1: ACTION "list" (Kök för en kommun, cache 24h) ──────────────────
  if (action === "list") {
    const municipality = data.municipality || "tranas";
    const result = await fetchMunicipalitySchools(municipality);
    return result;
  }

  // ── LÄGE 2: ACTION "menu" (Matsedlar för angivna skolor, cache 6h) ─────────
  let schoolsToFetch = [];

  if (Array.isArray(data.schools) && data.schools.length > 0) {
    schoolsToFetch = data.schools.slice(0, 10).map((s) => {
      if (typeof s === "object" && s !== null) {
        return {
          id: String(s.id || s.schoolId || "").trim(),
          name: s.name ? String(s.name).trim() : null,
        };
      }
      return { id: String(s).trim(), name: null };
    }).filter((s) => s.id.length > 0);
  } else if (Array.isArray(data.schoolIds) && data.schoolIds.length > 0) {
    schoolsToFetch = data.schoolIds.slice(0, 10).map((id) => ({
      id: String(id).trim(),
      name: null,
    })).filter((s) => s.id.length > 0);
  }

  // Om inga skolor skickades in (t.ex. default-konfiguration där inga skolor valts ännu), svara tomt och snällt
  if (schoolsToFetch.length === 0) {
    return {
      schools: [],
      menus: [],
      fetchedAt: new Date().toISOString(),
      source: "meny.mateo.se",
    };
  }

  const weekOffset = data.weekOffset === 1 ? 1 : 0;
  const { from, to } = getWeekRange(weekOffset);

  const results = [];
  let successCount = 0;

  for (let i = 0; i < schoolsToFetch.length; i++) {
    const school = schoolsToFetch[i];

    // Hövlig klient: pausa 100ms mellan externa anrop
    if (i > 0) {
      await delay(100);
    }

    try {
      const schoolData = await fetchSchoolMenu(school.id, from, to, school.name);
      results.push(schoolData);
      successCount++;
    } catch (e) {
      results.push({
        schoolId: school.id,
        schoolName: school.name || DEFAULT_SCHOOL_NAMES[school.id] || `Skola ${school.id}`,
        days: [],
        error: "Matsedel ej tillgänglig för tillfället",
      });
    }
  }

  if (successCount === 0 && schoolsToFetch.length > 0) {
    // Om alla anropade skolor misslyckades
    throw new HttpsError("unavailable", "Kunde inte hämta skolmatsedel från meny.mateo.se");
  }

  return {
    schools: results,
    menus: results,
    fetchedAt: new Date().toISOString(),
    source: "meny.mateo.se",
  };
});

// Exportera hjälpfunktioner för enhetstester
exports._test = {
  normalizeMunicipality,
  getWeekRange,
  fetchMunicipalitySchools,
  MUNICIPALITY_WHITELIST,
  DEFAULT_SCHOOL_NAMES,
};
