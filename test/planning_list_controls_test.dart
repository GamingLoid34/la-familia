import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/models/planning_task.dart';
import 'package:la_familia/models/user_model.dart';
import 'package:la_familia/widgets/planning_tasks.dart';

void main() {
  testWidgets(
    'sort and child filter work on a narrow screen without losing task actions',
    (tester) async {
      tester.view.physicalSize = (const Size(320, 900));
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? toggled;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: PlanningTasksContent(
                  all: true,
                  tasks: const [
                    PlanningTask('a', {
                      'title': 'Gympapåse',
                      'dueDate': '2026-12-31',
                      'aboutUids': ['a'],
                    }),
                    PlanningTask('b', {
                      'title': 'Utflykt',
                      'dueDate': '2027-01-01',
                      'aboutUids': ['b'],
                    }),
                  ],
                  members: const [
                    UserModel(
                      uid: 'a',
                      name: 'Ada',
                      email: '',
                      color: 'ff2196f3',
                      role: 'child',
                      viewMode: 'child',
                      energy: 3,
                    ),
                    UserModel(
                      uid: 'b',
                      name: 'Bo',
                      email: '',
                      color: 'ff2196f3',
                      role: 'child',
                      viewMode: 'child',
                      energy: 3,
                    ),
                  ],
                  onToggle: (task) => toggled = task.id,
                  onShowAll: () {},
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Datum'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vecka').last);
      await tester.pumpAndSettle();
      expect(find.text('Vecka 53 · 2026'), findsOneWidget);
      await tester.tap(find.text('Alla personer').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ada').last);
      await tester.pumpAndSettle();
      expect(find.text('Gympapåse'), findsOneWidget);
      expect(find.text('Utflykt'), findsNothing);
      await tester.tap(find.byType(Checkbox));
      expect(toggled, 'a');
      expect(tester.takeException(), isNull);
    },
  );
}
