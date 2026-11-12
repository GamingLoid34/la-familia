import 'package:flutter/material.dart';

/// Modell för en städzon (Ronald McDonald Hus-modellen).
class StadZon {
  final String key;
  final String titel;
  final String piktogram;
  final String? farg; // 'gul' | 'vit' | 'bla' | 'rod' | null
  final String? fargHex; // e.g. '#F4C430'
  final String? trasaLabel; // e.g. 'GUL TRASA' | null
  final List<String> verktyg;
  final List<String> steg;
  final int points;

  const StadZon({
    required this.key,
    required this.titel,
    required this.piktogram,
    required this.farg,
    required this.fargHex,
    required this.trasaLabel,
    required this.verktyg,
    required this.steg,
    this.points = 10, // 2 av 5 på AddChoreSheet-skalan (5, 10, 15, 20, 25)
  });

  /// Konverterar fargHex till en Color, eller returnerar null om färglös.
  Color? get color {
    if (fargHex == null) return null;
    final hex = fargHex!.replaceFirst('#', '');
    if (hex.length == 6) {
      return Color(int.parse('FF$hex', radix: 16));
    }
    return null;
  }
}

/// Färgkonstanter för städzonerna
abstract class StadFarger {
  static const String gulHex = '#F4C430';
  static const String vitHex = '#FFFFFF';
  static const String blaHex = '#4A90D9';
  static const String rodHex = '#E05B5B';

  static const Color gul = Color(0xFFF4C430);
  static const Color vit = Color(0xFFFFFFFF);
  static const Color bla = Color(0xFF4A90D9);
  static const Color rod = Color(0xFFE05B5B);
}

/// Startkit-varor för städskåpet till inköpslistan
const List<String> stadStartkitVaror = [
  'Röda mikrofibertrasor (toaletten)',
  'Extra moppdynor Vileda H2PrO',
  'Duschskrapa',
  'Tvättpåse för mikrofiber',
  'Städkaddy/bärlåda',
  'Toaborste (en per toalett)',
  'Gummihandskar',
  'Etiketter + krokar till städskåpet',
  'Dammvippa med skaft',
];

/// De 7 fasta städzonerna
const List<StadZon> stadZoner = [
  StadZon(
    key: 'stad_badrum',
    titel: 'Badrum',
    piktogram: '🚿',
    farg: 'gul',
    fargHex: StadFarger.gulHex,
    trasaLabel: 'GUL TRASA',
    verktyg: ['Gul trasa', 'Allrent', 'Duschskrapa'],
    steg: [
      '🧴 Plocka undan från ytorna',
      '🪞 Spegel — torr gul trasa',
      '🚰 Handfat & kranar — gul trasa + allrent',
      '🚿 Dusch — skrapa väggarna, torka av',
      '🧻 Fyll på toapapper & ren handduk',
    ],
  ),
  StadZon(
    key: 'stad_toalett',
    titel: 'Toalett',
    piktogram: '🚽',
    farg: 'rod',
    fargHex: StadFarger.rodHex,
    trasaLabel: 'RÖD TRASA',
    verktyg: ['Röd trasa eller papper', 'WC-rent', 'Toaborste'],
    steg: [
      '🚽 WC-rent i skålen, borsta, spola',
      '🧻 Sits & lock — röd trasa eller papper',
      '✨ Utsida, spolknapp & golvet runt om',
      '🧼 Tvätta händerna — klart!',
    ],
  ),
  StadZon(
    key: 'stad_kok',
    titel: 'Kök',
    piktogram: '🍳',
    farg: 'vit',
    fargHex: StadFarger.vitHex,
    trasaLabel: 'VIT TRASA',
    verktyg: ['Vit trasa', 'Allrent'],
    steg: [
      '🍽️ Plocka undan & ställ in disken',
      '🧽 Bänkar & stänkskydd — vit trasa + allrent',
      '🍳 Spis & spisknappar',
      '🚰 Diskho & kran',
      '✋ Handtag, strömbrytare & kylskåpsdörr',
      '🪑 Torka matbordet',
    ],
  ),
  StadZon(
    key: 'stad_damm',
    titel: 'Damm & ytor',
    piktogram: '🛋️',
    farg: 'bla',
    fargHex: StadFarger.blaHex,
    trasaLabel: 'BLÅ TRASA',
    verktyg: ['Blå trasa'],
    steg: [
      '📦 Plocka bort saker från ytorna',
      '🛋️ Hyllor, bord & TV-bänk — blå trasa',
      '📺 TV & skärmar — torr blå trasa',
      '🪟 Fönsterbrädor & speglar',
      '🚪 Dörrhandtag & lister',
    ],
  ),
  StadZon(
    key: 'stad_golv',
    titel: 'Golv',
    piktogram: '🧹',
    farg: null,
    fargHex: null,
    trasaLabel: null,
    verktyg: ['Dammsugare', 'Vileda-mopp'],
    steg: [
      '🧸 Plocka golven fria',
      '🛏️ Dammsug rum för rum — även under sängar & soffa',
      '💧 Fyll moppens rena vattentank',
      '🧴 Moppa alla hårda golv — hallen sist',
      '🚿 Töm smutsvattnet & skölj moppdynan',
    ],
  ),
  StadZon(
    key: 'stad_textil',
    titel: 'Sängar & tvätt',
    piktogram: '🛏️',
    farg: null,
    fargHex: null,
    trasaLabel: null,
    verktyg: ['Tvättkorg'],
    steg: [
      '🧺 Samla smutstvätt & använda handdukar',
      '🛏️ Byt lakan, påslakan & örngott',
      '🪟 Vädra rummen 10 minuter',
    ],
  ),
  StadZon(
    key: 'stad_sopor',
    titel: 'Sopor & återvinning',
    piktogram: '🗑️',
    farg: null,
    fargHex: null,
    trasaLabel: null,
    verktyg: ['Soppåsar'],
    steg: [
      '🗑️ Töm alla papperskorgar',
      '🛍️ Nya påsar i',
      '♻️ Ut med sopor & återvinning',
    ],
  ),
];

/// Hitta zon via dess nyckel
StadZon? stadZonByKey(String? key) {
  if (key == null || key.isEmpty) return null;
  for (final z in stadZoner) {
    if (z.key == key) return z;
  }
  return null;
}

/// Beräknar närmaste kommande lördag (eller idag om idag är lördag).
DateTime getNextSaturday([DateTime? from]) {
  final now = from ?? DateTime.now();
  final d = DateTime(now.year, now.month, now.day);
  final diff = (DateTime.saturday - d.weekday + 7) % 7;
  return d.add(Duration(days: diff));
}

