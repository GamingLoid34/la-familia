import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../display_module_registry.dart';

/// Modul: Stor klocka + svenskt datum (FAS 3).
/// Utbruten ur nattvyn med stöd för inbränningsskydd och anpassningsbar dämpning.
class KlockaModule extends StatelessWidget {
  final DisplayModuleContext moduleContext;
  final bool dimmed;
  final bool burnInShift;
  final Color? customTextColor;

  const KlockaModule({
    super.key,
    required this.moduleContext,
    this.dimmed = false,
    this.burnInShift = false,
    this.customTextColor,
  });

  String _formatSwedishDate(DateTime dt) {
    final raw = DateFormat('EEEE d MMMM', 'sv_SE').format(dt);
    if (raw.isEmpty) return raw;
    return raw[0].toUpperCase() + raw.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final now = moduleContext.now;
    final timeStr = DateFormat('HH:mm').format(now);
    final dateStr = _formatSwedishDate(now);

    final dx = burnInShift ? ((now.hour * 37) % 70) - 35.0 : 0.0;
    final dy = burnInShift ? ((now.hour * 19) % 50) - 25.0 : 0.0;

    final clockColor = customTextColor ??
        (dimmed
            ? Colors.white.withValues(alpha: 0.32)
            : const Color(0xFF1A1A2E));

    final dateColor = customTextColor?.withValues(alpha: 0.75) ??
        (dimmed
            ? Colors.white.withValues(alpha: 0.25)
            : const Color(0xFF5C6877));

    Widget content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          timeStr,
          style: TextStyle(
            fontFamily: 'Nunito',
            fontSize: 110,
            fontWeight: FontWeight.w800,
            letterSpacing: -2.0,
            color: clockColor,
            height: 1.0,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          dateStr,
          style: TextStyle(
            fontFamily: 'Nunito',
            fontSize: 26,
            fontWeight: FontWeight.w600,
            color: dateColor,
          ),
        ),
      ],
    );

    if (burnInShift) {
      content = Transform.translate(
        offset: Offset(dx, dy),
        child: content,
      );
    }

    return Center(child: content);
  }
}
