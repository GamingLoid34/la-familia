import 'package:flutter/material.dart';
import 'display_formatters.dart';
import 'display_theme.dart';

/// Ramhändelse för storskärmen (FAS 1.2, 2.2 & 4):
/// Enrads platta, ingen kantlinje, personens färg alpha 0.10, mörkgrå text (#333333).
class DisplayRamPlate extends StatelessWidget {
  final String text;
  final Color memberColor;

  const DisplayRamPlate({
    super.key,
    required this.text,
    required this.memberColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: memberColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: DisplayTheme.ramTextStyle.copyWith(
          color: const Color(0xFF333333),
        ),
      ),
    );
  }
}

/// Aktivitetschip för storskärmen (FAS 1.2, 2.2 & 4):
/// Vit chip med 3.5px vänsterkant i medlemsfärg, diskret skugga, 2 rader.
/// Stödjer markering för pågående aktivitet ("PÅGÅR"), nedräkningsetikett och nedtoning vid passerad tid.
class DisplayActivityCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final Color memberColor;
  final bool isFolded;
  final bool isLowStimuli;
  final bool isOngoing;
  final bool isPast;
  final String? badgeText;

  const DisplayActivityCard({
    super.key,
    required this.data,
    required this.memberColor,
    this.isFolded = false,
    this.isLowStimuli = false,
    this.isOngoing = false,
    this.isPast = false,
    this.badgeText,
  });

  @override
  Widget build(BuildContext context) {
    final t = (data['time'] as String? ?? '').trim();
    final end = (data['endTime'] as String? ?? '').trim();
    final pik = isFolded
        ? '👨👩👧👦'
        : (data['piktogram'] as String? ?? '📅').trim();
    final title = (data['title'] as String? ?? '').trim();

    final compactTime = formatCompactTime(t, end);

    final card = Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
            color: isOngoing ? const Color(0xFFE65100) : memberColor,
            width: isOngoing ? 4.5 : 3.5,
          ),
          top: BorderSide(
            color: isOngoing ? const Color(0xFFFFB74D) : const Color(0xFFE2E5EE),
            width: isOngoing ? 1.5 : 0.8,
          ),
          right: BorderSide(
            color: isOngoing ? const Color(0xFFFFB74D) : const Color(0xFFE2E5EE),
            width: isOngoing ? 1.5 : 0.8,
          ),
          bottom: BorderSide(
            color: isOngoing ? const Color(0xFFFFB74D) : const Color(0xFFE2E5EE),
            width: isOngoing ? 1.5 : 0.8,
          ),
        ),
        boxShadow: isLowStimuli
            ? null
            : [
                BoxShadow(
                  color: isOngoing
                      ? const Color(0xFFE65100).withValues(alpha: 0.15)
                      : Colors.black.withValues(alpha: 0.04),
                  blurRadius: isOngoing ? 6 : 4,
                  offset: const Offset(0, 1),
                ),
              ],
      ),
      padding: const EdgeInsets.fromLTRB(7, 5, 7, 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Rad 1: Piktogram + kompakt tid + eventuell badge
          Row(
            children: [
              Text(pik, style: const TextStyle(fontSize: 17)),
              if (compactTime.isNotEmpty) ...[
                const SizedBox(width: 5),
                Text(
                  compactTime,
                  style: DisplayTheme.chipTimeStyle.copyWith(
                    color: const Color(0xFF1A1A2E),
                  ),
                ),
              ],
              if (badgeText != null && badgeText!.isNotEmpty) ...[
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: isOngoing
                        ? const Color(0xFFE65100).withValues(alpha: 0.12)
                        : const Color(0xFF2C3E50).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    badgeText!,
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: isOngoing
                          ? const Color(0xFFE65100)
                          : const Color(0xFF4A5568),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          // Rad 2: Titel (w700, max 1 rad, ellipsis)
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DisplayTheme.chipTitleStyle.copyWith(
              color: const Color(0xFF2C3E50),
            ),
          ),
        ],
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
