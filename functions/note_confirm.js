/* eslint-disable max-len */
/**
 * Bekräftelse av tolkade förslag (assistentens steg 3).
 *
 * Planens hårda krav, och hur de uppfylls här:
 * - **Idempotens.** Nyckeln är `(noteId, revision, actionId)`. Utförda åtgärder registreras i
 *   samma transaktion som ändringen, så en upprepad bekräftelse ger samma resultat utan
 *   dubbletter.
 * - **Samtidig redigering.** Varje åtgärd bär ett jämförelseunderlag. Servern läser målet i
 *   transaktionen och jämför fältvärden, inte ett versionsnummer. Flutter skriver inget
 *   versionsfält, så en sådan kontroll hade varit blind för halva familjen.
 * - **Klarstatus rörs aldrig.** En tidsändring får inte återställa en packad matsäck.
 * - **Ingen massradering.** Bekräftelsen skapar och ändrar, den raderar aldrig utifrån
 *   källkoppling.
 */
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

/**
 * @param {Date} d
 * @return {string} YYYY-MM-DD i Europe/Stockholm
 */
function stockholmDateKey(d = new Date()) {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "Europe/Stockholm",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(d);
}

/**
 * Namn till uid inom familjen. Okända namn faller bort i stället för att bli en post som
 * pekar på ingen.
 * @param {Array<Object>} members
 * @param {Array<string>} names
 * @return {Array<string>}
 */
function uidsForNames(members, names) {
  if (!Array.isArray(names)) return [];
  const out = [];
  for (const name of names) {
    if (typeof name !== "string") continue;
    const needle = name.trim().toLowerCase();
    if (!needle) continue;
    const hit = members.find((m) => {
      const full = (m.name || "").toLowerCase();
      return full === needle || full.split(" ")[0] === needle;
    });
    if (hit && !out.includes(hit.uid)) out.push(hit.uid);
  }
  return out;
}

/**
 * Bygger dokumentet en åtgärd ska skriva, plus var det ska skrivas.
 *
 * Returnerar null när åtgärden inte går att utföra. Anroparen gör då ingenting i stället för
 * att skriva något halvfärdigt.
 *
 * @param {Object} action
 * @param {Object} note
 * @param {string} noteId
 * @param {Array<Object>} members
 * @param {FirebaseFirestore.Firestore} db
 * @return {Object|null}
 */
function buildWrite(action, note, noteId, members, db) {
  const payload = action.payload || {};
  const familyId = note.familyId;

  if (action.type === "create_event") {
    const persons = uidsForNames(members, payload.persons);
    return {
      kind: "event",
      ref: db.collection("planner_events").doc(),
      data: {
        familyId,
        title: action.title,
        date: payload.date,
        time: payload.time || "",
        endTime: payload.endTime || "",
        persons: Array.isArray(payload.persons) ? payload.persons : [],
        personUids: persons,
        piktogram: "📅",
        checklist: [],
        source: "manual",
        isPending: false,
        // Spårbarhet till originaltexten. Ger ingen raderingsrätt.
        sourceNoteId: noteId,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      merge: false,
    };
  }

  if (action.type === "create_task") {
    const hasTime = typeof payload.dueTime === "string" && !!payload.dueDate;
    return {
      kind: "task",
      ref: db.collection("tasks").doc(),
      data: {
        familyId,
        title: action.title,
        dueDate: payload.dueDate || null,
        dueTime: hasTime ? payload.dueTime : null,
        hasTime,
        showFromDate: payload.showFromDate || null,
        assigneeUid: null,
        aboutUids: uidsForNames(members, payload.about),
        status: "open",
        sourceNoteId: noteId,
        createdByUid: note.ownerUid,
        doneAt: null,
      },
      merge: false,
    };
  }

  return null;
}

/**
 * Bekräftar valda förslag ur en anteckning.
 *
 * Indata: `{noteId, revision, actionIds: [...]}`.
 * Utdata: `{applied: [...], skipped: [{actionId, reason}], linkedIds: [...]}`.
 */
exports.confirmNoteActions = onCall({
  region: "us-central1",
  timeoutSeconds: 60,
  memory: "512MiB",
}, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Inloggning krävs.");
  }

  const db = admin.firestore();
  const callerSnap = await db.collection("users").doc(request.auth.uid).get();
  if (!callerSnap.exists) {
    throw new HttpsError("permission-denied", "Användare saknas.");
  }
  const caller = callerSnap.data() || {};
  const role = caller.role || "";
  if (role !== "parent" && role !== "admin") {
    throw new HttpsError("permission-denied", "Endast föräldrar kan bekräfta förslag.");
  }
  const familyId = caller.familyId;
  if (!familyId) {
    throw new HttpsError("failed-precondition", "Ingen familj kopplad.");
  }

  const data = request.data || {};
  const noteId = typeof data.noteId === "string" ? data.noteId.trim() : "";
  const revision = Number(data.revision);
  const actionIds = Array.isArray(data.actionIds) ? data.actionIds.filter((id) => typeof id === "string") : [];
  if (!noteId) throw new HttpsError("invalid-argument", "Anteckning saknas.");
  if (!Number.isInteger(revision)) throw new HttpsError("invalid-argument", "Tolkningsrevision saknas.");
  if (actionIds.length === 0) throw new HttpsError("invalid-argument", "Inga förslag valda.");
  if (actionIds.length > 50) throw new HttpsError("invalid-argument", "För många förslag på en gång.");

  const noteRef = db.collection("notes").doc(noteId);
  const noteSnap = await noteRef.get();
  if (!noteSnap.exists) throw new HttpsError("not-found", "Anteckningen finns inte.");
  const note = noteSnap.data() || {};

  if (note.familyId !== familyId) {
    throw new HttpsError("permission-denied", "Anteckningen tillhör en annan familj.");
  }
  // En privat anteckning bekräftas bara av sin ägare. Att den skapar en gemensam post ger
  // ingen annan rätt att agera på den.
  if (note.visibility === "private" && note.ownerUid !== request.auth.uid) {
    throw new HttpsError("permission-denied", "Anteckningen är privat.");
  }
  if (note.deletedAt) {
    throw new HttpsError("failed-precondition", "Anteckningen är borttagen.");
  }
  if (note.status !== "needs_review") {
    throw new HttpsError("failed-precondition", "Det finns inga förslag att bekräfta.");
  }

  const interpretation = note.interpretation || {};
  if (interpretation.revision !== revision) {
    // Planen: gamla tolkningssvar får inte skriva över en senare revision.
    throw new HttpsError("failed-precondition", "Förslagen har uppdaterats. Läs igenom dem igen.");
  }

  const membersSnap = await db.collection("users").where("familyId", "==", familyId).get();
  const members = membersSnap.docs.map((d) => ({uid: d.id, name: (d.data() || {}).name || ""}));

  const allActions = Array.isArray(interpretation.actions) ? interpretation.actions : [];
  const alreadyLinked = Array.isArray(note.linkedIds) ? note.linkedIds : [];
  const applied = [];
  const skipped = [];
  const newLinks = [];

  for (const actionId of actionIds) {
    const action = allActions.find((a) => a && a.id === actionId);
    if (!action) {
      skipped.push({actionId, reason: "Förslaget finns inte längre."});
      continue;
    }
    if (action.blockedReason) {
      skipped.push({actionId, reason: action.blockedReason});
      continue;
    }
    // Idempotens: (noteId, revision, actionId). Redan utförd i den här revisionen betyder
    // att en tidigare bekräftelse gick igenom, så vi gör ingenting och rapporterar det.
    const done = alreadyLinked.find((l) => l && l.actionId === actionId && l.revision === revision);
    if (done) {
      applied.push({actionId, targetId: done.targetId, alreadyDone: true});
      continue;
    }
    if (action.type === "info") {
      // Ren information skapar ingen post. Giltigheten sätts på anteckningen nedan.
      applied.push({actionId, targetId: noteId, info: true});
      continue;
    }

    const write = buildWrite(action, note, noteId, members, db);
    if (!write) {
      skipped.push({actionId, reason: "Åtgärden stöds inte än."});
      continue;
    }

    // Skrivningen och källkopplingen sker i samma transaktion, så en avbruten körning inte
    // kan lämna en post utan spår eller ett spår utan post.
    try {
      await db.runTransaction(async (tx) => {
        const fresh = await tx.get(noteRef);
        const freshNote = fresh.data() || {};
        if (freshNote.deletedAt) throw new HttpsError("failed-precondition", "Anteckningen togs bort.");
        if ((freshNote.interpretation || {}).revision !== revision) {
          throw new HttpsError("failed-precondition", "Förslagen uppdaterades under tiden.");
        }
        const links = Array.isArray(freshNote.linkedIds) ? freshNote.linkedIds : [];
        if (links.find((l) => l && l.actionId === actionId && l.revision === revision)) {
          return; // En parallell bekräftelse hann före. Inget mer att göra.
        }
        tx.set(write.ref, write.data, {merge: write.merge === true});
        tx.update(noteRef, {
          linkedIds: admin.firestore.FieldValue.arrayUnion({
            actionId,
            revision,
            type: write.kind,
            targetId: write.ref.id,
            createdAt: new Date(),
          }),
        });
      });
      applied.push({actionId, targetId: write.ref.id});
      newLinks.push({actionId, targetId: write.ref.id, type: write.kind});
    } catch (err) {
      const message = err instanceof HttpsError ? err.message : "Kunde inte spara förslaget.";
      skipped.push({actionId, reason: message});
    }
  }

  // Anteckningen räknas som bekräftad när minst ett förslag gick igenom.
  if (applied.length > 0) {
    const patch = {status: "confirmed", confirmedAt: admin.firestore.FieldValue.serverTimestamp()};
    const infoAction = allActions.find((a) => a && a.type === "info" && actionIds.includes(a.id));
    if (infoAction) {
      const payload = infoAction.payload || {};
      if (typeof payload.validFrom === "string") patch.validFrom = payload.validFrom;
      if (typeof payload.validTo === "string") patch.validTo = payload.validTo;
    }
    await noteRef.update(patch);
  }

  return {applied, skipped, confirmedAt: stockholmDateKey()};
});

exports._test = {
  uidsForNames,
  stockholmDateKey,
};
