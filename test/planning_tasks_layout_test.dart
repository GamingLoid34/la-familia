import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/models/planning_task.dart';
import 'package:la_familia/widgets/planning_tasks.dart';

void main() {
  test('sparfel skiljer behörighet, inloggning och borttagen post', () {
    expect(
      taskSaveErrorMessage('permission-denied'),
      contains('åtkomst nekad'),
    );
    expect(taskSaveErrorMessage('unauthenticated'), contains('Logga in igen'));
    expect(taskSaveErrorMessage('not-found'), contains('finns inte längre'));
    expect(taskSaveErrorMessage('unavailable'), contains('anslutningen'));
    expect(taskSaveErrorMessage('webbklient'), contains('Felkod: webbklient'));
  });
  final tasks = List.generate(
    25,
    (i) => PlanningTask('$i', {
      'title':
          'Uppgift $i med en lång förklaring från veckobrevet som måste få plats',
      'dueDate': '2026-10-22',
      'sourceNoteId': 'brev',
    }),
  );
  testWidgets('Hem begränsar lång lista till tre uppgifter och öppnar resten', (
    tester,
  ) async {
    String? toggled;
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: PlanningTasksContent(
                tasks: tasks,
                onToggle: (t) => toggled = t.id,
                onShowAll: () => opened = true,
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(CheckboxListTile), findsNWidgets(3));
    expect(find.text('Visa alla uppgifter (25 aktuella)'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(Checkbox).first);
    expect(toggled, '0');
    await tester.tap(find.text('Visa alla uppgifter (25 aktuella)'));
    expect(opened, isTrue);
  });
  testWidgets(
    'Alla uppgifter behåller hela listan och väntande skrivning spärras',
    (tester) async {
      var writes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PlanningTasksContent(
                tasks: tasks,
                all: true,
                saving: const {'0'},
                onToggle: (_) => writes++,
                onShowAll: () {},
              ),
            ),
          ),
        ),
      );
      expect(find.byType(CheckboxListTile), findsNWidgets(25));
      await tester.tap(find.byType(Checkbox).first);
      expect(writes, 0);
      expect(find.textContaining('Väntar på bekräftelse'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
