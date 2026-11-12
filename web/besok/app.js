// ─── KONFIGURATION ──────────────────────────────────────────────────────────
// Cloud Function URL för Besöks-API
const API_BASE_URL = 'https://us-central1-la-familia-5d9f5.cloudfunctions.net/visitApi';

// ─── TILLSTÅND ──────────────────────────────────────────────────────────────
const state = {
  token: null,
  bookingId: null,
  editToken: null,
  availability: null,
  existingBooking: null,
  selectedDate: null,
  selectedWeekdayLabel: null,
  selectedTime: null,
  isMoveMode: false,
};

// ─── INITIALISERING ─────────────────────────────────────────────────────────
document.addEventListener('DOMContentLoaded', () => {
  const urlParams = new URLSearchParams(window.location.search);
  state.token = urlParams.get('t');
  state.bookingId = urlParams.get('b');
  state.editToken = urlParams.get('k');

  renderDirections();
  setupEventListeners();

  if (!state.token) {
    showView('invalid-token');
    return;
  }

  // Om b och k finns i länken: direkt till besökshantering
  if (state.bookingId && state.editToken) {
    loadExistingBooking();
  } else {
    loadAvailability();
  }
});

// ─── VY-HANTERING ───────────────────────────────────────────────────────────
function showView(viewName) {
  const views = [
    'loading',
    'error',
    'invalid-token',
    'start',
    'find',
    'booking',
    'confirmation',
    'manage',
  ];

  views.forEach((v) => {
    const el = document.getElementById(`view-${v}`);
    if (el) {
      if (v === viewName) {
        el.classList.remove('hidden');
      } else {
        el.classList.add('hidden');
      }
    }
  });

  window.scrollTo(0, 0);
}

// ─── API-ANROP: HÄMTA TILLGÄNGLIGHET ─────────────────────────────────────────
async function loadAvailability() {
  showView('loading');
  try {
    let url = `${API_BASE_URL}/availability?t=${encodeURIComponent(state.token)}`;
    if (state.isMoveMode && state.bookingId && state.editToken) {
      url += `&b=${encodeURIComponent(state.bookingId)}&k=${encodeURIComponent(state.editToken)}`;
    }
    const res = await fetch(url);

    if (res.status === 404) {
      showView('invalid-token');
      return;
    }

    if (!res.ok) {
      throw new Error(`HTTP ${res.status}`);
    }

    const data = await res.json();
    state.availability = data;
    renderStartView(data);
    showView('start');
  } catch (err) {
    console.error('Kunde inte hämta tillgänglighet:', err);
    document.getElementById('error-message').textContent =
      'Kunde inte hämta tiderna just nu. Kontrollera anslutningen och försök igen.';
    showView('error');
  }
}

// ─── API-ANROP: HÄMTA BEFINTLIGT BESÖK (Manage Mode) ────────────────────────
async function loadExistingBooking() {
  showView('loading');
  try {
    const url = `${API_BASE_URL}/booking?t=${encodeURIComponent(state.token)}&b=${encodeURIComponent(state.bookingId)}&k=${encodeURIComponent(state.editToken)}`;
    const res = await fetch(url);

    if (res.status === 403 || res.status === 404) {
      // Ogiltig eller redan avanmäld
      loadAvailability();
      return;
    }

    if (!res.ok) {
      throw new Error(`HTTP ${res.status}`);
    }

    const booking = await res.json();
    state.existingBooking = booking;
    renderManageView(booking);
    showView('manage');
  } catch (err) {
    console.error('Kunde inte läsa besök:', err);
    loadAvailability();
  }
}

// ─── RENDERING: STARTVY ─────────────────────────────────────────────────────
function renderStartView(data) {
  const firstName = data.personFirstName || 'Noomi';
  document.getElementById('person-first-name').textContent = firstName;

  // Flytt-läge banner
  const moveBanner = document.getElementById('move-mode-banner');
  if (state.isMoveMode) {
    moveBanner.classList.remove('hidden');
  } else {
    moveBanner.classList.add('hidden');
  }

  // Dagsläge idag
  // Grönt läge visas inte — familjen ringer anmälda besökare om läget ändras.
  const todayBanner = document.getElementById('today-banner');
  const todayIcon = document.getElementById('today-icon');
  const todayText = document.getElementById('today-text');

  if (data.todayStatus === 'yellow') {
    todayBanner.className = 'status-banner yellow';
    todayIcon.textContent = '💛';
    todayText.textContent = `${firstName} är lite trött idag — korta besök uppskattas.`;
    todayBanner.classList.remove('hidden');
  } else if (data.todayStatus === 'red') {
    todayBanner.className = 'status-banner red';
    todayIcon.textContent = '❤️';
    todayText.textContent = 'Idag passar det tyvärr inte med besök.';
    todayBanner.classList.remove('hidden');
  } else {
    todayBanner.classList.add('hidden');
  }

  // Dagslista
  const daysList = document.getElementById('days-list');
  daysList.innerHTML = '';

  const days = data.days || [];
  days.forEach((day) => {
    const card = document.createElement('div');
    card.className = 'day-card';
    card.id = `day-card-${day.date}`;

    let statusDotClass = 'green';
    if (day.status === 'yellow') statusDotClass = 'yellow';
    if (day.status === 'red') statusDotClass = 'red';

    let badgeHtml = `<span class="status-dot ${statusDotClass}"></span>`;
    if (day.status === 'red') {
      badgeHtml = `<span class="day-badge red">Vila ❤️</span>`;
    }

    card.innerHTML = `
      <div class="day-header">
        <div class="day-title">
          <span>${escapeHtml(day.weekdayLabel)}</span>
        </div>
        <div>${badgeHtml}</div>
      </div>
    `;

    const isOwnBookingDay = state.isMoveMode && state.existingBooking && state.existingBooking.date === day.date;

    if (day.status === 'red') {
      const redMsg = document.createElement('div');
      redMsg.className = 'red-day-message';
      redMsg.textContent = '❤️ Inga besök idag (vila)';
      card.appendChild(redMsg);
    } else if (day.dayBooked && !isOwnBookingDay) {
      // Dagen är fullbokad (och inte egna bokningens dag i flyttläge)
      const bookedMsg = document.createElement('div');
      bookedMsg.className = 'day-booked-message';
      bookedMsg.textContent = 'Ett besök är redan inbokat den här dagen 💜';
      card.appendChild(bookedMsg);
    } else {
      // Rubrik över ankomsttider
      const secTitle = document.createElement('div');
      secTitle.className = 'slots-section-title';
      secTitle.textContent = 'Jag kommer ca:';
      card.appendChild(secTitle);

      const slotsGrid = document.createElement('div');
      slotsGrid.className = 'slots-grid';

      const dayMealLabel = day.mealLabel || day.dinnerLabel || data.dinnerLabel || 'Middag 17–18';

      let hasDinnerSlot = false;

      day.slots.forEach((slot) => {
        const btn = document.createElement('button');
        btn.type = 'button';
        btn.className = 'slot-btn';

        const isOwnSlot = isOwnBookingDay && state.existingBooking.time === slot.time;

        if (isOwnSlot) {
          btn.classList.add('slot-own');
          btn.textContent = `${slot.time} (nuvarande)`;
          btn.disabled = true;
        } else if (slot.reason === 'dinner') {
          hasDinnerSlot = true;
          btn.classList.add('slot-dinner');
          btn.textContent = `${slot.time} 🍽️`;
          btn.disabled = true;
          btn.title = dayMealLabel;
        } else if (slot.reason === 'booked') {
          btn.classList.add('slot-booked');
          btn.textContent = 'Besök inbokat 💜';
          btn.disabled = true;
        } else if (slot.free) {
          btn.textContent = slot.time;
          btn.addEventListener('click', () => {
            selectSlot(day.date, day.weekdayLabel, slot.time);
          });
        } else {
          btn.textContent = 'Upptaget';
          btn.disabled = true;
        }

        slotsGrid.appendChild(btn);
      });

      card.appendChild(slotsGrid);

      if (hasDinnerSlot) {
        const mealHint = document.createElement('div');
        mealHint.className = 'day-meal-hint';
        mealHint.textContent = `🍽️ = ${dayMealLabel}, då passar det inte.`;
        card.appendChild(mealHint);
      }
    }

    daysList.appendChild(card);
  });
}

// ─── VAL AV TID ─────────────────────────────────────────────────────────────
function selectSlot(date, weekdayLabel, time) {
  state.selectedDate = date;
  state.selectedWeekdayLabel = weekdayLabel;
  state.selectedTime = time;

  const display = `${weekdayLabel} — jag kommer ca ${time}`;
  document.getElementById('booking-slot-display').textContent = display;

  const formTitle = document.getElementById('booking-form-title');
  const submitBtn = document.getElementById('btn-submit-booking');

  if (state.isMoveMode) {
    formTitle.textContent = 'Bekräfta ny ankomsttid';
    submitBtn.textContent = 'Jag kommer då 💜';
    if (state.existingBooking) {
      document.getElementById('input-names').value = state.existingBooking.names || '';
      document.getElementById('input-phone').value = state.existingBooking.phone || '';
    }
  } else {
    formTitle.textContent = 'Kom och hälsa på';
    submitBtn.textContent = 'Jag kommer då 💜';
  }

  document.getElementById('booking-error').classList.add('hidden');
  showView('booking');
}

// ─── FORMULÄR SUBMIT ────────────────────────────────────────────────────────
async function handleBookingSubmit(e) {
  e.preventDefault();

  const namesInput = document.getElementById('input-names');
  const phoneInput = document.getElementById('input-phone');
  const errorBox = document.getElementById('booking-error');
  const submitBtn = document.getElementById('btn-submit-booking');

  const names = namesInput.value.trim();
  const phone = phoneInput.value.trim();

  if (names.length < 2) {
    showBookingError('Vänligen ange namn på besökarna.');
    return;
  }
  if (phone.length < 6) {
    showBookingError('Vänligen ange ett giltigt telefonnummer.');
    return;
  }

  errorBox.classList.add('hidden');
  submitBtn.disabled = true;
  submitBtn.textContent = 'Sparar…';

  try {
    if (state.isMoveMode) {
      // POST /move
      const res = await fetch(`${API_BASE_URL}/move`, {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({
          t: state.token,
          b: state.bookingId,
          k: state.editToken,
          newDate: state.selectedDate,
          newTime: state.selectedTime,
        }),
      });

      const result = await res.json();
      if (!res.ok) {
        if (res.status === 409) {
          showBookingError(result.error || 'Den tiden hann tyvärr gå — välj gärna en annan.');
          setTimeout(loadAvailability, 2000);
          return;
        }
        throw new Error(result.error || 'Kunde inte byta tid.');
      }

      state.isMoveMode = false;
      renderConfirmation(state.selectedWeekdayLabel, state.selectedTime, state.bookingId, state.editToken);
      showView('confirmation');
    } else {
      // POST /book
      const res = await fetch(`${API_BASE_URL}/book`, {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({
          t: state.token,
          date: state.selectedDate,
          time: state.selectedTime,
          names,
          phone,
        }),
      });

      const result = await res.json();
      if (!res.ok) {
        if (res.status === 409) {
          showBookingError(result.error || 'Den tiden hann tyvärr gå — välj gärna en annan.');
          setTimeout(loadAvailability, 2000);
          return;
        }
        throw new Error(result.error || 'Kunde inte spara ditt besök.');
      }

      state.bookingId = result.bookingId;
      state.editToken = result.editToken;
      renderConfirmation(state.selectedWeekdayLabel, state.selectedTime, result.bookingId, result.editToken);
      showView('confirmation');
    }
  } catch (err) {
    console.error('Besöksfel:', err);
    showBookingError(err.message || 'Ett fel uppstod. Kontrollera anslutningen och försök igen.');
  } finally {
    submitBtn.disabled = false;
    submitBtn.textContent = 'Jag kommer då 💜';
  }
}

function showBookingError(msg) {
  const errorBox = document.getElementById('booking-error');
  errorBox.textContent = msg;
  errorBox.classList.remove('hidden');
}

// ─── RENDERING: BEKRÄFTELSE ─────────────────────────────────────────────────
function renderConfirmation(weekdayLabel, time, bookingId, editToken) {
  const summaryEl = document.getElementById('confirm-summary');
  const personName = (state.availability && state.availability.personFirstName) || 'Noomi';
  summaryEl.textContent = `${personName} ser fram emot ert besök ${weekdayLabel.toLowerCase()} ca ${time}.`;

  const origin = window.location.origin + window.location.pathname;
  const personalUrl = `${origin}?t=${encodeURIComponent(state.token)}&b=${encodeURIComponent(bookingId)}&k=${encodeURIComponent(editToken)}`;

  const linkBox = document.getElementById('confirm-link-url');
  linkBox.textContent = personalUrl;
}

// ─── RENDERING: MANAGE VY ───────────────────────────────────────────────────
function renderManageView(booking) {
  const dtEl = document.getElementById('manage-datetime');
  dtEl.textContent = `${booking.date} — ankomst ca ${booking.time}`;
  document.getElementById('manage-names').textContent = booking.names || '';
  document.getElementById('manage-phone').textContent = booking.phone || '';
}

// ─── AVBOKNING / AVANMÄLAN (Manage Mode) ────────────────────────────────────
async function handleCancelBooking() {
  if (!confirm('Är du säker på att du vill avanmäla besöket?')) return;

  showView('loading');
  try {
    const res = await fetch(`${API_BASE_URL}/cancel`, {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({
        t: state.token,
        b: state.bookingId,
        k: state.editToken,
      }),
    });

    if (!res.ok) {
      const err = await res.json();
      throw new Error(err.error || 'Kunde inte avanmäla.');
    }

    alert('Ditt besök har avanmälts. Välkommen en annan gång!');
    // Rensa b & k ur state och ladda om tiderna
    state.bookingId = null;
    state.editToken = null;
    state.existingBooking = null;
    state.isMoveMode = false;
    window.history.replaceState({}, '', `${window.location.pathname}?t=${encodeURIComponent(state.token)}`);
    loadAvailability();
  } catch (err) {
    console.error('Kunde inte avanmäla:', err);
    alert(`Kunde inte avanmäla: ${err.message}`);
    showView('manage');
  }
}

// ─── HITTA MIN ANMÄLAN ──────────────────────────────────────────────────────
async function handleFindSubmit(e) {
  e.preventDefault();

  const phoneInput = document.getElementById('input-find-phone');
  const errorBox = document.getElementById('find-error');
  const submitBtn = document.getElementById('btn-submit-find');
  const resultsBox = document.getElementById('find-results');
  const resultsList = document.getElementById('find-results-list');
  const emptyBox = document.getElementById('find-empty-message');

  const phone = phoneInput.value.trim();
  const digits = phone.replace(/\D/g, '');

  if (digits.length < 7) {
    errorBox.textContent = 'Vänligen ange minst 7 siffror i telefonnumret.';
    errorBox.classList.remove('hidden');
    return;
  }

  errorBox.classList.add('hidden');
  resultsBox.classList.add('hidden');
  emptyBox.classList.add('hidden');
  resultsList.innerHTML = '';
  submitBtn.disabled = true;
  submitBtn.textContent = 'Söker…';

  try {
    const res = await fetch(`${API_BASE_URL}/find`, {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({
        t: state.token,
        phone,
      }),
    });

    const data = await res.json();
    if (!res.ok) {
      throw new Error(data.error || 'Kunde inte söka efter anmälan.');
    }

    const bookings = data.bookings || [];
    if (bookings.length === 0) {
      emptyBox.classList.remove('hidden');
    } else {
      bookings.forEach((b) => {
        const card = document.createElement('div');
        card.className = 'found-booking-card';

        const title = document.createElement('div');
        title.className = 'found-booking-title';
        title.textContent = `📅 ${b.date} — ankomst ca ${b.time}`;

        const sub = document.createElement('div');
        sub.className = 'found-booking-sub';
        sub.textContent = `Besökare: ${escapeHtml(b.names)}`;

        const actions = document.createElement('div');
        actions.className = 'found-booking-actions';

        const moveBtn = document.createElement('button');
        moveBtn.type = 'button';
        moveBtn.className = 'btn-primary';
        moveBtn.textContent = 'Byt tid';
        moveBtn.addEventListener('click', () => {
          state.bookingId = b.b;
          state.editToken = b.k;
          state.isMoveMode = true;
          window.history.replaceState({}, '', `${window.location.pathname}?t=${encodeURIComponent(state.token)}&b=${encodeURIComponent(b.b)}&k=${encodeURIComponent(b.k)}`);
          loadAvailability();
        });

        const cancelBtn = document.createElement('button');
        cancelBtn.type = 'button';
        cancelBtn.className = 'btn-danger';
        cancelBtn.textContent = 'Avanmäl besöket';
        cancelBtn.addEventListener('click', () => {
          state.bookingId = b.b;
          state.editToken = b.k;
          window.history.replaceState({}, '', `${window.location.pathname}?t=${encodeURIComponent(state.token)}&b=${encodeURIComponent(b.b)}&k=${encodeURIComponent(b.k)}`);
          handleCancelBooking();
        });

        actions.appendChild(moveBtn);
        actions.appendChild(cancelBtn);

        card.appendChild(title);
        card.appendChild(sub);
        card.appendChild(actions);

        resultsList.appendChild(card);
      });

      resultsBox.classList.remove('hidden');
    }
  } catch (err) {
    console.error('Sökfel:', err);
    errorBox.textContent = err.message || 'Ett fel uppstod. Kontrollera anslutningen och försök igen.';
    errorBox.classList.remove('hidden');
  } finally {
    submitBtn.disabled = false;
    submitBtn.textContent = 'Hitta min anmälan';
  }
}

// ─── EVENT LISTENERS ────────────────────────────────────────────────────────
function setupEventListeners() {
  document.getElementById('btn-retry').addEventListener('click', loadAvailability);

  document.getElementById('btn-back-to-start').addEventListener('click', () => {
    showView('start');
    if (state.selectedDate) {
      const card = document.getElementById(`day-card-${state.selectedDate}`);
      if (card) {
        setTimeout(() => {
          card.scrollIntoView({ behavior: 'smooth', block: 'center' });
        }, 50);
      }
    }
  });

  document.getElementById('btn-show-find').addEventListener('click', () => {
    document.getElementById('find-results').classList.add('hidden');
    document.getElementById('find-empty-message').classList.add('hidden');
    document.getElementById('find-error').classList.add('hidden');
    document.getElementById('input-find-phone').value = '';
    showView('find');
  });

  document.getElementById('btn-back-from-find').addEventListener('click', () => {
    showView('start');
  });

  document.getElementById('find-form').addEventListener('submit', handleFindSubmit);

  document.getElementById('booking-form').addEventListener('submit', handleBookingSubmit);

  document.getElementById('btn-copy-confirm-link').addEventListener('click', () => {
    const linkText = document.getElementById('confirm-link-url').textContent;
    copyToClipboard(linkText);
    const fb = document.getElementById('copy-feedback');
    fb.classList.remove('hidden');
    setTimeout(() => fb.classList.add('hidden'), 3000);
  });

  document.getElementById('btn-done').addEventListener('click', () => {
    state.isMoveMode = false;
    loadAvailability();
  });

  document.getElementById('btn-start-move').addEventListener('click', () => {
    state.isMoveMode = true;
    loadAvailability();
  });

  document.getElementById('btn-cancel-move').addEventListener('click', () => {
    state.isMoveMode = false;
    if (state.existingBooking) {
      showView('manage');
    } else {
      loadAvailability();
    }
  });

  document.getElementById('btn-cancel-booking').addEventListener('click', handleCancelBooking);
}

// ─── HJÄLPMETODER ───────────────────────────────────────────────────────────
function copyToClipboard(text) {
  if (navigator.clipboard && navigator.clipboard.writeText) {
    navigator.clipboard.writeText(text).catch(() => fallbackCopy(text));
  } else {
    fallbackCopy(text);
  }
}

function fallbackCopy(text) {
  const ta = document.createElement('textarea');
  ta.value = text;
  ta.style.position = 'fixed';
  ta.style.opacity = '0';
  document.body.appendChild(ta);
  ta.select();
  try {
    document.execCommand('copy');
  } catch (_) {}
  document.body.removeChild(ta);
}

// ─── HITTA HIT / KARTLÄNK FÖR OLIKA PLATTFORMAR ─────────────────────────────
// medvetet familjespecifikt
// TODO: verifiera att nålen hamnar på hus T1 — annars ersätt med delningslänk från Google Maps / Apple Kartor
function renderDirections() {
  // iPadOS 13+ kan identifiera sig som MacIntel med multi-touch
  const isApple = /iPad|iPhone|iPod/.test(navigator.userAgent) ||
    (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);

  const mapsUrl = isApple
    ? 'https://maps.apple.com/?q=Rehabiliteringsmedicinska+kliniken+L%C3%A4nssjukhuset+Ryhov+J%C3%B6nk%C3%B6ping'
    : 'https://www.google.com/maps/search/?api=1&query=Rehabiliteringsmedicinska+kliniken+L%C3%A4nssjukhuset+Ryhov+J%C3%B6nk%C3%B6ping';

  document.querySelectorAll('.btn-maps').forEach((btn) => {
    btn.href = mapsUrl;
    btn.textContent = 'Visa vägen dit 🗺️';
    btn.target = '_blank';
    btn.rel = 'noopener noreferrer';
  });
}

function escapeHtml(str) {
  if (!str) return '';
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}
