import 'dart:developer' as developer;
import 'package:web/web.dart' as web;

/// Web-implementation: laddar om webbläsarsidan eller ersätter URL.
void reloadWebPageImpl({String? replaceUrl}) {
  try {
    if (replaceUrl != null && replaceUrl.isNotEmpty) {
      web.window.location.replace(replaceUrl);
    } else {
      web.window.location.reload();
    }
  } catch (e, stack) {
    developer.log('Kunde inte ladda om sidan via package:web',
        error: e, stackTrace: stack);
  }
}
