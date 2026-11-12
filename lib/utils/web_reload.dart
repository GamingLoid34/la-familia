import 'web_reload_stub.dart'
    if (dart.library.js_interop) 'web_reload_web.dart';

/// Laddar om sidan på webben, ev. med ersatt URL ([replaceUrl]), no-op på övriga plattformar.
void reloadWebPage({String? replaceUrl}) =>
    reloadWebPageImpl(replaceUrl: replaceUrl);
