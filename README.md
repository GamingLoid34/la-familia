# La Familia

Svensk familjeapp för aktiviteter, sysslor, scheman och vardagsstatus — byggd för delad användning i familjen (vuxna och barn).

## Stack

- **Flutter** (Dart) — mobilklient
- **Firebase** — Auth, Firestore, Storage, Cloud Functions, Messaging, Crashlytics
- **Provider** — app state (`FamilyProvider`)

Plan och roadmap: [PROJECT_PLAN_V3.md](PROJECT_PLAN_V3.md).

## Utveckling

```bash
flutter pub get
flutter run
```

Profile-läge (prestanda):

```bash
flutter run --profile
```

## Deploy (viktigt)

Appen delar Firebase-projekt med **MyMirai**. Deploya **aldrig** alla Cloud Functions.

Exempel (namngivna functions + rules efter granskning):

```bash
firebase deploy --only firestore:rules
firebase deploy --only functions:completeChore,functions:joinFamilyWithCode,functions:createUser
```

Ändra inte och deploya inte `functions/index.js` / rules utan att följa instruktionerna i `PROJECT_PLAN_V3.md` (stoppa före deploy när planen säger det).

## Struktur (kort)

- `lib/screens/` — flikar och sidor
- `lib/widgets/` — återanvändbara UI-delar (t.ex. `AddEventSheet`, `OfflineBanner`)
- `lib/providers/` — state
- `functions/` — Cloud Functions (delat projekt)
- `firestore.rules` — säkerhetsregler
