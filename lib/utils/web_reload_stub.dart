import 'dart:developer' as developer;

/// Stub för plattformar som inte är webb.
void reloadWebPageImpl({String? replaceUrl}) {
  developer.log(
      'reloadWebPage: Ej webbläsare, omladdning ignoreras (replaceUrl: $replaceUrl).');
}
