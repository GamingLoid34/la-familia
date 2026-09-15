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

### Deploysäkring Web, APK & Hosting (Storskärm, Nedladdning & Webb)

Följ alltid denna standardiserade bygg- och deployritual vid releaser:

1. **Versionering och tester:**
   - Bumpa versionsnumret i `pubspec.yaml` (t.ex. `version: 1.0.0+25`).
   - Kör testerna:
     ```powershell
     flutter test
     flutter analyze
     node --test functions/test/*.test.js
     ```

2. **Release-byggen (APK & Web):**
   - Bränn in versionsnumret vid kompilering med `--dart-define=APP_VERSION=1.0.0+N`:
     ```powershell
     flutter build apk --release --dart-define=APP_VERSION=1.0.0+N
     flutter build web --release --dart-define=APP_VERSION=1.0.0+N
     ```

3. **APK-distribution och nedladdningssida:**
   - Kopiera APK-filen till webbens utdelade kataloger:
     ```powershell
     Copy-Item -Force build\app\outputs\flutter-apk\app-release.apk build\web\app-release.apk
     Copy-Item -Force build\app\outputs\flutter-apk\app-release.apk build\web\la-familia.apk
     Copy-Item -Force build\app\outputs\flutter-apk\app-release.apk web\app-release.apk
     ```
   - Uppdatera versions-/build-numret i både `web/ladda-ner/index.html` och `build/web/ladda-ner/index.html`.

4. **Förkontroll före deploy:**
   - Läs av nuvarande live-version:
     ```powershell
     curl.exe -s https://la-familia-5d9f5.web.app/version.json
     ```

5. **Deploy:**
   - Distribuera till Firebase Hosting:
     ```powershell
     firebase deploy --only hosting --project la-familia-5d9f5
     ```

6. **De 6 obligatoriska efterkontrollerna med `curl.exe`:**
   Kör alltid samtliga 6 kontroller mot produktionsmiljön:
   ```powershell
   # 1. Version — verifiera att det nya build-numret är aktivt
   curl.exe -s https://la-familia-5d9f5.web.app/version.json

   # 2. Integritetspolicy — HTTP 200
   curl.exe -s -o NUL -w "%{http_code}" https://la-familia-5d9f5.web.app/privacy.html

   # 3. Besöksvy — HTTP 200
   curl.exe -s -o NUL -w "%{http_code}" https://la-familia-5d9f5.web.app/besok/

   # 4. Bootstrap JS — MIME-typ text/javascript (ej text/html)
   curl.exe -s -I https://la-familia-5d9f5.web.app/flutter_bootstrap.js | findstr /i content-type

   # 5. Nedladdningssida — HTTP 200
   curl.exe -s -o NUL -w "%{http_code}" https://la-familia-5d9f5.web.app/ladda-ner/

   # 6. APK-nedladdning — HTTP 200
   curl.exe -s -o NUL -w "%{http_code}" https://la-familia-5d9f5.web.app/app-release.apk
   ```

7. **Commit och tagg som sista steg:**
   - Varje deployad build ska committas och taggas med `git tag build-N` efter efterkontrollerna.
   - En deployad build utan commit är en avvikelse och ska redovisas i slutrapporten.
   - Committen ska innehålla den källkod och version som faktiskt deployades; en checkpoint med pågående arbete ersätter inte en release-commit.

### Storskärmen (display-lagret) — layout- och typografiregler

**Ingen SingleChildScrollView, ListView eller annan scroll på väggen.**
Väggen (storskärmen) har ingen pekskärm eller fjärrkontroll för att scrolla,
så innehåll som inte får plats får aldrig tystas bort bakom en scrollbar.
`DisplayRamPlate` (gren a/b) och tidraden i `DisplayActivityCard` läggs
därför utan någon scrollomslutning — innehållet är mätt att rymmas.
Det enda tillåtna undantaget är `FittedBox(fit: BoxFit.scaleDown)` i
`DisplayRamPlate` gren c och i `DisplayActivityCard`s tidrad, när texten i
full storlek inte ryms (beslutat undantag från FAS 5.6, Korrigering 6d.5).

**Typografiregel:** innehållstext (namn, tider, ämnen, rätter,
händelsetitlar, rubriker, tomtillstånd som "Inga …") ska vara **≥ 18 px**.
Ett antal avsiktliga undantag — kompakta etiketter, badges och pills där
utrymmet inte tillåter 18 px — är dokumenterade nedan och ska inte höjas:

| Text/element | Storlek | Kategori |
|---|---:|---|
| Attribution "data från Trafiklab.se" (kompakt kort) | 10 px | Undantag |
| Attribution "data från Trafiklab.se" (bred rubrikrad) | 11 px | Undantag |
| Synkstämpel "Synk HH:MM · La Familia" | 12 px | Undantag |
| Chip-badge (PÅGÅR m.fl., `_buildChipBadge`, mätstilen) | 12 px w800 | Undantag |
| Chip-badge i persondagsschemat (`isLarge`) | 18 px | Innehåll (plats finns) |
| Avgångskortets linjepill | 12 px | Undantag |
| Avgångskortets bytesbricka ("byte i Mjölby") | 10 px | Undantag |
| Avgångskortets tid/status (försenad, inställd, GA-tid) | 13 px | Undantag |
| Footerkickers ("Avgångar" m.fl., samma i alla footerkort) | 14 px | Undantag |
| Nedräkningsetikett minuter (idag_nu-chip) | 13 px | Undantag |
| Varningsikon ⚠ bredvid footerkicker | 13 px | Undantag |
| Varningsikon ⚠ bredvid bred rubrikrad | 16 px | Undantag |
| Tågemoji 🚆 bredvid footerkicker | 16 px | Undantag |
| Lunchrätter, skolmat, "Inga …"-tomtillstånd | 18 px | Innehåll |
| Hero-text och nedräkningstitlar (idag_nu) | 18 px | Innehåll |
| Middagsveckan, persondag (namn, sysslor, imorgon-text) | 18 px | Innehåll |
| Rubriker (IDAG, "Avgångar & Kollektivtrafik", hållplatsnamn) | 18 px | Innehåll |

> ℹ️ **Förklaring av APK-filstorlek (MiB vs MB):**
> När Flutter CLI bygger APK rapporteras t.ex. `✓ Built build\app\outputs\flutter-apk\app-release.apk (77.6MB)`.
> Flutter anger här storleken i binära mebibyte (MiB, $1024 \times 1024$ bytes):
> $81{,}409{,}728 \text{ bytes} / (1024 \times 1024) \approx 77.638 \text{ MiB}$.
> Windows Filhanterare och HTTP `Content-Length` anger däremot decimala megabyte (MB, $10^6$ bytes):
> $81{,}409{,}728 \text{ bytes} / 1{,}000{,}000 \approx 81.41 \text{ MB}$.
> Det rör sig alltså om exakt samma fil och bytes — ingen filtillväxt har skett.

> ⚠️ **VAKT — PowerShell curl-aliasregel (gäller alla faser):**
> Skriv **alltid `curl.exe`**, aldrig bara `curl`, i PowerShell-kommandon.
> I PowerShell är `curl` ett inbyggt alias för `Invoke-WebRequest`, som inte
> förstår `-s`-flaggan och hänger i väntan på inmatning. `curl.exe` anropar
> den riktiga curl-binären. **Ingen deploy får verifieras via aliaset `curl`.**


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
