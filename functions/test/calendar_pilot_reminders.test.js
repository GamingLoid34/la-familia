/* eslint-disable max-len, require-jsdoc */
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const path = require("node:path");

async function reminders(pilot) {
  const sent = [];
  const deduped = [];
  const fixedNow = Date.parse("2026-10-21T10:00:00Z"); // 12:00 Stockholm
  class FixedDate extends Date {
    constructor(...args) { super(...(args.length ? args : [fixedNow])); }
    static now() { return fixedNow; }
  }
  const docs = (rows) => ({docs: rows.map(([id, data]) => ({id, data: () => data})), empty: rows.length === 0});
  const db = {collection(name) {
    const query = {
      where() { return query; }, limit() { return query; },
      async get() {
        if (name === "planner_events") return docs([["event", {familyId: "f", date: "2026-10-21", time: "12:15", title: "Träning"}]]);
        if (name === "chores") return docs([["chore", {familyId: "f", dueDate: "2026-10-21", dueTime: "12:00", chore: "Vattna"}]]);
        if (name === "users") return docs([["user", {fcmTokensWeb: ["test-token"]}]]);
        return docs([]);
      },
      doc(id) { return {
        async get() { return {data: () => ({calendarPilot: pilot})}; },
        async create() { deduped.push(id); },
      }; },
    };
    return query;
  }};
  const firestore = () => db;
  firestore.FieldValue = {serverTimestamp: () => "test"};
  const admin = {firestore, messaging: () => ({async sendEachForMulticast(payload) {
    sent.push(payload.notification.title);
    return {responses: [{success: true}]};
  }})};
  const context = {exports: {}, Date: FixedDate, console: {log() {}, error() {}}, require(name) {
    if (name === "firebase-admin") return admin;
    if (name === "firebase-functions/v2/scheduler") return {onSchedule: (_, handler) => handler};
    throw Error(`Unexpected dependency ${name}`);
  }};
  vm.runInNewContext(fs.readFileSync(path.join(__dirname, "../web_reminders.js"), "utf8"), context);
  await context.exports.sendDueWebReminders();
  return {sent, deduped};
}

test("calendar pilot blocks chore delivery but retains calendar reminders", async () => {
  const result = await reminders(true);
  assert.equal(result.sent.length, 1);
  assert.ok(result.sent[0].includes("Aktivitet"));
  assert.ok(result.deduped.every((id) => !id.endsWith("_chore")));
});
test("families outside pilot retain chore and calendar delivery", async () => {
  const result = await reminders(false);
  assert.equal(result.sent.length, 2);
  assert.ok(result.deduped.some((id) => id.endsWith("_chore")));
});
