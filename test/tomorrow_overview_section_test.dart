// Granskning 2026-09-25, punkt 2: "Inför i morgon" får inte ge ett lugnande
// besked när underlaget är ofullständigt eller en källa har fel.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/models/user_model.dart';
import 'package:la_familia/providers/family_provider.dart';
import 'package:la_familia/widgets/tomorrow_overview_section.dart';
import 'package:provider/provider.dart';

const _anna = UserModel(
  uid: 'p1', name: 'Anna', email: 'a@test', color: 'ff2A6F97',
  role: 'parent', viewMode: 'parent', energy: 3, familyId: '',
);

Future<void> _pump(WidgetTester tester, FamilyProvider p) async {
  await tester.pumpWidget(ChangeNotifierProvider<FamilyProvider>.value(
      value: p,
      child: MaterialApp(
        home: Scaffold(
          body: TomorrowOverviewSection(now: DateTime(2026, 9, 25, 12)),
        ),
      ),
    ));
  // Providerns fördröjda notifieringar/widgetuppdatering får löpa ut.
  await tester.pump(const Duration(seconds: 3));
}

void main() {
  const lugnt = 'Inget särskilt att förbereda i morgon';

  testWidgets('allt laddat och tomt ger det lugnande beskedet', (tester) async {
    await _pump(tester, FamilyProvider.fixed(currentUser: _anna, members: const [_anna]));
    expect(find.text(lugnt), findsOneWidget);
  });

  for (final kalla in FamilyProvider.overviewStreams) {
    testWidgets('$kalla inte laddad: laddar, inte lugnt', (tester) async {
      final p = FamilyProvider.fixed(currentUser: _anna, members: const [_anna])
        ..debugSetStream(kalla, loaded: false);
      await _pump(tester, p);
      expect(find.text(lugnt), findsNothing);
      expect(find.text('Läser inför i morgon…'), findsOneWidget);
    });

    testWidgets('$kalla med fel: felrad och Försök igen', (tester) async {
      final p = FamilyProvider.fixed(currentUser: _anna, members: const [_anna])
        ..debugSetStream(kalla, error: Exception('nekad'));
      await _pump(tester, p);
      expect(find.text(lugnt), findsNothing);
      expect(find.text('Kunde inte läsa underlaget för i morgon.'), findsOneWidget);
      expect(find.text('Försök igen'), findsOneWidget);
    });
  }
}
