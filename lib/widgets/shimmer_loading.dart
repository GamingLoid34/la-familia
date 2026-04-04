import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../app_theme.dart';

class ShimmerListPlaceholder extends StatelessWidget {
  const ShimmerListPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16.0),
      itemCount: 4,
      itemBuilder: (context, index) {
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          child: Shimmer.fromColors(
            baseColor: AppTheme.getCardColor().withOpacity(0.5),
            highlightColor: AppTheme.getCardColor(),
            child: Container(
              height: 70,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
              ),
            ),
          ),
        );
      },
    );
  }
}
