import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/widgets/settings_group.dart';

void main() {
  testWidgets('gruppen öppnar valen utan att ändra dem och kan stängas', (tester) async {
    var changes = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox(width: 320,
      child: ListView(children: [SettingsGroup(title: 'Min vy', summary: 'Välj hur appen ska se ut för dig',
        children: [SwitchListTile(title: const Text('Lugnare utseende'),
          value: false, onChanged: (_) => changes++)])]),
    ))));
    expect(find.text('Lugnare utseende'), findsNothing);
    await tester.tap(find.text('Min vy'));
    await tester.pumpAndSettle();
    expect(find.text('Lugnare utseende'), findsOneWidget);
    expect(changes, 0);
    await tester.tap(find.byType(Switch));
    expect(changes, 1);
    await tester.tap(find.text('Min vy'));
    await tester.pumpAndSettle();
    expect(find.text('Lugnare utseende'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
