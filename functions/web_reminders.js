/* eslint-disable valid-jsdoc, max-len, require-jsdoc */
const {onSchedule} = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");

/**
 * Hjälpfunktioner för datum och återkommande händelser.
 * Ren port av lib/utils/recurrence.dart och lib/utils/date_utils.dart.
 *
 * Motsvarighet mot Dart:
 * ┌───────────────────────────┬────────────────────────────────────────────┐
 * │ Dart                      │ JavaScript (web_reminders.js)              │
 * ├───────────────────────────┼────────────────────────────────────────────┤
 * │ parseDate('YYYY-MM-DD')   │ parseDayKey('YYYY-MM-DD')                  │
 * │ dateKey(DateTime)         │ formatDayKey(y, m, d)                      │
 * │ recurringOccursOnDay      │ recurringOccursOnDay                       │
 * │   - type: daily           │   - daily: true                            │
 * │   - type: weekly          │   - weekly: same weekday                   │
 * │   - type: biweekly        │   - biweekly: same weekday && daysDiff % 14│
 * │   - type: monthly         │   - monthly: same day-of-month             │
 * │   - exceptions            │   - exceptions.includes(dayKey)            │
 * │   - startDate / endDate   │   - dayKey < startDate / dayKey > endDate  │
 * └───────────────────────────┴────────────────────────────────────────────┘
 */

function pad2(n) {
  return String(n).padStart(2, "0");
}

function formatDayKey(y, m, d) {
  return `${y}-${pad2(m)}-${pad2(d)}`;
}

function parseDayKey(str) {
  if (!str || typeof str !== "string") return null;
  const parts = str.split("-");
  if (parts.length < 3) return null;
  const y = parseInt(parts[0], 10);
  const m = parseInt(parts[1], 10);
  const d = parseInt(parts[2], 10);
  if (isNaN(y) || isNaN(m) || isNaN(d)) return null;
  return {y, m, d};
}

function getUtcTimestamp(y, m, d) {
  return Date.UTC(y, m - 1, d);
}

function getUtcWeekday(y, m, d) {
  // 1 = Måndag, 7 = Söndag (samma som Darts DateTime.weekday)
  const day = new Date(Date.UTC(y, m - 1, d)).getUTCDay();
  return day === 0 ? 7 : day;
}

function daysBetweenUtc(y1, m1, d1, y2, m2, d2) {
  const ms1 = getUtcTimestamp(y1, m1, d1);
  const ms2 = getUtcTimestamp(y2, m2, d2);
  return Math.round((ms2 - ms1) / (24 * 60 * 60 * 1000));
}

function recurringOccursOnDay(data, dayKey) {
  const rec = data.recurrence;
  if (!rec || typeof rec !== "object") return false;

  const startStr = rec.startDate || data.date || data.dueDate;
  const start = parseDayKey(startStr);
  const target = parseDayKey(dayKey);
  if (!start || !target) return false;

  // Före start?
  if (dayKey < formatDayKey(start.y, start.m, start.d)) return false;

  // Efter slut?
  if (rec.endDate && typeof rec.endDate === "string" && rec.endDate.trim() !== "") {
    if (dayKey > rec.endDate) return false;
  }

  // Undantag?
  const exceptions = Array.isArray(rec.exceptions) ? rec.exceptions : [];
  if (exceptions.includes(dayKey)) return false;

  const startW = getUtcWeekday(start.y, start.m, start.d);
  const targetW = getUtcWeekday(target.y, target.m, target.d);

  switch (rec.type) {
    case "daily":
      return true;
    case "weekly":
      return targetW === startW;
    case "biweekly": {
      if (targetW !== startW) return false;
      const diff = daysBetweenUtc(start.y, start.m, start.d, target.y, target.m, target.d);
      return diff % 14 === 0;
    }
    case "monthly":
      return target.d === start.d;
    default:
      return false;
  }
}

function eventOccursOnDay(data, dayKey) {
  if (data.isRecurring === true && data.recurrence) {
    return recurringOccursOnDay(data, dayKey);
  }
  return data.date === dayKey;
}

function choreOccursOnDay(data, dayKey) {
  if (data.isRecurring === true && data.recurrence) {
    return recurringOccursOnDay(data, dayKey);
  }
  return data.dueDate === dayKey;
}

/**
 * Drar av minuter från (dayKey, 'HH:mm') och hanterar övergång till föregående dag.
 */
function minusMinutes(dayKey, timeStr, minutes) {
  const dp = parseDayKey(dayKey);
  if (!dp) return null;
  const tp = (timeStr || "").split(":");
  if (tp.length < 2) return null;
  const h = parseInt(tp[0], 10);
  const m = parseInt(tp[1], 10);
  if (isNaN(h) || isNaN(m)) return null;

  const dt = new Date(Date.UTC(dp.y, dp.m - 1, dp.d, h, m - minutes));
  const ry = dt.getUTCFullYear();
  const rm = dt.getUTCMonth() + 1;
  const rd = dt.getUTCDate();
  const rh = dt.getUTCHours();
  const rmin = dt.getUTCMinutes();

  return {
    dayKey: formatDayKey(ry, rm, rd),
    timeKey: `${pad2(rh)}:${pad2(rmin)}`,
  };
}

/**
 * Returnerar { dayKey, timeKey } i Stockholm-tidszon för ett givet Date-objekt.
 */
function getStockholmParts(date) {
  const formatter = new Intl.DateTimeFormat("sv-SE", {
    timeZone: "Europe/Stockholm",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  });
  const parts = formatter.formatToParts(date);
  let y = "";
  let m = "";
  let d = "";
  let hour = "";
  let minute = "";
  for (const p of parts) {
    if (p.type === "year") y = p.value;
    if (p.type === "month") m = p.value;
    if (p.type === "day") d = p.value;
    if (p.type === "hour") hour = p.value;
    if (p.type === "minute") minute = p.value;
  }
  return {
    dayKey: `${y}-${m}-${d}`,
    timeKey: `${hour}:${minute}`,
  };
}

/**
 * Beräknar [igår, idag, imorgon] i Stockholm för att fånga midnattsövergångar.
 */
function getCandidateDays(todayKey) {
  const tp = parseDayKey(todayKey);
  if (!tp) return [todayKey];
  const ms = getUtcTimestamp(tp.y, tp.m, tp.d);
  const prev = new Date(ms - 24 * 60 * 60 * 1000);
  const next = new Date(ms + 24 * 60 * 60 * 1000);

  return [
    formatDayKey(prev.getUTCFullYear(), prev.getUTCMonth() + 1, prev.getUTCDate()),
    todayKey,
    formatDayKey(next.getUTCFullYear(), next.getUTCMonth() + 1, next.getUTCDate()),
  ];
}

/**
 * Schemalagd funktion som körs var 5:e minut.
 * Letar efter aktiviteter, övergångar och sysslor som förfaller i tidsfönstret (nu - 7 min, nu]
 * och skickar web push till användare med fcmTokensWeb.
 */
exports.sendDueWebReminders = onSchedule({
  schedule: "*/5 * * * *",
  timeZone: "Europe/Stockholm",
}, async () => {
  const db = admin.firestore();
  const now = new Date();
  const currentStockholm = getStockholmParts(now);
  const windowStartStockholm = getStockholmParts(new Date(now.getTime() - 7 * 60 * 1000));

  const windowStartStr = `${windowStartStockholm.dayKey} ${windowStartStockholm.timeKey}`;
  const windowEndStr = `${currentStockholm.dayKey} ${currentStockholm.timeKey}`;

  const candidateDays = getCandidateDays(currentStockholm.dayKey);

  // 1. Hämta planner_events
  const [datedEventsSnap, recurringEventsSnap] = await Promise.all([
    db.collection("planner_events")
        .where("date", "in", candidateDays)
        .get(),
    db.collection("planner_events")
        .where("isRecurring", "==", true)
        .get(),
  ]);

  const eventsMap = new Map();
  for (const doc of datedEventsSnap.docs) {
    eventsMap.set(doc.id, {id: doc.id, data: doc.data()});
  }
  for (const doc of recurringEventsSnap.docs) {
    eventsMap.set(doc.id, {id: doc.id, data: doc.data()});
  }

  // 2. Hämta chores
  const choresSnap = await db.collection("chores").get();

  // 3. Samla alla förfallande påminnelser
  const dueReminders = [];

  for (const ev of eventsMap.values()) {
    const d = ev.data;
    const time = (d.time || "").trim();
    const familyId = d.familyId || "";
    const title = (d.title || "Aktivitet").trim();

    if (!time || !familyId) continue;

    for (const day of candidateDays) {
      if (eventOccursOnDay(d, day)) {
        // 15 min innan
        const fire15 = minusMinutes(day, time, 15);
        if (fire15) {
          const fireStr = `${fire15.dayKey} ${fire15.timeKey}`;
          if (fireStr > windowStartStr && fireStr <= windowEndStr) {
            dueReminders.push({
              docId: ev.id,
              dayKey: day,
              kind: "activity15",
              familyId,
              title: "Aktivitet börjar snart ⏰",
              body: `${title} börjar om 15 minuter.`,
            });
          }
        }

        // 10 min innan (övergångsvarning)
        const fire10 = minusMinutes(day, time, 10);
        if (fire10) {
          const fireStr = `${fire10.dayKey} ${fire10.timeKey}`;
          if (fireStr > windowStartStr && fireStr <= windowEndStr) {
            dueReminders.push({
              docId: ev.id,
              dayKey: day,
              kind: "transition10",
              familyId,
              title: "Snart dags att byta 🔄",
              body: `Om 10 min: ${title}. Börja runda av det du gör.`,
            });
          }
        }
      }
    }
  }

  for (const doc of choresSnap.docs) {
    const d = doc.data();
    const dueTime = (d.dueTime || "").trim();
    const familyId = d.familyId || "";
    const title = (d.chore || d.title || "Syssla").trim();

    if (!dueTime || !familyId) continue;

    for (const day of candidateDays) {
      if (choreOccursOnDay(d, day)) {
        const fireStr = `${day} ${dueTime}`;
        if (fireStr > windowStartStr && fireStr <= windowEndStr) {
          dueReminders.push({
            docId: doc.id,
            dayKey: day,
            kind: "chore",
            familyId,
            title: "Syssla att göra ✅",
            body: title,
          });
        }
      }
    }
  }

  if (dueReminders.length === 0) {
    return;
  }

  // 4. Cacha users med fcmTokensWeb per familyId
  const familyUsersCache = new Map();
  async function getUsersForFamily(fid) {
    if (familyUsersCache.has(fid)) return familyUsersCache.get(fid);
    const usersSnap = await db.collection("users")
        .where("familyId", "==", fid)
        .get();
    const list = [];
    for (const uDoc of usersSnap.docs) {
      const u = uDoc.data() || {};
      if (u.webRemindersEnabled === false) continue;
      const webTokens = u.fcmTokensWeb;
      if (Array.isArray(webTokens) && webTokens.length > 0) {
        list.push({ref: uDoc.ref, tokens: webTokens});
      }
    }
    familyUsersCache.set(fid, list);
    return list;
  }

  let sentCount = 0;
  const countsByKind = {activity15: 0, transition10: 0, chore: 0};

  // 5. Deduplicera och skicka
  for (const reminder of dueReminders) {
    const dedupeDocId = `${reminder.docId}_${reminder.dayKey}_${reminder.kind}`;
    try {
      // Skapa dokument i sent_web_reminders — kastar ALREADY_EXISTS om redan skickad
      await db.collection("sent_web_reminders").doc(dedupeDocId).create({
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
        familyId: reminder.familyId,
        kind: reminder.kind,
      });
    } catch (err) {
      // Om dokumentet redan existerar: skicka inte igen!
      if (err.code === 6 || err.code === "already-exists" || String(err.message).includes("ALREADY_EXISTS")) {
        continue;
      }
      console.error(`Dedupe error for ${dedupeDocId}:`, err);
      continue;
    }

    const familyUsers = await getUsersForFamily(reminder.familyId);
    const tokens = [];
    const tokenOwner = {};
    for (const fu of familyUsers) {
      for (const t of fu.tokens) {
        tokens.push(t);
        tokenOwner[t] = fu.ref;
      }
    }

    if (tokens.length === 0) continue;

    const res = await admin.messaging().sendEachForMulticast({
      tokens,
      notification: {
        title: reminder.title,
        body: reminder.body,
      },
      webpush: {
        notification: {
          icon: "/icons/Icon-192.png",
          badge: "/icons/Icon-192.png",
        },
        fcmOptions: {link: "https://la-familia-5d9f5.web.app/"},
        headers: {Urgency: "high"},
      },
    });

    const removals = [];
    res.responses.forEach((r, idx) => {
      if (!r.success) {
        const code = r.error?.code || "";
        if (code.includes("registration-token-not-registered") ||
                    code.includes("invalid-argument")) {
          const t = tokens[idx];
          removals.push(tokenOwner[t].update({
            fcmTokens: admin.firestore.FieldValue.arrayRemove([t]),
            fcmTokensWeb: admin.firestore.FieldValue.arrayRemove([t]),
          }));
        }
      }
    });
    await Promise.all(removals);

    sentCount++;
    countsByKind[reminder.kind] = (countsByKind[reminder.kind] || 0) + 1;
  }

  // 6. Städning: radera gamla sent_web_reminders äldre än 3 dagar
  try {
    const threeDaysAgo = new Date(Date.now() - 3 * 24 * 60 * 60 * 1000);
    const oldSnap = await db.collection("sent_web_reminders")
        .where("sentAt", "<", threeDaysAgo)
        .limit(200)
        .get();

    if (!oldSnap.empty) {
      const batch = db.batch();
      for (const doc of oldSnap.docs) {
        batch.delete(doc.ref);
      }
      await batch.commit();
    }
  } catch (e) {
    console.error("Cleanup sent_web_reminders error:", e);
  }

  console.log(`sendDueWebReminders: skickade ${sentCount} webbpåminnelser (15-min: ${countsByKind.activity15}, 10-min: ${countsByKind.transition10}, sysslor: ${countsByKind.chore}).`);
});
