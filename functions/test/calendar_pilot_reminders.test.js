/* eslint-disable max-len, require-jsdoc */
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const path = require("node:path");

async function reminders(pilot, event = {familyId: "f", date: "2026-10-21", time: "12:15", title: "Träning"}) {
  const sent = [];
  const recipients = [];
  const deduped = [];
  const fixedNow = Date.parse("2026-10-21T10:00:00Z"); // 12:00 Stockholm
  class FixedDate extends Date {
    constructor(...args) { super(...(args.length ? args : [fixedNow])); }
    static now() { return fixedNow; }
  }
  const docs = (rows) => ({docs: rows.map(([id, data]) => ({id, ref: {id}, data: () => data})), empty: rows.length === 0});
  const db = {collection(name) {
    const query = {
      where() { return query; }, limit() { return query; },
      async get() {
        if (name === "planner_events") return docs([["event", event]]);
        if (name === "chores") return docs([["chore", {familyId: "f", dueDate: "2026-10-21", dueTime: "12:00", chore: "Vattna"}]]);
        if (name === "users") return docs([["user", {fcmTokensWeb: ["test-token"]}], ["other", {fcmTokensWeb: ["other-token"]}]]);
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
    recipients.push(payload.tokens);
    return {responses: [{success: true}]};
  }})};
  const context = {exports: {}, Date: FixedDate, console: {log() {}, error() {}}, require(name) {
    if (name === "firebase-admin") return admin;
    if (name === "firebase-functions/v2/scheduler") return {onSchedule: (_, handler) => handler};
    throw Error(`Unexpected dependency ${name}`);
  }};
  vm.runInNewContext(fs.readFileSync(path.join(__dirname, "../web_reminders.js"), "utf8"), context);
  await context.exports.sendDueWebReminders();
  return {sent, deduped, recipients};
}

test("calendar pilot blocks chore delivery but retains calendar reminders", async () => {
  const result = await reminders(true);
  assert.equal(result.sent.length, 1);
  assert.ok(result.sent[0].includes("Aktivitet"));
  assert.ok(result.deduped.every((id) => !id.endsWith("_chore")));
});
test("a private marker only notifies its owner", async () => {
  const event = {familyId: "f", date: "2026-10-21", time: "12:15", title: "Privat", visibility: "private", privateOwnerUid: "user"};
  const result = await reminders(true, event);
  assert.equal(result.sent.length, 1);
  assert.deepEqual(Array.from(result.recipients[0]), ["test-token"]);
});
test("malformed private markers do not notify anyone", async () => {
  const event = {familyId: "f", date: "2026-10-21", time: "12:15", title: "Privat", visibility: "private"};
  const result = await reminders(true, event);
  assert.equal(result.sent.length, 0);
});
test("families outside pilot retain chore and calendar delivery", async () => {
  const result = await reminders(false);
  assert.equal(result.sent.length, 2);
  assert.ok(result.deduped.some((id) => id.endsWith("_chore")));
});
