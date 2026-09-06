import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../providers/family_provider.dart';

/// Typografi- och måttskala för Storskärmsläget (FAS 1.2).
/// All text är i Nunito och anpassad för läsbarhet på 3–4 meters avstånd.
class DisplayTheme {
  DisplayTheme._();

  // ─── Fontstorlekar ────────────────────────────────────────────────────────
  static const double clockFontSize = 72.0;
  static const double weekNumFontSize = 44.0;
  static const double dateRangeFontSize = 20.0;
  static const double dayNameFontSize = 26.0;
  static const double dayDateFontSize = 18.0;
  static const double weatherFontSize = 18.0;
  static const double memberNameFontSize = 24.0;
  static const double chipTimeFontSize = 20.0;
  static const double chipTitleFontSize = 21.0;
  static const double ramTextFontSize = 19.0;
  static const double footerFontSize = 22.0;
  static const double footerSubFontSize = 18.0;
  static const double moreCountFontSize = 18.0;

  // ─── Layoutmått ───────────────────────────────────────────────────────────
  static const double headerHeight = 96.0;
  static const double dayHeaderHeight = 74.0;
  static const double footerHeight = 112.0;
  static const double memberColWidth = 190.0;
  static const double ramEstimatedHeight = 36.0;
  static const double activityEstimatedHeight = 58.0;

  // ─── Textstilar ───────────────────────────────────────────────────────────
  static const TextStyle clockStyle = TextStyle(
    fontFamily: 'Nunito',
    fontSize: clockFontSize,
    fontWeight: FontWeight.w800,
    letterSpacing: -1.0,
    height: 1.0,
  );

  static const TextStyle weekNumStyle = TextStyle(
    fontFamily: 'Nunito',
    fontSize: weekNumFontSize,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.5,
    height: 1.0,
  );

  static const TextStyle dateRangeStyle = TextStyle(
    fontFamily: 'Nunito',
    fontSize: dateRangeFontSize,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle dayNameStyle = TextStyle(
    fontFamily: 'Nunito',
    fontSize: dayNameFontSize,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.3,
  );

  static const TextStyle memberNameStyle = TextStyle(
    fontFamily: 'Nunito',
    fontSize: memberNameFontSize,
    fontWeight: FontWeight.w700,
  );

  static const TextStyle chipTimeStyle = TextStyle(
    fontFamily: 'Nunito',
    fontSize: chipTimeFontSize,
    fontWeight: FontWeight.w800,
    height: 1.1,
  );

  static const TextStyle chipTitleStyle = TextStyle(
    fontFamily: 'Nunito',
    fontSize: chipTitleFontSize,
    fontWeight: FontWeight.w700,
    height: 1.15,
  );

  static const TextStyle ramTextStyle = TextStyle(
    fontFamily: 'Nunito',
    fontSize: ramTextFontSize,
    fontWeight: FontWeight.w600,
    height: 1.15,
  );

  static const TextStyle footerStyle = TextStyle(
    fontFamily: 'Nunito',
    fontSize: footerFontSize,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle moreCountStyle = TextStyle(
    fontFamily: 'Nunito',
    fontSize: moreCountFontSize,
    fontWeight: FontWeight.w800,
  );

  static const TextStyle feedbackPillStyle = TextStyle(
    fontFamily: 'Nunito',
    fontSize: 18.0,
    fontWeight: FontWeight.w700,
    color: Colors.white,
  );

  static const TextStyle headerIndicatorStyle = TextStyle(
    fontFamily: 'Nunito',
    fontSize: 16.0,
    fontWeight: FontWeight.w700,
  );
}

/// Diskret synkstämpel för storskärmens nedre hörn (FAS 2.2 & 3).
class DisplaySyncStamp extends StatelessWidget {
  const DisplaySyncStamp({super.key});

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) {
        // Vi hämtar från FamilyProvider om tillgänglig i trädet
        final provider = Provider.of<FamilyProvider?>(context);
        if (provider == null) return const SizedBox.shrink();

        final lastSync = provider.lastSyncAt;
        final hasSyncErr = provider.syncError;
        final timeStr = lastSync != null
            ? DateFormat('HH:mm').format(lastSync)
            : null;
        final syncLabel =
            timeStr != null ? 'Synk $timeStr · La Familia' : 'La Familia';

        if (hasSyncErr) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 14,
                color: Colors.amber.shade900,
              ),
              const SizedBox(width: 4),
              Text(
                syncLabel,
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.amber.shade900,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          );
        }

        return Text(
          syncLabel,
          style: TextStyle(
            fontFamily: 'Nunito',
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Colors.grey.shade400,
            letterSpacing: 0.6,
          ),
        );
      },
    );
  }
}
