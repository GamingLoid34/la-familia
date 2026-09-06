import 'package:flutter/material.dart';
import '../data/stadzoner.dart';

/// Visar en färgprick med trasans etikett eller verktygsbeskrivning.
class TrasaChip extends StatelessWidget {
  final String? farg;
  final String? fargHex;
  final String? trasaLabel;
  final List<String> verktyg;
  final double circleSize;
  final TextStyle? textStyle;

  const TrasaChip({
    super.key,
    this.farg,
    this.fargHex,
    this.trasaLabel,
    this.verktyg = const [],
    this.circleSize = 18,
    this.textStyle,
  });

  /// Fabrik för att skapa TrasaChip direkt från en StadZon.
  factory TrasaChip.fromZon(StadZon zon, {double circleSize = 18, TextStyle? textStyle}) {
    return TrasaChip(
      farg: zon.farg,
      fargHex: zon.fargHex,
      trasaLabel: zon.trasaLabel,
      verktyg: zon.verktyg,
      circleSize: circleSize,
      textStyle: textStyle,
    );
  }

  Color _parseColor(String hex) {
    final clean = hex.replaceFirst('#', '');
    if (clean.length == 6) {
      return Color(int.parse('FF$clean', radix: 16));
    }
    return Colors.grey;
  }

  Color _borderColor(String? fargKey, Color baseColor) {
    if (fargKey == 'vit') {
      return const Color(0xFFBDBDBD);
    } else if (fargKey == 'gul') {
      return const Color(0xFFD4A017);
    } else if (fargKey == 'bla') {
      return const Color(0xFF2A6EB9);
    } else if (fargKey == 'rod') {
      return const Color(0xFFB83A3A);
    }
    return Colors.grey.shade400;
  }

  @override
  Widget build(BuildContext context) {
    final hasColor = farg != null && fargHex != null && fargHex!.isNotEmpty;

    if (hasColor) {
      final chipColor = _parseColor(fargHex!);
      final borderCol = _borderColor(farg, chipColor);
      final label = (trasaLabel != null && trasaLabel!.isNotEmpty)
          ? trasaLabel!
          : '${farg!.toUpperCase()} TRASA';

      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: circleSize,
            height: circleSize,
            decoration: BoxDecoration(
              color: chipColor,
              shape: BoxShape.circle,
              border: Border.all(
                color: borderCol,
                width: 1.5,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: textStyle ??
                const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
          ),
        ],
      );
    }

    // Färg saknas -> visa verktygen
    final toolText = verktyg.isNotEmpty ? verktyg.join(' · ') : 'Ingen trasa';
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(
          Icons.cleaning_services_rounded,
          size: circleSize * 0.85,
          color: Colors.grey.shade500,
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            toolText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textStyle ??
                TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                ),
          ),
        ),
      ],
    );
  }
}
