import 'package:flutter/material.dart';
import '../widgets/min_dag_view.dart';

/// Helskärmsvy "Min dag" — proportionell tidsaxel med vandrande NU-linje
/// för tidsorientering, minnesstöd och sjukhusmatsedel efter stroke.
/// Stöder dagbläddring med dagsfärger (FAS D2).
class MinDagPage extends StatelessWidget {
  const MinDagPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const MinDagView(embedded: false);
  }
}
