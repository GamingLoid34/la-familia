/// Tickets are short-lived, single-use, and kept only in memory after capture.
String? calendarConnectionTicket(Uri uri) {
  try {
    final fragment = Uri.parse(uri.fragment);
    if (fragment.path != '/calendar-connect') return null;
    final ticket = fragment.queryParameters['ticket'];
    return ticket != null && RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(ticket)
        ? ticket
        : null;
  } on FormatException {
    return null;
  }
}
