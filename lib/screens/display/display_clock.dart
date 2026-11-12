import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'display_log.dart';

/// Central klockkälla för Storskärmsläget (FAS 4.2).
///
/// Tillåter simulering av tid via URL-parametern:
///   `?display=1&testTime=YYYY-MM-DDTHH:mm`
///
/// Vid sidladdning beräknas en fast offset:
///   `offset = testTime − verklig now`
/// Skärmlagrets klocka = `verklig now + offset`, vilket innebär att
/// den simulerade tiden TICKAR vidare i normal takt så gränspassager
/// kan bevittnas live (t.ex. sätt 05:29, se 05:30 hända).
///
/// Ignoreras med logg om formatet är ogiltigt eller om `display != 1`.
class DisplayClock {
  DisplayClock._();

  static Duration _offset = Duration.zero;
  static bool _isTestTime = false;
  static DateTime Function() _realNowProvider = DateTime.now;

  /// Sant om en simulerad testtid är aktiv.
  static bool get isTestTime => _isTestTime;

  /// Fast offset mellan verklig tid och den simulerade tiden.
  static Duration get offset => _offset;

  /// Skärmlagrets nuvarande tid (verklig now + offset).
  static DateTime now() {
    return _realNowProvider().add(_offset);
  }

  /// Sätter provider för verklig tid (används främst i enhetstester).
  @visibleForTesting
  static void setRealNowProvider(DateTime Function() provider) {
    _realNowProvider = provider;
  }

  /// Återställer klockan till standardläge (verklig tid).
  static void reset() {
    _offset = Duration.zero;
    _isTestTime = false;
  }

  /// Initialiserar DisplayClock utifrån [uri] eller webbläsarens aktuella URL.
  static void init({
    Uri? uri,
    DateTime Function()? realNowProvider,
  }) {
    if (realNowProvider != null) {
      _realNowProvider = realNowProvider;
    }

    reset();

    final targetUri = uri ?? (kIsWeb ? Uri.base : null);
    if (targetUri == null) return;

    final isDisplay = targetUri.queryParameters['display'] == '1';
    final testTimeParam = targetUri.queryParameters['testTime'];

    if (testTimeParam == null || testTimeParam.trim().isEmpty) {
      return;
    }

    if (!isDisplay) {
      developer.log(
        'testTime ignoreras: aktiv endast tillsammans med display=1',
        name: 'DisplayClock',
      );
      return;
    }

    final parsed = parseTestTime(testTimeParam);
    if (parsed == null) {
      developer.log(
        'testTime ignoreras: ogiltigt format "$testTimeParam" (förväntar YYYY-MM-DDTHH:mm)',
        name: 'DisplayClock',
      );
      return;
    }

    final realNow = _realNowProvider();
    _offset = parsed.difference(realNow);
    _isTestTime = true;

    final offsetStr = formatOffset(_offset);
    DisplayLog.instance.log(
      'testtid',
      'testtid aktiverad (offset $offsetStr)',
    );
  }

  /// Tolkar sträng i formatet `YYYY-MM-DDTHH:mm` som lokal [DateTime].
  /// Returnerar null om formatet inte matchar exakt eller om datumet är ogiltigt.
  static DateTime? parseTestTime(String raw) {
    final trimmed = raw.trim();
    final regExp = RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$');
    if (!regExp.hasMatch(trimmed)) {
      return null;
    }
    try {
      final dt = DateTime.tryParse(trimmed);
      if (dt == null) return null;
      return dt;
    } catch (e, stack) {
      developer.log(
        'Kunde inte tolka testTime: $trimmed',
        name: 'DisplayClock',
        error: e,
        stackTrace: stack,
      );
      return null;
    }
  }

  /// Formaterar offset som `+Xh Ym` eller `-Xh Ym`.
  static String formatOffset(Duration d) {
    final totalMinutes = d.inMinutes;
    final sign = totalMinutes >= 0 ? '+' : '-';
    final absMin = totalMinutes.abs();
    final hours = absMin ~/ 60;
    final mins = absMin % 60;
    return '$sign${hours}h ${mins}m';
  }

  /// Formaterar banner-texten: `⚠ TESTTID · mån 7 sep 05:29`.
  static String formatBannerText(DateTime dt) {
    // intl sv_SE kan lägga till en punkt efter förkortningen (t.ex. "sep.").
    // Vi rensar eventuell avslutande punkt för att matcha specifikationen exakt.
    final dayName = DateFormat('EEE', 'sv_SE').format(dt).replaceAll('.', '');
    final monthName = DateFormat('MMM', 'sv_SE').format(dt).replaceAll('.', '');
    final timeStr = DateFormat('HH:mm').format(dt);
    return '⚠ TESTTID · $dayName ${dt.day} $monthName $timeStr';
  }
}
