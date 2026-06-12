import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Palett per veckodag — varje dag är en ädelsten eller metall.
/// [light] är glansbandet som ger den "metalliska" lystern i gradienter.
class DayPalette {
  final Color light;
  final Color base;
  final Color deep;
  final Color onColor;

  const DayPalette({
    required this.light,
    required this.base,
    required this.deep,
    required this.onColor,
  });

  /// Mycket ljus ton av dagsfärgen — för kortbakgrunder (istället för vitt).
  Color get tint => Color.alphaBlend(base.withValues(alpha: 0.07), Colors.white);

  /// Trestegsgradient med glansband upptill: ljus → bas → djup.
  /// Det är detta som ger metall-känslan utan glitter eller reflexer.
  LinearGradient get gradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        stops: const [0.0, 0.45, 1.0],
        colors: [light, base, deep],
      );
}

class AppTheme {
  // ─── Lågstimuli-läge (NPF) ──────────────────────────────────────────────────
  /// Tonar ner gradienter, färgad bakgrund och skuggor — för dagar då allt
  /// är för mycket. Laddas från SharedPreferences vid start ('lowStimuli')
  /// och växlas i Inställningar. Dagsfärgerna behålls (igenkänningen är
  /// trygghet) men ytorna blir platta och lugna.
  static bool lowStimuli = false;

  // ─── Day Palettes — "varje dag en ädelsten/metall" ─────────────────────────
  // Mån smaragd · Tis safir · Ons silver · Tor koppar · Fre guld ·
  // Lör roséguld · Sön granat. Behåller veckodagsfärgernas igenkänning.
  static const Map<int, DayPalette> _dayPalettes = {
    1: DayPalette( // Måndag — smaragd
        light: Color(0xFF6FBF8A),
        base: Color(0xFF4E9D68),
        deep: Color(0xFF2E7D4F),
        onColor: Colors.white),
    2: DayPalette( // Tisdag — safir
        light: Color(0xFF74AEDC),
        base: Color(0xFF4D8FC4),
        deep: Color(0xFF2F6593),
        onColor: Colors.white),
    3: DayPalette( // Onsdag — silver
        light: Color(0xFFB9C3CE),
        base: Color(0xFF8895A3),
        deep: Color(0xFF5C6877),
        onColor: Colors.white),
    4: DayPalette( // Torsdag — koppar
        light: Color(0xFFD08A5A),
        base: Color(0xFFB0683A),
        deep: Color(0xFF7E441F),
        onColor: Colors.white),
    5: DayPalette( // Fredag — guld
        light: Color(0xFFF2CD6B),
        base: Color(0xFFE2B53E),
        deep: Color(0xFFA9802B),
        onColor: Color(0xFF1A1A2E)),
    6: DayPalette( // Lördag — roséguld
        light: Color(0xFFE59CAC),
        base: Color(0xFFD3798F),
        deep: Color(0xFFA94F66),
        onColor: Colors.white),
    7: DayPalette( // Söndag — granat
        light: Color(0xFFD97259),
        base: Color(0xFFC6503E),
        deep: Color(0xFF93331F),
        onColor: Colors.white),
  };

  static DayPalette dayPalette([int? weekday]) =>
      _dayPalettes[weekday ?? DateTime.now().weekday] ?? _dayPalettes[1]!;

  /// Header-yta med dagens gradient och rundade nederhörn.
  /// I lågstimuli-läge: platt basfärg utan glansband.
  static BoxDecoration headerDecoration([int? weekday]) => BoxDecoration(
        color: lowStimuli ? dayPalette(weekday).base : null,
        gradient: lowStimuli ? null : dayPalette(weekday).gradient,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      );

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

  /// Returnerar en [Color] från en hex-sträng (utan '#').
  /// Accepterar både 'ffRRGGBB' och 'RRGGBB' och '0xffRRGGBB'.
  /// Faller tillbaka till första palette-färgen vid ogiltig input.
  static Color colorFromHex(String hex) {
    try {
      final cleaned = hex.startsWith('0x') ? hex.substring(2) : hex;
      // Acceptera både 'RRGGBB' (6 tecken) och 'AARRGGBB' (8 tecken).
      final withAlpha = cleaned.length == 6 ? 'FF$cleaned' : cleaned;
      return Color(int.parse(withAlpha, radix: 16));
    } catch (e, stack) {
      // Logga och returnera defaultfärgen, undvik att smyga undan fel.
      debugPrint('colorFromHex parse error for "$hex": $e\n$stack');
      final fallback = memberColorPalette.first;
      return Color(int.parse('0x$fallback'));
    }
  }

  // ─── NPF Day Colors ────────────────────────────────────────────────────────
  /// Dagens basfärg (juvelton). Behållen signatur — hela appen pekar hit.
  static Color getNpfDayColor(int weekday) => dayPalette(weekday).base;

  /// Textfärg ovanpå dagens färg/gradient.
  static Color getNpfTextColor(int weekday) => dayPalette(weekday).onColor;

  static Color getDayAccentColor([int? weekday]) =>
      getNpfDayColor(weekday ?? DateTime.now().weekday);

  // ─── App Background ────────────────────────────────────────────────────────
  /// Sidbakgrund med tydlig ton av dagens färg — korten är vita ovanpå,
  /// så färgen syns i "luften" mellan korten istället för i dem.
  static BoxDecoration getBackground() {
    if (lowStimuli) {
      return const BoxDecoration(color: Color(0xFFF4F6F8));
    }
    return BoxDecoration(
      color: Color.alphaBlend(
        dayPalette().base.withValues(alpha: 0.10),
        const Color(0xFFF6F6F4),
      ),
    );
  }

  /// Luft under systemets statusfält (klocka, batteri) utan global SafeArea.
  static EdgeInsets paddingBelowStatusBar(
    BuildContext context, {
    double horizontal = 20,
    double extraBelowStatus = 14,
    double bottom = 20,
  }) {
    final top = MediaQuery.paddingOf(context).top + extraBelowStatus;
    return EdgeInsets.fromLTRB(horizontal, top, horizontal, bottom);
  }

  // ─── Colors ────────────────────────────────────────────────────────────────
  static Color getCardColor() => Colors.white;
  static Color getTextColor() => const Color(0xFF1A1A2E);
  static Color getSubTextColor() => Colors.grey.shade500;

  // ─── Card Decoration ───────────────────────────────────────────────────────
  /// [tinted] ger kortet en svag ton av dagens färg istället för rent vitt —
  /// del av juvel-designen. Default är fortfarande vitt (övriga sidor).
  static BoxDecoration cardDecoration({
    double radius = 24, // Lite rundare hörn för modernare look
    Color? color,
    bool tinted = false,
  }) =>
      BoxDecoration(
        color: color ?? (tinted ? dayPalette().tint : Colors.white),
        borderRadius: BorderRadius.circular(radius),
        boxShadow: lowStimuli
            ? null
            : [
                // Skuggan tar dagens kulör — djup utan att bli "smutsgrå".
                BoxShadow(
                  color: dayPalette().deep.withValues(alpha: 0.10),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
        border: Border.all(
          color: lowStimuli
              ? Colors.black.withValues(alpha: 0.06)
              : dayPalette().base.withValues(alpha: 0.08),
        ),
      );

  // ─── Event Icons ───────────────────────────────────────────────────────────
  static IconData getEventIcon(String title, String type) {
    final t = title.toLowerCase();
    if (t.contains('läkare') || t.contains('bup') || t.contains('sjukhus'))
      return Icons.local_hospital_rounded;
    if (t.contains('skola') || t.contains('läxa')) return Icons.school_rounded;
    if (t.contains('tandläkare') || t.contains('tand'))
      return Icons.medical_services_rounded;
    if (type == 'work' || t.contains('jobb')) return Icons.work_rounded;
    if (type == 'food' || t.contains('middag') || t.contains('lunch'))
      return Icons.restaurant_rounded;
    if (t.contains('sport') || t.contains('fotboll') || t.contains('simning'))
      return Icons.sports_rounded;
    if (t.contains('möte')) return Icons.handshake_rounded;
    return Icons.event_rounded;
  }

  // ─── Typography (Nunito — rundat, varmt, lättläst) ─────────────────────────
  static TextTheme appTextTheme([TextTheme? base]) =>
      GoogleFonts.nunitoTextTheme(base);

  static TextStyle get pageTitleStyle => GoogleFonts.nunito(
        fontSize: 32,
        fontWeight: FontWeight.w800,
        color: const Color(0xFF1A1A2E),
        letterSpacing: -0.5,
      );

  static TextStyle get sectionLabelStyle => GoogleFonts.nunito(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        color: dayPalette().deep,
        letterSpacing: 1.2,
      );

  static TextStyle get sectionTitleStyle => GoogleFonts.nunito(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: const Color(0xFF1A1A2E),
        letterSpacing: -0.3,
      );

  static TextStyle get cardTitleStyle => GoogleFonts.nunito(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: const Color(0xFF1A1A2E),
      );

  static TextStyle get bodyStyle => GoogleFonts.nunito(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: const Color(0xFF1A1A2E),
      );

  static TextStyle get captionStyle => GoogleFonts.nunito(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: Colors.grey.shade500,
      );
}