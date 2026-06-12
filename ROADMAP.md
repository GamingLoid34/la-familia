# 🗺️ La Familia – Roadmap v3 (2026-06-11)

Ersätter tidigare roadmap (mycket var redan klart: Provider, Crashlytics, notistjänst, säkerhetsregler).
Baserad på kodgenomgång 2026-06-11. Princip: **enkelhet uppstår genom att ta bort, inte lägga till.**
Varje etapp avslutas med `flutter analyze` grönt + manuell verifiering innan nästa påbörjas.

---

## ✅ Etapp 1: Städning & ärlighet (UI:t ska inte ljuga)

Mål: ta bort dött/trasigt och sådant som ser ut att fungera men inte gör det.

- [x] 1.1 Ta bort `lib/screens/personal_countdown_screen.dart` — onåbar från all navigation + syntaxbugg (`static` på toppnivå). Fokus-timern (`timer_page.dart`) täcker behovet.
- [x] 1.2 Ta bort Skärmregler (`lib/screens/screen_rules_page.dart` + länken i `agenda_page.dart`) — manuell tabell som varken mäter eller blockerar något; underhållsbörda utan nytta.
- [x] 1.3 Ta bort `ManageTemplatesPage` — onåbar OCH inkompatibelt schema (`steps` ist. f. `substeps`, ingen piktogram/poäng). Mallar skapas redan via "spara som mall" i syssle-formuläret och raderas via långtryck i strippen — befintligt flöde räcker.
- [x] 1.4 Ta bort "Belöning godkänd"-toggeln i Inställningar — den gör ingenting (ingen kod läser `notifReward`).
- [x] 1.5 Ersätt alla `catch (_) {}` med `developer.log(..., error: e, stackTrace: stack)` (13 st efter raderingarna).
- [x] 1.6 `flutter analyze`: 0 errors, 0 warnings (41 info-lints kvar, se backlog). Bonus: raderade trasiga oanvända `responsive_wrapper.dart`, fixade `withOpacity` i main.dart + onödig cast i planner_page.

**Verifiering:** appen bygger, Agendan har ingen Skärmregler-knapp, mall-editorn öppnas från strippen, Inställningar visar två notistogglar.

---

## 📅 Etapp 2: Datumfundament (före allt annat)

Mål: ett datumformat i hela appen. Allt i Etapp 4 (återkommande) kräver detta.

- [x] 2.1 Skapa `lib/utils/date_utils.dart`: `dateKey()`, `timeKey()`, `parseDate()`, `parseDateTime()` + `legacyDateKey()`/`dateKeysForQuery()` för övergången.
- [x] 2.2 Ersätt alla lokala kopior av `_parseDate`/`_parseDateTime`/`_dateKey` (agenda, dashboard, member_day_sheet, work_schedule, planner, planner_event_leading; `parseYmdDate` i schedule_time_utils delegerar nu).
- [x] 2.3 All datumskrivning via `dateKey()` (chores ×2, planner, work_schedule, calendar_import). `FamilyProvider` frågar dagens events med `whereIn` (paddad + opaddad) tills 2.4 körts — ta sedan bort `legacyDateKey`.
- [x] 2.4 `migrateDateFormatOnce` deployad och KÖRD 2026-06-11 ✅ (obs: alla callables skrivna i v2-API — firebase-functions v7). Övergångskoden (`legacyDateKey`/`dateKeysForQuery`) borttagen efter migrering.
- [x] 2.5 Grep-verifierat: inga opaddade datumskrivningar kvar (endast `legacyDateKey` medvetet + `weekOf`-format). `flutter analyze`: 0 errors/warnings.

---

## 🎨 Sidospår: Ny design (klar 2026-06-11)

"Varje dag en ädelsten/metall": smaragd/safir/silver/koppar/guld/roséguld/granat med trestegsgradienter (glansband), tonad sidbakgrund (10 % av dagsfärgen), vita kort med färgad skugga/ram, färgade sektionsrubriker, ikonbrickor, frostat glas-bottennav, Nunito via google_fonts. Utrullat: tema + Hem + bottennav. **Utrullat överallt 2026-06-11:** gradient-headers på Agenda/Sysslor/Inställningar/Inköp/Familjestatus/Scheman/Kalenderimport; Fokus-timern följer dagspaletten (var röd/beige). **Kvar:** bundla Nunito lokalt (offline).

---

## 🆔 Etapp 3: Personer via uid, inte namn

Mål: byta namn ska inte trasa sönder kopplingar. Största strukturella risken i datat.

- [x] 3.1 `personUids`/`whoUid`/`userUid` skrivs nu vid alla 7 skrivställen (events, kalenderimport, sysslor ×3, arbetspass, upptagen-session). Central helper: `lib/utils/person_match.dart`.
- [x] 3.2 All matchning går via `eventIncludesPerson`/`assignedToPerson` (uid vinner, namn som fallback): dashboard, agenda (filter + glance), chores-filter, work_schedule-filter, family_status, member_presence, today_chores_sheet. Visning använder fortfarande lagrade namn.
- [x] 3.3 `backfillPersonUids` deployad och KÖRD 2026-06-11 ✅.
- [ ] 3.4 Verifiera namnbyte: byt namn på en medlem i Hantera medlemmar → events/sysslor/pass ska fortfarande visas för personen (kräver att 3.3-knappen körts).

---

## 🔁 Etapp 4: Återkommande aktiviteter

Mål: fotbollsträning varje tisdag läggs in EN gång. Största enkelhetsvinsten för familjen.

- [x] 4.1 `lib/utils/recurrence.dart`: `eventOccursOnDay`/`recurringOccursOnDay`/`expandRecurrence`/`recurrenceLabel`. Veckodag/dag-i-månad härleds ur startDate; DST-säker dagdiff.
- [x] 4.2 Sparas en gång med `isRecurring: true` + `recurrence{}`; agenda/planner matchar via `eventOccursOnDay`, providern har separat `isRecurring`-prenumeration som mergas (dedup på doc-id) in i `todayEvents`.
- [x] 4.3 AddEventSheet: dropdown Engång/Varje X/Varannan X/Varje månad + valfritt slutdatum. 🔁-etikett på raderna i Agendan.
- [x] 4.4 Ta bort på återkommande frågar "Bara denna dag" (→ `exceptions[]` + avbokar instansnotis) eller "Alla gånger". Redigering ändrar alla (bevarar exceptions).
- [x] 4.5 Notiser per instans (`{docId}_{datum}`) 14 dagar framåt, schemaläggs om vid varje spara/redigera. OBS: ingen `rescheduleAll()` vid appstart ännu — instanser bortom 14 dagar från senaste ändring saknar notis (backlog).

---

## 🔔 Etapp 5: Notiser som håller vad de lovar + övergångsvarningar (NPF)

- [ ] 5.1 Verifiera på fysisk enhet: skapa event ~20 min fram → 15-min-påminnelse + 10-min-övergångsvarning; radera → båda avbokas.
- [x] 5.2 Notiser taggas med payload (`activity`/`transition`/`chore`); togglarna avbokar nu BARA sin typ via `cancelByPayloads` — `cancelAll()` borta ur Inställningar.
- [x] 5.3 Övergångsvarning: "Snart dags att byta 🔄 — Om 10 min: X. Börja runda av det du gör." 10 min före start, egen kanal + toggle i Inställningar (default på). Funkar även för återkommande instanser.

---

## ⏳ Etapp 6: Visuell tid + förutsägbarhet (NPF)

- [x] 6.1 Fokuskortet visar "17:00 · om 45 min" / "Pågår nu", krympande tidsbalk sista timmen, minutpuls håller allt färskt.
- [x] 6.2 "Starta nedräkning"-knapp → Fokus-timern förinställd på tiden kvar, autostartad, med etikett "Tills X börjar".
- [x] 6.3 I morgon-vyn på Hem (egen variant) efter kl 18: piktogram + tid + titel, eller "Inget planerat i morgon — sov gott!". Provider prenumererar på morgondagens events + expanderar återkommande.

---

## 🌅 Etapp 7: Morgon- och kvällsrutiner (NPF)

Mål: rutiner är trygghet, inte uppgifter — separata från sysslor/poäng.

- [x] 7.1 Collection `routines` (regler deployade): `{familyId, ownerUid, ownerName, type: morning|evening, steps[{title,piktogram}], doneDate, doneSteps[]}`. Provider prenumererar.
- [x] 7.2 `RoutineCard` på Hem: morgonrutin före kl 12, kvällsrutin från kl 18. Stora tryckytor, "X av Y"/"Klart! 🌟", auto-reset via doneDate (gårdagens bockar räknas inte). Inga poäng — medvetet.
- [x] 7.3 `ManageRoutinesPage` via Inställningar → familjekortet → "Morgon- & kvällsrutiner" (endast föräldrar ser kortet). Snabbval av 16 rutin-emojis + fritextsteg.

---

## 🔋 Etapp 8: Energi som gör något + lågstimuli-läge (NPF)

- [x] 8.1 Energi på medlemskorten är nu emoji-badge (😔😌😊🚀) i vit cirkel med färgad ring, 20px — form + färg, färgblindsäkert. Samma skala som energiväljaren.
- [x] 8.2 Sätter man energi till Låg frågar appen "Tung dag? 💛 — Pausa dagens påminnelser?" → avbokar aktivitets-/övergångs-/sysslonotiser lokalt. (Lokala notiser kan inte dämpas av ANDRAS energi — de ligger på respektive persons enhet.)
- [x] 8.3 Lågstimuli-läge: toggle i Inställningar → platta dagsfärger utan glansband, neutral bakgrund, inga skuggor/dekorcirklar. Laddas före första frame; slår igenom på alla flikar direkt via provider-refresh. Dagsfärgerna behålls — igenkänningen är trygghet.

---

## 🗓️ Etapp 9: Veckogrid & navigationsförenkling (fd PROJECT_PLAN Fas 4)

Mål: "Hem" = min dag. "Familjen" = veckans översikt. Varje flik ett tydligt svar på "varför går jag hit?".

- [x] 9.1 `family_week_page.dart` + `week_grid.dart`: medlemmar som rader (fast avatarkolumn), 7 dagkolumner med horisontell scroll, idag-markering, max 2 events/cell + "+N till", tap → MemberDaySheet. Veckonav ‹ › + "Idag". Återkommande events expanderas.
- [x] 9.2 `conflict_detector.dart`: överlapp mellan vuxnas events (med tid) + arbetspass → röda chips "🚨 tis 16:00 — båda upptagna" → dialog med "✋ Jag tar det" som lägger en familjenotis på konfliktdagen.
- [x] 9.3 `FamilyWeekPage` ersätter `DashboardPage(variant: family)` i main.dart; FamilyNotesStrip + Familjestatus-länk + "Jag är upptagen"-FAB flyttade med. (DashboardVariant.family-koden ligger kvar oanvänd — städas i backlog.)

---

## ⚡ Etapp 10: Snabbinmatning (konkurrensanalys 2026-06-12: inmatning är svagaste punkten)

Mål: "Fotboll tis 17:00 Liam" i en rad → färdig aktivitet. Sänker tröskeln som flerstegsformuläret skapar — extra viktigt vid exekutiva svårigheter.

- [x] 10.1 `lib/utils/quick_add_parser.dart`: lokal svensk fritexttolk — veckodagar (tis/tisdag), "idag"/"imorgon", datum 12/6, "varje/varannan X" (→ recurrence), tid ("kl 17", "17:00", "17.30"), medlemsnamn, resten blir titel. Auto-piktogram via piktogrambiblioteket.
- [x] 10.2 `QuickAddBar` överst i Agendan: skriv → bekräftelseblad med tolkningen som chips (datum/tid/vem/upprepning) → Spara. Skriver med alla konventioner + schemalägger notiser (inkl. återkommande instanser).
- [x] 10.3 O-tolkbar text öppnar vanliga formuläret med texten förifylld som titel.

## 🔔 Etapp 11: Riktiga pushar mellan medlemmar (FCM)

Mål: appen ska kännas levande — reaktioner, familjetavlan, "Jag tar det" och tilldelade sysslor ska nå andras mobiler. firebase_messaging finns redan i pubspec.

- [ ] 11.1 FCM-token per enhet sparas på users-dokumentet; Cloud Function skickar push vid ny familjenotis/reaktion/syssle-tilldelning till berörda (ej avsändaren).
- [ ] 11.2 Respektera presence: ingen push till den som är "Upptagen" eller har energi Låg (servern läser users-dokumentet).
- [ ] 11.3 Notisinställningar utökas med "Familjehändelser"-toggle.

## 🍽️ Etapp 12: Matplanering light

Mål: veckans middagar i appen (kärnbehov: "handla mat") utan att bygga receptbank.

- [ ] 12.1 Collection `meals` {familyId, date, title, emoji}; vecko-vy (7 rader) nåbar från Hem-snabbverktyg + Familjen.
- [ ] 12.2 "Lägg ingredienser i inköpslistan"-knapp per middag (fritextrader → shopping_items).
- [ ] 12.3 Dagens middag visas på Hem ("🍽️ Ikväll: tacos").

## 📱 Etapp 13: Hemskärms-widget (Android)

Mål: nästa aktivitet + rutinstatus utan att öppna appen — för ADHD är widgeten ofta hela appen.

- [ ] 13.1 home_widget-paketet: liten widget med nästa aktivitet ("om 45 min: ⚽ Fotboll") i dagens färg.
- [ ] 13.2 Medium-variant med dagens rutinsteg kvar att bocka.

## 🚪 Etapp 14: Onboarding & login i nya designen

- [ ] 14.1 Login/registrering/onboarding får juveltema, Nunito och gradient-headers (enda skärmarna kvar med gamla stilen) + lint-städning (BuildContext async-gaps).
- [ ] 14.2 Förstagångs-upplevelse: förifyllda exempel (en aktivitet, en rutin, en syssla) så appen inte är tom dag 1.

---

## 🧹 Backlog (ingen egen etapp — tas löpande)

- [ ] Inköpslistan: snabbval-chips för vanliga varor (mjölk, bröd, ägg...) — enda tillägget, inget mer.
- [ ] Migrera `manage_members_page` från SecondaryApp till `createUser` Cloud Function.
- [ ] Lyft `work_shifts`/`busy_sessions`-streams till `FamilyProvider` (bort med nästlade StreamBuilders).
- [ ] Typa `UserModel.colorValue` som `int`.
- [ ] README.md: ersätt Flutter-starter-texten.
- [ ] Ta bort gammal `android/.../com/example/myapp/MainActivity.kt` om kvar.
- [ ] `OfflineBanner` (lib/widgets/offline_banner.dart) är byggd men aldrig inkopplad — wrappa MainPage med den eller ta bort.
- [ ] Besluta om `activity_templates`: läses i AddEventSheet (planner) men det finns inget UI som skapar dem sedan ManageTemplatesPage togs bort — bygg "spara som mall" för aktiviteter (som sysslor har) eller ta bort läsningen.
