import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:la_familia/models/user_model.dart';
import 'package:la_familia/providers/family_provider.dart';
import 'package:la_familia/widgets/planning_tasks.dart';

class _Family extends ChangeNotifier implements FamilyProvider {
  @override
  final UserModel? currentUser;
  _Family(this.currentUser);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  // Firebase är avsiktligt inte initialiserat: även ett försök att starta en
  // tasks-fråga för barn/utloggad användare skulle fälla testet.
  for (final role in ['child', 'youth', 'signed-out', 'parent-without-family']) {
    testWidgets('$role startar ingen tasks-prenumeration', (tester) async {
      final user = role == 'signed-out' ? null : UserModel(
        uid: 'u', name: 'Test', email: '', color: 'ff2196f3',
        role: role == 'parent-without-family' ? 'parent' : role,
        viewMode: 'parent', energy: 3,
        familyId: role == 'parent-without-family' ? null : 'family',
      );
      final family = _Family(user);
      await tester.pumpWidget(ChangeNotifierProvider<FamilyProvider>.value(
        value: family, child: const MaterialApp(home: Scaffold(body: PlanningTasks())),
      ));
      expect(tester.takeException(), isNull);
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(find.text('Alla uppgifter'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      family.dispose();
    });
  }
}
