# 🗺️ La Familia – Utvecklingsplan v3 (2026-07-31)

Ersätter PROJECT_PLAN.md (v2 — i princip helt genomförd, se ROADMAP.md). Baserad på fullständig kodgranskning 2026-07-31 med familjens verkliga behov som facit: 2 föräldrar (en dagtid, en oregelbundna tider/nattpass), barn 9, 12, 16, 18 — de två äldsta har iPhone.

**Beslut som styr planen (fattade av Oscar):**
1. iPhone löses med **PWA** (webbappen + web push), inte native iOS.
2. **Poäng/veckoliga tas bort** och ersätts med **rättvisestatistik** — en logg över vem som gjort vad, att luta sig mot när någon tycker det är orättvist.
3. Barnen **får skapa egna aktiviteter fritt** — men inte redigera/radera andras eller familjens data.

**Prioritetsordning:** förtroende först (rättigheter, sysslor som funkar), sedan frugans skiftschema, sedan pålitlighet, sedan översikt, sist iPhone-PWA:n. Fas 1–2 är små; kör dem först — de förklarar varför appen känts trasig.

---

## 🛠️ Globala konventioner (gäller alla faser)

Samma som v2, med tillägg:
- EN fas i taget i Cursor. Stoppa vid varje verifieringsgate.
- Alla Firestore-skrivningar innehåller `familyId`. Datum via `dateKey()`, tider via `timeKey()` från `lib/utils/date_utils.dart` — aldrig handbyggda strängar.
- Inga `catch (_) {}` — `developer.log('beskrivning', error: e, stackTrace: stack)`.
- Inga `withOpacity` — använd `withValues(alpha: x)`.
- Cloud Functions i **v2-API** (firebase-functions v7), som befintliga.
- Mobil-först, maxbredd 430 px.
- **NYTT:** Alla nya `planner_events`- och `chores`-skrivningar sätter `createdByUid: <auth.uid>` (Fas 1 inför fältet).
- **NYTT:** Rör ALDRIG MyMirai-blocken i `firestore.rules` (documents/homework/decks/flashcards/user_stats).
- Om firestore.rules ändras: visa nya regler och STOPPA innan deploy.
- Om kompilering misslyckas: visa felet, gör inget mer.

---

## 🔐 FAS 1: Roller och rättigheter på riktigt

### Varför
Reglerna skiljer inte på förälder och barn: alla kan radera allt, och `allow write: if request.auth.uid == userId` låter ett barn sätta sin egen `role: 'admin'`. Dessutom sätter både `onboarding_page._joinFamily` och `login_page` (invite-dialogen) `role: 'member'` — ett värde som inte finns (`isParent` kräver parent/admin), så **den som går med via kod blir de facto barn**. Det är därför mamman saknar föräldrafunktioner. Bonus: dagens regler tillåter INTE föräldrar att uppdatera andras user-dokument — så "Hantera medlemmar" har sannolikt aldrig kunnat spara ändringar på andra. Nya reglerna lagar det också.

### Berörda filer
- `firestore.rules` — rollkontroll
- `functions/index.js` — ny callable `joinFamilyWithCode`
- `lib/screens/onboarding_page.dart`, `lib/screens/login_page.dart` — join via callable + rollval
- `lib/screens/planner_page.dart` (AddEventSheet), `lib/widgets/quick_add_bar.dart`, `lib/screens/calendar_import_page.dart` — skriv `createdByUid`
- `lib/screens/agenda_page.dart`, `lib/screens/chores_page.dart`, `lib/widgets/member_day_sheet.dart`, `lib/widgets/activity_detail_sheet.dart` — göm radera/redigera för icke-ägare som inte är förälder
- `lib/screens/settings_page.dart` — ta bort Underhållskortet (migreringarna är körda och verifierade)

### 1.1 Nya firestore.rules (kärnan)

```
function isAuth() { return request.auth != null; }
function myDoc() { return get(/databases/$(database)/documents/users/$(request.auth.uid)).data; }
function myFamilyId() { return myDoc().familyId; }
function iAmParent() { return myDoc().role == 'parent' || myDoc().role == 'admin'; }

match /users/{userId} {
  allow read: if isAuth() && (request.auth.uid == userId
      || resource.data.familyId == myFamilyId());
  // Egen doc skapas vid onboarding (skapa familj) och av SecondaryApp-flödet.
  allow create: if isAuth() && request.auth.uid == userId;
  allow update: if isAuth() && (
    // Jag själv: allt UTOM role och familyId.
    (request.auth.uid == userId
      && !request.resource.data.diff(resource.data).affectedKeys()
           .hasAny(['role', 'familyId'].toSet()))
    ||
    // Förälder: får ändra familjemedlemmar (namn, färg, roll, viewMode...) — aldrig familyId.
    (iAmParent() && resource.data.familyId == myFamilyId()
      && !request.resource.data.diff(resource.data).affectedKeys()
           .hasAny(['familyId'].toSet()))
  );
  allow delete: if isAuth() && iAmParent() && resource.data.familyId == myFamilyId();
}

match /families/{familyId} {
  // Endast medlemmar läser. Kodsökning vid join går via callable (admin-SDK).
  allow read: if isAuth() && familyId == myFamilyId();
  allow create: if isAuth();
  allow update: if isAuth() && familyId == myFamilyId() && iAmParent();
}

match /planner_events/{docId} {
  allow read: if isAuth() && resource.data.familyId == myFamilyId();
  allow create: if isAuth() && request.resource.data.familyId == myFamilyId()
      && request.resource.data.createdByUid == request.auth.uid;
  allow update: if isAuth() && resource.data.familyId == myFamilyId() && (
    iAmParent()
    || resource.data.createdByUid == request.auth.uid
    // Vem som helst i familjen får reagera — men bara röra reactions-fältet.
    || request.resource.data.diff(resource.data).affectedKeys()
         .hasOnly(['reactions'].toSet())
  );
  allow delete: if isAuth() && resource.data.familyId == myFamilyId()
      && (iAmParent() || resource.data.createdByUid == request.auth.uid);
}

match /chores/{docId} {
  allow read: if isAuth() && resource.data.familyId == myFamilyId();
  allow create: if isAuth() && request.resource.data.familyId == myFamilyId()
      && request.resource.data.createdByUid == request.auth.uid;
  allow update: if isAuth() && resource.data.familyId == myFamilyId() && (
    iAmParent()
    || resource.data.createdByUid == request.auth.uid
    // Avbockning (hela familjen får bocka av — föräldrar bockar åt barn):
    || request.resource.data.diff(resource.data).affectedKeys()
         .hasOnly(['isDone', 'doneSteps', 'doneDates'].toSet())
  );
  allow delete: if isAuth() && resource.data.familyId == myFamilyId()
      && (iAmParent() || resource.data.createdByUid == request.auth.uid);
}

match /work_shifts/{docId} {
  allow read: if isAuth() && resource.data.familyId == myFamilyId();
  allow create: if isAuth() && request.resource.data.familyId == myFamilyId() && iAmParent();
  allow update, delete: if isAuth() && resource.data.familyId == myFamilyId() && iAmParent();
}

match /routines/{docId} {
  allow read: if isAuth() && resource.data.familyId == myFamilyId();
  // Alla får bocka av steg; bara föräldrar redigerar rutinen själv.
  allow update: if isAuth() && resource.data.familyId == myFamilyId() && (
    iAmParent()
    || request.resource.data.diff(resource.data).affectedKeys()
         .hasOnly(['doneDate', 'doneSteps'].toSet())
  );
  allow create, delete: if isAuth()
      && request.resource.data.familyId == myFamilyId() && iAmParent();
}
```

Övriga collections (`family_notes`, `shopping_items`, `meals`, `busy_sessions`, `chore_templates`, `activity_templates`, `calendar_imports`, `countdowns`, `points_history`): behåll befintliga familjeregler oförändrade, MEN `busy_sessions.create` ska kräva `request.resource.data.userUid == request.auth.uid`, och `calendar_imports` alla operationer `iAmParent()`. MyMirai-blocken och catch-all `allow read, write: if false` behålls exakt som de är.

OBS: `weeklyPoints` lämnas medvetet skrivbart av en själv i denna fas — poängkoden lever tills Fas 2 tar bort den.

### 1.2 Callable `joinFamilyWithCode` i functions/index.js

```javascript
exports.joinFamilyWithCode = onCall(async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Inloggning krävs.");
    const { code, name, role } = request.data;
    if (!code || !name) throw new HttpsError("invalid-argument", "Kod och namn krävs.");

    const famSnap = await admin.firestore().collection("families")
        .where("inviteCode", "==", code.trim().toUpperCase()).limit(1).get();
    if (famSnap.empty) throw new HttpsError("not-found", "Ogiltig inbjudningskod.");
    const familyId = famSnap.docs[0].id;

    const safeRole = ["parent", "child", "youth"].includes(role) ? role : "child";
    // Återanvänd färglogiken: nästa lediga färg ur paletten (kopiera listan från app_theme.dart)
    const usersSnap = await admin.firestore().collection("users")
        .where("familyId", "==", familyId).get();
    const used = new Set(usersSnap.docs.map((d) => d.data().color).filter(Boolean));
    const PALETTE = ["ff2A6F97","ff8E3B46","ffC2654A","ff5C8D5C","ffB58A2C",
                     "ff6B5B95","ff3D5A6C","ff8C5E58","ff4F7942","ff8B6F47"];
    const color = PALETTE.find((c) => !used.has(c)) || PALETTE[usersSnap.size % PALETTE.length];

    await admin.firestore().collection("users").doc(request.auth.uid).set({
        uid: request.auth.uid,
        email: request.auth.token.email || "",
        name: name.trim(),
        familyId, role: safeRole, color,
        energy: 3, weeklyPoints: 0,
        viewMode: safeRole === "parent" ? "parent" : safeRole,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    return { familyId, familyName: famSnap.docs[0].data().name || "" };
});
```

Klienten (`onboarding_page._joinFamily` + `login_page` invite-dialogen): ersätt Firestore-läsningen/skrivningen med callable-anropet, och lägg till ett **rollval** i join-UI:t: tre stora knappar "Vuxen 👤 / Ungdom 🧑 / Barn 🧒" (default Barn). Ta bort all `role: 'member'`-kod.

### 1.3 `createdByUid` + UI-döljning

- Alla create-vägar för events/sysslor sätter `createdByUid`. (AddEventSheet, QuickAddBar, QuickChoreSheet, AddChoreSheet, kalenderimport, onboarding-seed.)
- Hjälpare i `person_match.dart` eller ny `lib/utils/permissions.dart`: `bool canEditDoc(UserModel? me, Map<String,dynamic> data)` → `me.isParent || data['createdByUid'] == me.uid`. Saknat `createdByUid` (legacy-data) ⇒ endast förälder.
- Använd i: aktivitetsdetaljer (redigera/radera-knappar), agenda-listornas menyer, sysslokortens radera, MemberDaySheet. Barn ser fortfarande allt och kan bocka av — de kan bara inte förstöra.

### 1.4 Städning
Ta bort Underhållskortet i Inställningar (knapparna för datummigrering + uid-backfill — båda körda 2026-06-11 enligt ROADMAP). Låt Cloud Functions ligga kvar tills gaten är godkänd, radera dem i Fas 2.

### Datafix efter deploy (Oscar gör manuellt i appen)
1. Hantera medlemmar → sätt fruns roll till **Vuxen** (fungerar nu tack vare nya reglerna).
2. Kontrollera barnens roller: 9+12 = Barn, 16+18 = Ungdom.
3. Verifiera att ditt eget konto har role parent/admin.

### Verifieringsgate Fas 1
- [ ] Logga in som barn: kan skapa egen aktivitet, kan bocka av sin syssla, kan reagera med emoji
- [ ] Samma barn: får PERMISSION_DENIED vid försök att radera förälders event (testa via UI — knappen ska inte ens synas)
- [ ] Barn kan inte ändra sin roll (testa att skriva `role` via en tillfällig debugknapp eller Firestore-konsol med barnets konto)
- [ ] Gå med i familj med kod → rollvalet respekteras, färg tilldelas, `member` förekommer inte längre (grep i koden + kolla nya dokument)
- [ ] Förälder kan byta namn/färg/roll på ett barn i Hantera medlemmar och det SPARAS
- [ ] Utloggad/främmande konto kan inte läsa `families` (verifiera i Rules Playground)
- [ ] Emoji-reaktion på annans event fungerar fortfarande (reactions-undantaget)
- [ ] `flutter analyze`: 0 errors/warnings

---

## ✅ FAS 2: Sysslor att lita på — statistik ersätter poäng

### Varför
`_onChoreCompleted` ger alltid 10 p till **den som trycker** (inte den tilldelade, inte sysslans utlovade poäng), TodayChoresSheet ger 0 p, av/på-bockning ger nya poäng varje gång, och poängen går inte att växla in mot något. Beslut: skrota poängekonomin, inför en **rättviselogg**.

### Datamodell
Ny collection `chore_log` (skrivs ENDAST av servern):
```
{ familyId, choreId, choreTitle, piktogram, weight (int, fd. points),
  whoUid, whoName, date ('YYYY-MM-DD'), completedAt (Timestamp) }
```
Dokument-ID: `{choreId}` för engångssysslor, `{choreId}_{date}` för återkommande (Fas 3) — gör loggen idempotent.

### Steg
**2.1 Callable `completeChore`** i functions/index.js: parametrar `{choreId, done, dateKey}`. Transaktion: verifiera samma familj; verifiera att anroparen är förälder, skaparen, den tilldelade (`whoUid`) ELLER att sysslan är otilldelad; vid `done` → skriv chore_log-dokumentet (deterministiskt ID) + `isDone: true`; vid `!done` → radera loggposten + `isDone: false`. `weight` = sysslans `points` ?? 0, `whoUid` = tilldelad om satt, annars anroparen.

**2.2 Klienten:** `chores_page.dart` och `today_chores_sheet.dart` byter isDone-skrivning + `UserService.addPoints` mot callable-anropet (optimistisk UI: bocka direkt, rulla tillbaka + snackbar vid fel). Konfettin behålls — den är firande, inte valuta. Ta bort: "+X ⭐"-utlovningar på korten, veckoliga/poängvisningar på Hem och i medlemsvyer, läs-timerns poängutdelning (timern behålls). Slidern i AddChoreSheet döps om till **"Vikt"** (1–5 stjärnor räcker — mappa 5/10/20/30/50 → 1–5) med förklaring "väger i statistiken".

**2.3 Delsteg klickbara:** `_ChoreCard`s delsteg blir checkboxar som skriver `doneSteps` (arrayUnion/arrayRemove med stegets titel). När alla delsteg är klara: föreslå avbockning av hela sysslan (auto-trigga callablen). Fixa också räknefelet i TodayChoresSheet ("X av Y klara" räknar just nu alltid 0 — `isDone`-filtreringen sker före räkningen).

**2.4 Statistikvyn** `lib/screens/chore_stats_page.dart`, nås via ikon i Sysslor-headern: segmentväljare Denna vecka / Förra veckan / 4 veckor. Per medlem: antal klarade + viktsumma som horisontella staplar i medlemmens färg. Tap på medlem → lista över loggposter (titel, dag, vikt). Query: `chore_log` where familyId + `completedAt` range. Tom state: "Inget loggat än — statistiken byggs när sysslor bockas av."

**2.5 Rules:** `chore_log`: `allow read` för familjen, `allow write: if false` (servern skriver via admin-SDK). `chores.update`-undantaget från Fas 1 justeras: ta bort `isDone` ur hasOnly-listan (nu går den vägen via callable), behåll `doneSteps`/`doneDates`.

**2.6 Riv:** `resetWeeklyPoints`-cronen, `UserService.addPoints`, `points_history`-regeln (och migreringsfunktionerna från Fas 1), `weeklyPoints`/`pointsResetDate` ur UserModel + alla vyer. Grep på `weeklyPoints|addPoints|points_history` ska ge noll träffar i lib/.

### Verifieringsgate Fas 2
- [ ] Barn bockar av sin tilldelade syssla (vikt 3) → chore_log-post med barnets uid och weight 3, oavsett vems telefon
- [ ] Bocka av → ångra → bocka av = EN loggpost (inte tre)
- [ ] Barn kan inte bocka av syskons tilldelade syssla (permission-denied från callablen)
- [ ] Delsteg går att bocka; alla delsteg klara → hela sysslan föreslås klar
- [ ] Statistiken visar rätt summor för två medlemmar över två veckor (lägg testdata)
- [ ] "X av Y klara" räknar rätt i TodayChoresSheet
- [ ] Inga poängreferenser kvar (grep) · flutter analyze grönt

---

## ⚡ FAS 2½: Prestanda (mellanklass-Android)

Mål: appen ska kännas native-smooth. Inga funktionsändringar, ingen ändrad visuell identitet (dagsfärger/gradienter/lågstimuli oförändrade). Inga ändringar i `firestore.rules` eller `functions`.

### Steg
**0. Mät före** med `flutter run --profile` + DevTools Performance (Hem/Familjen/Agenda). Anteckna janken (>16 ms). Samma mätning efter varje steg.

**1. Ta bort blur-navet** i `main.dart` `_buildBottomNav`: bort med `BackdropFilter`/`ImageFilter.blur`. Solid vit `Colors.white.withValues(alpha: 0.94)` på `BottomNavigationBar`; behåll border, radius, skugga, `extendBody`.

**2. Bundla Nunito lokalt** under `assets/fonts/` (Regular/SemiBold/Bold/ExtraBold), deklarera i `pubspec.yaml`, byt `google_fonts` i `app_theme.dart` mot `fontFamily: 'Nunito'`. Ta bort `google_fonts` om oanvänt.

**3. Central `MinuteTicker`** (`lib/utils/minute_ticker.dart`): `ValueNotifier<DateTime>` + periodisk timer (~20 s, uppdatera vid minutbyte). Ersätt `_minuteTicker` i dashboard; lägg till puls i `family_status_page`. Wrappa tidstexter i `ValueListenableBuilder` — inte hela sidan.

**4. Coalesca `FamilyProvider.notifyListeners`** (50 ms debounce + befintlig widget-debounce). Byt `context.watch` mot `context.select`/`Selector` för dataskivor per vy.

**5. WeekGrid förberäkna** `Map<uid, Map<dateKey, List>>` + recurrence-cache per `(docId, veckostart)` — cellerna slår bara upp.

**6. Datumbegränsa queries** i `FamilyWeekPage`/`AgendaPage`: `date` i fönster (vecka ±1 dag / synlig månad ±1 vecka) + separat `isRecurring`-ström som mergas (samma mönster som FamilyProvider). Kräver composite index `(familyId, date)`.

**7. `RepaintBoundary`** runt event-/sysslokort i agendan och WeekGrid-rader.

**8. Verifiera Impeller** via `adb logcat | grep -i impeller` — bara rapportera.

### Verifieringsgate Fas 2½
- [ ] Profile: scroll Hem/Familjen/Agenda utan röda staplar (>16 ms)
- [ ] En Firestore-ändring bygger inte om alla fyra flikar
- [ ] Kallstart i flygplansläge: rätt typsnitt direkt
- [ ] Hem + Familjestatus tickar minut utan full sid-rebuild
- [ ] Veckogrid mjuk med 6 medlemmar; Agenda visar samma events som före
- [ ] Lågstimuli oförändrat · `flutter analyze` grönt

---

## 🧹 FAS 2¾: Städning & modernisering

Mål: slimmad kodbas utan beteendeförändringar (enda funktionella tillägget: OfflineBanner). Rör inte `functions/index.js`.

### Steg
**1. Radera död kod:** `DashboardVariant.family`-grenen; flytta `AddEventSheet` till `lib/widgets/add_event_sheet.dart` och radera övriga `planner_page.dart`; verifiera att `android/.../com/example/myapp/` saknas.

**2. Ta bort `weekOf`-skrivningar** (chores/quick_add m.fl.). Fältet läses aldrig; gamla dokument behåller det ofarligt.

**3. Beroende-audit** i `pubspec.yaml`: ta bort oanvända direkta deps (inga versionshöjningar).

**4. `dart fix --apply`** + städa återstående analyze-info manuellt.

**5. `UserModel.colorValue` → `int`** (behåll try/catch-fallback).

**6. Byt `debugPrint`/`withOpacity`** mot `developer.log` / `withValues(alpha:)`.

**7. Repo-hygien:** radera `fix_context.js` och `.idx/`; `.firebase/` i `.gitignore` + bort från repo; arkivera `PROJECT_PLAN.md` + `GEMINI.md` under `docs/arkiv/`; skriv riktig `README.md`.

**8. Montera `OfflineBanner`** runt MainPage-innehållet. Ta bort punkten ur Fas 5.

**9. `firestore.rules`:** ta bort `screen_rules`-blocket (följer med i väntande rules-deploy).

### Verifieringsgate Fas 2¾
- [ ] `flutter analyze`: 0 errors, 0 warnings, ~0 info
- [ ] grep: `DashboardVariant.family`, `weekOf`, `withOpacity`, `debugPrint` → 0; `PlannerPage` → 0 utanför historik
- [ ] Smoke: skapa aktivitet, quick add, bocka syssla, statistik, flygplansläge → banner
- [ ] APK-storlek före/efter rapporteras

---

## 📐 FAS 2⅞: Stora skärmar — visa mer, inte större (Galaxy Fold)

Mål: på skärmar &lt; 600 dp ska allt vara pixel-identiskt. Breakpoints: kompakt &lt; 600, mellan 600–839, bred ≥ 840. Ingen uppskalning — mer synligt innehåll. Central hjälpare `lib/utils/layout.dart` (`WindowSize`).

### Steg
**1.** `main.dart`: ta bort 430-klämman. Kompakt = som idag. Expanded: innehåll upp till max ~1000 dp centrerat.

**2.** WeekGrid på bred: alla 7 dagar synliga, cellbredd = (bredd − avatar) / 7, upp till 4 händelser med emoji + tid + trunkerad titel.

**3.** Agenda på bred: Row — vänster ~40 % kalender + quick add, höger ~60 % vald dags lista.

**4.** Dashboard på bred: två kolumner (dagslinje/sysslor | rutin/ikväll/imorgon).

**5.** Statistik på bred: Denna vecka och Förra veckan sida vid sida.

**6.** Bottom sheets: maxWidth 560 centrerat på expanded.

**7.** Vikning: layout via `MediaQuery` varje build — inga cachade breddar i state.

### Verifieringsgate Fas 2⅞
- [ ] Fold uppfälld: mer innehåll per vy enligt ovan
- [ ] Fold hopfälld + vanlig mobil: oförändrat
- [ ] `flutter analyze` 0/0

---

## 🔁 FAS 3: Återkommande sysslor + rotation

### Varför
`'isRecurring': false` är hårdkodat i alla tre skrivvägar. "Diska varje kväll" är kärnan i sysslor för 4 barn. Recurrence-motorn finns redan (`lib/utils/recurrence.dart`) — återanvänd den.

### Steg
**3.1 Datamodell:** chores får `isRecurring: true` + samma `recurrence{}`-struktur som events (type daily/weekly/biweekly/monthly, startDate, endDate?, exceptions[]) + `doneDates: ['YYYY-MM-DD']` istället för `isDone`, + **`rotationUids: [uid...]`** (tom = fast person).

**3.2 Visning:** dagens sysslor = engångs (befintlig logik) + återkommande där `recurringOccursOnDay(data, day)` och `!doneDates.contains(dateKey(day))`. Central hjälpare i `lib/utils/chore_utils.dart` (ny): `choreOccursOnDay`, `choreDoneOnDay`, `assigneeForDay`.

**3.3 Rotation:** `assigneeForDay(chore, day)` = `rotationUids[occurrenceIndex % length]` där occurrenceIndex = antal förekomster sedan startDate (räkna via expandRecurrence — deterministiskt, inga skrivningar). Kortet visar "Idag: Liam · nästa gång: Ebba". `completeChore`-callablen får `dateKey`-parametern använd på riktigt: loggID `{choreId}_{dateKey}`, skriv `doneDates` arrayUnion/Remove istället för isDone, och whoUid = dagens rotationsperson (servern räknar om samma logik — kopiera occurrence-beräkningen till JS eller skicka med förväntad uid och validera att den ligger i rotationUids).

**3.4 UI i AddChoreSheet:** dropdown Engång / Varje dag / Varje vecka / Varannan vecka / Varje månad (+ veckodag där relevant, ärvd från valt datum) + multi-select av personer när återkommande ("roterar mellan: …"). 🔁-badge på korten.

**3.5 Notiser:** återkommande sysslor med dueTime → schemalägg instanser 14 dagar framåt med ID `{choreId}_{date}`, avboka instans när den bockas av. Samma mönster som events.

### Verifieringsgate Fas 3
- [ ] "Diska, varje dag, roterar Liam/Ebba/Alva" → rätt namn per dag, imorgon-nästa visas
- [ ] Bocka av idag → borta idag, tillbaka imorgon med nästa person
- [ ] Loggen får en post per dag med rätt barn — ångra samma dag tar bara bort dagens
- [ ] Engångssysslor fungerar exakt som innan
- [ ] Statistiken räknar återkommande korrekt över en vecka

---

## 🌙 FAS 4: Skiftschema för oregelbundna tider

### Varför
Nattpass (22–06) lagras på en dag och "slutar" före det börjar: `workShiftIsActiveNow` ger Ledig hela natten, konfliktdetektorn hoppar över passet, morgondagen visar inget. Dessutom: ingen redigering, inga mallar, ingen veckoöversikt.

### Steg
**4.1 Datamodell:** inga nya fält behövs — regeln blir: `endTime <= startTime` ⇒ passet korsar midnatt och slutar dagen efter. Central hjälpare i `schedule_time_utils.dart`:
```dart
/// Absolut intervall för ett pass. 22:00–06:00 på 2026-08-01 ⇒ 08-01 22:00 → 08-02 06:00.
({DateTime start, DateTime end}) shiftInterval(Map<String, dynamic> shift);
/// Pass som berör en given dag (startar den dagen ELLER nattpass från dagen innan).
bool shiftTouchesDay(Map<String, dynamic> shift, DateTime day);
```
Uppdatera `workShiftIsActiveNow`, `member_presence.dart` och `conflict_detector.dart` att gå via `shiftInterval` (ta samtidigt bort 1 h-gissningen för pass — pass har alltid sluttid). Visning på "fel" dag: "🌙 …–06 (natt från igår)".

**4.2 Veckoöversikt i `work_schedule_page.dart`:** överst en 7-dagarsrad (mån–sön) per förälder med passen som färgade block (starttid–sluttid, nattpass visas på båda dagarna). Under: befintliga månadskalendern för inmatning. Dagar med pass får markör i kalendern.

**4.3 Skiftmallar:** familydokumentet får `shiftTemplates: [{label, start, end}]`, seedat med Dag 06–14 / Kväll 14–22 / Natt 22–06. I inmatningsflödet: chips för mallarna (fyller tiderna) + "spara som mall" + långtryck raderar. Multiselect av dagar behålls — en skiftvecka blir: välj mall → markera dagar → spara, tre omgångar ≈ 8 tryck totalt.

**4.4 Redigering:** tap på pass (i veckoraden eller daglistan) → sheet med förifyllda tider → uppdatera dokumentet (idag kan pass bara raderas). Validering: samma start/slut ⇒ fel; endTime < startTime ⇒ visa "☾ slutar dagen efter" som bekräftelse, inte fel. Fixa också `if (shiftSnap.waiting && calSnap.waiting)`-buggen (ska vara `||`).

### Verifieringsgate Fas 4
- [ ] Lägg nattpass fre 22–06 → syns fredag OCH lördag morgon; familjestatus visar "Arbetar" kl 23 och kl 05
- [ ] Konfliktdetektorn flaggar krock mot nattpasset (lägg förälder 2 på event lör 05:30)
- [ ] Skiftvecka med tre mallar inlagd på under en minut
- [ ] Redigera ett pass utan att radera det
- [ ] Gamla pass (utan midnattskorsning) visas exakt som innan

---

## ⏰ FAS 5: Pålitlighet — appen ljuger aldrig om tid

OfflineBanner, minutticker och family_status är redan klara eller borttagna.

### Steg
**5.1 Midnatt i `FamilyProvider`:** `_subscribeToFamilyData` låste tidigare `dateKey(now)` vid prenumeration. Fix: spara `_subscribedDateKey`; `Timer` till nästa midnatt som re-prenumererar dagens/morgondagens events, meals och notes; förnyas efter varje körning; avbryts i dispose. Dessutom `AppLifecycleState.resumed` → om dateKey ändrats, re-prenumerera direkt (telefon i fickan över natten).

**5.2 `KalenderPage`:** om vald dag == gamla "idag" vid midnatt/resume → flytta valet till nya idag (alla fyra lägen).

**5.3 `rescheduleAllForFamily`:** vid appstart (`MainPage.initState`, efter providerns första data, fire-and-forget): avboka alla väntande lokala notiser, schemalägg om enligt togglarna — daterade events 14 dagar, återkommande event-instanser, sysslor med dueTime inkl. återkommande sysslors instanser. `idForDoc` = FNV-1a över codeUnits (inte `String.hashCode`).

**5.4 `TimerService`:** singleton (överlever flikbyte) + ljud/vibration vid noll; bakgrund via schemalagd/omedelbar lokal notis med ljud.

### Verifieringsgate Fas 5
- [ ] Ställ systemklockan till 23:59 → 00:01: Hem och Kalender visar nya dagen utan omstart
- [ ] Rensa appens notiser i systeminställningarna → starta om appen → påminnelser återschemalagda
- [ ] Timer som lämnas och öppnas igen tickar vidare och plingar vid noll

---

## 📅 FAS 6: Kalendern — Planering + Familjen blir EN vy

### Varför
Två flikar (Familjen + Planering) splittrade samma fråga: "vad händer när?". Närvaro bodde på en egen undersida, veckogriden dolde gemensamma events och arbetspass, och konflikter täckte bara vuxna — inte "barn ska iväg 17:00 och ingen förälder är ledig".

### Steg
**6.1 Nav:** bottennav `Hem · Kalender · Sysslor · Inställningar` (`main.dart`). Ikoner home / calendar_month / checklist / settings.

**6.2 KalenderPage** (`lib/screens/kalender_page.dart`):
- Header (gradient) + QuickAdd + FamilyNotesStrip + medlemsavatarer med närvaroprick (grön/gul/röd via `member_presence`); tap → MemberDaySheet för idag.
- Segmentväljare **Dag | Vecka | Månad | Agenda** — sparas i SharedPreferences (`kalender_lage`). Default: barn/ungdom → Dag, föräldrar → Vecka.
- Konflikt-chips (`detectAllConflicts`) i Dag/Vecka: vuxen-krock + 🚗-hämtning när alla föräldrar är upptagna. Samma "Jag tar det"-flöde (family_notes).
- FAB "Jag är upptagen". Föräldrar: ⋮-meny → Kalenderimport, Mat, Schema.

**6.3 Dag-vyn** (`lib/widgets/kalender_day_view.dart`) — enda nybygget:
- Datumrad (‹ ›, Idag, swipe). Kolumn per medlem (scroll på telefon, alla på Fold).
- Skolblock, aktiviteter, arbetspass, bockbara sysslor; "+" → AddEventSheet förifyllt. Gemensamma events full bredd över kolumnerna.

**6.4 Vecka:** WeekGrid med Familjen-rad (events utan personer) + arbetspass-rand via `shiftTouchesDay`.

**6.5 Månad / Agenda:** TableCalendar + daglista respektive rullande blandad lista (återanvänder AgendaActivityRow / AgendaChoreRow).

**6.6 SysslorPage:** egen flik — idag/öppna/klara, mallstrip, snabb syssla, statistik, lästimer.

**6.7 Rivning:** FamilyWeekPage + FamilyStatusPage bort. ChoresPage-klassen raderad (AddChoreSheet/QuickChoreSheet kvar). AgendaPage behålls som widget-bibliotek för list-rader. Energiväljaren finns i MemberDaySheet.

### Verifieringsgate Fas 6 (telefon + Fold)
- [ ] Fyra flikar, rätt innehåll, inga döda länkar till gamla sidor
- [ ] Dag-vyn: kolumner, skolblock + pass + sysslor, bocka syssla i kolumn, + förifyllt
- [ ] Vecka/Månad/Agenda beter sig som före flytten (+ Familjen-rad / pass-rand)
- [ ] Lägesval minns; barnkonto landar i Dag
- [ ] Närvaroprickar stämmer; konflikt + 🚗-chip vid testdata
- [ ] Lågstimuli fungerar i alla fyra lägen
- [ ] `flutter analyze` 0 issues. Ingen functions/rules-deploy.

---

## 📱 FAS 7: iPhone via PWA + serverpåminnelser

### Varför
16- och 18-åringen har iPhone; repot saknar ios/. Beslut: PWA. Web saknar lokala notiser ⇒ påminnelser för webbanvändare måste skickas från servern via FCM web push (funkar på iOS 16.4+ när appen lagts på hemskärmen).

### Steg
**7.1 Manifest + service worker:** `web/manifest.json` (name "La Familia", short_name, display standalone, theme_color #2A6F97, maskable-ikoner 192+512). Ny `web/firebase-messaging-sw.js` med Firebase-config + `onBackgroundMessage`. Generera VAPID-nyckel i Firebase Console (Cloud Messaging → Web Push certificates).

**7.2 `PushService` på web:** `kIsWeb`-gren: begär Notification-tillstånd EFTER användargest (knapp "Aktivera notiser 🔔" i Inställningar — iOS kräver gest, ingen auto-prompt), hämta token med `getToken(vapidKey: ...)`, spara i **`webFcmTokens`** (SEPARAT array från `fcmTokens` — så Android-telefoner inte får dubbla påminnelser). `sendFamilyPush` i functions får en `tokenField`-parameter (default `fcmTokens`) och familjepushar (lappar/sysslor/reaktioner) skickas till BÅDA fälten.

**7.3 Serverpåminnelser (endast web-tokens):** ny schemalagd funktion var 5:e minut (Europe/Stockholm):
- Hämta dagens events (date == dateKey(idag)) + alla isRecurring som infaller idag (porta `recurringOccursOnDay` till JS — den är ~30 rader).
- För varje event med tid: om start ligger 13–17 min bort ⇒ "⏰ {titel} börjar om 15 min"; 8–12 min ⇒ övergångsvarningen "🔄 Snart dags att byta". Mottagare: personUids (eller hela familjen om tomt), ENDAST `webFcmTokens`, med befintliga filtren (energi, upptagen, toggle).
- Dubblettskydd: `sent_reminders/{eventId}_{date}_{typ}` skrivs före utskick; nattcronen städar poster äldre än 2 dagar.

**7.4 Installations-hjälp:** på login-sidan och i Inställningar, om `kIsWeb` + iOS Safari + inte standalone (`display-mode`): kort med "Så får du appen på hemskärmen: Dela-knappen → Lägg till på hemskärmen" + att notiser aktiveras efteråt via Inställningar. Verifiera att `firebase.json`-hostingen inte cachar `firebase-messaging-sw.js` hårt (sätt no-cache-header för just den).

### Verifieringsgate Fas 7 (kräver en riktig iPhone)
- [ ] Lägg till på hemskärmen → appen öppnas standalone med ikon och rätt färg
- [ ] "Aktivera notiser" → tillstånd → token dyker upp i webFcmTokens
- [ ] Familjelapp från Android-mobil → pling på iPhonen (även med appen stängd)
- [ ] Event om 16 min på 16-åringen → serverpåminnelse på iPhonen; Android-mobilen får INTE dubbel (lokal + push)
- [ ] Reaktioner och tilldelad syssla plingar på iPhonen
- [ ] Energi Låg / Upptagen-session stoppar pushar även till web

---

## 🧹 FAS 8 (backlog, i valfri ordning när ovan sitter)
- Kalenderimport 2.0: RRULE-expansion (skolscheman/Sportadmin är nästan alltid återkommande — idag importeras bara första förekomsten), UTC-fix (Z-tider tolkas nu som lokal tid), "Uppdatera"-knapp med dedupe på UID. Tills detta är gjort: lägg en varningstext i import-vyn.
- Åldersanpassade vyer: aktivera `isChildMode`/`isYouthMode` (finns i modellen, används aldrig) — barnläge = stora kort, ingen månadskalender.
- Quick add: redigerbara chips i bekräftelsebladet (idag går tolkningen inte att rätta), sluttid ("17–18"), dueTime för sysslor (idag får quick add-sysslor aldrig påminnelse eftersom dueTime saknas).
- Migrera Hantera medlemmar från SecondaryApp-hacket till `createUser`-callablen (deployad sedan länge) + radera Auth-konto när medlem tas bort.
- ISO 8601-veckonummer (nu `.ceil()` på dagdiff — kan ge fel vecka), inköpslistans kategorier/"rensa klara", README.

---

## 📌 Arbetsflöde
1. Klistra in EN fas i Cursor: *"Här är Fas X från PROJECT_PLAN_V3.md. Implementera enligt planen, stoppa vid verifieringsgaten."*
2. Kör gaten själv på riktiga enheter (Fas 1–2 kräver två konton: ett förälder-, ett barnkonto).
3. Rapportera resultat + avvikelser till Claude (hjärnan) innan nästa fas — särskilt om Cursor avvikit från reglerna i Fas 1, de är säkerhetskritiska.
4. Firestore-backup före Fas 1 och Fas 2 (`gcloud firestore export`), reglerna deployas först efter granskning.
5. Uppskattning: Fas 1–2 en helg vardera, Fas 3–5 ~en helg ihop, Fas 6 en helg, Fas 7 en helg + iPhone-testkväll.
