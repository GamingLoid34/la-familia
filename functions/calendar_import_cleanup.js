/* eslint-disable max-len, require-jsdoc, valid-jsdoc */
"use strict";
const {onDocumentDeleted} = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

async function removeOriginalSource(db, importId, deleted) {
  if (!/^ics_[a-f0-9]{64}$/.test(importId) || deleted?.originalSourceId !== importId || !deleted.familyId) return;
  const original = db.collection("calendar_import_sources").doc(importId);
  // A delete event can be delivered after the same file was imported again.
  // Both checks are repeated in a transaction, so a late trigger cannot remove
  // the new import's source. Only this import's bounded chunk collection is read.
  await db.runTransaction(async (tx) => {
    const currentImport = await tx.get(db.collection("calendar_imports").doc(importId));
    if (currentImport.exists) return;
    const source = await tx.get(original);
    if (!source.exists || source.data().familyId !== deleted.familyId || source.data().importId !== importId) return;
    const chunks = await tx.get(original.collection("chunks"));
    for (const chunk of chunks.docs) tx.delete(chunk.ref);
    tx.delete(original);
  });
}

exports.onCalendarImportDeleted = onDocumentDeleted({document: "calendar_imports/{importId}", region: "us-central1", retry: true},
    (event) => event.data ? removeOriginalSource(admin.firestore(), event.params.importId, event.data.data()) : null);
exports._test = {removeOriginalSource};
