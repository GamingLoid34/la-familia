const test = require("node:test");
const assert = require("node:assert");
const fs = require("node:fs");
const path = require("node:path");
const { parseMateoDays, classifyMeals, cleanText } = require("../mateo_parser");

test("mateo_parser parses real fixture for grundskola (318)", () => {
  const fixturePath = path.join(__dirname, "../../test/fixtures/mateo_tranas_sample.json");
  const rawData = JSON.parse(fs.readFileSync(fixturePath, "utf8"));

  assert.ok(Array.isArray(rawData), "Fixtur ska vara en array");
  assert.strictEqual(rawData.length, 10, "Fixtur ska innehålla 10 skoldagar");

  const parsed = parseMateoDays(rawData);
  assert.strictEqual(parsed.length, 10, "10 dagar ska ha parsats");

  // Dag 0: Måndag 2026-09-07
  const day0 = parsed[0];
  assert.strictEqual(day0.date, "2026-09-07");
  assert.ok(day0.lunch.includes("blodpudding") || day0.lunch.includes("potatisbullar"), "Lunch ska vara potatisbullar/blodpudding");
  assert.ok(day0.vegetarian.includes("Quorn"), "Vegetarisk ska vara Quorn");

  // Dag 1: Tisdag 2026-09-08
  const day1 = parsed[1];
  assert.strictEqual(day1.date, "2026-09-08");
  assert.ok(day1.lunch.includes("laxfilé"), "Lunch ska vara laxfilé");
  assert.ok(day1.vegetarian.includes("rotselleri"), "Vegetarisk ska vara rotselleri");

  // Dag 3: Torsdag 2026-09-10 (Soppa)
  const day3 = parsed[3];
  assert.strictEqual(day3.date, "2026-09-10");
  assert.ok(day3.lunch.includes("favoritsoppa"), "Ska ha soppa");
  assert.strictEqual(day3.vegetarian, null, "Samma soppa för båda linjer -> veg ska vara null");
});

test("mateo_parser parses real fixture for gymnasiet (352, Parkhallen)", () => {
  const fixturePath = path.join(__dirname, "../../test/fixtures/mateo_parkhallen_sample.json");
  const rawData = JSON.parse(fs.readFileSync(fixturePath, "utf8"));

  assert.ok(Array.isArray(rawData), "Fixtur ska vara en array");
  assert.strictEqual(rawData.length, 10, "Fixtur ska innehålla 10 skoldagar");

  const parsed = parseMateoDays(rawData);
  assert.strictEqual(parsed.length, 10, "10 dagar ska ha parsats");

  // Dag 0: Måndag 2026-09-07
  const day0 = parsed[0];
  assert.strictEqual(day0.date, "2026-09-07");
  assert.ok(day0.lunch.includes("Fiskburgare"), "Lunch ska vara Fiskburgare");
  assert.ok(day0.vegetarian.includes("Veggieburgare"), "Vegetarisk ska vara Veggieburgare");
  // Bekräfta att 'Salladsbuffé efter säsong' inte överskuggade lunchen
  assert.strictEqual(day0.lunch.includes("Salladsbuffé"), false);
});

test("classifyMeals heuristik för osäkra rätter visar båda råa utan prefix", () => {
  const ambiguousMeals = [
    { type: "Dagens special", name: "Husets gryta" },
    { type: "Kockens val", name: "Ugnsbakad frestelse" },
  ];

  const result = classifyMeals(ambiguousMeals);
  assert.ok(result.lunch.includes("Husets gryta"));
  assert.ok(result.lunch.includes("Ugnsbakad frestelse"));
  assert.strictEqual(result.lunch.includes("Dagens special:"), false);
  assert.strictEqual(result.lunch.includes("Kockens val:"), false);
  assert.strictEqual(result.vegetarian, null);
});

test("classifyMeals med flera ordinarie rätter och en veg (rena rätter utan prefix)", () => {
  const meals = [
    { type: "Lunch 1", name: "Kyckling i mild currysås, ris" },
    { type: "Lunch 2", name: "Kroppkakor, skirat smör, lingon" },
    { type: "Lunch 3", name: "Grönsakscurry, ris" },
  ];

  const result = classifyMeals(meals);
  assert.ok(result.lunch.includes("Kyckling i mild currysås, ris"));
  assert.ok(result.lunch.includes("Kroppkakor, skirat smör, lingon"));
  assert.strictEqual(result.lunch.includes("Lunch 1:"), false);
  assert.strictEqual(result.lunch.includes("Lunch 2:"), false);
  assert.strictEqual(result.vegetarian, "Grönsakscurry, ris");
});

test("Tranås v.37 torsdag / falukorv klassas rätt (nyckelord före position, inga rubriker)", () => {
  const fixturePath = path.join(__dirname, "../../test/fixtures/mateo_tranas_sample.json");
  const rawData = JSON.parse(fs.readFileSync(fixturePath, "utf8"));
  const parsed = parseMateoDays(rawData);

  // Dag i fixturen: 2026-09-16 (Falukorv vs Sojakorv)
  const falukorvDay = parsed.find((d) => d.date === "2026-09-16");
  assert.ok(falukorvDay, "2026-09-16 ska finnas i fixturen");
  assert.ok(falukorvDay.lunch.includes("falukorv"), "Lunch ska vara falukorv");
  assert.ok(falukorvDay.vegetarian.includes("sojakorv"), "Vegetarisk ska vara sojakorv");
  assert.strictEqual(falukorvDay.lunch.includes("Lunch 2:"), false);
  assert.strictEqual(falukorvDay.vegetarian.includes("Lunch 1:"), false);

  // Inverterat test: Falukorv i Lunch 1 och Sojakorv i Lunch 2
  const invertedMeals = [
    { type: "Lunch 1", name: "Ostgratinerad ugnsbakad falukorv serveras med kökets potatismos" },
    { type: "Lunch 2", name: "Ostgratinerad ugnsbakad sojakorv serveras med kökets potatismos" },
  ];
  const invertedResult = classifyMeals(invertedMeals);
  assert.ok(invertedResult.lunch.includes("falukorv"), "Falukorv i Lunch 1 ska klassas som lunch via nyckelord");
  assert.ok(invertedResult.vegetarian.includes("sojakorv"), "Sojakorv i Lunch 2 ska klassas som veg via nyckelord");
  assert.strictEqual(invertedResult.lunch.includes("Lunch 1:"), false);
  assert.strictEqual(invertedResult.vegetarian.includes("Lunch 2:"), false);
});

test("mateo_parser robusthet och felhantering", () => {
  assert.deepStrictEqual(parseMateoDays(null), []);
  assert.deepStrictEqual(parseMateoDays("ogiltig"), []);
  assert.deepStrictEqual(parseMateoDays({}), []);

  const invalidDays = [
    null,
    123,
    "text",
    { date: undefined },
    { date: "fel-datum" },
    { date: "2026-09-15" }, // saknar meals
  ];

  const parsed = parseMateoDays(invalidDays);
  assert.strictEqual(parsed.length, 1);
  assert.strictEqual(parsed[0].date, "2026-09-15");
  assert.strictEqual(parsed[0].lunch, null);
  assert.strictEqual(parsed[0].vegetarian, null);
});

test("cleanText hanterar strängar korrekt", () => {
  assert.strictEqual(cleanText("  hej   på   dig  "), "hej på dig");
  assert.strictEqual(cleanText(""), null);
  assert.strictEqual(cleanText("   "), null);
  assert.strictEqual(cleanText(null), null);
  assert.strictEqual(cleanText(123), null);
});
