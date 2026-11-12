import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../utils/layout.dart';

/// Sidhuvud med titel, som Android-appens `VardagTitleHeader`: enfärgad yta i
/// färgrollen `header`, titel 28 Bold, samma höjd på alla flikar. [onBack]
/// visar en tillbakapil.
class VardagTitleHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onBack;
  final List<Widget> actions;

  const VardagTitleHeader({
    super.key,
    required this.title,
    this.onBack,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final textColor = AppTheme.headerTextColor();
    return Container(
      decoration: AppTheme.headerDecoration(),
      padding: AppTheme.paddingBelowStatusBar(context,
          horizontal: onBack != null ? 8 : 20, bottom: 12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            if (onBack != null)
              IconButton(
                icon: Icon(Icons.arrow_back_rounded, color: textColor, size: 26),
                tooltip: 'Tillbaka',
                onPressed: onBack,
              ),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
            ),
            ...actions,
          ],
        ),
      ),
    );
  }
}

/// Sidrubrik för en sektion direkt på sidbakgrunden ("ÖPPNA", "VARDAG" …).
class VardagSectionLabel extends StatelessWidget {
  final String text;
  final EdgeInsetsGeometry padding;
  const VardagSectionLabel(this.text,
      {super.key, this.padding = const EdgeInsets.fromLTRB(4, 16, 4, 8)});

  @override
  Widget build(BuildContext context) =>
      Padding(padding: padding, child: Text(text, style: AppTheme.sectionLabelStyle));
}

/// Kort i färgrollen `cardSurface` (radie 20 som Androids Mer/Inställningar).
class VardagCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  const VardagCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) => Container(
        margin: margin,
        padding: padding,
        decoration: AppTheme.cardDecoration(radius: 20),
        child: child,
      );
}

/// Ark som inte stängs av svep eller tryck utanför — bara av sina egna
/// knappar eller systemets Tillbaka (Androids `skyddatFormularState`).
Future<T?> showProtectedSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => wrapBottomSheet(ctx, builder(ctx)),
  );
}

/// Arkets ram: vit yta, rundade överhörn, rubrik och stängknapp.
class SheetFrame extends StatelessWidget {
  final String title;
  final Widget child;
  final List<Widget> actions;
  final VoidCallback? onClose;

  const SheetFrame({
    super.key,
    required this.title,
    required this.child,
    this.actions = const [],
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final kb = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: kb),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.92,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(title, style: AppTheme.sectionTitleStyle),
                  ),
                  ...actions,
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Stäng',
                    onPressed: onClose ?? () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
            ),
            Flexible(child: child),
          ],
        ),
      ),
    );
  }
}

/// Visa ett kort besked. [isError] ger röd bakgrund.
void showVardagSnack(
  BuildContext context,
  String message, {
  bool isError = false,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(
    content: Text(message),
    backgroundColor: isError ? const Color(0xFFB3261E) : null,
    action: actionLabel != null && onAction != null
        ? SnackBarAction(label: actionLabel, onPressed: onAction)
        : null,
  ));
}
