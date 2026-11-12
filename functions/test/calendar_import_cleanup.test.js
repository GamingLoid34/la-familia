"use strict";
const {test} = require("node:test");
const assert = require("node:assert/strict");
const {removeOriginalSource} = require("../calendar_import_cleanup")._test;
const id = `ics_${"a".repeat(64)}`;
function fake({recreated = false, family = "family"} = {}) {
  const deletes = [];
  const ref = (path) => ({path, doc: (key) => ref(`${path}/${key}`), collection: (key) => ref(`${path}/${key}`)});
  const db = {collection: ref, runTransaction: (fn) => fn({
    get: async (r) => {
      if (r.path === `calendar_imports/${id}`) return {exists: recreated};
      if (r.path.endsWith("/chunks")) return {docs: [{ref: ref(`${r.path}/000`)}]};
      return {exists: true, data: () => ({familyId: family, importId: id})};
    }, delete: (r) => deletes.push(r.path),
  })};
  return {db, deletes};
}
test("user removal clears its original source and chunks", async () => {
  const {db, deletes} = fake();
  await removeOriginalSource(db, id, {familyId: "family", originalSourceId: id});
  assert.deepEqual(deletes, [`calendar_import_sources/${id}/chunks/000`, `calendar_import_sources/${id}`]);
});
test("late delete, foreign source, and non-file imports cannot erase originals", async () => {
  for (const options of [{recreated: true}, {family: "other"}]) {
    const {db, deletes} = fake(options);
    await removeOriginalSource(db, id, {familyId: "family", originalSourceId: id});
    assert.deepEqual(deletes, []);
  }
  const {db, deletes} = fake();
  await removeOriginalSource(db, id, {familyId: "family"});
  assert.deepEqual(deletes, []);
});
