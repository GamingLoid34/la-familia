# 🗺️ La Familia – Utvecklingsplan v2

Det här är en faseindelad plan för att lyfta La Familia från "fungerar" till "polerad familjeapp för NPF-användare". Varje fas är fristående och tänkt att klistras in i Cursor Agent i sin helhet. Mellan varje fas finns en verifieringsgate — kör appen, testa, godkänn innan nästa fas.

---

## 🛠️ Globala konventioner (läs först, gäller alla faser)

**Arbetsflöde mellan oss:**
- Cursor utför EN fas i taget. Stoppa vid varje verifieringsgate.
- Skapa nya filer hellre än att stoppa in mer i befintliga "gud-filer" som `dashboard_page.dart`.
- Inga `catch (_) {}` — använd `developer.log('beskrivning', error: e, stackTrace: stack)`.
- Inga `withOpacity` i ny kod — använd `withValues(alpha: x)` som resten av kodbasen.
- Alla Firestore-skrivningar måste innehålla `familyId` (säkerhetsreglerna kräver det).
- Datum sparas som strängar i format `YYYY-MM-DD` (zero-padded) ELLER `Timestamp`. Inga `${now.year}-${now.month}-${now.day}` utan padding (det är en bugg vi rättar i Fas 5).
- Tider sparas som zero-padded `HH:mm` strängar (redan konventionen).
- Mobil-först. Inga UI-element som blir över 430px breda.

**Hur Cursor ska kommunicera:**
- Lista berörda filer först, sedan ändringarna.
- Visa fullständiga filer för nya filer. Visa diff för ändringar i befintliga filer.
- Efter implementation: lista hur jag (utvecklaren) verifierar att det funkar.

**Stoppkriterier för Cursor:**
- Om en fas kräver att en annan fas är färdig — stoppa och berätta.
- Om Flutter-kompilering misslyckas — visa felet, gör inte fler ändringar förrän jag svarat.
- Om Firestore-regler behöver ändras — visa nya regler och stoppa innan jag deployar.

---

## 🎨 FAS 1: Färger och identitet

### Mål
Lös tre sammanhängande problem:
1. Alla medlemmar har default-färgen `ff6bae75` (måndagens NPF-grön) eftersom onboarding aldrig sätter någon färg. Resultat: namnen är osynliga på måndagar och alla ser likadana ut.
2. Färgpaletten i `manage_members_page.dart` blandar grälla Material-färger med dämpade NPF-färger — de talar inte samma visuella språk.
3. Launcher-ikonen är en logga på vit bakgrund. Inga av appens karaktärsdrag syns där.

### Berörda filer
- `lib/app_theme.dart` — lägg till medlemspalett som en konstant.
- `lib/models/user_model.dart` — uppdatera default-färgen.
- `lib/screens/onboarding_page.dart` — tilldela unik färg automatiskt vid registrering.
- `lib/screens/manage_members_page.dart` — byt ut den hårdkodade `_colors`-listan mot den nya paletten.
- `lib/services/family_service.dart` — ny funktion `assignNextAvailableColor(familyId)`.
- `lib/main.dart` — kör backfill för befintliga användare med default-färgen.
- `assets/images/logo.png` — ny ikon (eller `assets/icon/icon.png`).
- `pubspec.yaml` — uppdatera `flutter_launcher_icons`-konfig.

### Steg

**1.1 Definiera medlemspaletten i `app_theme.dart`**

Lägg till längst upp i klassen `AppTheme`, under NPF-färgerna:

```dart
// ─── Member Colors ─────────────────────────────────────────────────────────
/// Personliga medlemsfärger, dämpade för att harmoniera med NPF-dagsfärgerna
/// men distinkta nog för att synas mot dem som bakgrund.
/// ORDNING ÄR VIKTIG — assignNextAvailableColor tilldelar i ordningen nedan.
static const List<String> memberColorPalette = [
  'ff2A6F97', // Djup petrol
  'ff8E3B46', // Plommon
  'ffC2654A', // Terracotta
  'ff5C8D5C', // Mossgrön
  'ffB58A2C', // Ockra
  'ff6B5B95', // Lavendel
  'ff3D5A6C', // Skifferblå
  'ff8C5E58', // Rost
  'ff4F7942', // Skog
  'ff8B6F47', // Kamel
];

/// Returnerar en Color från hex-sträng (utan '#').
static Color colorFromHex(String hex) {
  try {
    return Color(int.parse(hex.startsWith('0x') ? hex : '0xFF${hex.substring(hex.length > 6 ? 2 : 0)}', radix: 16));
  } catch (_) {
    return colorFromHex(memberColorPalette.first);
  }
}
```

**1.2 Uppdatera default-färgen i `user_model.dart`**

Byt rad 4946 från `data['color'] ?? 'ff6bae75'` till `data['color'] ?? AppTheme.memberColorPalette.first` (importera app_theme).

**1.3 Ny service-funktion i `family_service.dart`**

```dart
/// Returnerar nästa lediga färg från paletten för en given familj.
/// Om alla färger är tagna, börjar om från början.
static Future<String> assignNextAvailableColor(String familyId) async {
  final snap = await FirebaseFirestore.instance
      .collection('users')
      .where('familyId', isEqualTo: familyId)
      .get();
  final usedColors = snap.docs
      .map((d) => (d.data()['color'] as String?) ?? '')
      .where((c) => c.isNotEmpty)
      .toSet();
  for (final color in AppTheme.memberColorPalette) {
    if (!usedColors.contains(color)) return color;
  }
  // Alla tagna — börja om
  return AppTheme.memberColorPalette[
      usedColors.length % AppTheme.memberColorPalette.length];
}
```

**1.4 Tilldela färg i `onboarding_page.dart`**

I `_createFamily()` och `_joinFamily()`, innan `users.doc(user.uid).set(...)`:

```dart
final assignedColor = await FamilyService.assignNextAvailableColor(familyId);
// ... och inkludera 'color': assignedColor i set-anropet
```

**1.5 Byt palett i `manage_members_page.dart`**

Ta bort hela `_colors`-listan på rad 10774-10785. Ersätt alla referenser med `AppTheme.memberColorPalette`. Default `_selectedColor = AppTheme.memberColorPalette.first` istället för `'ff2196f3'`.

**1.6 Backfill för befintliga användare**

I `main.dart`, efter Firebase init men innan `runApp`, lägg till ett engångsanrop som körs när auth blir tillgänglig. Skapa istället en ny fil `lib/services/migration_service.dart`:

```dart
class MigrationService {
  /// Tilldelar en unik medlemsfärg till användare som har default-grön
  /// eller saknar färg. Idempotent — säker att köra varje uppstart.
  static Future<void> backfillMemberColors() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final myDoc = await FirebaseFirestore.instance
          .collection('users').doc(uid).get();
      if (!myDoc.exists) return;
      final data = myDoc.data()!;
      final currentColor = data['color'] as String?;
      final familyId = data['familyId'] as String?;
      if (familyId == null || familyId.isEmpty) return;

      // Kör bara om användaren har gamla default-färgen eller saknar färg
      if (currentColor == null || currentColor == 'ff6bae75') {
        final newColor = await FamilyService.assignNextAvailableColor(familyId);
        await FirebaseFirestore.instance
            .collection('users').doc(uid).update({'color': newColor});
      }
    } catch (e, stack) {
      developer.log('backfillMemberColors error', error: e, stackTrace: stack);
    }
  }
}
```

Anropa från `FamilyCheckWrapper` i `main.dart` efter att användaren har laddat: `MigrationService.backfillMemberColors();` (fire-and-forget, blockera inte UI).

**1.7 Launcher-ikon**

Generera en ny enkel adaptiv ikon:
- Bakgrund: `#2A6F97` (samma som första medlemsfärgen — appens "primärfärg")
- Förgrund: ett vitt "❤️" eller stiliserad "F"-bokstav, centrerad
- Spara som `assets/icon/icon.png` (1024x1024)

Uppdatera `pubspec.yaml`:
```yaml
flutter_launcher_icons:
  android: true
  ios: false
  image_path: "assets/icon/icon.png"
  adaptive_icon_background: "#2A6F97"
  adaptive_icon_foreground: "assets/icon/icon_foreground.png"
  min_sdk_android: 21
```

Cursor: om du inte kan generera bilder, skapa istället **bara konfigurationen** och en placeholder-kommentar `// TODO: Oscar genererar nya ikoner manuellt i Figma och kör flutter pub run flutter_launcher_icons`.

### Verifieringsgate Fas 1

Kör appen och kontrollera:
- [ ] Skapa ny familj → din färg är inte längre `ff6bae75`
- [ ] Lägg till barn via Hantera medlemmar → barnet får en ny färg automatiskt (om du inte explicit valt)
- [ ] Befintlig användare som loggar in → får ny färg om gamla var grön
- [ ] Två medlemmar i samma familj har ALDRIG samma färg (om familjen är ≤ 10 medlemmar)
- [ ] Färgväljaren i Hantera medlemmar visar 10 dämpade färger, inga grälla blå/röda
- [ ] Namnet syns tydligt mot alla 7 dagsbakgrunder (testa genom att tillfälligt ändra `DateTime.now().weekday` till varje veckodag i `getDayAccentColor`)

---

## 💬 FAS 2: Familjeklotter (kontextuella meddelanden)

### Mål
Bygga ett smalt meddelandesystem som lever bredvid schemat — INTE en full chatt. Två funktioner:

1. **Dagsnotiser**: Varje medlem kan släppa 1-3 korta meddelanden per dag på "familjedagstavlan". Synliga på Familjen-fliken under datumet.
2. **Eventreaktioner**: Snabba emoji-reaktioner på planerade events ("Lycka till! 💪", "Vi ses 🥐"). En medlem kan lägga max 1 reaktion per event.

Båda funktionerna respekterar presence — om någon är "Upptagen" skickas ingen push (Fas 3 sätter upp pushar; Fas 2 förbereder datat).

### Berörda filer
**Nya:**
- `lib/models/family_note.dart` — datamodell
- `lib/widgets/family_notes_strip.dart` — widget för dagstavlan
- `lib/widgets/event_reactions_row.dart` — reaktioner på events
- `lib/widgets/add_family_note_sheet.dart` — bottom sheet för att lägga till notis

**Ändrade:**
- `firestore.rules` — regler för `family_notes` collection
- `lib/providers/family_provider.dart` — prenumerera på dagens notiser
- `lib/screens/dashboard_page.dart` — visa `FamilyNotesStrip` i Familjen-variant
- `lib/widgets/activity_detail_sheet.dart` — visa och tillåt reaktioner
- `functions/index.js` — Cron som rensar gamla notiser (>7 dagar)

### Datamodell

**Firestore collection: `family_notes`**
```
{
  id: auto,
  familyId: string,
  fromUid: string,
  fromName: string,
  fromColor: string,
  date: string ('YYYY-MM-DD', zero-padded),
  createdAt: Timestamp,
  text: string (max 140 tecken),
  expiresAt: Timestamp (7 dagar efter createdAt)
}
```

**Utökning av `planner_events`:**
Lägg till en `reactions`-map:
```
{
  // ... befintliga fält
  reactions: {
    [uid]: {
      emoji: string,
      name: string,
      color: string,
      at: Timestamp
    }
  }
}
```

### Steg

**2.1 Skapa `family_note.dart`**

```dart
import 'package:cloud_firestore/cloud_firestore.dart';

class FamilyNote {
  final String id;
  final String familyId;
  final String fromUid;
  final String fromName;
  final String fromColor;
  final String date; // YYYY-MM-DD
  final DateTime createdAt;
  final String text;

  const FamilyNote({
    required this.id,
    required this.familyId,
    required this.fromUid,
    required this.fromName,
    required this.fromColor,
    required this.date,
    required this.createdAt,
    required this.text,
  });

  factory FamilyNote.fromDoc(QueryDocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return FamilyNote(
      id: doc.id,
      familyId: d['familyId'] ?? '',
      fromUid: d['fromUid'] ?? '',
      fromName: d['fromName'] ?? '',
      fromColor: d['fromColor'] ?? '',
      date: d['date'] ?? '',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      text: d['text'] ?? '',
    );
  }
}
```

**2.2 Uppdatera `firestore.rules`**

Lägg till INNAN catch-all-regeln längst ner:

```
match /family_notes/{docId} {
  allow read: if isAuth() && resource.data.familyId == getUserFamilyId();
  allow create: if isAuth() 
    && request.resource.data.familyId == getUserFamilyId()
    && request.resource.data.fromUid == request.auth.uid
    && request.resource.data.text.size() <= 140;
  allow delete: if isAuth() 
    && resource.data.familyId == getUserFamilyId()
    && resource.data.fromUid == request.auth.uid;
  // Notiser är inte editerbara — radera och skapa ny
  allow update: if false;
}
```

**Reaktioner på planner_events**: Befintliga regler tillåter `update` om man är i samma familj. Det räcker — men lägg en kommentar i `firestore.rules` att `reactions`-fältet är avsett för medlemmar att uppdatera fritt.

**2.3 Backfilla notiserna i `FamilyProvider`**

Lägg till en stream för dagens notiser i `_subscribeToFamilyData`:

```dart
StreamSubscription? _notesSub;
List<FamilyNote> _todayNotes = [];
List<FamilyNote> get todayNotes => _todayNotes;

// ... i _subscribeToFamilyData:
_notesSub?.cancel();
final today = _todayDateKey(); // YYYY-MM-DD zero-padded — använd helper
_notesSub = FirebaseFirestore.instance.collection('family_notes')
    .where('familyId', isEqualTo: familyId)
    .where('date', isEqualTo: today)
    .snapshots().listen((snap) {
  _todayNotes = snap.docs.map((d) => FamilyNote.fromDoc(d)).toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  notifyListeners();
});

String _todayDateKey() {
  final n = DateTime.now();
  return '${n.year.toString().padLeft(4, '0')}-'
         '${n.month.toString().padLeft(2, '0')}-'
         '${n.day.toString().padLeft(2, '0')}';
}
```

Notera: det här är *zero-padded* — vilket inte matchar resten av kodbasen ännu. Det fixas i Fas 5. För Fas 2 räcker det att vi använder padded format för notiser eftersom det är ny data.

**2.4 Bygg `FamilyNotesStrip`**

En kompakt horisontell rad med dagens notiser + en "Lägg till"-knapp först. Varje notis är ett kort med medlemmens färg som border-left, namn i färg, text under, och en liten timestamp ("nyss", "för 2h sedan"). Klicktryck på egen notis → bekräftelsedialog "Ta bort?".

Visa endast i `DashboardVariant.family`. Tom state: "Inga noteringar idag. Lägg till en?" med plus-knapp.

**2.5 Bygg `AddFamilyNoteSheet`**

`ModalBottomSheet` med ett TextField (max 140 tecken, räknare), 4-6 snabbtryck-mallar:
- "På väg hem 🚗"
- "Sover middag 😴"
- "Behöver bli hämtad"
- "Lite seg idag"
- "Allt bra! ✨"
- "Lämnar kl ___"

Skickar `family_notes.add({...})`.

**2.6 Bygg `EventReactionsRow`**

Inuti `ActivityDetailSheet`, under titel/tid: en rad med 6 reaktions-emojis (`💪`, `❤️`, `🎉`, `🍀`, `🚗`, `🥐`). Om jag har reagerat, är min reaktion markerad. Klick igen → tar bort min reaktion.

Visa även befintliga reaktioner som små chips: "Mamma 💪 · Pappa 🍀".

Skriv via `planner_events.doc(id).update({ 'reactions.<uid>': {...} })` eller `FieldValue.delete()` för borttagning.

**2.7 Cleanup-cron i `functions/index.js`**

```javascript
exports.cleanupOldFamilyNotes = onSchedule({
    schedule: "0 3 * * *", // 03:00 varje natt
    timeZone: "Europe/Stockholm"
}, async (event) => {
    const db = admin.firestore();
    const cutoff = new Date();
    cutoff.setDate(cutoff.getDate() - 7);
    
    const oldNotes = await db.collection("family_notes")
        .where("createdAt", "<", cutoff)
        .get();
    
    let batch = db.batch();
    let count = 0;
    for (const doc of oldNotes.docs) {
        batch.delete(doc.ref);
        count++;
        if (count >= 400) {
            await batch.commit();
            batch = db.batch();
            count = 0;
        }
    }
    if (count > 0) await batch.commit();
    console.log(`Tog bort ${oldNotes.size} gamla notiser.`);
    return null;
});
```

### Verifieringsgate Fas 2

- [ ] Öppna Familjen-fliken → ser tom notisstrip med "Lägg till"-knapp
- [ ] Lägg till notis → den visas direkt (StreamBuilder reagerar)
- [ ] Logga in som annan familjemedlem → ser samma notis
- [ ] Reagera på ett event → annan medlems telefon visar reaktionen direkt
- [ ] Två medlemmar kan ha olika reaktioner på samma event
- [ ] Ta bort min reaktion → bara mina försvinner, andras är kvar
- [ ] Notiser >140 tecken blockeras (testa via Firestore-konsolen att skriva för långa)
- [ ] Loggade-ut användare kan inte läsa notiser (verifiera reglerna)

---

## 🔔 FAS 3: Aktivera notifikationer

### Mål
`NotificationService` är installerad och initierad men anropas aldrig. Resultat: togglarna i Inställningar är teater. Den här fasen hooker ihop den med planer och sysslor.

### Berörda filer
- `lib/services/notification_service.dart` — utöka med stöd för sysslor och tider
- `lib/screens/planner_page.dart` (`AddEventSheet`) — schemalägg/avboka vid skapa/ta bort
- `lib/screens/chores_page.dart` — schemalägg påminnelse om syssla har dueDate och time
- `lib/screens/settings_page.dart` — gör så togglarna faktiskt avbokar alla väntande
- `android/app/src/main/AndroidManifest.xml` — behörigheter
- `lib/main.dart` — be om notif-tillstånd vid första uppstart

### Steg

**3.1 Utöka `notification_service.dart`**

```dart
class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  // Befintlig initialize() ...

  /// Genererar ett deterministiskt int-ID från en Firestore docId.
  static int idForDoc(String docId) {
    return docId.hashCode & 0x7FFFFFFF; // alltid positivt
  }

  /// Aktiviteter — påminnelse 15 min innan start.
  static Future<void> scheduleActivityReminder({
    required String docId,
    required String title,
    required DateTime startTime,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('notifActivity') ?? true)) return;
    final scheduled = startTime.subtract(const Duration(minutes: 15));
    if (scheduled.isBefore(DateTime.now())) return;
    await _plugin.zonedSchedule(
      idForDoc(docId),
      'Aktivitet börjar snart ⏰',
      '$title börjar om 15 minuter.',
      tz.TZDateTime.from(scheduled, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'activity_channel',
          'Aktiviteter',
          channelDescription: 'Påminnelser för aktiviteter',
          importance: Importance.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  /// Sysslor — påminnelse på given tid.
  static Future<void> scheduleChoreReminder({
    required String docId,
    required String title,
    required DateTime dueAt,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('notifChore') ?? true)) return;
    if (dueAt.isBefore(DateTime.now())) return;
    await _plugin.zonedSchedule(
      idForDoc(docId),
      'Syssla att göra ✅',
      title,
      tz.TZDateTime.from(dueAt, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'chore_channel',
          'Sysslor',
          channelDescription: 'Påminnelser om sysslor',
          importance: Importance.defaultImportance,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  static Future<void> cancel(String docId) =>
      _plugin.cancel(idForDoc(docId));

  static Future<void> cancelAll() => _plugin.cancelAll();

  /// Be om tillstånd (Android 13+).
  static Future<bool> requestPermissions() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final granted = await android?.requestNotificationsPermission() ?? false;
    return granted;
  }
}
```

**3.2 AndroidManifest.xml — behörigheter**

I `<manifest>`-elementet, lägg till:

```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
<uses-permission android:name="android.permission.USE_EXACT_ALARM"/>
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
```

**3.3 Hooks i `planner_page.dart` (AddEventSheet)**

I `_saveEvent`-funktionen, efter `set/add`:
- Om event har `time` och inte är i det förflutna:
  ```dart
  final start = DateTime(d.year, d.month, d.day, hour, minute);
  await NotificationService.scheduleActivityReminder(
    docId: savedDocId,
    title: title,
    startTime: start,
  );
  ```
- Om edit → först `NotificationService.cancel(oldDocId)` innan ny schemalägging.

I delete-flödet (där events kan tas bort), lägg till `NotificationService.cancel(docId)`.

**3.4 Hooks i `chores_page.dart`**

Liknande: om en syssla får `dueDate` och `dueTime`, schemalägg. Annars inte. Avboka vid radering eller när `isDone = true`.

**3.5 Settings-togglar ska faktiskt göra något**

I `settings_page.dart`, när `_notifActivity` toggles av → `NotificationService.cancelAll()` (enkel approach; alternativ: cancel bara aktivitets-IDn — komplicerat utan att hålla extra register). Lägg en informationsdialog: "Avbokar alla väntande aktivitetspåminnelser. Nya händelser schemaläggs igen om du slår på."

**3.6 Tillståndsbegäran**

I `main.dart`, efter `NotificationService.initialize()`, om plattform är Android: kör inte direkt utan vänta tills användaren är inloggad och inne i `MainPage`. Lägg en första-gångs-check i `MainPage.initState`:

```dart
SharedPreferences.getInstance().then((prefs) {
  if (prefs.getBool('notifPermissionAsked') != true) {
    NotificationService.requestPermissions().then((_) {
      prefs.setBool('notifPermissionAsked', true);
    });
  }
});
```

### Verifieringsgate Fas 3

Krävs fysisk Android-enhet (emulator notifikationer är opålitliga).

- [ ] Skapa en aktivitet kl. nu+16 minuter → notis ploppar upp efter 1 minut
- [ ] Skapa aktivitet kl. nu+10 minuter → ingen notis (inom 15-min-fönstret)
- [ ] Radera aktiviteten → notisen avbokad (gå till Inställningar → Appar → Notiser för att verifiera)
- [ ] Slå av "Aktivitet börjar snart" i Inställningar → nya events får ingen notis
- [ ] Stäng appen → notisen poppar upp ändå (lokala notiser, inte FCM)
- [ ] Starta om enheten → notisen poppar upp (RECEIVE_BOOT_COMPLETED behörigheten)
- [ ] Syssla med dueDate och dueTime → påminnelse fungerar

---

## 📅 FAS 4: Veckogrid + konfliktdetektering

### Mål
Slå ihop Dashboard-Familjen och Familjestatus till en sammanhängande Familjevy. Lägg till en **veckogrid** som visar hela familjens vecka i ett ögonkast. Detektera krockar mellan vuxnas scheman och föreslå vem som kan hämta/lämna.

### Berörda filer
**Nya:**
- `lib/screens/family_week_page.dart` — den nya samlingsvyn
- `lib/widgets/week_grid.dart` — själva gridden
- `lib/widgets/conflict_banner.dart` — varnar om vuxna är dubbelbokade
- `lib/utils/conflict_detector.dart` — logik

**Ändrade:**
- `lib/main.dart` (`MainPage`) — `DashboardPage(variant: family)` ersätts med `FamilyWeekPage`
- `lib/screens/dashboard_page.dart` — ta bort family-varianten (den blir för splittrad annars)

### Datamodell
Inga schemaändringar — vi använder bara befintlig data smartare.

### Steg

**4.1 `conflict_detector.dart`**

```dart
class ScheduleConflict {
  final DateTime start;
  final DateTime end;
  final List<UserModel> involvedAdults;
  final List<QueryDocumentSnapshot> events;
  // "Båda föräldrar har ett event som överlappar"
}

List<ScheduleConflict> detectAdultConflicts({
  required List<UserModel> family,
  required List<QueryDocumentSnapshot> events,
  required List<QueryDocumentSnapshot> workShifts,
  required DateTime weekStart,
  required DateTime weekEnd,
}) {
  // 1. Filtrera till vuxna (role == 'parent' || 'admin')
  // 2. Bygg occupied intervals per vuxen från events + work_shifts
  // 3. För varje tidsslot där > 1 vuxen är upptagen, skapa en ScheduleConflict
  // 4. Returnera sorterat på start
}
```

**4.2 `week_grid.dart`**

Layout: 7 kolumner (Mån–Sön) × N rader (familjemedlemmar). Header med datum + dagens veckodag. Varje cell visar upp till 2 events kompakt (emoji + tid). "Mer"-indikator om fler. Klick på cell → öppna `MemberDaySheet` för (medlem, dag).

Veckonavigering: föregående/nästa, "Idag"-knapp.

Mobiloptimering: gridd kan scrollas horisontellt. Eller bättre: visa 3 dagar i taget med swipe.

**4.3 `conflict_banner.dart`**

Om `detectAdultConflicts` returnerar något, visa en horisontell scrollbar med banners ovanför griden. Varje banner: "🚨 Tis 16:00 – båda föräldrar upptagna" + klick öppnar detaljvy.

Detaljvy ger förslag: "Vem hämtar [barnens aktivitet under den tiden]?" — om barn har event i samma slot kan vi föreslå hämtningsansvarig. Tillfällig "Jag tar det"-knapp som skapar ett `family_note` av typen "ansvarig för hämtning kl X".

**4.4 `family_week_page.dart`**

Struktur:
```
[Header med veckodatum + navigation]
[ConflictBanner (om någon)]
[FamilyNotesStrip — flyttad hit från dashboard]
[WeekGrid]
[FAB: "Jag är upptagen"]
```

**4.5 Uppdatera `main.dart`**

```dart
_pages = [
  const DashboardPage(variant: DashboardVariant.me),
  const FamilyWeekPage(), // <-- ersätter DashboardPage.family
  const AgendaPage(initialTab: AgendaTab.all),
  const SettingsPage(),
];
```

Och ta bort `DashboardVariant.family`-grenen i `dashboard_page.dart` (eller behåll men markera deprecated tills migrationen är beprövad).

### Verifieringsgate Fas 4

- [ ] Familjen-fliken visar ny veckogrid
- [ ] Veckan navigerbar fram/tillbak
- [ ] Klick på cell → öppnar dagsbladet för rätt medlem
- [ ] Skapa två överlappande events för två föräldrar → konfliktbanner visas
- [ ] Notiser från Fas 2 visas fortfarande
- [ ] "Jag är upptagen"-FAB fungerar
- [ ] Ingen white-flash vid sidbyte (PageController från MainPage håller liv)
- [ ] Performance: scroll i grid är 60fps på testenheten

---

## 🔁 FAS 5: Återkommande events + datumformat-migration

### Mål
Två saker som hör ihop tekniskt:
1. **Återkommande events** — fotbollsträning varje tisdag, simning ojämna veckor. Kritisk feature som saknas.
2. **Datumformat** — migrera från `2026-5-21` till zero-padded `2026-05-21` (eller Timestamp). Återkommande events behöver datumrange-queries, som kräver konsistent format.

### Berörda filer
**Nya:**
- `lib/utils/date_utils.dart` — central datum-helpers (ersätter scattered date-parsing)
- `lib/utils/recurrence.dart` — RRULE-ish logik
- `functions/migrate_date_format.js` — engångsmigration

**Ändrade:**
- `lib/utils/schedule_time_utils.dart` — uppdatera `parseYmdDate` (redan tolerant, men säkerställ)
- Alla ställen som skriver datum: `planner_page.dart`, `chores_page.dart`, `work_schedule_page.dart`, `family_provider.dart`, `calendar_import_page.dart`, `agenda_page.dart`
- `lib/models/planner_event.dart` (nytt — flytta från Map<String,dynamic> till typad modell)

### Steg

**5.1 Central date helper**

```dart
// lib/utils/date_utils.dart
String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

String timeKey(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:'
    '${d.minute.toString().padLeft(2, '0')}';
```

Sök hela kodbasen efter mönstret `'${d.year}-${d.month}-${d.day}'` och `'${now.year}-${now.month}-${now.day}'` och `'${date.year}-${date.month}-${date.day}'`. Ersätt alla med `dateKey(...)`. Samma för time. Listan jag kunde se i koden: rad 829, 3580, 14496, 14497, 14519, 15829, 16189 i den packade filen — men sök hellre med grep för att hitta alla.

**5.2 Migration-Cloud-Function (engångs)**

```javascript
exports.migrateDateFormatOnce = functions.https.onCall(async (data, context) => {
    if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "");
    // Säkerhetscheck: bara admin får köra
    const callerDoc = await admin.firestore()
        .collection("users").doc(context.auth.uid).get();
    if (callerDoc.data()?.role !== "admin") {
        throw new functions.https.HttpsError("permission-denied", "");
    }
    
    const collections = ["planner_events", "chores", "work_shifts", "family_notes"];
    let migrated = 0;
    
    for (const coll of collections) {
        const snap = await admin.firestore().collection(coll).get();
        let batch = admin.firestore().batch();
        let count = 0;
        
        for (const doc of snap.docs) {
            const data = doc.data();
            const updates = {};
            
            for (const field of ["date", "dueDate"]) {
                const v = data[field];
                if (typeof v === "string" && v.match(/^\d{4}-\d{1,2}-\d{1,2}$/)) {
                    const [y, m, d] = v.split("-");
                    const padded = `${y.padStart(4,'0')}-${m.padStart(2,'0')}-${d.padStart(2,'0')}`;
                    if (padded !== v) updates[field] = padded;
                }
            }
            
            if (Object.keys(updates).length > 0) {
                batch.update(doc.ref, updates);
                count++;
                migrated++;
                if (count >= 400) {
                    await batch.commit();
                    batch = admin.firestore().batch();
                    count = 0;
                }
            }
        }
        if (count > 0) await batch.commit();
    }
    
    return { migrated };
});
```

Kör en gång via test-knapp i Inställningar (göm bakom admin-roll, ta bort efter migrering).

**5.3 Återkommande events — datamodell**

Utöka `planner_events` med:
```
recurrence: {
  type: 'weekly' | 'biweekly' | 'monthly',
  weekday: int (1-7, för weekly/biweekly),
  startDate: 'YYYY-MM-DD',
  endDate: 'YYYY-MM-DD' eller null,
  exceptions: ['YYYY-MM-DD', ...] // datum där den inte ska visas
}
```

Eventet sparas EN gång med `date = startDate`. Vid läsning expanderar vi det till instanser i klienten via `recurrence.dart`-helpers:

```dart
List<DateTime> expandRecurrence({
  required Map<String, dynamic> eventData,
  required DateTime rangeStart,
  required DateTime rangeEnd,
}) {
  // Returnerar lista av datum där eventet ska visas inom range
}
```

**5.4 UI: lägg till återkommande-väljare**

I `AddEventSheet`:
- Dropdown: "Engångshändelse / Varje vecka / Varannan vecka / Varje månad"
- Om återkommande: visa "Slut: aldrig / efter X gånger / på datum"
- Förhandsvisning: "Skapar 12 instanser fram till ___"

**5.5 Visa återkommande i läsvyer**

Uppdatera `_getEventsForDay` i `planner_page.dart`, `agenda_page.dart`, och `FamilyProvider._todayEvents` att inkludera expanderade instanser. Cachea expansionen per docId + range för att inte göra det på varje rebuild.

Undantag (exceptions): klick på en återkommande instans → "Redigera bara denna gång" eller "Redigera alla". "Bara denna" → lägg till datumet i `exceptions[]` + skapa ett nytt single-event för den dagen.

**5.6 Avbryt/uppdatera notiser för återkommande**

När recurrence-event uppdateras: avboka alla relaterade notis-IDn (svårt utan att hålla extra register — alternativ: använd ett deterministiskt ID per instans: `idForDoc('${docId}_${dateKey}')`). Schemalägg om för alla framtida instanser inom 14 dagar (gränsen för "vi orkar schemalägga"; resten kan vänta tills nästa app-uppstart där vi kör en `rescheduleAll()`-pass).

### Verifieringsgate Fas 5

- [ ] Migrationsfunktion körs framgångsrikt — verifiera i Firestore-konsolen att alla `date`-fält nu är zero-padded
- [ ] Skapa återkommande event "Varje tisdag 17:00" → syns på alla framtida tisdagar i Agenda
- [ ] Skapa undantag → den enstaka instansen försvinner
- [ ] Redigera ALLA instanser → ändringen träder i kraft framåt
- [ ] Återkommande event genererar notiser för minst 2 instanser framåt
- [ ] Inga "2026-5-21"-format kvar någonstans (grep)
- [ ] Befintliga events fungerar fortfarande efter migration

---

## 🧹 FAS 6 (valfri städning, gör om du orkar)

### Småfix som inte är värda en egen fas men irriterar i koden:

- [ ] Ta bort `android/app/src/main/kotlin/com/example/myapp/MainActivity.kt` (gammal mapp, package matchar inte)
- [ ] Uppdatera `README.md` från Flutter-starter-text till riktig beskrivning av La Familia
- [ ] Byt ut alla `catch (_) {}` mot `catch (e, stack) { developer.log(...); }` (sök i hela `lib/`)
- [ ] Byt deprecated `withOpacity` mot `withValues(alpha:)` (mest i `dashboard_page.dart` rad 15101 + bottom nav)
- [ ] Typa `UserModel.colorValue` som `int` istället för `dynamic`
- [ ] Migrera `manage_members_page` från `SecondaryApp` till `createUser` Cloud Function (Fas 1.2 i den GAMLA roadmap är fortfarande halv-gjord)
- [ ] Lyft `work_shifts` och `busy_sessions` streams till `FamilyProvider` så vi slutar med nestade StreamBuilders i `FamilyStatusPage`
- [ ] Uppdatera `ROADMAP.md` — markera vad som faktiskt är klart

---

## 📌 Hur du jobbar med planen

1. **Klistra in en fas i taget** i Cursor Agent. Inte hela planen — det blir för mycket kontext.
2. Säg till Cursor: *"Här är Fas X från PROJECT_PLAN.md. Implementera enligt planen, stoppa vid verifieringsgaten."*
3. Vid varje gate: **kör appen själv**, gå igenom checklistan. Rapportera tillbaka med skärmdumpar/terminal-output som vanligt, så fixar vi det som inte stämmer innan nästa fas.
4. Säkerhetsregler (Fas 2): jag ger dig en sista koll innan du deployar till Firebase.
5. Cloud Functions (Fas 2, Fas 5): `firebase deploy --only functions` — testa på en dev-familj först.
6. Migrationen i Fas 5 är **inte reversibel utan backup**. Gör en Firestore export innan.

Totalt: ungefär 5 helger plus en städhelg. Efter Fas 1 ser appen redan ut som en helt annan produkt.
