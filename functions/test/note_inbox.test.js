/* eslint-disable max-len */
const test = require("node:test");
const assert = require("node:assert");
const {_test} = require("../note_inbox");

const {shouldInterpret, parseInterpretation, validationProblem, actionId} = _test;

const note = (overrides = {}) => ({
  familyId: "f1", ownerUid: "u1", text: "Utflykt torsdag", status: "saved",
  requestId: "r1", deletedAt: null, ...overrides,
});

// --- Vad triggern reagerar pa ---

test("en ny anteckning tolkas", () => {
  assert.equal(shouldInterpret(null, note()), true);
});

test("serverns egen resultatskrivning triggar inte en ny tolkning", () => {
  // Utan detta skulle tolkningen trigga sig sjalv i all oandlighet.
  const before = note({status: "interpreting"});
  const after = note({status: "needs_review"});
  assert.equal(shouldInterpret(before, after), false);
});

test("upprepad leverans av samma handelse tolkas bara en gang", () => {
  const same = note();
  assert.equal(shouldInterpret(same, same), false);
});

test("ett nytt begarans-id ger en ny tolkning", () => {
  const before = note({status: "failed", requestId: "r1"});
  const after = note({status: "saved", requestId: "r2"});
  assert.equal(shouldInterpret(before, after), true);
});

test("en mjukraderad anteckning tolkas aldrig", () => {
  assert.equal(shouldInterpret(null, note({deletedAt: new Date()})), false);
});

test("en anteckning utan begarans-id eller text tolkas inte", () => {
  assert.equal(shouldInterpret(null, note({requestId: ""})), false);
  assert.equal(shouldInterpret(null, note({requestId: null})), false);
  assert.equal(shouldInterpret(null, note({text: "   "})), false);
});

test("en raderad anteckning ger ingen tolkning", () => {
  assert.equal(shouldInterpret(note(), null), false);
});

// --- Tolkning av AI-svaret ---

test("ett normalt svar blir forslag med stabila id", () => {
  const raw = JSON.stringify({
    actions: [{
      type: "create_event", title: "Utflykt", summary: "Skogen",
      payload: {date: "2026-09-24", time: "09:00", persons: ["Liam"]},
    }],
    question: null,
  });
  const {actions, question} = parseInterpretation(raw);
  assert.equal(actions.length, 1);
  assert.equal(actions[0].type, "create_event");
  assert.equal(actions[0].status, "pending");
  assert.equal(actions[0].blockedReason, null);
  assert.equal(question, null);
});

test("samma forslag ger samma id vid en omtolkning", () => {
  // Idempotensen bygger pa det: bekraftelsen matchar pa actionId.
  const payload = {date: "2026-09-24", time: "09:00", persons: ["Liam"]};
  assert.equal(
      actionId("create_event", "Utflykt", payload),
      actionId("create_event", "Utflykt", payload),
  );
});

test("olika forslag ger olika id", () => {
  const a = actionId("create_event", "Utflykt", {date: "2026-09-24"});
  const b = actionId("create_event", "Utflykt", {date: "2026-09-25"});
  assert.notEqual(a, b);
});

test("markdown-inramning runt JSON hanteras", () => {
  const raw = "```json\n{\"actions\":[],\"question\":null}\n```";
  assert.deepEqual(parseInterpretation(raw), {actions: [], question: null});
});

test("okanda atgardstyper faller bort", () => {
  const raw = JSON.stringify({actions: [
    {type: "delete_everything", title: "Nej", payload: {}},
    {type: "info", title: "Oppettider", payload: {}},
  ]});
  const {actions} = parseInterpretation(raw);
  assert.deepEqual(actions.map((a) => a.type), ["info"]);
});

test("ett forslag utan titel faller bort", () => {
  const raw = JSON.stringify({actions: [{type: "info", title: "  ", payload: {}}]});
  assert.equal(parseInterpretation(raw).actions.length, 0);
});

test("en fraga fran AI tas med", () => {
  const raw = JSON.stringify({actions: [], question: "Vilken av barnen gäller det?"});
  assert.equal(parseInterpretation(raw).question, "Vilken av barnen gäller det?");
});

test("trasig JSON kastar i stallet for att ge halvfardiga forslag", () => {
  assert.throws(() => parseInterpretation("inte json alls"));
});

// --- Validering: oklart datum eller person blockerar ---

test("en aktivitet utan datum blockeras med en fraga", () => {
  assert.equal(validationProblem("create_event", {persons: ["Liam"]}), "Vilken dag gäller det?");
});

test("en aktivitet utan person blockeras", () => {
  assert.equal(validationProblem("create_event", {date: "2026-09-24"}), "Vem gäller det?");
});

test("en komplett aktivitet blockeras inte", () => {
  assert.equal(validationProblem("create_event", {date: "2026-09-24", persons: ["Liam"]}), null);
});

test("en uppgift far sakna deadline", () => {
  assert.equal(validationProblem("create_task", {}), null);
  assert.equal(validationProblem("create_task", {dueDate: "i host"}), "Vilket datum ska det vara klart?");
});

test("en packlistrad kraver aktivitet, dag och sak", () => {
  assert.equal(validationProblem("add_checklist_item", {}), "Vilken dag gäller det?");
  assert.equal(validationProblem("add_checklist_item", {date: "2026-09-24"}), "Vad ska packas?");
  assert.equal(
      validationProblem("add_checklist_item", {date: "2026-09-24", item: "Matsäck"}),
      "Vilken aktivitet gäller det?",
  );
  assert.equal(
      validationProblem("add_checklist_item", {date: "2026-09-24", item: "Matsäck", eventTitle: "Utflykt"}),
      null,
  );
});

test("ett undantag kraver aktivitet och dag", () => {
  assert.equal(validationProblem("add_exception", {eventTitle: "Simning"}), "Vilken dag ställs in?");
  assert.equal(validationProblem("add_exception", {date: "2026-09-24", eventTitle: "Simning"}), null);
});

test("ogiltiga datum i information blockeras", () => {
  assert.equal(validationProblem("info", {validTo: "tills vidare"}), "Till vilket datum gäller det?");
  assert.equal(validationProblem("info", {validFrom: "2026-09-01", validTo: "2026-09-30"}), null);
});

test("ett ogiltigt klockslag blockeras", () => {
  assert.equal(
      validationProblem("create_event", {date: "2026-09-24", time: "25:00", persons: ["Liam"]}),
      "Vilken tid gäller det?",
  );
});

test("AI:ns egen blockedReason vinner over valideringen", () => {
  const raw = JSON.stringify({actions: [{
    type: "create_event", title: "Utflykt", blockedReason: "Står två olika datum i brevet.",
    payload: {date: "2026-09-24", persons: ["Liam"]},
  }]});
  assert.equal(parseInterpretation(raw).actions[0].blockedReason, "Står två olika datum i brevet.");
});
