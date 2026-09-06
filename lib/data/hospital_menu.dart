// Sjukhusmeny — Patientmeny VOS Måltid 9.0 260417
// Byt vid ny säsongsmeny.

enum HospitalMenuCategory {
  varmratt,
  smaratt,
  rakost,
  dessert,
}

class HospitalMenuItem {
  final String id;
  final int? nummer;
  final String namn;
  final HospitalMenuCategory kategori;

  const HospitalMenuItem({
    required this.id,
    this.nummer,
    required this.namn,
    required this.kategori,
  });
}

const List<HospitalMenuItem> hospitalMenuItems = [
  // Varmrätter (id 1–15)
  HospitalMenuItem(
    id: '1',
    nummer: 1,
    namn: 'Chili sin carne med nachochips och grönsaker',
    kategori: HospitalMenuCategory.varmratt,
  ),
  HospitalMenuItem(
    id: '2',
    nummer: 2,
    namn: 'Linsgryta med ingefära och kokos',
    kategori: HospitalMenuCategory.varmratt,
  ),
  HospitalMenuItem(
    id: '3',
    nummer: 3,
    namn: 'Marinerad kycklinglårfilé med gräddig äppelcidersås',
    kategori: HospitalMenuCategory.varmratt,
  ),
  HospitalMenuItem(
    id: '4',
    nummer: 4,
    namn: 'Pasta med köttfärssås',
    kategori: HospitalMenuCategory.varmratt,
  ),
  HospitalMenuItem(
    id: '5',
    nummer: 5,
    namn: 'Hemlagade köttbullar med gräddsås',
    kategori: HospitalMenuCategory.varmratt,
  ),
  HospitalMenuItem(
    id: '6',
    nummer: 6,
    namn: 'Kassler med mango- och currysås',
    kategori: HospitalMenuCategory.varmratt,
  ),
  HospitalMenuItem(
    id: '7',
    nummer: 7,
    namn: 'Kycklingbiff med fransk örtsås',
    kategori: HospitalMenuCategory.varmratt,
  ),
  HospitalMenuItem(
    id: '8',
    nummer: 8,
    namn: 'Fransk kycklinggryta Marengo',
    kategori: HospitalMenuCategory.varmratt,
  ),
  HospitalMenuItem(
    id: '9',
    nummer: 9,
    namn: 'Kokt sejfilé med hummersås',
    kategori: HospitalMenuCategory.varmratt,
  ),
  HospitalMenuItem(
    id: '10',
    nummer: 10,
    namn: 'Asiatisk fiskgryta med kokosmjölk och röd curry',
    kategori: HospitalMenuCategory.varmratt,
  ),
  HospitalMenuItem(
    id: '11',
    nummer: 11,
    namn: 'Kåldolmar med gräddsås',
    kategori: HospitalMenuCategory.varmratt,
  ),
  HospitalMenuItem(
    id: '12',
    nummer: 12,
    namn: 'Korv Stroganoff',
    kategori: HospitalMenuCategory.varmratt,
  ),
  HospitalMenuItem(
    id: '13',
    nummer: 13,
    namn: 'Ugnsomelett med svampstuvning',
    kategori: HospitalMenuCategory.varmratt,
  ),
  HospitalMenuItem(
    id: '14',
    nummer: 14,
    namn: 'Högsbosoppa',
    kategori: HospitalMenuCategory.varmratt,
  ),
  HospitalMenuItem(
    id: '15',
    nummer: 15,
    namn: 'Köttsoppa',
    kategori: HospitalMenuCategory.varmratt,
  ),

  // Smårätter (id 16–19)
  HospitalMenuItem(
    id: '16',
    nummer: 16,
    namn: 'Pannkakor',
    kategori: HospitalMenuCategory.smaratt,
  ),
  HospitalMenuItem(
    id: '17',
    nummer: 17,
    namn: 'Korv med mos',
    kategori: HospitalMenuCategory.smaratt,
  ),
  HospitalMenuItem(
    id: '18',
    nummer: 18,
    namn: 'Kycklingspett med potatissallad',
    kategori: HospitalMenuCategory.smaratt,
  ),
  HospitalMenuItem(
    id: '19',
    nummer: 19,
    namn: 'Tomatsoppa med krutonger',
    kategori: HospitalMenuCategory.smaratt,
  ),

  // Råkost (r1–r3)
  HospitalMenuItem(
    id: 'r1',
    namn: 'Pizzasallad',
    kategori: HospitalMenuCategory.rakost,
  ),
  HospitalMenuItem(
    id: 'r2',
    namn: 'Kikärtssallad',
    kategori: HospitalMenuCategory.rakost,
  ),
  HospitalMenuItem(
    id: 'r3',
    namn: 'Picklade morötter',
    kategori: HospitalMenuCategory.rakost,
  ),

  // Dessert (d1–d5)
  HospitalMenuItem(
    id: 'd1',
    namn: 'Bärkompott',
    kategori: HospitalMenuCategory.dessert,
  ),
  HospitalMenuItem(
    id: 'd2',
    namn: 'Drömrulltårta',
    kategori: HospitalMenuCategory.dessert,
  ),
  HospitalMenuItem(
    id: 'd3',
    namn: 'Fruktsallad',
    kategori: HospitalMenuCategory.dessert,
  ),
  HospitalMenuItem(
    id: 'd4',
    namn: 'Citronfromage',
    kategori: HospitalMenuCategory.dessert,
  ),
  HospitalMenuItem(
    id: 'd5',
    namn: 'Färsk frukt',
    kategori: HospitalMenuCategory.dessert,
  ),
];

/// Hitta en menyartikel via dess unika ID.
HospitalMenuItem? getHospitalMenuItemById(String? id) {
  if (id == null || id.isEmpty) return null;
  for (final item in hospitalMenuItems) {
    if (item.id == id) return item;
  }
  return null;
}

/// Formaterar valt måltidsobjekt till huvudtitel och valfria tillägg.
({String mainTitle, String? extras}) formatHospitalMealChoice(
  Map<String, dynamic>? choiceMap, {
  required String mealLabel,
}) {
  if (choiceMap == null) {
    return (mainTitle: '$mealLabel — tryck för att välja', extras: null);
  }

  final dishId = choiceMap['dishId'] as String?;
  final dish = getHospitalMenuItemById(dishId);

  if (dish == null) {
    return (mainTitle: '$mealLabel — tryck för att välja', extras: null);
  }

  final dishTitle = dish.nummer != null ? '${dish.nummer}. ${dish.namn}' : dish.namn;
  final mainTitle = '$mealLabel: $dishTitle';

  final rakostId = choiceMap['rakostId'] as String?;
  final dessertId = choiceMap['dessertId'] as String?;
  final rakost = getHospitalMenuItemById(rakostId);
  final dessert = getHospitalMenuItemById(dessertId);

  final extraParts = <String>[];
  if (rakost != null) extraParts.add(rakost.namn);
  if (dessert != null) extraParts.add(dessert.namn);

  final extras = extraParts.isNotEmpty ? '+ ${extraParts.join(' · ')}' : null;
  return (mainTitle: mainTitle, extras: extras);
}
