import 'dart:developer' as developer;

import 'package:flutter/material.dart';

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
  Color get tint =>
      Color.alphaBlend(base.withValues(alpha: 0.07), Colors.white);

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
  static final ValueNotifier<ThemeMode> mode = ValueNotifier(ThemeMode.system);
  static ThemeMode modeFromStorage(String? value) => switch (value) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
  static String modeToStorage(ThemeMode value) => switch (value) {
    ThemeMode.light => 'light',
    ThemeMode.dark => 'dark',
    ThemeMode.system => 'system',
  };
  static bool get isDark =>
      mode.value == ThemeMode.dark ||
      (mode.value == ThemeMode.system &&
          WidgetsBinding.instance.platformDispatcher.platformBrightness ==
              Brightness.dark);
  static Color get surface => isDark ? const Color(0xFF202427) : Colors.white;
  static Color get page =>
      isDark ? const Color(0xFF141719) : const Color(0xFFF4F5F6);
  static Color get surfaceMuted =>
      isDark ? const Color(0xFF30393E) : const Color(0xFFF1F5F9);
  static Color get outline =>
      isDark ? const Color(0xFF465159) : const Color(0xFFD3D9DD);
  static Color get onAccent => isDark ? const Color(0xFF123547) : Colors.white;
  static Color onColor(Color background) {
    const ink = Color(0xFF10191D);
    final luminance = background.computeLuminance();
    final lightContrast = 1.05 / (luminance + 0.05);
    final darkContrast = (luminance + 0.05) / (ink.computeLuminance() + 0.05);
    return lightContrast >= darkContrast ? Colors.white : ink;
  }

  static ThemeData materialTheme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final pageColor = dark ? const Color(0xFF141719) : const Color(0xFFF4F5F6);
    final card = dark ? const Color(0xFF202427) : Colors.white;
    final ink = dark ? const Color(0xFFF0F2F3) : const Color(0xFF20272C);
    final secondary = dark ? const Color(0xFFBEC7CD) : const Color(0xFF56616A);
    final accent = dark ? const Color(0xFFA4CBE0) : const Color(0xFF2B617E);
    final edge = dark ? const Color(0xFF465159) : const Color(0xFFD3D9DD);
    final base = ThemeData(brightness: brightness, useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: pageColor,
      colorScheme:
          ColorScheme.fromSeed(
            seedColor: const Color(0xFF2B617E),
            brightness: brightness,
          ).copyWith(
            primary: accent,
            onPrimary: dark ? const Color(0xFF123547) : Colors.white,
            secondary: accent,
            onSecondary: dark ? const Color(0xFF123547) : Colors.white,
            surface: card,
            onSurface: ink,
            onSurfaceVariant: secondary,
            surfaceContainerLowest: pageColor,
            surfaceContainerLow: card,
            surfaceContainer: card,
            surfaceContainerHigh: card,
            surfaceContainerHighest: edge,
            outline: secondary,
            outlineVariant: edge,
          ),
      textTheme: appTextTheme(base.textTheme),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

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
    1: DayPalette(
      // Måndag — smaragd
      light: Color(0xFF6FBF8A),
      base: Color(0xFF4E9D68),
      deep: Color(0xFF2E7D4F),
      onColor: Colors.white,
    ),
    2: DayPalette(
      // Tisdag — safir
      light: Color(0xFF74AEDC),
      base: Color(0xFF4D8FC4),
      deep: Color(0xFF2F6593),
      onColor: Colors.white,
    ),
    3: DayPalette(
      // Onsdag — silver
      light: Color(0xFFB9C3CE),
      base: Color(0xFF8895A3),
      deep: Color(0xFF5C6877),
      onColor: Colors.white,
    ),
    4: DayPalette(
      // Torsdag — koppar
      light: Color(0xFFD08A5A),
      base: Color(0xFFB0683A),
      deep: Color(0xFF7E441F),
      onColor: Colors.white,
    ),
    5: DayPalette(
      // Fredag — guld
      light: Color(0xFFF2CD6B),
      base: Color(0xFFE2B53E),
      deep: Color(0xFFA9802B),
      onColor: Color(0xFF1A1A2E),
    ),
    6: DayPalette(
      // Lördag — roséguld
      light: Color(0xFFE59CAC),
      base: Color(0xFFD3798F),
      deep: Color(0xFFA94F66),
      onColor: Colors.white,
    ),
    7: DayPalette(
      // Söndag — granat
      light: Color(0xFFD97259),
      base: Color(0xFFC6503E),
      deep: Color(0xFF93331F),
      onColor: Colors.white,
    ),
  };

  static DayPalette dayPalette([int? weekday]) =>
      _dayPalettes[weekday ?? DateTime.now().weekday] ?? _dayPalettes[1]!;

  /// Neutral calendar accent, aligned with Android. Member colours stay separate.
  static const DayPalette _calendarPalette = DayPalette(
    light: Color(0xFF40728A),
    base: Color(0xFF2B617E),
    deep: Color(0xFF214A60),
    onColor: Colors.white,
  );

  static const DayPalette _darkCalendarPalette = DayPalette(
    light: Color(0xFFB7D9EA),
    base: Color(0xFFA4CBE0),
    deep: Color(0xFF8CB9CF),
    onColor: Color(0xFF123547),
  );

  static DayPalette calendarPalette([int? weekday]) =>
      isDark ? _darkCalendarPalette : _calendarPalette;

  /// Header-yta med dagens gradient och rundade nederhörn.
  /// I lågstimuli-läge: platt basfärg utan glansband.
  static BoxDecoration headerDecoration([int? weekday]) => BoxDecoration(
    color: lowStimuli ? calendarPalette(weekday).base : null,
    gradient: lowStimuli ? null : calendarPalette(weekday).gradient,
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
      var cleaned = hex.trim();
      if (cleaned.startsWith('#')) cleaned = cleaned.substring(1);
      if (cleaned.startsWith('0x')) cleaned = cleaned.substring(2);
      // Acceptera både 'RRGGBB' (6 tecken) och 'AARRGGBB' (8 tecken).
      final withAlpha = cleaned.length == 6 ? 'FF$cleaned' : cleaned;
      return Color(int.parse(withAlpha, radix: 16));
    } catch (e, stack) {
      // Logga och returnera defaultfärgen, undvik att smyga undan fel.
      developer.log(
        'colorFromHex parse error for "$hex"',
        error: e,
        stackTrace: stack,
      );
      final fallback = memberColorPalette.first;
      return Color(int.parse('0x$fallback'));
    }
  }

  // ─── NPF Day Colors ────────────────────────────────────────────────────────
  /// Neutral accent. Den äldre signaturen behålls för befintliga vyer.
  static Color getNpfDayColor(int weekday) => calendarPalette(weekday).base;

  /// Textfärg ovanpå dagens färg/gradient.
  static Color getNpfTextColor(int weekday) => calendarPalette(weekday).onColor;

  static Color getDayAccentColor([int? weekday]) =>
      getNpfDayColor(weekday ?? DateTime.now().weekday);

  // ─── App Background ────────────────────────────────────────────────────────
  /// Lugn neutral sidbakgrund med vita kort ovanpå.
  static BoxDecoration getBackground() => BoxDecoration(color: page);

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
  static Color getCardColor() => surface;
  static Color getTextColor() =>
      isDark ? const Color(0xFFF0F2F3) : const Color(0xFF20272C);
  static Color getSubTextColor() =>
      isDark ? const Color(0xFFBEC7CD) : const Color(0xFF56616A);

  // ─── Card Decoration ───────────────────────────────────────────────────────
  /// [tinted] ger kortet en svag ton av dagens färg istället för rent vitt —
  /// del av juvel-designen. Default är fortfarande vitt (övriga sidor).
  static BoxDecoration cardDecoration({
    double radius = 24, // Lite rundare hörn för modernare look
    Color? color,
    bool tinted = false,
  }) => BoxDecoration(
    color: color ?? (tinted && !isDark ? calendarPalette().tint : surface),
    borderRadius: BorderRadius.circular(radius),
    boxShadow: lowStimuli
        ? null
        : [
            // Skuggan tar dagens kulör — djup utan att bli "smutsgrå".
            BoxShadow(
              color: calendarPalette().deep.withValues(alpha: 0.10),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
    border: Border.all(
      color: isDark
          ? outline
          : (lowStimuli
                ? Colors.black.withValues(alpha: 0.06)
                : calendarPalette().base.withValues(alpha: 0.08)),
    ),
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

  static TextStyle get pageTitleStyle => TextStyle(
    fontFamily: 'Nunito',
    fontSize: 32,
    fontWeight: FontWeight.w800,
    color: getTextColor(),
    letterSpacing: -0.5,
  );

  static TextStyle get sectionLabelStyle => TextStyle(
    fontFamily: 'Nunito',
    fontSize: 12,
    fontWeight: FontWeight.w800,
    color: calendarPalette().deep,
    letterSpacing: 1.2,
  );

  static TextStyle get sectionTitleStyle => TextStyle(
    fontFamily: 'Nunito',
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: getTextColor(),
    letterSpacing: -0.3,
  );

  static TextStyle get cardTitleStyle => TextStyle(
    fontFamily: 'Nunito',
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: getTextColor(),
  );

  static TextStyle get bodyStyle => TextStyle(
    fontFamily: 'Nunito',
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: getTextColor(),
  );

  static TextStyle get captionStyle => TextStyle(
    fontFamily: 'Nunito',
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: getSubTextColor(),
  );
}
