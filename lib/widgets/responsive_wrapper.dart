// Create this file: lib/widgets/responsive_wrapper.dart

import 'package:flutter/material.dart';

class ResponsiveWrapper extends StatelessWidget {
  final Widget child;
  final double maxWidth = 430;

  const ResponsiveWrapper({
    super.key,
    required this.child,
    this.maxWidth = 430,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
