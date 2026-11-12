"use strict";
const {test} = require("node:test");
const assert = require("node:assert/strict");

test("portability release declares only ready calendar endpoints and never loads provider secrets", () => {
  const functions = require("../index");
  for (const name of ["exportCalendar", "previewIcsText", "importIcsText", "onCalendarImportDeleted"]) {
    assert.equal(typeof functions[name], "function", name);
  }
  for (const name of ["getCalendarConnections", "calendarOAuthCallback", "syncCalendarNow", "syncConnectedCalendars"]) {
    assert.equal(functions[name], undefined, name);
  }
  assert.equal(require.cache[require.resolve("../calendar_sync/runtime")], undefined);
  assert.equal(require.cache[require.resolve("../calendar_sync/functions")], undefined);
});
