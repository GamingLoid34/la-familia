import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../models/user_model.dart';

/// Cirkelavatar med valfri bild, annars initial mot profilfärg.
/// [presenceColor] ritar närvaroring (grön/gul/röd) utanpå.
class FamilyMemberAvatar extends StatelessWidget {
  final UserModel member;
  final double size;
  final double borderWidth;
  final Color? presenceColor;

  const FamilyMemberAvatar({
    super.key,
    required this.member,
    this.size = 48,
    this.borderWidth = 2.5,
    this.presenceColor,
  });

  @override
  Widget build(BuildContext context) {
    Color mc;
    try {
      mc = Color(member.colorValue);
    } catch (_) {
      mc = AppTheme.getDayAccentColor();
    }
    final initial =
        member.name.isNotEmpty ? member.name[0].toUpperCase() : '?';
    final url = member.avatarUrl;
    final ring = presenceColor;
    final ringW = ring != null ? 3.0 : borderWidth;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: ring ?? mc,
          width: ringW,
        ),
      ),
      child: ClipOval(
        child: url != null && url.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                placeholder: (_, _) => Container(
                  color: mc.withValues(alpha: 0.15),
                  child: Center(
                    child: SizedBox(
                      width: size * 0.4,
                      height: size * 0.4,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: mc,
                      ),
                    ),
                  ),
                ),
                errorWidget: (_, _, _) => ColoredBox(
                  color: mc,
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
              )
            : ColoredBox(
                color: mc,
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
      ),
    );
  }
}
