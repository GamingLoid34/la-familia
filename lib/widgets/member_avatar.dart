import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../models/user_model.dart';

/// Cirkelavatar med valfri bild, annars initial mot profilfärg.
class FamilyMemberAvatar extends StatelessWidget {
  final UserModel member;
  final double size;
  final double borderWidth;

  const FamilyMemberAvatar({
    super.key,
    required this.member,
    this.size = 48,
    this.borderWidth = 2.5,
  });

  @override
  Widget build(BuildContext context) {
    Color mc;
    try {
      mc = Color(member.colorValue as int);
    } catch (_) {
      mc = AppTheme.getDayAccentColor();
    }
    final initial =
        member.name.isNotEmpty ? member.name[0].toUpperCase() : '?';
    final url = member.avatarUrl;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: mc, width: borderWidth),
      ),
      child: ClipOval(
        child: url != null && url.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
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
                errorWidget: (_, __, ___) => ColoredBox(
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
