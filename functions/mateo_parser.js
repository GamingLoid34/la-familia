/* eslint-disable linebreak-style, max-len, require-jsdoc, indent, object-curly-spacing, valid-jsdoc, comma-dangle */
/**
 * Normaliserar strängar genom att ta bort överflödiga blanksteg.
 */
function cleanText(str) {
  if (typeof str !== "string") return null;
  const cleaned = str.replace(/\s+/g, " ").trim();
  return cleaned.length > 0 ? cleaned : null;
}

/**
 * Rensar bort prefix som "Lunch 1:", "Lunch 2:", "Dagens 1:", "Alternativ 1:", etc.
 */
function cleanDishName(str) {
  const cleaned = cleanText(str);
  if (!cleaned) return null;
  const stripped = cleaned.replace(/^(?:lunch\s*\d+|dagens\s*\d+|dagens\s*rätt\s*\d+|alternativ\s*\d+|dagens)\s*[:.-]\s*/i, "");
  return cleanText(stripped) || cleaned;
}

// Utökad lista över vegetariska nyckelord (FAS 5.7)
// vegetar, vego, vegan, quorn, soja, tofu, halloumi, falafel, linser, bönor, oumph, grönsaks-, "veg."
const VEG_REGEX = /(vegetar|vego|vegan|quorn|soja|tofu|halloumi|falafel|linser|lins|bönor|oumph|grönsaks|veggie|sin carne|\bveg\b|veg\.)/i;
const SALAD_BUFFET_REGEX = /\b(sallad|salladsbuffé|salladsbuffe|buffé|buffe)\b/i;

/**
 * Analyserar veckans alla dagar för en skola och identifierar den slot (m.type)
 * som oftast matchar vegetariska nyckelord (FAS 5.7 Datadriven inferens).
 *
 * @param {Array<Object>} rawDays
 * @returns {string|null} T.ex. "lunch 1" eller null vid oavgjort/inga träffar
 */
function inferVegSlot(rawDays) {
  if (!Array.isArray(rawDays)) return null;
  const slotCounts = {};

  for (const day of rawDays) {
    if (!day || typeof day !== "object" || !Array.isArray(day.meals)) continue;
    const candidates = day.meals.filter(
      (m) => m && typeof m === "object" && cleanText(m.name) &&
             !SALAD_BUFFET_REGEX.test(m.type || "") &&
             !SALAD_BUFFET_REGEX.test(m.name || "")
    );
    for (const m of candidates) {
      const typeKey = (m.type || "").trim().toLowerCase();
      if (!typeKey) continue;
      if (VEG_REGEX.test(m.name || "")) {
        slotCounts[typeKey] = (slotCounts[typeKey] || 0) + 1;
      }
    }
  }

  let topSlot = null;
  let topCount = 0;
  let isTie = false;
  for (const [slot, count] of Object.entries(slotCounts)) {
    if (count > topCount) {
      topSlot = slot;
      topCount = count;
      isTie = false;
    } else if (count === topCount && count > 0) {
      isTie = true;
    }
  }

  return (topCount > 0 && !isTie) ? topSlot : null;
}

/**
 * Klassificerar måltider för en dag (FAS 5.7):
 * (a) Nyckelord först (utökad lista: vegetar, vego, quorn, soja, tofu, halloumi, falafel, linser, bönor, oumph, grönsaks-, "veg.")
 * (b) Datadriven inferens per skola (den slot som oftast är veg under veckan)
 * (c) Positionsfallback först därefter (Lunch 2 ordinarie / Lunch 1 veg)
 *
 * Alla rätter tvättas rena från "Lunch 1:/Lunch 2:"-rubriker.
 *
 * @param {Array<Object>} meals - Rå måltidsarray för en dag.
 * @param {string|null} inferredVegSlot - Den slot som oftast är veg för denna skola.
 * @returns {{lunch: string|null, vegetarian: string|null}}
 */
function classifyMeals(meals, inferredVegSlot = null) {
  if (!Array.isArray(meals) || meals.length === 0) {
    return { lunch: null, vegetarian: null };
  }

  // Filtrera bort tomma och separera salladsbuffé/tillbehör
  const validMeals = meals.filter((m) => m && typeof m === "object" && cleanText(m.name));
  if (validMeals.length === 0) {
    return { lunch: null, vegetarian: null };
  }

  const candidates = validMeals.filter((m) => !SALAD_BUFFET_REGEX.test(m.type || "") && !SALAD_BUFFET_REGEX.test(m.name || ""));
  const mealPool = candidates.length > 0 ? candidates : validMeals;

  // 1. Om alla rätter har identiskt namn (t.ex. soppdag för alla linjer)
  const firstClean = cleanDishName(mealPool[0].name);
  if (mealPool.length > 1 && mealPool.every((m) => cleanDishName(m.name)?.toLowerCase() === firstClean?.toLowerCase())) {
    return { lunch: firstClean, vegetarian: null };
  }

  // 2. En enda rätt
  if (mealPool.length === 1) {
    return { lunch: firstClean, vegetarian: null };
  }

  // 3. (a) Nyckelord först
  const vegMeals = [];
  const standardMeals = [];

  for (const m of mealPool) {
    if (VEG_REGEX.test(m.name || "")) {
      vegMeals.push(m);
    } else {
      standardMeals.push(m);
    }
  }

  if (vegMeals.length === 1 && standardMeals.length > 0) {
    const vegText = cleanDishName(vegMeals[0].name);
    const lunchText = standardMeals.map((m) => cleanDishName(m.name)).join(" · ");
    return { lunch: lunchText, vegetarian: vegText };
  }

  if (vegMeals.length > 1 && standardMeals.length === 1) {
    // En ordinarie och flera veg
    const vegText = vegMeals.map((m) => cleanDishName(m.name)).join(" · ");
    const lunchText = cleanDishName(standardMeals[0].name);
    return { lunch: lunchText, vegetarian: vegText };
  }

  // 4. (b) Datadriven inferens per skola (om varken eller eller båda matchar nyckelord)
  if (inferredVegSlot && mealPool.length >= 2) {
    const vegIdx = mealPool.findIndex(
      (m) => (m.type || "").trim().toLowerCase() === inferredVegSlot
    );
    if (vegIdx !== -1) {
      const vegMeal = mealPool[vegIdx];
      const otherMeals = mealPool.filter((_, idx) => idx !== vegIdx);
      const vegText = cleanDishName(vegMeal.name);
      const lunchText = otherMeals.map((m) => cleanDishName(m.name)).join(" · ");
      return { lunch: lunchText, vegetarian: vegText };
    }
  }

  // 5. (c) Positionsbaserad fallback (Tranås historiska standard: Lunch 2 = ordinarie, Lunch 1 = veg)
  if (mealPool.length === 2) {
    const m0Type = (mealPool[0].type || "").toLowerCase();
    const m1Type = (mealPool[1].type || "").toLowerCase();

    const m0IsL2 = /lunch\s*2|dagens\s*2/i.test(m0Type);
    const m1IsL2 = /lunch\s*2|dagens\s*2/i.test(m1Type);
    const m0IsL1 = /lunch\s*1|dagens\s*1/i.test(m0Type);
    const m1IsL1 = /lunch\s*1|dagens\s*1/i.test(m1Type);

    if (m0IsL2 && m1IsL1) {
      return { lunch: cleanDishName(mealPool[0].name), vegetarian: cleanDishName(mealPool[1].name) };
    }
    if (m1IsL2 && m0IsL1) {
      return { lunch: cleanDishName(mealPool[1].name), vegetarian: cleanDishName(mealPool[0].name) };
    }
  }

  // 6. Kvarstående osäkerhet: visa alla rätter utan rubriker
  const rawCombo = mealPool
    .map((m) => cleanDishName(m.name))
    .join(" · ");

  return { lunch: rawCombo, vegetarian: null };
}

/**
 * Parsar och normaliserar rådata från Mateo Meny API för en skola.
 * @param {Array} rawDays - Rå array av dagsobjekt från Mateo API (/api/v1/days/{id})
 * @returns {Array<{date: string, lunch: string|null, vegetarian: string|null, note: string|null}>}
 */
function parseMateoDays(rawDays) {
  if (!Array.isArray(rawDays)) {
    console.warn("[schema-mismatch] Förväntade array av dagar, fick:", typeof rawDays, JSON.stringify(rawDays)?.slice(0, 200));
    return [];
  }

  // Analysera hela perioden för att härleda skolans vanliga veg-slot (FAS 5.7)
  const inferredVegSlot = inferVegSlot(rawDays);

  const days = [];
  for (const day of rawDays) {
    if (!day || typeof day !== "object") {
      console.warn("[schema-mismatch] Ogiltigt dag-objekt i rådata:", day);
      continue;
    }

    // 1. Datum (YYYY-MM-DD)
    let dateStr = null;
    if (typeof day.date === "string" && day.date.length >= 10) {
      dateStr = day.date.slice(0, 10);
    }
    if (!dateStr || !/^\d{4}-\d{2}-\d{2}$/.test(dateStr)) {
      console.warn("[schema-mismatch] Ogiltigt eller saknat datum i dag-objekt:", day.date);
      continue;
    }

    // 2. Eventuell avvikelse/notering
    let note = null;
    if (day.deviation && typeof day.deviation === "string") {
      note = cleanText(day.deviation);
    }

    // 3. Måltider med (a) nyckelord -> (b) inferens -> (c) fallback
    const rawMeals = Array.isArray(day.meals) ? day.meals : [];
    if (!Array.isArray(day.meals)) {
      console.warn(`[schema-mismatch] Saknar meals-array för datum: ${dateStr}`);
    }

    const { lunch, vegetarian } = classifyMeals(rawMeals, inferredVegSlot);

    days.push({
      date: dateStr,
      lunch,
      vegetarian,
      note,
    });
  }

  return days;
}

module.exports = {
  parseMateoDays,
  classifyMeals,
  cleanDishName,
  cleanText,
  inferVegSlot,
};
