import 'dart:developer' as developer;

import 'package:flutter/material.dart';

import 'theme/app_colors.dart';

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

  /// Färgläge ("Färg på sidorna": veckodagsfärg eller neutral), som i
  /// Android-appen Vardag. Laddas från SharedPreferences ('colorMode').
  static ColorMode colorMode = ColorMode.weekday;

  /// Färgroller för dagens (eller [weekday]:s) sidor — samma beräkning som
  /// Android-appens `AppColors.compute`.
  static AppColors colors([int? weekday]) => AppColors.compute(
        mode: colorMode,
        lowStimuli: lowStimuli,
        palette: dayPalette(weekday),
      );

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

  /// Tvingad veckodag för färgerna (skärmdumpar/tester). Null = dagens datum.
  static int? weekdayOverride;

  static DayPalette dayPalette([int? weekday]) =>
      _dayPalettes[weekday ?? weekdayOverride ?? DateTime.now().weekday] ??
      _dayPalettes[1]!;

  /// Header-yta i enfärgad rollfärg, som i Android-appen Vardag. När headern
  /// har samma färg som sidan bildar de en yta utan rundade hörn; annars
  /// (lågstimuli) rundas nederhörnen.
  static BoxDecoration headerDecoration([int? weekday]) {
    final c = colors(weekday);
    return BoxDecoration(
      color: c.header,
      borderRadius: c.headerMergesWithPage
          ? null
          : const BorderRadius.vertical(bottom: Radius.circular(28)),
    );
  }

  /// Text och ikoner i headern.
  static Color headerTextColor([int? weekday]) {
    final c = colors(weekday);
    return c.headerMergesWithPage ? c.onPage : dayPalette(weekday).onColor;
  }

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
      var cleaned = hex.trim();
      if (cleaned.startsWith('#')) cleaned = cleaned.substring(1);
      if (cleaned.startsWith('0x')) cleaned = cleaned.substring(2);
      // Acceptera både 'RRGGBB' (6 tecken) och 'AARRGGBB' (8 tecken).
      final withAlpha = cleaned.length == 6 ? 'FF$cleaned' : cleaned;
      return Color(int.parse(withAlpha, radix: 16));
    } catch (e, stack) {
      // Logga och returnera defaultfärgen, undvik att smyga undan fel.
      developer.log('colorFromHex parse error for "$hex"',
          error: e, stackTrace: stack);
      final fallback = memberColorPalette.first;
      return Color(int.parse('0x$fallback'));
    }
  }

  // ─── NPF Day Colors ────────────────────────────────────────────────────────
  /// Dagens basfärg (juvelton). Behållen signatur — hela appen pekar hit.
  static Color getNpfDayColor(int weekday) => dayPalette(weekday).base;

  /// Textfärg i sidhuvudet (headern). Följer färgrollerna — se
  /// [headerTextColor]. För text ovanpå en yta i dagens basfärg, använd
  /// `dayPalette(weekday).onColor`.
  static Color getNpfTextColor(int weekday) => headerTextColor(weekday);

  static Color getDayAccentColor([int? weekday]) =>
      getNpfDayColor(weekday ?? DateTime.now().weekday);

  // ─── App Background ────────────────────────────────────────────────────────
  /// Sidbakgrund med tydlig ton av dagens färg — korten är vita ovanpå,
  /// så färgen syns i "luften" mellan korten istället för i dem.
  static BoxDecoration getBackground() =>
      BoxDecoration(color: colors().pageBackground);

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
  static Color getCardColor() => colors().cardSurface;
  static Color getTextColor() => const Color(0xFF1A1A2E);
  /// Sekundär text på kort (#5F6368 klarar WCAG AA på tonade kort).
  static Color getSubTextColor() => colors().onCardSecondary;

  // ─── Card Decoration ───────────────────────────────────────────────────────
  /// Kortets yta följer färgrollen `cardSurface` (18 % dagsfärg mot vitt i
  /// veckodagsläget, vitt i lågstimuli). [tinted] finns kvar för bakåtkompat
  /// men påverkar inte längre färgen.
  static BoxDecoration cardDecoration({
    double radius = 24, // Lite rundare hörn för modernare look
    Color? color,
    bool tinted = false,
  }) =>
      BoxDecoration(
        color: color ?? colors().cardSurface,
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
        border: Border.all(color: colors().cardBorder),
      );

  // ─── Event Icons ───────────────────────────────────────────────────────────
  static IconData getEventIcon(String title, String type) {
    final t = title.toLowerCase();
    if (t.contains('läkare') || t.contains('bup') || t.contains('sjukhus')) {
      return Icons.local_hospital_rounded;
    }
    if (t.contains('skola') || t.contains('läxa')) return Icons.school_rounded;
    if (t.contains('tandläkare') || t.contains('tand')) {
      return Icons.medical_services_rounded;
    }
    if (type == 'work' || t.contains('jobb')) return Icons.work_rounded;
    if (type == 'food' || t.contains('middag') || t.contains('lunch')) {
      return Icons.restaurant_rounded;
    }
    if (t.contains('sport') || t.contains('fotboll') || t.contains('simning')) {
      return Icons.sports_rounded;
    }
    if (t.contains('möte')) return Icons.handshake_rounded;
    return Icons.event_rounded;
  }

  // ─── Typography (Nunito — bundlad lokalt, Fas 2½) ─────────────────────────
  static TextTheme appTextTheme([TextTheme? base]) {
    final b = base ?? ThemeData.light().textTheme;
    return b.apply(fontFamily: 'Nunito');
  }

  static TextStyle get pageTitleStyle => const TextStyle(
        fontFamily: 'Nunito',
        fontSize: 32,
        fontWeight: FontWeight.w800,
        color: Color(0xFF1A1A2E),
        letterSpacing: -0.5,
      );

  /// Sektionsrubrik direkt på sidbakgrunden (färgrollen `onPage`).
  static TextStyle get sectionLabelStyle => TextStyle(
        fontFamily: 'Nunito',
        fontSize: 12,
        fontWeight: FontWeight.w800,
        color: colors().onPage,
        letterSpacing: 1.2,
      );

  static TextStyle get sectionTitleStyle => const TextStyle(
        fontFamily: 'Nunito',
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: Color(0xFF1A1A2E),
        letterSpacing: -0.3,
      );

  static TextStyle get cardTitleStyle => const TextStyle(
        fontFamily: 'Nunito',
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: Color(0xFF1A1A2E),
      );

  static TextStyle get bodyStyle => const TextStyle(
        fontFamily: 'Nunito',
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: Color(0xFF1A1A2E),
      );

  static TextStyle get captionStyle => TextStyle(
        fontFamily: 'Nunito',
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: Colors.grey.shade500,
      );
}