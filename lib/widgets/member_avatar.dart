import 'dart:typed_data';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../models/user_model.dart';

/// Cirkelavatar med valfri bild, annars initial mot profilfärg.
/// [presenceColor] ritar närvaroring (grön/gul/röd) utanpå.
/// [previewBytes] visar minnesbild direkt vid bildval (webbsäkert via XFile.readAsBytes()).
/// [overlay] visar valfri widget ovanpå (t.ex. laddningsindikator eller kameraikon).
class FamilyMemberAvatar extends StatelessWidget {
  final String name;
  final String? avatarUrl;
  final Color color;
  final double size;
  final double borderWidth;
  final bool showRing;
  final Color? presenceColor;
  final Uint8List? previewBytes;
  final Widget? overlay;

  const FamilyMemberAvatar.raw({
    super.key,
    required this.name,
    this.avatarUrl,
    required this.color,
    this.size = 48,
    this.borderWidth = 2.5,
    this.showRing = false,
    this.presenceColor,
    this.previewBytes,
    this.overlay,
  });

  FamilyMemberAvatar({
    Key? key,
    required UserModel member,
    double size = 48,
    double borderWidth = 2.5,
    bool showRing = false,
    Color? presenceColor,
    Uint8List? previewBytes,
    Widget? overlay,
  }) : this.raw(
          key: key,
          name: member.name,
          avatarUrl: member.avatarUrl,
          color: _parseColor(member.color),
          size: size,
          borderWidth: borderWidth,
          showRing: showRing,
          presenceColor: presenceColor,
          previewBytes: previewBytes,
          overlay: overlay,
        );

  static Color _parseColor(dynamic colorValue) {
    if (colorValue is Color) {
      return colorValue;
    }
    if (colorValue is int) {
      return Color(colorValue);
    }
    if (colorValue is String) {
      try {
        return AppTheme.colorFromHex(colorValue);
      } catch (_) {
        return AppTheme.getDayAccentColor();
      }
    }
    return AppTheme.getDayAccentColor();
  }

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    final ring = presenceColor;
    final hasBorder = ring != null || (showRing && borderWidth > 0);
    final ringW = ring != null ? 3.0 : borderWidth;
    final url = avatarUrl?.trim();

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: hasBorder
            ? Border.all(
                color: ring ?? color,
                width: ringW,
              )
            : null,
      ),
      child: ClipOval(
        child: Stack(
          alignment: Alignment.center,
          fit: StackFit.expand,
          children: [
            // 1. Baslager: initial på profilfärgen (syns ALLTID som fallback)
            ColoredBox(
              color: color,
              child: Center(
                child: Text(
                  initial,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: size * 0.38,
                  ),
                ),
              ),
            ),

            // 2. Förhandsvisningslager: minnesbild från XFile.readAsBytes()
            if (previewBytes != null)
              Image.memory(
                previewBytes!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    const SizedBox.shrink(),
              )
            // 3. Nätverkslager: CachedNetworkImage med feltolerant fallback till baslagret
            else if (url != null && url.isNotEmpty)
              CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                placeholder: (context, imageUrl) => const SizedBox.shrink(),
                errorWidget: (context, imageUrl, error) =>
                    const SizedBox.shrink(),
              ),

            // 4. Overlaylager: laddningsindikator eller kameraikon
            if (overlay != null)
              Container(
                color: Colors.black.withValues(alpha: 0.35),
                child: Center(child: overlay!),
              ),
          ],
        ),
      ),
    );
  }
}
