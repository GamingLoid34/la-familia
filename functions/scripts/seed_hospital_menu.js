/* eslint-disable linebreak-style, max-len, require-jsdoc */
/**
 * Engångsskript: seedar config/hospital_menu i Firestore från den hårdkodade
 * listan i lib/data/hospital_menu.dart (Android Fas 7 läser detta dokument
 * i stället för att duplicera listan i Kotlin).
 *
 * Idempotent — set() skriver över dokumentet med identiskt innehåll varje
 * gång (utom updatedAt) tills listan nedan ändras för hand.
 *
 * OBS: värdena nedan är en KOPIA av lib/data/hospital_menu.dart. Vid
 * säsongsbyte (ny "Byt vid ny säsongsmeny"-kommentar i Dart-filen): uppdatera
 * SEASON och ITEMS nedan till samma innehåll, kör sedan om skriptet.
 *
 * Körs lokalt mot ett riktigt Firebase-projekt (kräver inloggad
 * `gcloud`/`firebase login` med behörighet, eller GOOGLE_APPLICATION_CREDENTIALS):
 *
 *   cd functions
 *   node scripts/seed_hospital_menu.js [projectId]
 *
 * Standard-projectId är la-familia-5d9f5 om inget anges.
 */

const admin = require("firebase-admin");

const SEASON = "Patientmeny VOS Måltid 9.0 260417";

// Exakt kopia av hospitalMenuItems i lib/data/hospital_menu.dart — samma
// ordning, samma id:n (id är den existerande strängen, inte ett nytt id).
const ITEMS = [
  // Varmrätter (id 1–15)
  {id: "1", nummer: 1, namn: "Chili sin carne med nachochips och grönsaker", kategori: "varmratt"},
  {id: "2", nummer: 2, namn: "Linsgryta med ingefära och kokos", kategori: "varmratt"},
  {id: "3", nummer: 3, namn: "Marinerad kycklinglårfilé med gräddig äppelcidersås", kategori: "varmratt"},
  {id: "4", nummer: 4, namn: "Pasta med köttfärssås", kategori: "varmratt"},
  {id: "5", nummer: 5, namn: "Hemlagade köttbullar med gräddsås", kategori: "varmratt"},
  {id: "6", nummer: 6, namn: "Kassler med mango- och currysås", kategori: "varmratt"},
  {id: "7", nummer: 7, namn: "Kycklingbiff med fransk örtsås", kategori: "varmratt"},
  {id: "8", nummer: 8, namn: "Fransk kycklinggryta Marengo", kategori: "varmratt"},
  {id: "9", nummer: 9, namn: "Kokt sejfilé med hummersås", kategori: "varmratt"},
  {id: "10", nummer: 10, namn: "Asiatisk fiskgryta med kokosmjölk och röd curry", kategori: "varmratt"},
  {id: "11", nummer: 11, namn: "Kåldolmar med gräddsås", kategori: "varmratt"},
  {id: "12", nummer: 12, namn: "Korv Stroganoff", kategori: "varmratt"},
  {id: "13", nummer: 13, namn: "Ugnsomelett med svampstuvning", kategori: "varmratt"},
  {id: "14", nummer: 14, namn: "Högsbosoppa", kategori: "varmratt"},
  {id: "15", nummer: 15, namn: "Köttsoppa", kategori: "varmratt"},

  // Smårätter (id 16–19)
  {id: "16", nummer: 16, namn: "Pannkakor", kategori: "smaratt"},
  {id: "17", nummer: 17, namn: "Korv med mos", kategori: "smaratt"},
  {id: "18", nummer: 18, namn: "Kycklingspett med potatissallad", kategori: "smaratt"},
  {id: "19", nummer: 19, namn: "Tomatsoppa med krutonger", kategori: "smaratt"},

  // Råkost (r1–r3)
  {id: "r1", nummer: null, namn: "Pizzasallad", kategori: "rakost"},
  {id: "r2", nummer: null, namn: "Kikärtssallad", kategori: "rakost"},
  {id: "r3", nummer: null, namn: "Picklade morötter", kategori: "rakost"},

  // Dessert (d1–d5)
  {id: "d1", nummer: null, namn: "Bärkompott", kategori: "dessert"},
  {id: "d2", nummer: null, namn: "Drömrulltårta", kategori: "dessert"},
  {id: "d3", nummer: null, namn: "Fruktsallad", kategori: "dessert"},
  {id: "d4", nummer: null, namn: "Citronfromage", kategori: "dessert"},
  {id: "d5", nummer: null, namn: "Färsk frukt", kategori: "dessert"},
];

async function main() {
  const projectId = process.argv[2] || "la-familia-5d9f5";
  admin.initializeApp({projectId});

  const db = admin.firestore();
  await db.collection("config").doc("hospital_menu").set({
    season: SEASON,
    items: ITEMS,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  console.log(`config/hospital_menu skrivet i projekt "${projectId}" (${ITEMS.length} rätter, säsong "${SEASON}").`);
}

main().catch((err) => {
  console.error("seed_hospital_menu misslyckades:", err);
  process.exitCode = 1;
});
