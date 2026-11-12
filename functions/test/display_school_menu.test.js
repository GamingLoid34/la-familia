const test = require("node:test");
const assert = require("node:assert");
const { _test } = require("../display_school_menu");

test("normalizeMunicipality normalizes Swedish characters and defaults", () => {
  assert.strictEqual(_test.normalizeMunicipality("Tranås"), "tranas");
  assert.strictEqual(_test.normalizeMunicipality("tranås"), "tranas");
  assert.strictEqual(_test.normalizeMunicipality("TRANÅS"), "tranas");
  assert.strictEqual(_test.normalizeMunicipality("Linköping"), "linkoping");
  assert.strictEqual(_test.normalizeMunicipality(" linköping "), "linkoping");
  assert.strictEqual(_test.normalizeMunicipality(""), "tranas");
  assert.strictEqual(_test.normalizeMunicipality(null), "tranas");
  assert.strictEqual(_test.normalizeMunicipality(undefined), "tranas");
});

test("MUNICIPALITY_WHITELIST contains only approved municipalities", () => {
  assert.ok(_test.MUNICIPALITY_WHITELIST.has("tranas"));
  assert.ok(_test.MUNICIPALITY_WHITELIST.has("linkoping"));
  assert.strictEqual(_test.MUNICIPALITY_WHITELIST.has("stockholm"), false);
  assert.strictEqual(_test.MUNICIPALITY_WHITELIST.has("goteborg"), false);
});

test("getWeekRange computes Monday to Sunday range in YYYY-MM-DD format", () => {
  const range0 = _test.getWeekRange(0);
  assert.match(range0.from, /^\d{4}-\d{2}-\d{2}$/);
  assert.match(range0.to, /^\d{4}-\d{2}-\d{2}$/);

  const dFrom = new Date(range0.from);
  const dTo = new Date(range0.to);
  const diffDays = Math.round((dTo - dFrom) / (1000 * 60 * 60 * 24));
  assert.strictEqual(diffDays, 6, "Ska vara 6 dagars skillnad mellan måndag och söndag");

  const range1 = _test.getWeekRange(1);
  const dFrom1 = new Date(range1.from);
  const diffWeek = Math.round((dFrom1 - dFrom) / (1000 * 60 * 60 * 24));
  assert.strictEqual(diffWeek, 7, "Nästa vecka ska börja 7 dagar senare");
});

test("fetchMunicipalitySchools returns empty list gracefully for non-whitelisted municipality", async () => {
  const result = await _test.fetchMunicipalitySchools("stockholm");
  assert.strictEqual(result.municipality, "stockholm");
  assert.deepStrictEqual(result.schools, []);
});
