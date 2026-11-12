import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/widgets/quick_add_bar.dart';

void main() {
  testWidgets('quick entry exposes speech and still allows typing', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: QuickAddBar(familyMembers: [], familyId: 'test-family'),
        ),
      ),
    );
    expect(find.byTooltip('Tala in'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Träning på fredag');
    expect(find.text('Träning på fredag'), findsOneWidget);
  });
}
