/* eslint-disable max-len, require-jsdoc, valid-jsdoc */
"use strict";
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {onDocumentDeleted} = require("firebase-functions/v2/firestore");
const {configuredRuntime, safeError, SECRETS} = require("./runtime");
const {createSyncService} = require("./sync_service");
const admin = require("firebase-admin");

function service() {
  return createSyncService({db: admin.firestore(), runtime: configuredRuntime()});
}
function checked(request, conflict = false) {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Logga in i Vardag först.");
  const data = request.data || {};
  if (typeof data.connectionId !== "string" || !/^[A-Za-z0-9_-]{1,128}$/.test(data.connectionId) ||
      (conflict && (typeof data.conflictId !== "string" || !/^[a-f0-9]{64}$/.test(data.conflictId)))) {
    throw new HttpsError("invalid-argument", "Välj en giltig kalenderkoppling.");
  }
  // Only the authenticated UID is authoritative; never spread caller data
  // over it. Unknown client fields cannot change membership or server options.
  return {uid: request.auth.uid, connectionId: data.connectionId,
    calendarId: data.calendarId, conflictId: data.conflictId, choice: data.choice};
}
function callable(method, {secret = true, conflict = false} = {}) {
  return onCall({region: "us-central1", timeoutSeconds: 540, memory: "512MiB", ...(secret ? {secrets: SECRETS} : {})}, async (request) => {
    const data = checked(request, conflict);
    try {
      return await service()[method](data);
    } catch (error) {
      if (error.code === "conflict-changed-refresh-required") throw new HttpsError("aborted", "Aktiviteten har ändrats igen. Synka och granska båda versionerna på nytt.");
      if (error.code === "calendar-not-writable") throw new HttpsError("failed-precondition", "Du saknar skrivrättighet till den valda kalendern. Välj en annan kalender.");
      if (error.code === "ambiguous-create-outcome") throw new HttpsError("failed-precondition", "Synkningen är pausad eftersom en tidigare överföring inte kunde bekräftas. Försök stoppa synk för aktiviteten igen senare eller koppla från kalendern.");
      if (error.code === "calendar-already-connected") throw new HttpsError("already-exists", "Kalendern är redan kopplad till ditt konto.");
      if (error.code === "disconnect-before-changing-calendar") throw new HttpsError("failed-precondition", "Koppla från innan du väljer en annan kalender.");
      if (error.code === "unsupported-conflict-resolution") throw new HttpsError("failed-precondition", "Den här aktiviteten kan inte synkas säkert. Välj att stoppa synk för den.");
      if (error.code === "retry-later" || error.code === "rate-limited") throw new HttpsError("resource-exhausted", "Kalendertjänsten behöver en paus. Vardag försöker igen senare.");
      throw safeError(error);
    }
  });
}

exports.selectCalendarSyncCalendar = callable("selectCalendar");
exports.syncCalendarNow = callable("syncNow");
exports.getCalendarSyncConflicts = callable("getConflicts", {secret: false});
exports.resolveCalendarSyncConflict = callable("resolveConflict", {conflict: true});
exports.syncConnectedCalendars = onSchedule({schedule: "every 15 minutes", region: "us-central1", timeZone: "Europe/Stockholm",
  timeoutSeconds: 540, memory: "512MiB", maxInstances: 1, secrets: SECRETS}, async () => {
  // Status is persisted per connection. Never log provider payloads or tokens.
  await service().scheduled();
});
exports.onSyncedCalendarEventDeleted = onDocumentDeleted({document: "planner_events/{eventId}", region: "us-central1", retry: true},
    async (event) => {
      if (event.data) await service().captureEventDeletion({id: event.params.eventId, data: event.data.data(), eventId: event.id});
    });
exports._test = {checked};
