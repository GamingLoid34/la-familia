// Granskning 2026-09-25, punkt 3: ett nekat sparande får inte kasta texten.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/widgets/compose_note_sheet.dart';

void main() {
  testWidgets('nekad sparning öppnar formuläret igen med texten kvar', (tester) async {
    var attempts = 0;
    ComposedNote? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              result = await composeUntilSaved(
                context,
                people: const [],
                describeError: (e) => 'Kunde inte spara: nekad.',
                save: (note) async {
                  attempts++;
                  if (attempts == 1) throw Exception('permission-denied');
                  return true;
                },
              );
            },
            child: const Text('öppna'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('öppna'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Utflykt torsdag, ta med matsäck.');
    await tester.pump();
    await tester.tap(find.text('Spara'));
    await tester.pumpAndSettle();

    // Första försöket nekades: formuläret är öppet igen, texten finns kvar.
    expect(attempts, 1);
    expect(find.text('Utflykt torsdag, ta med matsäck.'), findsOneWidget);
    expect(find.textContaining('Texten finns kvar'), findsOneWidget);

    await tester.tap(find.text('Spara'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(result?.text, 'Utflykt torsdag, ta med matsäck.');
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('stänger användaren formuläret sparas ingenting', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => composeUntilSaved(context,
                people: const [],
                describeError: (_) => 'fel',
                save: (_) async {
                  attempts++;
                  return true;
                }),
            child: const Text('öppna'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('öppna'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Stäng'));
    await tester.pumpAndSettle();
    expect(attempts, 0);
  });
}
