const calendarAccountSyncEnabled = bool.fromEnvironment(
  'CALENDAR_ACCOUNT_SYNC',
);

String calendarProviderName(String provider) => switch (provider) {
  'google' => 'Google Kalender',
  'outlook' => 'Outlook',
  'icloud' => 'iCloud / Apple Kalender',
  _ => 'Kalender',
};

bool canConnectCalendar(String? role) =>
    const {'parent', 'admin', 'youth'}.contains(role);

bool safeCalendarAuthorizationUrl(String value) {
  final uri = Uri.tryParse(value);
  return uri != null &&
      uri.scheme == 'https' &&
      uri.userInfo.isEmpty &&
      uri.port == 443 &&
      const {
        'accounts.google.com',
        'login.microsoftonline.com',
      }.contains(uri.host);
}

String calendarConnectionStatus(String? status) => switch (status) {
  'authorized' => 'Välj kalender för att starta synken',
  'connected' => 'Ansluten',
  'paused' => 'Synken är pausad',
  'disconnected' => 'Frånkopplad',
  _ => 'Kontrollera anslutningen',
};

String calendarConflictVersion(Map<String, dynamic>? version) {
  if (version == null) return 'Ingen version finns kvar.';
  if (version['deleted'] == true) return 'Aktiviteten har tagits bort.';
  final time = [
    version['time'],
    version['endTime'],
  ].whereType<String>().where((value) => value.isNotEmpty).join('–');
  return [
    version['title'],
    version['date'],
    time,
  ].whereType<String>().where((value) => value.isNotEmpty).join('\n');
}
