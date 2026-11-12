import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/utils/calendar_connection_ui.dart';

void main() {
  test('calendar accounts are offered only to parents, admins and youth', () {
    for (final role in ['parent', 'admin', 'youth']) {
      expect(canConnectCalendar(role), isTrue);
    }
    for (final role in ['child', 'unknown', '', null]) {
      expect(canConnectCalendar(role), isFalse);
    }
  });

  test('authorization links cannot escape the configured providers', () {
    expect(
      safeCalendarAuthorizationUrl(
        'https://accounts.google.com/o/oauth2/v2/auth?state=x',
      ),
      isTrue,
    );
    expect(
      safeCalendarAuthorizationUrl(
        'https://login.microsoftonline.com/common/oauth2/v2.0/authorize',
      ),
      isTrue,
    );
    for (final url in [
      'http://accounts.google.com/',
      'https://accounts.google.com.attacker.example/',
      'https://accounts.google.com@attacker.example/',
      'https://attacker@accounts.google.com/',
      'https://accounts.google.com:8443/',
      'javascript:alert(1)',
      '/relative',
    ]) {
      expect(safeCalendarAuthorizationUrl(url), isFalse, reason: url);
    }
  });

  test(
    'conflict display distinguishes missing, deleted and timed versions',
    () {
      expect(calendarConflictVersion(null), contains('Ingen version'));
      expect(
        calendarConflictVersion({'deleted': true, 'title': 'Gammalt namn'}),
        'Aktiviteten har tagits bort.',
      );
      expect(
        calendarConflictVersion({
          'title': 'Träning',
          'date': '2026-11-02',
          'time': '17:00',
          'endTime': '18:30',
        }),
        'Träning\n2026-11-02\n17:00–18:30',
      );
    },
  );
}
