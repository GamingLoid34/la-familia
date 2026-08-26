import 'package:flutter/material.dart';

/// Fönsterstorlek för responsiv layout (Fas 2⅞).
/// Kompakt < 600 måste förbli pixel-identisk med mobil.
enum WindowSize {
  compact,
  medium,
  wide;

  static const double compactBreakpoint = 600;
  static const double wideBreakpoint = 840;
  static const double contentMaxWidth = 1000;
  static const double sheetMaxWidth = 560;
  static const double navMaxWidth = 700;
  static const double settingsMaxWidth = 700;

  /// Ungefärlig höjd för bottennav + marginal (scroll-padding).
  static const double navScrollPadding = 100;

  static WindowSize of(BuildContext context) =>
      fromWidth(MediaQuery.sizeOf(context).width);

  static WindowSize fromWidth(double width) {
    if (width < compactBreakpoint) return WindowSize.compact;
    if (width < wideBreakpoint) return WindowSize.medium;
    return WindowSize.wide;
  }

  bool get isCompact => this == WindowSize.compact;
  bool get isMedium => this == WindowSize.medium;
  bool get isWide => this == WindowSize.wide;

  /// ≥ 600 — mer yta (ingen 430-klämma, capped sheets).
  bool get isExpanded => this != WindowSize.compact;
}

/// Centrerar bottom sheets till [WindowSize.sheetMaxWidth] på icke-kompakt.
Widget wrapBottomSheet(BuildContext context, Widget child) {
  if (WindowSize.of(context).isCompact) return child;
  return Align(
    alignment: Alignment.bottomCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: WindowSize.sheetMaxWidth),
      child: SizedBox(width: double.infinity, child: child),
    ),
  );
}
