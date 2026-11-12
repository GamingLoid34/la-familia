import 'dart:developer' as developer;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import '../app_theme.dart';
import '../models/user_model.dart';
import '../utils/date_utils.dart';
import '../utils/person_match.dart';

/// Matar hemskärms-widgeten (ROADMAP Etapp 13) med nästa aktivitet och
/// rutinstatus. Anropas debounced från FamilyProvider när datat ändras —
/// widgeten visar alltså senast kända läge (uppdateras även var 30:e min
/// av Android samt varje gång appen öppnas).
class WidgetService {
  static String? _lastPayload;

  static String _untilLabel(Duration left) {
    if (left.inMinutes < 1) return 'nu!';
    if (left.inMinutes < 60) return 'om ${left.inMinutes} min';
    final h = left.inHours;
    final m = left.inMinutes % 60;
    return m == 0 ? 'om $h h' : 'om $h h $m min';
  }

  static const _dayNames = [
    '', 'MÅNDAG', 'TISDAG', 'ONSDAG', 'TORSDAG', 'FREDAG', 'LÖRDAG', 'SÖNDAG'
  ];

  static Future<void> updateFromData({
    required UserModel? user,
    required List<QueryDocumentSnapshot> todayEvents,
    required List<QueryDocumentSnapshot> routines,
  }) async {
    if (kIsWeb || user == null) return;
    try {
      final now = DateTime.now();

      // Mina events idag med tid, sorterade.
      final mine = <({DateTime start, String title, String pik})>[];
      for (final doc in todayEvents) {
        final d = doc.data() as Map<String, dynamic>;
        if (!eventHasNoPersons(d) &&
            !eventIncludesPerson(d, uid: user.uid, name: user.name)) {
          continue;
        }
        final t = (d['time'] as String?)?.trim() ?? '';
        if (t.isEmpty) continue;
        final tp = t.split(':');
        if (tp.length < 2) continue;
        final start = DateTime(now.year, now.month, now.day,
            int.tryParse(tp[0]) ?? 0, int.tryParse(tp[1]) ?? 0);
        mine.add((
          start: start,
          title: d['title'] as String? ?? '',
          pik: d['piktogram'] as String? ?? '📅',
        ));
      }
      mine.sort((a, b) => a.start.compareTo(b.start));

      String title;
      String time;
      final upcoming = mine.where((e) => e.start.isAfter(now)).toList();
      final active = mine.where((e) =>
          e.start.isBefore(now) &&
          e.start.add(const Duration(hours: 1)).isAfter(now));
      if (upcoming.isNotEmpty) {
        final next = upcoming.first;
        title = '${next.pik} ${next.title}';
        final hh = next.start.hour.toString().padLeft(2, '0');
        final mm = next.start.minute.toString().padLeft(2, '0');
        time = '$hh:$mm · ${_untilLabel(next.start.difference(now))}';
      } else if (active.isNotEmpty) {
        final cur = active.first;
        title = '${cur.pik} ${cur.title}';
        time = 'Pågår nu';
      } else {
        title = 'Inget mer planerat idag 😌';
        time = '';
      }

      // Rutinstatus för rätt tid på dygnet.
      String routineLine = '';
      final wantedType =
          now.hour < 12 ? 'morning' : (now.hour >= 18 ? 'evening' : null);
      if (wantedType != null) {
        for (final doc in routines) {
          final d = doc.data() as Map<String, dynamic>;
          if (d['ownerUid'] != user.uid) continue;
          if ((d['type'] as String? ?? 'morning') != wantedType) continue;
          final steps = (d['steps'] as List? ?? []);
          if (steps.isEmpty) continue;
          final doneToday = (d['doneDate'] == dateKey(now))
              ? (d['doneSteps'] as List? ?? []).length
              : 0;
          final label = wantedType == 'morning' ? '🌅 Morgon' : '🌙 Kväll';
          routineLine = doneToday >= steps.length
              ? '$label: klart! 🌟'
              : '$label: $doneToday av ${steps.length} steg';
          break;
        }
      }

      final palette = AppTheme.dayPalette();
      final accentHex =
          '#${palette.base.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
      final header = 'LA FAMILIA · ${_dayNames[now.weekday]}';

      // Skriv bara om något faktiskt ändrats (spar batteri/IO).
      final payload = '$header|$title|$time|$routineLine|$accentHex';
      if (payload == _lastPayload) return;
      _lastPayload = payload;

      await HomeWidget.saveWidgetData<String>('header', header);
      await HomeWidget.saveWidgetData<String>('title', title);
      await HomeWidget.saveWidgetData<String>('time', time);
      await HomeWidget.saveWidgetData<String>('routine', routineLine);
      await HomeWidget.saveWidgetData<String>('accentColor', accentHex);
      await HomeWidget.updateWidget(
        name: 'NextActivityWidgetProvider',
        androidName: 'NextActivityWidgetProvider',
      );
    } catch (e, stack) {
      developer.log('WidgetService.updateFromData misslyckades',
          error: e, stackTrace: stack);
    }
  }
}
