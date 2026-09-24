# Vardag-ikoner

`convert.js` för över Android-appen Vardags originalvektorer
(`vardag-android/app/src/main/res/drawable/*.xml`) till SVG och PNG utan omritning:
pathData, färger, fillType och gruppernas skala/förflyttning förs över oförändrade.

```
npm install @resvg/resvg-js fast-xml-parser
node convert.js      # skriver till ./out
```

Utdata och var de ligger i Flutter-projektet:

| Fil i `out/` | Används som |
|---|---|
| `vardag_logo.png` (1510 px bred) | `assets/images/vardag_logo.png` – hel logga i appen |
| `icon_1024.png` | `assets/images/vardag_icon.png` |
| `icon_foreground.png` | `assets/images/vardag_icon_foreground.png` |
| `icon_48.png`…`icon_192.png` | `android/app/src/main/res/mipmap-*/ic_launcher(_round).png` (äldre Android) |
| `icon_192.png`, `icon_512.png` | `web/icons/Icon-*.png` och `Icon-maskable-*.png` |
| `icon_180.png` | `web/icons/apple-touch-icon.png` |
| `icon_48.png` | `web/favicon.png` |

Android 8+ använder vektorerna direkt (`res/drawable/ic_launcher_*.xml`,
`res/mipmap-anydpi-v26/*.xml`), kopierade oförändrade från Android-projektet.
