# 🗺️ La Familia – Master Åtgärdslista (Roadmap)

Denna roadmap hanterar kritiska säkerhetsrisker, prestandaproblem, teknisk skuld och framtida funktionalitet för Flutter/Firebase-appen "La Familia". Åtgärderna är prioriterade från mest affärskritiskt (Fas 1) till framtida optimeringar (Fas 3).

---

## 🚨 Fas 1: Kritiska Blockers (Säkerhet, Skalbarhet & Auth)
Dessa punkter måste åtgärdas innan appen distribueras till faktiska användare för att undvika dataläckor, krascher och onödiga serverkostnader.

- [ ] **1.1 Lås ner Firestore-säkerhetsregler (`firestore.rules`)**
  - **Problem:** Nuvarande `allow read, write: if request.auth != null;` tillåter alla inloggade att manipulera all data.
  - **Åtgärd:** Skriv om reglerna så att en användare endast kan läsa/skriva i dokument där dokumentets `familyId` matchar användarens eget `familyId`.
  - **Beroende:** Kräver en uppdatering i t.ex. `screen_rules_page.dart` och `countdowns` för att säkerställa att `familyId` faktiskt sparas ner på alla nya dokument innan reglerna aktiveras.
  - **Filer:** `firestore.rules`, `lib/screens/screen_rules_page.dart`, `lib/screens/personal_countdown_screen.dart`.

- [ ] **1.2 Säker hantering av familjemedlemmar (Cloud Functions)**
  - **Problem:** `manage_members_page.dart` använder en inbyggd Firebase `SecondaryApp` för att föräldrar ska kunna skapa barnkonton. Detta är instabilt och leder till utloggningar/session-strul.
  - **Åtgärd:** Sätt upp Firebase Cloud Functions. Skapa en säker "Callable Endpoint" (t.ex. `createUser`) som anropas från appen, skapar användaren i Firebase Auth säkert på backend, och returnerar det nya UID:t.
  - **Filer:** `lib/screens/manage_members_page.dart`, `functions/index.js` (ska initieras).

- [ ] **1.3 Optimera klientstyrd datahämtning (Firestore Queries)**
  - **Problem:** `DashboardPage` laddar ner alldeles för mycket rådata och gör sorteringen/filtreringen i Dart-koden (t.ex. i `_buildEventsStream`). Detta skapar enorma läskostnader i Firebase när databasen växer.
  - **Åtgärd:** Applicera korrekta queries i koden med `.where('date', isGreaterThanOrEqualTo: ...).orderBy('date')`. Skapa nödvändiga "Composite Indexes" i Firebase Console.
  - **Filer:** `lib/screens/dashboard_page.dart`, `lib/screens/planner_page.dart`.

---

## ⚠️ Fas 2: Teknisk Skuld & Stabilitet
Dessa punkter hanterar appens interna hälsa. De syns inte nödvändigtvis för slutanvändaren, men är avgörande för att koden ska vara underhållbar.

- [ ] **2.1 Implementera State Management (Provider / Riverpod)**
  - **Problem:** Koden har ett tungt beroende av nästlade `StreamBuilder` och `setState` direkt i UI-koden. Logik och gränssnitt är tätt sammankopplade.
  - **Åtgärd:** Lyft ut databasanrop och tillståndshantering till dedikerade controllers/tjänster med ett State Management-paket. Detta kommer minska widget-rebuilds avsevärt och snabba upp appen.
  - **Filer:** Projektövergripande (störst behov i `dashboard_page.dart` och `chores_page.dart`).

- [ ] **2.2 Fånga och logga "Tysta Fel" (Error Handling)**
  - **Problem:** Kodbasen innehåller flera generella `catch (_) {}` (exempelvis vid datum-parsning eller ICS-import) som sväljer krascher utan att lämna spår.
  - **Åtgärd:** Byt ut till strukturerad loggning med `dart:developer`. Inför Firebase Crashlytics för att fånga upp eventuella krascher som sker hos slutanvändare.
  - **Filer:** `lib/widgets/activity_detail_sheet.dart`, `lib/screens/settings_page.dart`, `lib/main.dart`.

---

## 🚀 Fas 3: Kärnfunktionalitet & UX
Dessa punkter tar appen från "bra" till "oumbärlig" för målgruppen (särskilt för NPF-användare).

- [ ] **3.1 Aktivera riktiga Push-notiser & Lokala larm**
  - **Problem:** Toggles i `SettingsPage` ("Aktivitet börjar snart") uppdaterar bara den lokala widgetens tillstånd och gör ingenting i praktiken.
  - **Åtgärd:** Integrera `firebase_messaging` och `flutter_local_notifications`. Sätt upp logik som triggar schemalagda larm lokalt på enheten 15 minuter före en aktivitet.
  - **Filer:** `lib/main.dart`, `lib/screens/settings_page.dart`, samt en ny fil för Notification-hantering.

- [ ] **3.2 Automatisera veckopoäng (Cron Jobs)**
  - **Problem:** Idag finns logik för att nollställa poäng manuellt via klienten. Det bör ske per automatik.
  - **Åtgärd:** Skapa en schemalagd Cloud Function (Pub/Sub) som körs automatiskt varje söndagnatt kl. 23:59 och nollställer `weeklyPoints` för alla aktiva användare.
  - **Filer:** `functions/index.js`.