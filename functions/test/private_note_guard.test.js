/* eslint-disable require-jsdoc */
const test = require("node:test");
const assert = require("node:assert/strict");
const {isSharedEvent, findEventByTitleAndDate} = require("../note_confirm")._test;

function fakeDb(events) {
  const docs = events.map((data, index) => ({id: String(index), data: () => data}));
  const query = {where: () => query, limit: () => query, get: async () => ({docs})};
  return {collection: () => query};
}

test("private markers are never selected for an inbox checklist or exception", async () => {
  const privateMarker = {visibility: "private", title: "Privat"};
  assert.equal(isSharedEvent(privateMarker), false);
  assert.equal(await findEventByTitleAndDate(fakeDb([privateMarker]), "f", "Privat", "2026-11-09"), null);
});

test("ordinary activities are still matched and private markers do not create ambiguous hits", async () => {
  const shared = {title: "Privat"};
  const marker = {visibility: "private", title: "Privat"};
  const hit = await findEventByTitleAndDate(fakeDb([shared, marker]), "f", "Privat", "2026-11-09");
  assert.equal(hit?.data(), shared);
  assert.equal(isSharedEvent(null), false);
});
