import 'package:web/web.dart' as web;

void clearCalendarReturnUrl() {
  // Never leave the completion ticket in browser history or subsequent URLs.
  final uri = Uri.base.replace(fragment: '/');
  web.window.history.replaceState(null, '', uri.toString());
}
