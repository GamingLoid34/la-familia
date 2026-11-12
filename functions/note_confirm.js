/* eslint-disable max-len */
/**
 * Bekräftelse av tolkade förslag (assistentens steg 3).
 *
 * Planens hårda krav, och hur de uppfylls här:
 * - **Idempotens.** Nyckeln är `(noteId, actionId)` — medvetet **utan** revision.
 *   Åtgärds-id är härlett ur innehållet och är därför stabilt över omtolkningar. Hade
 *   revisionen ingått skulle samma sakförslag skapa en andra kalenderpost så fort någon
 *   tolkat om anteckningen, vilket är precis vad planen förbjuder: "Omtolkning visar en diff
 *   och skapar inga dubbletter vid upprepad bekräftelse av samma åtgärd."
 *   Revisionen sparas ändå på länken, som spårbarhet till vilken tolkning som godkändes.
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
/**
 * Namnen för en lista uid:n, i samma ordning.
 *
 * @param {Array} members familjemedlemmar
 * @param {Array} uids uid:n
 * @return {Array} namn
 */
function namesForUids(members, uids) {
  const out = [];
  for (const uid of uids) {
    const hit = members.find((m) => m.uid === uid);
    if (hit && hit.name && !out.includes(hit.name)) out.push(hit.name);
  }
  return out;
}

/**
 * Vilka personer gäller posten?
 *
 * Användarens val vid inklistringen är **facit**. Tolkningen får komplettera, aldrig ersätta.
 *
 * Skälet: när ett veckobrev klistras in väljer man vilket barn det gäller, eftersom brevet
 * sällan nämner barnets namn i varje mening. Tidigare byggdes mottagarlistan enbart ur
 * `payload.about`/`payload.persons` — alltså namn som tolkningen hittat i texten. Stod det
 * bara "Läxa till fredag" blev listan tom, och posten hamnade på Hem utan barn
 * (rapporterat 2026-09-20: "engelska läxa och prov i idrott ... men inte vilket barn").
 *
 * @param {Array} members familjemedlemmar
 * @param {Array} valda uid:n användaren valde i inkorgen (`note.aboutUids`)
 * @param {Array} tolkade namn tolkningen hittade i texten
 * @return {Array} uid:n, användarens val först
 */
function personUidsFor(members, valda, tolkade) {
  const out = [];
  if (Array.isArray(valda)) {
    for (const uid of valda) {
      if (typeof uid === "string" && uid && !out.includes(uid)) out.push(uid);
    }
  }
  for (const uid of uidsForNames(members, tolkade)) {
    if (!out.includes(uid)) out.push(uid);
  }
  return out;
}

function buildWrite(action, note, noteId, members, db) {
  const payload = action.payload || {};
  const familyId = note.familyId;
  // Barnen som valdes när brevet klistrades in.
  const valdaUids = Array.isArray(note.aboutUids) ? note.aboutUids : [];

  if (action.type === "create_event") {
    const persons = personUidsFor(members, valdaUids, payload.persons);
    return {
      kind: "event",
      ref: db.collection("planner_events").doc(),
      data: {
        familyId,
        title: action.title,
        date: payload.date,
        time: payload.time || "",
        endTime: payload.endTime || "",
        // Namnlistan speglar samma personer som personUids. Aldre klienter och
        // PersonMatchUtils.eventIncludesPerson laser den nar personUids saknas.
        persons: namesForUids(members, persons),
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
        aboutUids: personUidsFor(members, valdaUids, payload.about),
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
 * Letar upp aktiviteten ett förslag pekar på, via titel och datum.
 *
 * AI:n ser bara titel och datum i sitt underlag, inte dokument-id. Matchningen måste därför
 * ske här, och den ska vara exakt: hellre inget träff än fel aktivitet.
 *
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} familyId
 * @param {string} title
 * @param {string} date
 * @return {Promise<Object|null>} dokumentet, eller null när det inte gick att peka ut ett enda
 */
async function findEventByTitleAndDate(db, familyId, title, date) {
  const snap = await db.collection("planner_events")
      .where("familyId", "==", familyId)
      .where("date", "==", date)
      .limit(20)
      .get();
  const needle = String(title || "").trim().toLowerCase();
  // Admin SDK bypasses Firestore rules. Never treat a private busy marker as
  // an editable activity: adding checklist text there would expose it to the family.
  const hits = snap.docs.filter((d) => isSharedEvent(d.data()) &&
    ((d.data() || {}).title || "").trim().toLowerCase() === needle);
  // Flera träffar betyder att vi inte vet vilken som avses. Då gör vi ingenting.
  return hits.length === 1 ? hits[0] : null;
}

function isSharedEvent(data) {
  return !!data && data.visibility !== "private";
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
    // Idempotens på (noteId, actionId), utan revision: samma sakförslag får bara utföras en
    // gång, även om det föreslagits på nytt i en senare tolkning.
    const done = alreadyLinked.find((l) => l && l.actionId === actionId);
    if (done) {
      applied.push({actionId, targetId: done.targetId, alreadyDone: true});
      continue;
    }
    if (action.type === "info") {
      // Ren information skapar ingen post. Giltigheten sätts på anteckningen nedan.
      applied.push({actionId, targetId: noteId, info: true});
      continue;
    }

    // De två typer som rör en befintlig aktivitet behöver först peka ut vilken.
    let targetDoc = null;
    if (action.type === "add_checklist_item" || action.type === "add_exception") {
      targetDoc = await findEventByTitleAndDate(
          db, familyId, action.payload.eventTitle, action.payload.date,
      );
      if (!targetDoc) {
        skipped.push({actionId, reason: "Hittade ingen aktivitet som stämmer. Lägg till den för hand."});
        continue;
      }
      if (action.type === "add_checklist_item") {
        const data = targetDoc.data() || {};
        // Planen: checklistrader bara på engångsaktiviteter. En återkommande aktivitet
        // delar sin lista mellan alla veckor, så raden skulle dyka upp överallt.
        if (data.recurrence || data.isRecurring === true) {
          skipped.push({actionId, reason: "Aktiviteten är återkommande. Spara som uppgift i stället."});
          continue;
        }
      }
    }

    const write = targetDoc ?
      null :
      buildWrite(action, note, noteId, members, db);
    if (!write && !targetDoc) {
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
        if (links.find((l) => l && l.actionId === actionId)) {
          return; // En parallell bekräftelse hann före. Inget mer att göra.
        }
        let kind;
        let targetId;
        let rowId = null;

        if (targetDoc) {
          // Läs om aktiviteten i transaktionen: någon kan ha hunnit ändra den sedan
          // förslaget byggdes. Jämförelsen sker på fältvärden, inte på ett versionsnummer,
          // eftersom Flutter inte skriver något sådant.
          const eventRef = targetDoc.ref;
          const eventSnap = await tx.get(eventRef);
          const eventData = eventSnap.data();
          if (!eventData) throw new HttpsError("failed-precondition", "Aktiviteten finns inte längre.");
          if (!isSharedEvent(eventData)) {
            throw new HttpsError("failed-precondition", "En privat aktivitet kan inte ändras från inkorgen.");
          }
          if ((eventData.title || "").trim().toLowerCase() !==
              String(action.payload.eventTitle || "").trim().toLowerCase()) {
            throw new HttpsError("failed-precondition", "Aktiviteten har ändrats. Läs igenom förslaget igen.");
          }

          if (action.type === "add_checklist_item") {
            const rows = Array.isArray(eventData.checklist) ? eventData.checklist : [];
            const text = String(action.payload.item || "").trim();
            const exists = rows.some((r) => {
              const rowText = r && typeof r === "object" ? (r.item || r.text) : r;
              return String(rowText || "").trim().toLowerCase() === text.toLowerCase();
            });
            // Klarstatus på övriga rader rörs aldrig: hela listan skrivs om, men varje
            // befintlig rad behåller sitt eget objekt.
            if (!exists) {
              tx.update(eventRef, {checklist: rows.concat([{item: text, isDone: false}])});
            }
            kind = "checklist_item";
            targetId = eventRef.id;
            rowId = text;
          } else {
            const date = action.payload.date;
            const exceptions = ((eventData.recurrence || {}).exceptions) || [];
            if (!exceptions.includes(date)) {
              tx.update(eventRef, {
                "recurrence.exceptions": admin.firestore.FieldValue.arrayUnion(date),
              });
            }
            kind = "exception";
            targetId = eventRef.id;
          }
        } else {
          tx.set(write.ref, write.data, {merge: write.merge === true});
          kind = write.kind;
          targetId = write.ref.id;
        }

        const link = {actionId, revision, type: kind, targetId, createdAt: new Date()};
        if (rowId) link.rowId = rowId;
        if (action.payload && action.payload.date) link.occurrenceDate = action.payload.date;
        tx.update(noteRef, {linkedIds: admin.firestore.FieldValue.arrayUnion(link)});
      });
      const resultId = targetDoc ? targetDoc.ref.id : write.ref.id;
      applied.push({actionId, targetId: resultId});
      newLinks.push({actionId, targetId: resultId, type: action.type});
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
  isSharedEvent,
  findEventByTitleAndDate,
};
