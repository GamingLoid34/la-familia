const test = require("node:test");
const assert = require("node:assert");
const { _test } = require("../parse_menu_document");

test("getIsoWeek beräknar korrekta ISO-8601 veckor", () => {
  assert.strictEqual(_test.getIsoWeek("2026-09-07"), "2026-W37");
  assert.strictEqual(_test.getIsoWeek("2026-09-11"), "2026-W37");
  assert.strictEqual(_test.getIsoWeek("2026-09-14"), "2026-W38");
  assert.strictEqual(_test.getIsoWeek("2026-09-18"), "2026-W38");
  assert.strictEqual(_test.getIsoWeek("2026-01-01"), "2026-W01");
  assert.strictEqual(_test.getIsoWeek("ogiltigt"), null);
  assert.strictEqual(_test.getIsoWeek(""), null);
  assert.strictEqual(_test.getIsoWeek(null), null);
});

test("getDatesForIsoWeek genererar måndag till fredag för angiven vecka", () => {
  const datesW37 = _test.getDatesForIsoWeek("2026-W37");
  assert.strictEqual(datesW37.length, 5);
  assert.strictEqual(datesW37[0], "2026-09-07");
  assert.strictEqual(datesW37[4], "2026-09-11");

  const datesW38 = _test.getDatesForIsoWeek("2026-W38");
  assert.strictEqual(datesW38.length, 5);
  assert.strictEqual(datesW38[0], "2026-09-14");
  assert.strictEqual(datesW38[4], "2026-09-18");

  assert.deepStrictEqual(_test.getDatesForIsoWeek("felaktig"), []);
});

test("computeWeekDiff beräknar differens i veckor korrekt", () => {
  assert.strictEqual(_test.computeWeekDiff("2026-W37", "2026-W37"), 0);
  assert.strictEqual(_test.computeWeekDiff("2026-W38", "2026-W37"), 1);
  assert.strictEqual(_test.computeWeekDiff("2026-W40", "2026-W37"), 3);
  assert.strictEqual(_test.computeWeekDiff("2026-W36", "2026-W37"), -1);
  assert.strictEqual(_test.computeWeekDiff("2026-W35", "2026-W37"), -2);
});

test("parseAiJson rensar markdown-kodblock och parsar JSON", () => {
  const withMarkdown = "```json\n{\"weekNumber\": 38, \"confidence\": \"high\"}\n```";
  const parsed = _test.parseAiJson(withMarkdown);
  assert.strictEqual(parsed.weekNumber, 38);
  assert.strictEqual(parsed.confidence, "high");

  const rawJson = "{\"weekNumber\": 37, \"confidence\": \"needs_review\"}";
  const parsedRaw = _test.parseAiJson(rawJson);
  assert.strictEqual(parsedRaw.weekNumber, 37);
  assert.strictEqual(parsedRaw.confidence, "needs_review");
});

test("stockholmDateKey returnerar svensk tidszonsdatum YYYY-MM-DD", () => {
  const d = new Date("2026-09-10T00:30:00.000Z");
  const key = _test.stockholmDateKey(d);
  assert.match(key, /^\d{4}-\d{2}-\d{2}$/);
});

test("cleanMenuDays: veg sätts till null om samma som lunch (ingen fallback/dubblering)", () => {
  const rawDays = [
    {
      date: "2026-09-14",
      lunch: "Kebabpytt",
      vegetarian: "Kebabpytt", // Fallback från AI som måste rensas bort
      note: null,
    },
    {
      date: "2026-09-15",
      lunch: "Laxpudding med skirat smör",
      vegetarian: "Vegetarisk paj med spenat",
      note: null,
    },
    {
      date: "2026-09-16",
      lunch: "Pasta Bolognese",
      vegetarian: "  pasta bolognese  ", // Case-insensitive match
      note: null,
    },
  ];

  const cleaned = _test.cleanMenuDays(rawDays);
  assert.strictEqual(cleaned.length, 3);
  // Måndag v.38: Kebabpytt utan veg -> vegetarian ska vara null
  assert.strictEqual(cleaned[0].lunch, "Kebabpytt");
  assert.strictEqual(cleaned[0].vegetarian, null);

  // Tisdag: Distinkt veg -> bevaras
  assert.strictEqual(cleaned[1].lunch, "Laxpudding med skirat smör");
  assert.strictEqual(cleaned[1].vegetarian, "Vegetarisk paj med spenat");

  // Onsdag: Samma rätt fast med blanksteg/små bokstäver -> rensas bort
  assert.strictEqual(cleaned[2].lunch, "Pasta Bolognese");
  assert.strictEqual(cleaned[2].vegetarian, null);
});
