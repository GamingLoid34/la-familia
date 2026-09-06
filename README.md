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

## Google Play — release-signering

Release-byggen signeras med en **upload-keystore** (inte debug-nyckeln).

### 1. Skapa keystore (kör själv en gång)

PowerShell (Windows), byt sökväg om du vill:

```powershell
keytool -genkey -v `
  -keystore "$env:USERPROFILE\upload-keystore.jks" `
  -storetype JKS `
  -keyalg RSA -keysize 2048 -validity 10000 `
  -alias upload
```

Svara på frågorna och **spara lösenorden säkert** (lösenordsarkiv / lösenordshanterare). Utan keystore + lösenord går det inte att uppdatera appen på Play.

Kopiera nyckelfilen till projektets `android/`-mapp (eller peka absolut sökväg i `key.properties`):

```powershell
Copy-Item "$env:USERPROFILE\upload-keystore.jks" "android\upload-keystore.jks"
```

### 2. `android/key.properties` (gitignorad)

```powershell
Copy-Item android\key.properties.example android\key.properties
# Redigera och fyll i storePassword, keyPassword, keyAlias, storeFile
```

Exempel (relativt `android/app/`):

```
storePassword=...
keyPassword=...
keyAlias=upload
storeFile=../upload-keystore.jks
```

### 3. Bygg App Bundle till Play

```bash
flutter build appbundle --release
```

Fil: `build/app/outputs/bundle/release/app-release.aab`

> **VARNING — sidladdade installationer:** När du byter från debug-signering till
> upload-keystore kan familjens telefoner **inte** uppdatera den gamla APK:n
> över sidladdning. Alla ominstallerar **en gång** via Play (eller avinstallerar
> den gamla och installerar den Play-signerade). All appdata ligger i Firebase-molnet,
> så inloggning med samma konto återställer familjedata.

## Versioner (Play kräver ny `versionCode` varje uppladdning)

I `pubspec.yaml`:

```yaml
version: 1.0.0+2
#         ^^^^^  ^
#         namn   versionCode (heltal, måste öka för varje Play-uppladdning)
```

Rutin före varje uppladdning till Play Console:

1. Höj `+N` (t.ex. `1.0.0+2` → `1.0.0+3`). Vid synlig app-version: höj även `1.0.0` → `1.0.1`.
2. `flutter build appbundle --release`
3. Ladda upp AAB i Play Console.

Alternativ utan att redigera filen (engångsöverstyrning):

```bash
flutter build appbundle --release --build-number=3 --build-name=1.0.1
```

## Integritetspolicy (Play Console)

Källa: [`web/privacy.html`](web/privacy.html).

1. Byt `BYT_UT_KONTAKT@exempel.se` till er riktiga kontaktadress.
2. Bygg och deploya hosting:

```bash
flutter build web
firebase deploy --only hosting
```

URL (efter hosting är live), t.ex.:

`https://la-familia-5d9f5.web.app/privacy.html`

Klistra in den i Play Console under Appinnehåll → Integritetspolicy.

## Struktur (kort)

- `lib/screens/` — flikar och sidor
- `lib/widgets/` — återanvändbara UI-delar (t.ex. `AddEventSheet`, `OfflineBanner`)
- `lib/providers/` — state
- `functions/` — Cloud Functions (delat projekt)
- `firestore.rules` — säkerhetsregler
