import 'package:flutter/material.dart';
import '../../app_theme.dart';
import 'display_formatters.dart';
import 'display_palette.dart';
import 'display_theme.dart';

/// Standard accentfärg för pågående post (#E65100).
const Color _ongoingAccentStandard = Color(0xFFE65100);

/// Dämpad terracotta för lågstimuli (NPF) (#C2654A, ur memberColorPalette).
const Color _ongoingAccentLowStimuli = Color(0xFFC2654A);

/// Hjälpklass för strukturerad data i ramplattor (FAS 4.3).
class _ParsedRamData {
  final String piktogram;
  final String label;
  final String time;

  const _ParsedRamData({
    required this.piktogram,
    required this.label,
    required this.time,
  });
}

/// Kontrollerar om en given textsträng ryms på en rad inom [maxWidth]
/// via exakt mätning med [TextPainter.layout] i den faktiska textstilen.
bool _doesTextFit({
  required String text,
  required TextStyle style,
  required double maxWidth,
}) {
  if (maxWidth <= 0 || maxWidth.isInfinite) return true;
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  return painter.width <= maxWidth;
}

/// Enhetlig badge-rendering för ramar och aktiviteter (PÅGÅR, nedräkning).
Widget _buildChipBadge(
  String text, {
  bool isOngoing = false,
  bool isLarge = false,
  bool isLowStimuli = false,
  DisplayPalette? palette,
}) {
  final ongoingColor = palette?.ongoingAccent(isLowStimuli: isLowStimuli) ??
      (isLowStimuli ? _ongoingAccentLowStimuli : _ongoingAccentStandard);
  final isDark = palette?.isDark ?? false;

  final defaultBg = isDark
      ? (palette?.textMuted.withValues(alpha: 0.15) ??
          const Color(0xFF98A2B3).withValues(alpha: 0.15))
      : const Color(0xFF2C3E50).withValues(alpha: 0.08);
  final defaultTextColor = isDark
      ? (palette?.textMuted ?? const Color(0xFF98A2B3))
      : const Color(0xFF4A5568);

  return Container(
    padding: EdgeInsets.symmetric(
      horizontal: isLarge ? 8 : 5,
      vertical: isLarge ? 3 : 1.5,
    ),
    decoration: BoxDecoration(
      color: isOngoing ? ongoingColor.withValues(alpha: 0.12) : defaultBg,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontFamily: 'Nunito',
        fontSize: isLarge ? 18 : 12,
        fontWeight: FontWeight.w800,
        color: isOngoing ? ongoingColor : defaultTextColor,
      ),
    ),
  );
}

/// Beräknar exakt bredd för en badge inklusive container-padding och marginal.
double _measureBadgeWidth(
  String text, {
  bool isLarge = false,
}) {
  final badgeStyle = TextStyle(
    fontFamily: 'Nunito',
    fontSize: isLarge ? 18.0 : 12.0,
    fontWeight: FontWeight.w800,
  );
  final painter = TextPainter(
    text: TextSpan(text: text, style: badgeStyle),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  final padding = isLarge ? 16.0 : 10.0;
  const gap = 4.0;
  return painter.width + padding + gap;
}

/// Ramhändelse för storskärmen (FAS 1.2, 2.2, 4, 4.3, 5.5 & 5.6):
/// Enrads platta, personens färg alpha 0.10, mörkgrå text (#333333).
/// Vid pågående post: accentram (#E65100, i lågstimuli dämpad #C2654A, 1.5px) + "PÅGÅR"-badge.
///
/// Adaptiv densitet (FAS 5.5 & 5.6, Korrigering 6d.5):
///   a) "piktogram · etikett · tid" i full storlek får plats -> visa allt (ingen omslutning).
///   b) Annars -> släpp etiketten: "piktogram · tid" i full storlek (>= 18 px) får plats (ingen omslutning).
///   c) Om (b) inte får plats -> FittedBox(scaleDown) som beslutat undantag från 5.6.
class DisplayRamPlate extends StatelessWidget {
  final String? text;
  final String? piktogram;
  final String? label;
  final String? time;
  final Color memberColor;
  final DisplayChipDensity? density;
  final bool isLarge;
  final bool isOngoing;
  final bool isLowStimuli;
  final String? badgeText;

  const DisplayRamPlate({
    super.key,
    this.text,
    this.piktogram,
    this.label,
    this.time,
    required this.memberColor,
    this.density,
    this.isLarge = false,
    this.isOngoing = false,
    this.isLowStimuli = false,
    this.badgeText,
  });

  _ParsedRamData _resolveData() {
    if (piktogram != null || label != null || time != null) {
      return _ParsedRamData(
        piktogram: (piktogram ?? '').trim(),
        label: (label ?? '').trim(),
        time: formatWallRange(time ?? ''),
      );
    }
    final raw = (text ?? '').trim();
    if (raw.isEmpty) {
      return const _ParsedRamData(piktogram: '', label: '', time: '');
    }
    final parts = raw.split(' · ');
    if (parts.length >= 3) {
      return _ParsedRamData(
        piktogram: parts.first.trim(),
        label: parts.sublist(1, parts.length - 1).join(' · ').trim(),
        time: formatWallRange(parts.last.trim()),
      );
    } else if (parts.length == 2) {
      final p1 = parts[1].trim();
      final isTime = RegExp(r'\d').hasMatch(p1) &&
          (p1.contains(':') || p1.contains('–') || p1.contains('-'));
      return _ParsedRamData(
        piktogram: parts[0].trim(),
        label: isTime ? '' : p1,
        time: isTime ? formatWallRange(p1) : '',
      );
    } else {
      return _ParsedRamData(
        piktogram: raw,
        label: '',
        time: '',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return _buildPlate(context, constraints.maxWidth);
      },
    );
  }

  Widget _buildPlate(BuildContext context, double maxWidth) {
    final palette = DisplayPalette.of(context);
    final parsed = _resolveData();
    final ramStyle = isLarge
        ? DisplayTheme.ramTextStyle.copyWith(fontSize: 23)
        : DisplayTheme.ramTextStyle;

    final badge = badgeText ?? (isOngoing ? 'PÅGÅR' : null);
    final effectiveLowStimuli = isLowStimuli || AppTheme.lowStimuli;
    final ongoingColor = palette.ongoingAccent(isLowStimuli: effectiveLowStimuli);
    final textColor = palette.ramPlateTextColor();

    final padding = isLarge
        ? const EdgeInsets.symmetric(horizontal: 14, vertical: 10)
        : const EdgeInsets.symmetric(horizontal: 8, vertical: 6);

    final availWidth = maxWidth - padding.horizontal;

    double badgeWidth = 0;
    if (badge != null && badge.isNotEmpty) {
      badgeWidth = _measureBadgeWidth(badge, isLarge: isLarge);
    }

    final maxTextWidth = availWidth - badgeWidth;

    final hasTime = parsed.time.isNotEmpty;
    final hasLabel = parsed.label.isNotEmpty;
    final hasPik = parsed.piktogram.isNotEmpty;

    bool fitsA = false;
    if (density != DisplayChipDensity.compact && hasLabel && hasTime) {
      final fullText = hasPik
          ? '${parsed.piktogram} · ${parsed.label} · ${parsed.time}'
          : '${parsed.label} · ${parsed.time}';
      fitsA = _doesTextFit(
        text: fullText,
        style: ramStyle,
        maxWidth: maxTextWidth,
      );
    }

    Widget content;
    if (fitsA) {
      // (a) Visa allt — ingen omslutning (innehållet är mätt att rymmas)
      content = Row(
        children: [
          Expanded(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasPik)
                  Text(
                    '${parsed.piktogram} · ',
                    style: ramStyle.copyWith(color: textColor),
                  ),
                Text(
                  parsed.label,
                  style: ramStyle.copyWith(color: textColor),
                ),
                Text(
                  ' · ${parsed.time}',
                  style: ramStyle.copyWith(color: textColor),
                ),
              ],
            ),
          ),
          if (badge != null && badge.isNotEmpty) ...[
            const SizedBox(width: 4),
            _buildChipBadge(
              badge,
              isOngoing: isOngoing,
              isLarge: isLarge,
              isLowStimuli: effectiveLowStimuli,
              palette: palette,
            ),
          ],
        ],
      );
    } else {
      // (b / c) Släpp etiketten: "piktogram · tid" i full storlek (>= 18 px)
      // Mät om (b) ryms i full storlek. Om inte -> gren c med FittedBox(scaleDown).
      final mainText = hasTime ? parsed.time : parsed.label;
      final bText = hasPik ? '${parsed.piktogram} · $mainText' : mainText;
      final fitsB = _doesTextFit(
        text: bText,
        style: ramStyle.copyWith(fontWeight: FontWeight.w800),
        maxWidth: maxTextWidth,
      );

      final rowContent = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasPik) ...[
            Text(
              parsed.piktogram,
              style: ramStyle.copyWith(color: textColor),
            ),
            Text(
              ' · ',
              style: ramStyle.copyWith(color: textColor),
            ),
          ],
          Text(
            mainText,
            style: ramStyle.copyWith(
              color: textColor,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      );

      content = Row(
        children: [
          Expanded(
            child: fitsB
                ? rowContent
                : FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: rowContent,
                  ),
          ),
          if (badge != null && badge.isNotEmpty) ...[
            const SizedBox(width: 4),
            _buildChipBadge(
              badge,
              isOngoing: isOngoing,
              isLarge: isLarge,
              isLowStimuli: effectiveLowStimuli,
              palette: palette,
            ),
          ],
        ],
      );
    }

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: palette.ramPlateBg(memberColor),
        borderRadius: BorderRadius.circular(8),
        border: isOngoing
            ? Border.all(
                color: ongoingColor,
                width: 1.5,
              )
            : null,
      ),
      child: content,
    );
  }
}

/// Aktivitetschip för storskärmen (FAS 1.2, 2.2, 4, 4.3, 5.5 & 5.6):
/// Vit chip med 3.5px vänsterkant i medlemsfärg, diskret skugga, 2 rader.
/// Titeln får ALDRIG släppas — den är innehållet.
/// Kompakt läge (FAS 4.3 & 5.6):
///   - Rad 1: piktogram + kompakt tid i full storlek (>= 18 px) (+ eventuell badge).
///   - Rad 2: titel på en rad med ellips (maxLines: 1, overflow: ellipsis).
///   - Minskat padding: EdgeInsets.fromLTRB(5, 3.5, 5, 3.5).
///   - Det enda mätbeslutet är om TIDRADEN ryms i full storlek; annars FittedBox(scaleDown) på enbart tidraden.
class DisplayActivityCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final Color memberColor;
  final bool isFolded;
  final bool isLowStimuli;
  final bool isOngoing;
  final bool isPast;
  final String? badgeText;
  final DisplayChipDensity? density;
  final bool isLarge;

  const DisplayActivityCard({
    super.key,
    required this.data,
    required this.memberColor,
    this.isFolded = false,
    this.isLowStimuli = false,
    this.isOngoing = false,
    this.isPast = false,
    this.badgeText,
    this.density,
    this.isLarge = false,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return _buildCard(context, constraints.maxWidth);
      },
    );
  }

  Widget _buildCard(BuildContext context, double maxWidth) {
    final palette = DisplayPalette.of(context);
    final t = (data['time'] as String? ?? '').trim();
    final end = (data['endTime'] as String? ?? '').trim();
    final pik = isFolded
        ? '👨👩👧👦'
        : (data['piktogram'] as String? ?? '📅').trim();
    final title = (data['title'] as String? ?? '').trim();

    final compactTime = formatWallRange(t, end);

    final timeStyle = isLarge
        ? DisplayTheme.chipTimeStyle.copyWith(
            fontSize: 26,
            color: palette.textPrimary,
          )
        : DisplayTheme.chipTimeStyle.copyWith(
            color: palette.textPrimary,
          );

    final titleStyle = isLarge
        ? DisplayTheme.chipTitleStyle.copyWith(
            fontSize: 26,
            color: palette.isDark ? palette.textPrimary : const Color(0xFF2C3E50),
          )
        : DisplayTheme.chipTitleStyle.copyWith(
            color: palette.isDark ? palette.textPrimary : const Color(0xFF2C3E50),
          );

    final effectiveLowStimuli = isLowStimuli || AppTheme.lowStimuli;
    final ongoingColor = palette.ongoingAccent(isLowStimuli: effectiveLowStimuli);
    final ongoingBorderLight = effectiveLowStimuli
        ? ongoingColor.withValues(alpha: 0.35)
        : (palette.isDark
            ? const Color(0xFFE65100).withValues(alpha: 0.40)
            : const Color(0xFFFFB74D));

    // Kompakt läge (FAS 4.3): minskad padding vid smal kolumn (< 220 px) eller explicit kompakt densitet
    final isCompact = density == DisplayChipDensity.compact ||
        (density == null && maxWidth < 220);

    final padding = isLarge
        ? (isCompact
            ? const EdgeInsets.fromLTRB(10, 7, 10, 7)
            : const EdgeInsets.fromLTRB(14, 10, 14, 10))
        : (isCompact
            ? const EdgeInsets.fromLTRB(5, 3.5, 5, 3.5)
            : const EdgeInsets.fromLTRB(7, 5, 7, 5));

    final hasTime = compactTime.isNotEmpty;
    final hasTitle = title.isNotEmpty;
    final hasBadge = badgeText != null && badgeText!.isNotEmpty;

    // Det enda mätbeslutet i aktivitetskort är om TIDRADEN ryms i full storlek;
    // annars vågrät rullning på enbart tidraden. Titeln släpps ALDRIG.
    final leftBorderW = isLarge
        ? (isOngoing ? 6.0 : 5.0)
        : (isOngoing ? 4.5 : 3.5);
    final rightBorderW = isOngoing ? 1.5 : 0.8;
    final availInnerWidth =
        maxWidth - padding.horizontal - leftBorderW - rightBorderW;

    double badgeW = 0.0;
    if (hasBadge) {
      badgeW = _measureBadgeWidth(badgeText!, isLarge: isLarge);
    }
    final availTimeWidth = availInnerWidth - badgeW;

    // Mät tidradens innehåll i full storlek med TextPainter.layout()
    double pikW = 0.0;
    if (pik.isNotEmpty) {
      final pPainter = TextPainter(
        text: TextSpan(
          text: pik,
          style: TextStyle(fontSize: isLarge ? 24.0 : 18),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      pikW = pPainter.width;
    }

    double timeW = 0.0;
    if (hasTime) {
      final tPainter = TextPainter(
        text: TextSpan(text: compactTime, style: timeStyle),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      timeW = tPainter.width;
    }

    final gap = (pik.isNotEmpty && hasTime) ? (isLarge ? 8.0 : 5.0) : 0.0;
    final neededTimeW = pikW + gap + timeW;
    final timeFits = availTimeWidth.isInfinite || neededTimeW <= availTimeWidth;

    final timeAndPikContent = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (pik.isNotEmpty)
          Text(pik, style: TextStyle(fontSize: isLarge ? 24.0 : 18)),
        if (pik.isNotEmpty && hasTime)
          SizedBox(width: isLarge ? 8 : 5),
        if (hasTime)
          Text(
            compactTime,
            style: timeStyle,
          ),
      ],
    );

    final row1 = Row(
      children: [
        Expanded(
          child: timeFits
              ? Align(
                  alignment: Alignment.centerLeft,
                  child: timeAndPikContent,
                )
              : FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: timeAndPikContent,
                ),
        ),
        if (hasBadge) ...[
          const SizedBox(width: 4),
          _buildChipBadge(
            badgeText!,
            isOngoing: isOngoing,
            isLarge: isLarge,
            isLowStimuli: effectiveLowStimuli,
            palette: palette,
          ),
        ],
      ],
    );

    // Rad 2: Titel på en rad med ellips (släpps ALDRIG)
    final row2 = Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: titleStyle,
    );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        row1,
        if (hasTitle) ...[
          SizedBox(height: isLarge ? 5 : 2),
          row2,
        ],
      ],
    );

    final card = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        boxShadow: effectiveLowStimuli
            ? null
            : [
                BoxShadow(
                  color: isOngoing
                      ? const Color(0xFFE65100).withValues(alpha: 0.15)
                      : (palette.isDark
                          ? Colors.black.withValues(alpha: 0.25)
                          : Colors.black.withValues(alpha: 0.04)),
                  blurRadius: isOngoing ? 6 : 4,
                  offset: const Offset(0, 1),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
            color: palette.card,
            border: Border(
              left: BorderSide(
                color: isOngoing ? ongoingColor : memberColor,
                width: leftBorderW,
              ),
              top: BorderSide(
                color: isOngoing ? ongoingBorderLight : palette.cardBorder,
                width: isOngoing ? 1.5 : 0.8,
              ),
              right: BorderSide(
                color: isOngoing ? ongoingBorderLight : palette.cardBorder,
                width: rightBorderW,
              ),
              bottom: BorderSide(
                color: isOngoing ? ongoingBorderLight : palette.cardBorder,
                width: isOngoing ? 1.5 : 0.8,
              ),
            ),
          ),
          padding: padding,
          child: content,
        ),
      ),
    );

    if (isPast) {
      return Opacity(
        opacity: 0.45,
        child: card,
      );
    }

    return card;
  }
}
