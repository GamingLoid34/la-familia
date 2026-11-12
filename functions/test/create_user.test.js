/* eslint-disable max-len */
const test = require("node:test");
const assert = require("node:assert/strict");
const {createUserHandler} = require("../create_user")._test;

/**
 * @param {object|null} profile Caller profile.
 * @param {boolean} familyExists Whether the family exists.
 * @return {object} Handler and recorded calls.
 */
function harness(profile, familyExists = true) {
  const calls = [];
  const firestore = () => ({collection: (collection) => ({doc: (id) => ({
    get: async () => {
      calls.push(["get", collection, id]);
      return collection === "users" ? {exists: !!profile, data: () => profile} : {exists: familyExists};
    },
    set: async (data) => {
      calls.push(["set", collection, id, data]);
    },
  })})});
  firestore.FieldValue = {serverTimestamp: () => "server-time"};
  const services = {firestore, auth: () => ({createUser: async (data) => {
    calls.push(["createUser", data]);
    return {uid: "new-member"};
  }})};
  return {calls, run: createUserHandler(services)};
}
const request = (changes = {}) => ({auth: {uid: "caller"}, data: {
  email: "synthetic@example.invalid", password: "synthetic-test-password", name: "Test member",
  role: "child", familyId: "family-a", ...changes,
}});
/**
 * @param {object} h Test harness.
 * @param {object} req Callable request.
 * @param {string} code Expected error code.
 */
async function denied(h, req, code) {
  await assert.rejects(h.run(req), (error) => error.code === code);
  assert.equal(h.calls.some(([kind]) => kind === "createUser" || kind === "set"), false);
}

test("signed-out caller creates neither an Auth account nor a profile", async () => {
  await denied(harness(null), {...request(), auth: null}, "unauthenticated");
});
for (const role of ["child", "youth", "unknown"]) {
  test(`${role} cannot provision another member`, async () => {
    await denied(harness({role, familyId: "family-a"}), request(), "permission-denied");
  });
}
test("missing caller profile is denied", async () => {
  await denied(harness(null), request(), "permission-denied");
});
test("unassigned parent is denied", async () => {
  await denied(harness({role: "parent"}), request(), "permission-denied");
});
for (const role of ["parent", "admin"]) {
  test(`${role} cannot provision into another family`, async () => {
    await denied(harness({role, familyId: "family-b"}), request({role: "admin"}), "permission-denied");
  });
  for (const memberRole of ["child", "youth", "parent", "admin"]) {
    test(`${role} can create ${memberRole} in own family`, async () => {
      const h = harness({role, familyId: "family-a"});
      assert.deepEqual(await h.run(request({role: memberRole})), {uid: "new-member", success: true});
      const saved = h.calls.find(([kind]) => kind === "set")[3];
      assert.equal(saved.role, memberRole);
      assert.equal(saved.familyId, "family-a");
      assert.equal(saved.uid, "new-member");
      assert.equal(h.calls.filter(([kind]) => kind === "createUser").length, 1);
    });
  }
}
test("nonexistent family is denied before account creation", async () => {
  await denied(harness({role: "parent", familyId: "family-a"}, false), request(), "failed-precondition");
});
test("invalid role is denied", async () => {
  await denied(harness({role: "parent", familyId: "family-a"}), request({role: "owner"}), "invalid-argument");
});
test("malformed data is denied", async () => {
  await denied(harness(null), {...request(), data: null}, "invalid-argument");
  await denied(harness(null), request({familyId: 42}), "invalid-argument");
});
