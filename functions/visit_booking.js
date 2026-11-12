/* eslint-disable valid-jsdoc, max-len */
const {onRequest, onCall, HttpsError} = require("firebase-functions/v2/https");
const {onDocumentCreated, onDocumentDeleted} = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");
const crypto = require("crypto");

// ─── HJÄLPARE FÖR DATUM & TID (Stockholm) ───────────────────────────────────

function parseYmd(ymd) {
  if (!ymd || typeof ymd !== "string") return null;
  const parts = ymd.split("-").map(Number);
  if (parts.length !== 3 || parts.some(isNaN)) return null;
  return new Date(Date.UTC(parts[0], parts[1] - 1, parts[2]));
}

function dateKeyUtc(d) {
  const y = d.getUTCFullYear();
  const m = String(d.getUTCMonth() + 1).padStart(2, "0");
  const day = String(d.getUTCDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

function daysBetweenUtc(a, b) {
  return Math.round((b.getTime() - a.getTime()) / 86400000);
}

function getStockholmNow() {
  const now = new Date();
  const parts = Object.fromEntries(
      new Intl.DateTimeFormat("en-GB", {
        timeZone: "Europe/Stockholm",
        year: "numeric",
        month: "2-digit",
        day: "2-digit",
        hour: "2-digit",
        minute: "2-digit",
        hourCycle: "h23",
      }).formatToParts(now).filter((p) => p.type !== "literal").map((p) => [p.type, p.value]),
  );
  return {
    dateKey: `${parts.year}-${parts.month}-${parts.day}`,
    timeStr: `${parts.hour}:${parts.minute}`,
    rawDate: now,
  };
}

function formatWeekdayLabelSv(dateStr) {
  const dt = parseYmd(dateStr);
  if (!dt) return dateStr;
  const days = ["sön", "mån", "tis", "ons", "tor", "fre", "lör"];
  const dayName = days[dt.getUTCDay()];
  const d = dt.getUTCDate();
  const m = dt.getUTCMonth() + 1;
  return `${dayName} ${d}/${m}`;
}

function timeToMinutes(hm) {
  if (!hm || !/^\d{2}:\d{2}$/.test(hm)) return 0;
  const [h, m] = hm.split(":").map(Number);
  return h * 60 + m;
}

function minutesToTime(mins) {
  const h = Math.floor(mins / 60) % 24;
  const m = mins % 60;
  return `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}`;
}

function intervalsOverlap(startA, endA, startB, endB) {
  return startA < endB && startB < endA;
}

// ─── ÅTERKOMMANDE HÄNDELSER (Recurrence) ─────────────────────────────────────

function recurringOccursOnDayJs(d, targetDateKey) {
  const rec = d.recurrence;
  if (!rec) return false;
  const startKey = rec.startDate || d.date;
  const targetDt = parseYmd(targetDateKey);
  const startDt = parseYmd(startKey);
  if (!targetDt || !startDt) return false;
  if (targetDt < startDt) return false;

  if (rec.endDate) {
    const endDt = parseYmd(rec.endDate);
    if (endDt && targetDt > endDt) return false;
  }

  const exceptions = Array.isArray(rec.exceptions) ? rec.exceptions : [];
  if (exceptions.includes(targetDateKey)) return false;

  const targetDayOfWeek = targetDt.getUTCDay();
  const startDayOfWeek = startDt.getUTCDay();
  const targetDayOfMonth = targetDt.getUTCDate();
  const startDayOfMonth = startDt.getUTCDate();

  switch (rec.type) {
    case "daily":
      return true;
    case "weekly":
      return targetDayOfWeek === startDayOfWeek;
    case "biweekly":
      return targetDayOfWeek === startDayOfWeek && daysBetweenUtc(startDt, targetDt) % 14 === 0;
    case "monthly":
      return targetDayOfMonth === startDayOfMonth;
    default:
      return false;
  }
}

function eventOccursOnDayJs(d, targetDateKey) {
  if (d.recurrence) return recurringOccursOnDayJs(d, targetDateKey);
  return d.date === targetDateKey;
}

// ─── IN-MEMORY RATE LIMITER (20 anrop/min per IP) ────────────────────────────
const rateLimitMap = new Map();
function checkRateLimit(ip) {
  const now = Date.now();
  const windowMs = 60000;
  const maxReqs = 20;
  let record = rateLimitMap.get(ip);
  if (!record || now - record.resetTime > windowMs) {
    record = {count: 1, resetTime: now};
    rateLimitMap.set(ip, record);
    return true;
  }
  if (record.count >= maxReqs) {
    return false;
  }
  record.count++;
  return true;
}

// ─── KONTROLL AV TILLGÄNGLIGHET ──────────────────────────────────────────────

async function getLinkByToken(db, token) {
  if (!token || typeof token !== "string") return null;
  const snap = await db.collection("visit_links")
      .where("token", "==", token)
      .where("active", "==", true)
      .limit(1)
      .get();
  if (snap.empty) return null;
  const doc = snap.docs[0];
  return {id: doc.id, ...doc.data()};
}

function isWeekend(dateStr) {
  const dt = new Date(dateStr + "T12:00:00Z");
  const day = dt.getUTCDay();
  return day === 0 || day === 6;
}

function getHoursForDate(dateStr, link) {
  if (isWeekend(dateStr)) {
    return {
      startHour: (link && link.weekendStartHour !== undefined) ? link.weekendStartHour : 11,
      endHour: (link && link.weekendEndHour !== undefined) ? link.weekendEndHour : 20,
    };
  }
  return {
    startHour: (link && link.startHour !== undefined) ? link.startHour : 16,
    endHour: (link && link.endHour !== undefined) ? link.endHour : 20,
  };
}

function isTimeInMeal(timeStr, dateStr, dinnerStartHour = 17, dinnerEndHour = 18, weekendLunchStartHour = 12, weekendLunchEndHour = 13) {
  const mins = timeToMinutes(timeStr);
  // Middag gäller alla dagar
  if (mins >= dinnerStartHour * 60 && mins < dinnerEndHour * 60) {
    return true;
  }
  // Lunch gäller lördag och söndag
  if (isWeekend(dateStr)) {
    if (mins >= weekendLunchStartHour * 60 && mins < weekendLunchEndHour * 60) {
      return true;
    }
  }
  return false;
}

function getMealLabelForDay(dateStr, dinnerStartHour = 17, dinnerEndHour = 18, weekendLunchStartHour = 12, weekendLunchEndHour = 13) {
  if (isWeekend(dateStr)) {
    return `Lunch ${weekendLunchStartHour}–${weekendLunchEndHour} & middag ${dinnerStartHour}–${dinnerEndHour}`;
  }
  return `Middag ${dinnerStartHour}–${dinnerEndHour}`;
}

function isTimeInDinner(timeStr, dinnerStartHour, dinnerEndHour) {
  const mins = timeToMinutes(timeStr);
  return mins >= dinnerStartHour * 60 && mins < dinnerEndHour * 60;
}

function isValidStepTime(timeStr, startHour, endHour, stepMinutes) {
  if (!/^\d{2}:\d{2}$/.test(timeStr)) return false;
  const mins = timeToMinutes(timeStr);
  const startMins = startHour * 60;
  const endMins = endHour * 60;
  if (mins < startMins || mins + stepMinutes > endMins) return false;
  return (mins - startMins) % stepMinutes === 0;
}

/**
 * Kontrollerar om en specifik tid på ett datum är ledig.
 */
function isSlotFreeForDay({
  dateStr,
  slotTime,
  arrivalStepMinutes = 30,
  nowStockholm,
  dayStatus,
  plannerEvents,
  personUid,
  personName,
  excludeEventId,
}) {
  // (1) Inte i dåtid
  if (dateStr < nowStockholm.dateKey) return false;
  if (dateStr === nowStockholm.dateKey && slotTime <= nowStockholm.timeStr) return false;

  // (2) Dagsläge inte rött (rött dagsläge låser fortfarande hela dagen)
  if (dayStatus === "red") return false;

  // (3) Inget överlappande planner_event (ankomsttid antas uppta [time, time+arrivalStepMinutes))
  const slotStartMins = timeToMinutes(slotTime);
  const slotEndMins = slotStartMins + (arrivalStepMinutes || 30);

  for (const ev of plannerEvents) {
    if (excludeEventId && ev.id === excludeEventId) continue;
    const hasUid = Array.isArray(ev.personUids) && ev.personUids.includes(personUid);
    const hasName = Array.isArray(ev.persons) && ev.persons.includes(personName);
    if (!hasUid && !hasName) continue;

    if (!eventOccursOnDayJs(ev, dateStr)) continue;

    if (ev.time && /^\d{2}:\d{2}$/.test(ev.time)) {
      const evStartMins = timeToMinutes(ev.time);
      const evEndMins = ev.endTime && /^\d{2}:\d{2}$/.test(ev.endTime) ?
          timeToMinutes(ev.endTime) :
          evStartMins + 30; // Saknad endTime antas 30 min i överlappskollen
      if (intervalsOverlap(slotStartMins, slotEndMins, evStartMins, evEndMins)) {
        return false;
      }
    }
  }

  return true;
}

// ─── DEL A: PUBLIKT HTTP-API (visitApi) ─────────────────────────────────────

exports.visitApi = onRequest({
  region: "us-central1",
  timeoutSeconds: 30,
  memory: "256MiB",
}, async (req, res) => {
  // CORS-headers
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  res.set("Access-Control-Allow-Headers", "Content-Type");

  if (req.method === "OPTIONS") {
    res.status(204).send("");
    return;
  }

  const clientIp = req.headers["x-forwarded-for"] || req.socket.remoteAddress || "unknown";
  if (!checkRateLimit(String(clientIp))) {
    res.status(429).json({error: "För många anrop. Försök igen om en minut."});
    return;
  }

  const token = req.query.t || (req.body && req.body.t);
  const db = admin.firestore();

  const link = await getLinkByToken(db, token);
  if (!link) {
    res.status(404).json({error: "Länken är inte aktiv."});
    return;
  }

  const path = req.path.replace(/^\/api/, "").replace(/\/$/, "");

  try {
    // ─────────────────────────────────────────────────────────────────────────
    // GET /availability
    // ─────────────────────────────────────────────────────────────────────────
    if (req.method === "GET" && (path === "/availability" || path === "")) {
      const nowStockholm = getStockholmNow();
      const daysAhead = link.daysAhead || 14;
      const arrivalStepMinutes = link.arrivalStepMinutes || 30;
      const dinnerStartHour = link.dinnerStartHour !== undefined ? link.dinnerStartHour : 17;
      const dinnerEndHour = link.dinnerEndHour !== undefined ? link.dinnerEndHour : 18;
      const weekendLunchStartHour = link.weekendLunchStartHour !== undefined ? link.weekendLunchStartHour : 12;
      const weekendLunchEndHour = link.weekendLunchEndHour !== undefined ? link.weekendLunchEndHour : 13;
      const maxPartySize = link.maxPartySize || 2;
      const maxBookingsPerDay = link.maxBookingsPerDay || 1; // regeln är aktiv igen: max 1 sällskap per dag

      const b = req.query.b;
      const k = req.query.k;
      let excludeBookingId = null;
      let excludePlannerEventId = null;

      if (b && k) {
        const bSnap = await db.collection("visit_bookings").doc(String(b)).get();
        if (bSnap.exists) {
          const bData = bSnap.data();
          if (bData.linkId === link.id && bData.editToken === k && bData.status === "active") {
            excludeBookingId = String(b);
            excludePlannerEventId = bData.plannerEventId;
          }
        }
      }

      // Hämta status och bokningar för länken
      const [statusSnap, bookingsSnap, eventsSnap] = await Promise.all([
        db.collection("visit_day_status").where("linkId", "==", link.id).get(),
        db.collection("visit_bookings")
            .where("linkId", "==", link.id)
            .where("status", "==", "active")
            .get(),
        db.collection("planner_events").where("familyId", "==", link.familyId).get(),
      ]);

      const statusMap = new Map();
      for (const doc of statusSnap.docs) {
        const d = doc.data();
        if (d.date && d.status) statusMap.set(d.date, d.status);
      }

      // Samla alla aktiva bokade tider och datum (exkludera egna bokningen vid flyttläge)
      const bookedTimesByDate = new Map();
      const activeBookingsCountByDate = new Map();
      for (const doc of bookingsSnap.docs) {
        if (excludeBookingId && doc.id === excludeBookingId) continue;
        const d = doc.data();
        if (d.date) {
          activeBookingsCountByDate.set(d.date, (activeBookingsCountByDate.get(d.date) || 0) + 1);
          if (d.time) {
            if (!bookedTimesByDate.has(d.date)) {
              bookedTimesByDate.set(d.date, new Set());
            }
            bookedTimesByDate.get(d.date).add(d.time);
          }
        }
      }

      const plannerEvents = eventsSnap.docs.map((d) => ({id: d.id, ...d.data()}));

      // Skapa datumlista från idag och framåt
      const days = [];
      const startDateUtc = parseYmd(nowStockholm.dateKey);

      for (let i = 0; i < daysAhead; i++) {
        const dayDt = new Date(startDateUtc.getTime() + i * 86400000);
        const dateStr = dateKeyUtc(dayDt);
        const weekdayLabel = formatWeekdayLabelSv(dateStr);
        const dayStatus = statusMap.get(dateStr) || "green";
        const bookedTimesSet = bookedTimesByDate.get(dateStr);
        const activeBookingsOnDate = activeBookingsCountByDate.get(dateStr) || 0;
        const dayBooked = activeBookingsOnDate >= maxBookingsPerDay;

        const {startHour, endHour} = getHoursForDate(dateStr, link);
        const mealLabel = getMealLabelForDay(dateStr, dinnerStartHour, dinnerEndHour, weekendLunchStartHour, weekendLunchEndHour);

        // Generera slots i steg om arrivalStepMinutes från startHour till endHour
        const slots = [];
        const startMins = startHour * 60;
        const endMins = endHour * 60;

        for (let m = startMins; m + arrivalStepMinutes <= endMins; m += arrivalStepMinutes) {
          const time = minutesToTime(m);
          const isTimeBooked = bookedTimesSet ? bookedTimesSet.has(time) : false;

          if (isTimeInMeal(time, dateStr, dinnerStartHour, dinnerEndHour, weekendLunchStartHour, weekendLunchEndHour)) {
            slots.push({time, free: false, reason: "dinner"});
          } else if (dayBooked || isTimeBooked) {
            slots.push({time, free: false, reason: "booked"});
          } else {
            const free = isSlotFreeForDay({
              dateStr,
              slotTime: time,
              arrivalStepMinutes,
              nowStockholm,
              dayStatus,
              plannerEvents,
              personUid: link.personUid,
              personName: link.personName,
              excludeEventId: excludePlannerEventId,
            });

            slots.push({time, free});
          }
        }

        days.push({
          date: dateStr,
          weekdayLabel,
          status: dayStatus,
          dayBooked: Boolean(dayBooked),
          mealLabel,
          dinnerLabel: mealLabel,
          slots,
        });
      }

      const todayStatus = statusMap.get(nowStockholm.dateKey) || "green";
      const personFirstName = (link.personName || "Familjen").split(" ")[0];
      const todayMealLabel = getMealLabelForDay(nowStockholm.dateKey, dinnerStartHour, dinnerEndHour, weekendLunchStartHour, weekendLunchEndHour);

      res.json({
        personFirstName,
        todayStatus,
        maxPartySize,
        dinnerLabel: todayMealLabel,
        days,
      });
      return;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // POST /book
    // ─────────────────────────────────────────────────────────────────────────
    if (req.method === "POST" && path === "/book") {
      const body = req.body || {};
      const {date, time, names, partySize, phone} = body;

      const trimmedNames = String(names || "").trim();
      const rawPartySize = Number(partySize);
      const parsedPartySize = (rawPartySize === 1 || rawPartySize === 2) ? rawPartySize : 1;
      const trimmedPhone = String(phone || "").trim();
      const {startHour, endHour} = getHoursForDate(date, link);
      const arrivalStepMinutes = link.arrivalStepMinutes || 30;
      const dinnerStartHour = link.dinnerStartHour !== undefined ? link.dinnerStartHour : 17;
      const dinnerEndHour = link.dinnerEndHour !== undefined ? link.dinnerEndHour : 18;
      const weekendLunchStartHour = link.weekendLunchStartHour !== undefined ? link.weekendLunchStartHour : 12;
      const weekendLunchEndHour = link.weekendLunchEndHour !== undefined ? link.weekendLunchEndHour : 13;

      if (!trimmedNames || trimmedNames.length < 2 || trimmedNames.length > 60) {
        res.status(400).json({error: "Ange namn på besökarna (2–60 tecken)."});
        return;
      }
      if (!trimmedPhone || trimmedPhone.length < 6 || trimmedPhone.length > 20 || !/^[\d\s+\-()]+$/.test(trimmedPhone)) {
        res.status(400).json({error: "Ange ett giltigt telefonnummer."});
        return;
      }
      if (!date || !/^\d{4}-\d{2}-\d{2}$/.test(date) || !time || !/^\d{2}:\d{2}$/.test(time)) {
        res.status(400).json({error: "Ogiltigt datum eller tid."});
        return;
      }

      // Validera att tiden är ett giltigt ankomststeg och inte inom måltidsfönstret
      if (!isValidStepTime(time, startHour, endHour, arrivalStepMinutes) ||
          isTimeInMeal(time, date, dinnerStartHour, dinnerEndHour, weekendLunchStartHour, weekendLunchEndHour)) {
        res.status(400).json({error: "Den tiden går inte att boka."});
        return;
      }

      const editToken = crypto.randomBytes(24).toString("base64url");

      // Firestore transaction för att garantera atomär bokning
      let bookingId;
      try {
        await db.runTransaction(async (tx) => {
          // Kontrollera dagsregel: max 1 sällskap per dag för linkId + date
          const dayBookingsQuery = db.collection("visit_bookings")
              .where("linkId", "==", link.id)
              .where("date", "==", date)
              .where("status", "==", "active");
          const dayBookingsSnap = await tx.get(dayBookingsQuery);
          if (!dayBookingsSnap.empty) {
            throw new Error("DAY_ALREADY_BOOKED");
          }

          // Kontrollera aktiva bokningar på samma linkId + date + time som extra skydd
          const existingTimeQuery = db.collection("visit_bookings")
              .where("linkId", "==", link.id)
              .where("date", "==", date)
              .where("time", "==", time)
              .where("status", "==", "active");
          const existingTimeSnap = await tx.get(existingTimeQuery);
          if (!existingTimeSnap.empty) {
            throw new Error("TIME_ALREADY_BOOKED");
          }

          // Läs dagstatus (rött dagsläge låser hela dagen)
          const statusRef = db.collection("visit_day_status").doc(`${link.id}_${date}`);
          const statusDoc = await tx.get(statusRef);
          const dayStatus = statusDoc.exists ? (statusDoc.data().status || "green") : "green";
          if (dayStatus === "red") {
            throw new Error("SLOT_NOT_AVAILABLE");
          }

          // Läs planner_events
          const eventsQuery = db.collection("planner_events").where("familyId", "==", link.familyId);
          const eventsSnap = await tx.get(eventsQuery);
          const plannerEvents = eventsSnap.docs.map((d) => ({id: d.id, ...d.data()}));

          const free = isSlotFreeForDay({
            dateStr: date,
            slotTime: time,
            arrivalStepMinutes,
            nowStockholm: getStockholmNow(),
            dayStatus,
            plannerEvents,
            personUid: link.personUid,
            personName: link.personName,
          });

          if (!free) {
            throw new Error("SLOT_NOT_AVAILABLE");
          }

          const visitMaxMinutes = link.visitMaxMinutes || 60;
          const startMins = timeToMinutes(time);
          const endTime = minutesToTime(startMins + visitMaxMinutes);

          // Skapa planner_event MED endTime (max 1 timme)
          const eventRef = db.collection("planner_events").doc();
          const bookingRef = db.collection("visit_bookings").doc();
          bookingId = bookingRef.id;

          tx.set(eventRef, {
            familyId: link.familyId,
            title: `🫶 Besök: ${trimmedNames}`,
            piktogram: "🫶",
            type: "activity",
            date,
            time,
            endTime,
            persons: link.personName ? [link.personName] : [],
            personUids: link.personUid ? [link.personUid] : [],
            checklist: [],
            source: "besok",
            visitBookingId: bookingRef.id,
            createdBy: link.createdByUid || "",
            createdByUid: link.createdByUid || "",
            isPending: false,
          });

          tx.set(bookingRef, {
            linkId: link.id,
            familyId: link.familyId,
            date,
            time,
            names: trimmedNames,
            partySize: parsedPartySize,
            phone: trimmedPhone,
            editToken,
            status: "active",
            plannerEventId: eventRef.id,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        });
      } catch (err) {
        if (err.message === "DAY_ALREADY_BOOKED") {
          res.status(409).json({error: "Den här dagen har redan ett besök inbokat — välj gärna en annan dag."});
          return;
        }
        if (err.message === "TIME_ALREADY_BOOKED") {
          res.status(409).json({error: "Den tiden hann tyvärr gå — välj gärna en annan."});
          return;
        }
        if (err.message === "SLOT_NOT_AVAILABLE") {
          res.status(409).json({error: "Den valda tiden är inte längre ledig."});
          return;
        }
        console.error("visitApi /book error:", err);
        res.status(500).json({error: "Ett internt fel uppstod vid bokningen."});
        return;
      }

      res.json({
        bookingId,
        editToken,
        summary: {
          date,
          time,
          names: trimmedNames,
        },
      });
      return;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // GET /booking
    // ─────────────────────────────────────────────────────────────────────────
    if (req.method === "GET" && path === "/booking") {
      const b = req.query.b;
      const k = req.query.k;
      if (!b || !k) {
        res.status(400).json({error: "Boknings-ID och redigeringsnyckel krävs."});
        return;
      }

      const bookingSnap = await db.collection("visit_bookings").doc(String(b)).get();
      if (!bookingSnap.exists) {
        res.status(404).json({error: "Bokningen hittades inte."});
        return;
      }
      const booking = bookingSnap.data();
      if (booking.linkId !== link.id || booking.editToken !== k || booking.status !== "active") {
        res.status(403).json({error: "Behörighet saknas."});
        return;
      }

      res.json({
        bookingId: b,
        date: booking.date,
        time: booking.time,
        names: booking.names,
        partySize: booking.partySize,
        phone: booking.phone,
        status: booking.status,
      });
      return;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // POST /cancel
    // ─────────────────────────────────────────────────────────────────────────
    if (req.method === "POST" && path === "/cancel") {
      const body = req.body || {};
      const b = body.b || req.query.b;
      const k = body.k || req.query.k;

      if (!b || !k) {
        res.status(400).json({error: "Boknings-ID och redigeringsnyckel krävs."});
        return;
      }

      const bookingRef = db.collection("visit_bookings").doc(String(b));
      const bookingSnap = await bookingRef.get();
      if (!bookingSnap.exists) {
        res.status(404).json({error: "Bokningen hittades inte."});
        return;
      }
      const booking = bookingSnap.data();
      if (booking.linkId !== link.id || booking.editToken !== k) {
        res.status(403).json({error: "Behörighet saknas."});
        return;
      }

      await bookingRef.update({status: "cancelled"});
      if (booking.plannerEventId) {
        try {
          await db.collection("planner_events").doc(booking.plannerEventId).delete();
        } catch (_) {}
      }

      res.json({ok: true, message: "Bokningen är avbokad."});
      return;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // POST /move
    // ─────────────────────────────────────────────────────────────────────────
    if (req.method === "POST" && path === "/move") {
      const body = req.body || {};
      const b = body.b || req.query.b;
      const k = body.k || req.query.k;
      const newDate = body.newDate;
      const newTime = body.newTime;

      if (!b || !k || !newDate || !newTime) {
        res.status(400).json({error: "Boknings-ID, nyckel, nytt datum och ny tid krävs."});
        return;
      }
      if (!/^\d{4}-\d{2}-\d{2}$/.test(newDate) || !/^\d{2}:\d{2}$/.test(newTime)) {
        res.status(400).json({error: "Ogiltigt datum- eller tidsformat."});
        return;
      }

      const {startHour, endHour} = getHoursForDate(newDate, link);
      const arrivalStepMinutes = link.arrivalStepMinutes || 30;
      const dinnerStartHour = link.dinnerStartHour !== undefined ? link.dinnerStartHour : 17;
      const dinnerEndHour = link.dinnerEndHour !== undefined ? link.dinnerEndHour : 18;
      const weekendLunchStartHour = link.weekendLunchStartHour !== undefined ? link.weekendLunchStartHour : 12;
      const weekendLunchEndHour = link.weekendLunchEndHour !== undefined ? link.weekendLunchEndHour : 13;

      // Validera att tiden är ett giltigt ankomststeg och inte inom måltidsfönstret
      if (!isValidStepTime(newTime, startHour, endHour, arrivalStepMinutes) ||
          isTimeInMeal(newTime, newDate, dinnerStartHour, dinnerEndHour, weekendLunchStartHour, weekendLunchEndHour)) {
        res.status(400).json({error: "Den tiden går inte att boka."});
        return;
      }

      let updatedNames = "";

      try {
        await db.runTransaction(async (tx) => {
          const bookingRef = db.collection("visit_bookings").doc(String(b));
          const bookingDoc = await tx.get(bookingRef);
          if (!bookingDoc.exists) throw new Error("NOT_FOUND");
          const booking = bookingDoc.data();
          if (booking.linkId !== link.id || booking.editToken !== k || booking.status !== "active") {
            throw new Error("FORBIDDEN");
          }
          updatedNames = booking.names;

          // Kontrollera dagsregel på måldatumet (exkludera denna bokning)
          const dayBookingsQuery = db.collection("visit_bookings")
              .where("linkId", "==", link.id)
              .where("date", "==", newDate)
              .where("status", "==", "active");
          const dayBookingsSnap = await tx.get(dayBookingsQuery);
          const otherDayBookings = dayBookingsSnap.docs.filter((d) => d.id !== String(b));
          if (otherDayBookings.length > 0) {
            throw new Error("DAY_ALREADY_BOOKED");
          }

          // Kontrollera aktiva bokningar på mål-tiden (exkludera denna bokning)
          const existingTimeQuery = db.collection("visit_bookings")
              .where("linkId", "==", link.id)
              .where("date", "==", newDate)
              .where("time", "==", newTime)
              .where("status", "==", "active");
          const existingTimeSnap = await tx.get(existingTimeQuery);
          const otherTimeBookings = existingTimeSnap.docs.filter((d) => d.id !== String(b));
          if (otherTimeBookings.length > 0) {
            throw new Error("TIME_ALREADY_BOOKED");
          }

          // Läs dagstatus
          const statusRef = db.collection("visit_day_status").doc(`${link.id}_${newDate}`);
          const statusDoc = await tx.get(statusRef);
          const dayStatus = statusDoc.exists ? (statusDoc.data().status || "green") : "green";
          if (dayStatus === "red") {
            throw new Error("SLOT_NOT_AVAILABLE");
          }

          // Läs planner_events
          const eventsQuery = db.collection("planner_events").where("familyId", "==", link.familyId);
          const eventsSnap = await tx.get(eventsQuery);
          const plannerEvents = eventsSnap.docs.map((d) => ({id: d.id, ...d.data()}));

          const free = isSlotFreeForDay({
            dateStr: newDate,
            slotTime: newTime,
            arrivalStepMinutes,
            nowStockholm: getStockholmNow(),
            dayStatus,
            plannerEvents,
            personUid: link.personUid,
            personName: link.personName,
            excludeEventId: booking.plannerEventId,
          });

          if (!free) {
            throw new Error("SLOT_NOT_AVAILABLE");
          }

          const visitMaxMinutes = link.visitMaxMinutes || 60;
          const startMins = timeToMinutes(newTime);
          const newEndTime = minutesToTime(startMins + visitMaxMinutes);

          // Uppdatera bokning
          tx.update(bookingRef, {
            date: newDate,
            time: newTime,
          });

          // Uppdatera planner_event med ny tid och endTime (max 1 timme)
          if (booking.plannerEventId) {
            const eventRef = db.collection("planner_events").doc(booking.plannerEventId);
            tx.update(eventRef, {
              date: newDate,
              time: newTime,
              endTime: newEndTime,
            });
          }
        });
      } catch (err) {
        if (err.message === "NOT_FOUND") {
          res.status(404).json({error: "Bokningen hittades inte."});
          return;
        }
        if (err.message === "FORBIDDEN") {
          res.status(403).json({error: "Behörighet saknas."});
          return;
        }
        if (err.message === "DAY_ALREADY_BOOKED") {
          res.status(409).json({error: "Den här dagen har redan ett besök inbokat — välj gärna en annan dag."});
          return;
        }
        if (err.message === "TIME_ALREADY_BOOKED") {
          res.status(409).json({error: "Den tiden hann tyvärr gå — välj gärna en annan."});
          return;
        }
        if (err.message === "SLOT_NOT_AVAILABLE") {
          res.status(409).json({error: "Den valda tiden är inte längre ledig."});
          return;
        }
        console.error("visitApi /move error:", err);
        res.status(500).json({error: "Ett fel uppstod vid flytt av besöket."});
        return;
      }

      res.json({
        ok: true,
        summary: {
          date: newDate,
          time: newTime,
          names: updatedNames,
        },
      });
      return;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // POST /find
    // ─────────────────────────────────────────────────────────────────────────
    if (req.method === "POST" && path === "/find") {
      const body = req.body || {};
      const rawPhone = String(body.phone || req.query.phone || "").trim();
      const inputDigits = rawPhone.replace(/\D/g, "");

      if (inputDigits.length < 7) {
        res.status(400).json({error: "Ange minst 7 siffror i telefonnumret."});
        return;
      }

      const todayKey = getStockholmNow().dateKey;
      const bookingsSnap = await db.collection("visit_bookings")
          .where("linkId", "==", link.id)
          .where("status", "==", "active")
          .get();

      const inputTail = inputDigits.slice(-Math.min(9, inputDigits.length));

      const matchingBookings = [];
      for (const doc of bookingsSnap.docs) {
        const bData = doc.data();
        if (!bData.date || bData.date < todayKey) continue;
        const bDigits = String(bData.phone || "").replace(/\D/g, "");
        if (bDigits.length < 7) continue;
        const bTail = bDigits.slice(-Math.min(9, bDigits.length));

        const minTailLen = Math.min(inputTail.length, bTail.length, 9);
        if (inputDigits.slice(-minTailLen) === bDigits.slice(-minTailLen)) {
          matchingBookings.push({
            b: doc.id,
            k: bData.editToken || "",
            date: bData.date,
            time: bData.time || "",
            names: bData.names || "",
          });
        }
      }

      // Sortera efter datum och tid
      matchingBookings.sort((a, b) => {
        const cmp = (a.date || "").localeCompare(b.date || "");
        if (cmp !== 0) return cmp;
        return (a.time || "").localeCompare(b.time || "");
      });

      res.json({bookings: matchingBookings});
      return;
    }

    res.status(404).json({error: "Ogiltig ändpunkt."});
  } catch (err) {
    console.error("visitApi unhandled error:", err);
    res.status(500).json({error: "Internt serverfel."});
  }
});

// ─── DEL B: CALLABLES FÖR FAMILJEN ──────────────────────────────────────────

async function requireParentOrAdmin(request, db) {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Inloggning krävs.");
  }
  const callerSnap = await db.collection("users").doc(request.auth.uid).get();
  if (!callerSnap.exists) {
    throw new HttpsError("permission-denied", "Användare saknas.");
  }
  const caller = callerSnap.data() || {};
  const role = caller.role || "";
  if (role !== "parent" && role !== "admin") {
    throw new HttpsError("permission-denied", "Endast föräldrar och administratörer.");
  }
  const familyId = caller.familyId;
  if (!familyId) {
    throw new HttpsError("failed-precondition", "Ingen familj kopplad.");
  }
  return {caller, familyId, uid: request.auth.uid};
}

/**
 * createOrGetVisitLink({ personUid })
 */
exports.createOrGetVisitLink = onCall({
  region: "us-central1",
  timeoutSeconds: 30,
}, async (request) => {
  const db = admin.firestore();
  const {familyId, uid} = await requireParentOrAdmin(request, db);

  const data = request.data || {};
  const requestedPersonUid = data.personUid;

  // Leta efter befintlig aktiv länk för familjen
  let linksQuery = db.collection("visit_links")
      .where("familyId", "==", familyId)
      .where("active", "==", true);
  if (requestedPersonUid) {
    linksQuery = linksQuery.where("personUid", "==", requestedPersonUid);
  }
  const snap = await linksQuery.limit(1).get();

  const projectId = process.env.GCLOUD_PROJECT || "la-familia-5d9f5";

  if (!snap.empty) {
    const doc = snap.docs[0];
    const linkData = doc.data();
    const {createdAt, ...cleanData} = linkData;
    return {
      exists: true,
      linkId: doc.id,
      url: `https://${projectId}.web.app/besok/?t=${linkData.token}`,
      ...cleanData,
    };
  }

  // Om ingen aktiv länk finns och personUid saknas i anropet -> skapa ingenting, returnera exists: false
  if (!requestedPersonUid) {
    return {exists: false};
  }

  // Skapa ny länk för den valda personen
  const personUid = requestedPersonUid;
  let personName = "Familjen";
  const userSnap = await db.collection("users").doc(personUid).get();
  if (userSnap.exists) {
    personName = userSnap.data()?.name || personName;
  }

  const token = crypto.randomBytes(24).toString("base64url");
  const newLinkData = {
    familyId,
    personUid,
    personName,
    token,
    active: true,
    startHour: 16,
    endHour: 20,
    weekendStartHour: 11,
    weekendEndHour: 20,
    arrivalStepMinutes: 30,
    dinnerStartHour: 17,
    dinnerEndHour: 18,
    weekendLunchStartHour: 12,
    weekendLunchEndHour: 13,
    maxPartySize: 2,
    maxBookingsPerDay: 1,
    visitMaxMinutes: 60,
    daysAhead: 14,
    createdByUid: uid,
  };

  const newRef = await db.collection("visit_links").add({
    ...newLinkData,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return {
    exists: true,
    linkId: newRef.id,
    url: `https://${projectId}.web.app/besok/?t=${token}`,
    ...newLinkData,
  };
});

/**
 * regenerateVisitLink({ linkId, personUid })
 */
exports.regenerateVisitLink = onCall({
  region: "us-central1",
  timeoutSeconds: 30,
}, async (request) => {
  const db = admin.firestore();
  const {familyId, uid} = await requireParentOrAdmin(request, db);

  const data = request.data || {};
  const linkId = data.linkId;

  let existingLink = null;
  if (linkId) {
    const doc = await db.collection("visit_links").doc(linkId).get();
    if (doc.exists && doc.data()?.familyId === familyId) {
      existingLink = doc.data();
      await doc.ref.update({active: false});
    }
  }

  // Deaktivera alla gamla aktiva länkar för denna person/familj
  const activeSnap = await db.collection("visit_links")
      .where("familyId", "==", familyId)
      .where("active", "==", true)
      .get();
  const batch = db.batch();
  for (const d of activeSnap.docs) {
    batch.update(d.ref, {active: false});
  }
  await batch.commit();

  let personUid = (existingLink && existingLink.personUid) || data.personUid || uid;
  let personName = (existingLink && existingLink.personName) || "Familjen";
  const userSnap = await db.collection("users").doc(personUid).get();
  if (userSnap.exists) {
    personName = userSnap.data()?.name || personName;
  }

  const token = crypto.randomBytes(24).toString("base64url");
  const newLinkData = {
    familyId,
    personUid,
    personName,
    token,
    active: true,
    startHour: (existingLink && existingLink.startHour) || 16,
    endHour: (existingLink && existingLink.endHour) || 20,
    weekendStartHour: (existingLink && existingLink.weekendStartHour !== undefined) ? existingLink.weekendStartHour : 11,
    weekendEndHour: (existingLink && existingLink.weekendEndHour !== undefined) ? existingLink.weekendEndHour : 20,
    arrivalStepMinutes: (existingLink && existingLink.arrivalStepMinutes) || 30,
    dinnerStartHour: (existingLink && existingLink.dinnerStartHour !== undefined) ? existingLink.dinnerStartHour : 17,
    dinnerEndHour: (existingLink && existingLink.dinnerEndHour !== undefined) ? existingLink.dinnerEndHour : 18,
    weekendLunchStartHour: (existingLink && existingLink.weekendLunchStartHour !== undefined) ? existingLink.weekendLunchStartHour : 12,
    weekendLunchEndHour: (existingLink && existingLink.weekendLunchEndHour !== undefined) ? existingLink.weekendLunchEndHour : 13,
    maxPartySize: (existingLink && existingLink.maxPartySize) || 2,
    maxBookingsPerDay: (existingLink && existingLink.maxBookingsPerDay) || 1,
    visitMaxMinutes: (existingLink && existingLink.visitMaxMinutes) || 60,
    daysAhead: (existingLink && existingLink.daysAhead) || 14,
    createdByUid: uid,
  };

  const newRef = await db.collection("visit_links").add({
    ...newLinkData,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  const projectId = process.env.GCLOUD_PROJECT || "la-familia-5d9f5";

  return {
    exists: true,
    linkId: newRef.id,
    url: `https://${projectId}.web.app/besok/?t=${token}`,
    ...newLinkData,
  };
});

/**
 * setVisitDayStatus({ linkId, date, status })
 */
exports.setVisitDayStatus = onCall({
  region: "us-central1",
  timeoutSeconds: 30,
}, async (request) => {
  const db = admin.firestore();
  const {familyId, uid} = await requireParentOrAdmin(request, db);

  const data = request.data || {};
  const {linkId, date, status} = data;

  if (!linkId || !date || !/^\d{4}-\d{2}-\d{2}$/.test(date)) {
    throw new HttpsError("invalid-argument", "Ogiltigt linkId eller datum.");
  }
  if (!["green", "yellow", "red"].includes(status)) {
    throw new HttpsError("invalid-argument", "Ogiltig status (green, yellow eller red).");
  }

  const docId = `${linkId}_${date}`;
  await db.collection("visit_day_status").doc(docId).set({
    linkId,
    familyId,
    date,
    status,
    updatedByUid: uid,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});

  return {ok: true};
});

/**
 * listVisitBookings({ linkId, fromDate })
 */
exports.listVisitBookings = onCall({
  region: "us-central1",
  timeoutSeconds: 30,
}, async (request) => {
  const db = admin.firestore();
  const {familyId} = await requireParentOrAdmin(request, db);

  const data = request.data || {};
  const fromDate = data.fromDate || getStockholmNow().dateKey;

  // Använd endast likhetsfilter (.where familyId och status) för att undvika composite index.
  // Filtrera istället datum i JS eftersom datamängden per familj är liten.
  const snap = await db.collection("visit_bookings")
      .where("familyId", "==", familyId)
      .where("status", "==", "active")
      .get();

  const allActiveDocs = snap.docs.map((d) => {
    const data = d.data();
    const {createdAt, ...cleanData} = data;
    return {
      bookingId: d.id,
      ...cleanData,
    };
  });

  const bookings = allActiveDocs.filter((b) => (b.date || "") >= fromDate);

  // Sortera datum stigande, tid stigande
  bookings.sort((a, b) => {
    if (a.date !== b.date) return a.date.localeCompare(b.date);
    return (a.time || "").localeCompare(b.time || "");
  });

  return {bookings};
});

/**
 * cancelVisitBookingAdmin({ bookingId })
 */
exports.cancelVisitBookingAdmin = onCall({
  region: "us-central1",
  timeoutSeconds: 30,
}, async (request) => {
  const db = admin.firestore();
  const {familyId} = await requireParentOrAdmin(request, db);

  const data = request.data || {};
  const bookingId = data.bookingId;
  if (!bookingId) {
    throw new HttpsError("invalid-argument", "Saknar bookingId.");
  }

  const bookingRef = db.collection("visit_bookings").doc(bookingId);
  const snap = await bookingRef.get();
  if (!snap.exists) {
    throw new HttpsError("not-found", "Bokningen hittades inte.");
  }
  const booking = snap.data();
  if (booking.familyId !== familyId) {
    throw new HttpsError("permission-denied", "Fel familj.");
  }

  await bookingRef.update({status: "cancelled"});
  if (booking.plannerEventId) {
    try {
      await db.collection("planner_events").doc(booking.plannerEventId).delete();
    } catch (_) {}
  }

  return {ok: true};
});

// ─── DEL C: TRIGGERS ────────────────────────────────────────────────────────

/**
 * onDocumentCreated visit_bookings: skickar push till föräldrar i familjen.
 */
exports.onVisitBookingCreated = onDocumentCreated("visit_bookings/{id}", async (event) => {
  const d = event.data?.data();
  if (!d || d.status !== "active") return;

  const weekdayLabel = formatWeekdayLabelSv(d.date);
  const title = `Ny besöksbokning 🫶`;
  const body = `${d.names || "Någon"}, ${weekdayLabel} kl ${d.time || ""}`.trim();

  // Importera sendFamilyPush-funktion från index
  const {sendFamilyPush} = require("./index");
  if (typeof sendFamilyPush === "function") {
    await sendFamilyPush({
      familyId: d.familyId,
      title,
      body,
    });
  }
});

/**
 * onDocumentDeleted planner_events: om källan är 'besok', avboka kopplad visit_booking.
 */
exports.onPlannerEventDeleted = onDocumentDeleted("planner_events/{id}", async (event) => {
  const d = event.data?.data();
  if (!d || d.source !== "besok" || !d.visitBookingId) return;

  const db = admin.firestore();
  const bookingRef = db.collection("visit_bookings").doc(d.visitBookingId);
  const snap = await bookingRef.get();
  if (snap.exists && snap.data()?.status === "active") {
    await bookingRef.update({status: "cancelled"});
  }
});
