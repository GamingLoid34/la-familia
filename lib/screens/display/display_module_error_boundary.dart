import 'package:flutter/material.dart';
import 'display_log.dart';
import 'display_palette.dart';

/// Error boundary för moduler på storskärmen (FAS 6d Incident/Build 22).
///
/// Fångar undantag under modulens uppbyggnad och rendering.
/// Loggar `[render] <modul-id>: <första raden av felet>` till [DisplayLog],
/// vilket automatiskt reflekteras i `lastError` i hjärtslaget.
///
/// Renderar en säker fallback:
/// - För `persondag`: den klumpade ramen (beteendet före 6d via [fallbackBuilder]).
/// - För övriga moduler: en dämpad platta "Kunde inte visa `modul`".
/// Flutters grå ruta (ErrorWidget i release) tillåts aldrig synas på väggen.
class DisplayModuleErrorBoundary extends StatefulWidget {
  final String moduleId;
  final Widget? child;
  final WidgetBuilder? childBuilder;
  final Widget Function(BuildContext context, Object error)? fallbackBuilder;
  final DisplayPalette displayPalette;

  const DisplayModuleErrorBoundary({
    super.key,
    required this.moduleId,
    this.child,
    this.childBuilder,
    this.fallbackBuilder,
    this.displayPalette = DisplayPalette.light,
  }) : assert(child != null || childBuilder != null, 'Antingen child eller childBuilder måste anges');

  static bool _initialized = false;

  /// Initierar den globala ErrorWidget.builder-omdirigeringen så att
  /// fel i delträd fångas och kopplas till närmaste DisplayModuleErrorBoundary.
  static void initialize() {
    if (_initialized) return;
    _initialized = true;
    ErrorWidget.builder = (FlutterErrorDetails details) {
      return _ModuleErrorFallbackWidget(details: details);
    };
  }

  @override
  State<DisplayModuleErrorBoundary> createState() => DisplayModuleErrorBoundaryState();
}

class DisplayModuleErrorBoundaryState extends State<DisplayModuleErrorBoundary> {
  Object? _caughtError;
  bool _hasLogged = false;

  void notifyError(Object error, StackTrace? stack) {
    if (_hasLogged) return;
    _hasLogged = true;
    _caughtError = error;
    final firstLine = error.toString().split('\n').first.trim();
    DisplayLog.instance.log('render', '${widget.moduleId}: $firstLine');
    if (mounted) {
      setState(() {});
    }
  }

  Widget buildFallback(BuildContext context, Object error) {
    if (widget.fallbackBuilder != null) {
      return widget.fallbackBuilder!(context, error);
    }
    return _buildDefaultPlate(context);
  }

  Widget _buildDefaultPlate(BuildContext context) {
    final palette = widget.displayPalette;
    return Container(
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.cardBorder),
      ),
      padding: const EdgeInsets.all(20),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: palette.textMuted,
            size: 28,
          ),
          const SizedBox(height: 8),
          Text(
            'Kunde inte visa ${widget.moduleId}',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: palette.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_caughtError != null) {
      return buildFallback(context, _caughtError!);
    }
    try {
      return widget.child ?? widget.childBuilder!(context);
    } catch (e, stack) {
      notifyError(e, stack);
      return buildFallback(context, e);
    }
  }
}

class _ModuleErrorFallbackWidget extends StatefulWidget {
  final FlutterErrorDetails details;
  const _ModuleErrorFallbackWidget({required this.details});

  @override
  State<_ModuleErrorFallbackWidget> createState() => _ModuleErrorFallbackWidgetState();
}

class _ModuleErrorFallbackWidgetState extends State<_ModuleErrorFallbackWidget> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final boundary = context.findAncestorStateOfType<DisplayModuleErrorBoundaryState>();
    if (boundary != null) {
      boundary.notifyError(widget.details.exception, widget.details.stack);
    }
  }

  @override
  Widget build(BuildContext context) {
    final boundary = context.findAncestorStateOfType<DisplayModuleErrorBoundaryState>();
    if (boundary != null) {
      return boundary.buildFallback(context, widget.details.exception);
    }
    // Utanför modulboundary: visa dämpad neutral ruta istället för grå release-ruta
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.all(16),
      child: const Text(
        'Kunde inte visa innehåll',
        style: TextStyle(
          fontFamily: 'Nunito',
          fontSize: 14,
          color: Color(0xFF888899),
        ),
      ),
    );
  }
}
