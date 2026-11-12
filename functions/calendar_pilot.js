/* eslint-disable max-len, require-jsdoc */
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const OBSERVATION_MS = 48 * 60 * 60 * 1000;

// The same gate is used by the callable and the authorized operator's transaction.
function pilotProblems(family, members, clients, checks, now = Date.now()) {
  const problems = [];
  for (const key of ["androidDeviceTest", "iphonePwaTest", "reimportTest"]) {
    if (checks?.[key] !== true) problems.push(`Saknar verifiering: ${key}`);
  }
  if (!Array.isArray(clients) || clients.length < 1 || clients.length > 32) return [...problems, "Välj 1–32 provinstallationer."];
  const seen = new Set();
  const platforms = new Set();
  for (const client of clients) {
    if (!client || typeof client.uid !== "string" || typeof client.installationId !== "string" || !client.uid || !client.installationId) {
      problems.push("Ogiltig provinstallation.");
      continue;
    }
    const key = `${client.uid}/${client.installationId}`;
    if (seen.has(key)) problems.push("Samma provinstallation har valts flera gånger.");
    seen.add(key);
    const member = members.find((m) => m.id === client.uid);
    const report = member?.data?.calendarClients?.[client.installationId];
    const at = report?.seenAt?.toMillis?.() ?? NaN;
    if (!member || member.data.familyId !== family.id || !report || !(report.protocol >= 2) || report.familyId !== family.id || !report.version || !Number.isFinite(at) || at > now || now - at > 7 * 86400000) {
      problems.push(`Provinstallationen ${key} saknar aktuell kompatibel rapport.`);
    } else {
      platforms.add(report.platform);
    }
  }
  if (!platforms.has("android") || !platforms.has("pwa")) problems.push("Provet ska omfatta både Android och webbappen.");
  return problems;
}

function startTrialPatch(family, members, clients, checks, timestamp, now = Date.now()) {
  const problems = pilotProblems(family, members, clients, checks, now);
  if (problems.length) throw new HttpsError("failed-precondition", problems.join("\n"));
  if (family.calendarPilot === true) {
    if (["observing", "verified"].includes(family.calendarPilotTrial?.status)) return null;
    throw new HttpsError("failed-precondition", "Kalenderläget är redan aktivt utan provstatus.");
  }
  return {
    calendarPilot: true,
    calendarPilotTrial: {
      status: "observing", startedAt: timestamp,
      clients: clients.map(({uid, installationId}) => ({uid, installationId})),
      checks: {androidDeviceTest: true, iphonePwaTest: true, reimportTest: true},
      legacyClientPolicy: "compatible-data-unverified-local-notifications",
    },
  };
}

function completionProblems(family, confirmed, now = Date.now()) {
  const trial = family.calendarPilotTrial;
  const start = trial?.startedAt?.toMillis?.() ?? NaN;
  const problems = [];
  if (family.calendarPilot !== true || trial?.status !== "observing") problems.push("Inget pågående kalenderprov.");
  if (!Number.isFinite(start) || now - start < OBSERVATION_MS) problems.push("Minst 48 verkliga timmar måste ha gått.");
  if (confirmed !== true) problems.push("Bekräfta att observationen faktiskt är godkänd.");
  return problems;
}

async function trialTransaction(request, complete) {
  if (!request.auth) throw new HttpsError("unauthenticated", "Logga in.");
  const db = admin.firestore();
  return db.runTransaction(async (tx) => {
    const user = (await tx.get(db.collection("users").doc(request.auth.uid))).data();
    if (!user || !["parent", "admin"].includes(user.role) || !user.familyId) throw new HttpsError("permission-denied", "Endast förälder.");
    const ref = db.collection("families").doc(user.familyId);
    const family = (await tx.get(ref)).data();
    if (!family) throw new HttpsError("not-found", "Familjen saknas.");
    if (complete) {
      const problems = completionProblems(family, request.data?.observationConfirmed);
      if (problems.length) throw new HttpsError("failed-precondition", problems.join("\n"));
      tx.update(ref, {"calendarPilotTrial.status": "verified", "calendarPilotTrial.verifiedAt": admin.firestore.FieldValue.serverTimestamp()});
      return {activated: true, status: "verified"};
    }
    const members = await tx.get(db.collection("users").where("familyId", "==", user.familyId));
    const patch = startTrialPatch({...family, id: user.familyId}, members.docs.map((d) => ({id: d.id, data: d.data()})), request.data?.clients, request.data?.checks, admin.firestore.FieldValue.serverTimestamp());
    if (patch) tx.update(ref, patch);
    return {activated: true, status: patch ? "observing" : family.calendarPilotTrial.status};
  });
}
exports.activateCalendarPilot = onCall((request) => trialTransaction(request, false));
exports.completeCalendarPilotTrial = onCall((request) => trialTransaction(request, true));
exports._test = {pilotProblems, startTrialPatch, completionProblems, OBSERVATION_MS};
