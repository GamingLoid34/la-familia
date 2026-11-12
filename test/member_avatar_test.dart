import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/models/user_model.dart';
import 'package:la_familia/widgets/member_avatar.dart';

void main() {
  group('FamilyMemberAvatar fallback- och förhandsvisningstester', () {
    testWidgets('null-url visar initial på profilfärg (ingen tom cirkel)',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FamilyMemberAvatar.raw(
              name: 'Lionel',
              avatarUrl: null,
              color: Color(0xFF2196F3),
              size: 50,
            ),
          ),
        ),
      );

      expect(find.text('L'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is ColoredBox && w.color == const Color(0xFF2196F3),
        ),
        findsOneWidget,
      );
    });

    testWidgets('tom sträng som url visar initial',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FamilyMemberAvatar.raw(
              name: 'Céline',
              avatarUrl: '   ',
              color: Color(0xFFE91E63),
              size: 50,
            ),
          ),
        ),
      );

      expect(find.text('C'), findsOneWidget);
    });

    testWidgets('felande bild-URL faller tillbaka till initial (tom cirkel uppstår aldrig)',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FamilyMemberAvatar.raw(
              name: 'Milo',
              avatarUrl: 'https://invalid-host.example.com/broken_avatar.jpg',
              color: Color(0xFF4CAF50),
              size: 50,
            ),
          ),
        ),
      );

      // Pumpa frames så eventuella nätverksfel fångas av errorWidget
      await tester.pumpAndSettle();

      expect(find.text('M'), findsOneWidget);
    });

    testWidgets('previewBytes från XFile.readAsBytes visar minnesbild över baslager',
        (WidgetTester tester) async {
      // 1x1 transparent GIF i minnet
      final dummyBytes = Uint8List.fromList([
        0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x01, 0x00,
        0x01, 0x00, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00,
        0xff, 0xff, 0xff, 0x21, 0xf9, 0x04, 0x01, 0x00,
        0x00, 0x00, 0x00, 0x2c, 0x00, 0x00, 0x00, 0x00,
        0x01, 0x00, 0x01, 0x00, 0x00, 0x02, 0x02, 0x44,
        0x01, 0x00, 0x3b
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FamilyMemberAvatar.raw(
              name: 'Noomi',
              avatarUrl: null,
              previewBytes: dummyBytes,
              color: const Color(0xFFFF9800),
              size: 50,
            ),
          ),
        ),
      );

      expect(find.byType(Image), findsOneWidget);
      expect(find.text('N'), findsOneWidget); // Baslagret finns alltid under
    });

    testWidgets('UserModel-konstruktorn läser namn och avatarUrl korrekt',
        (WidgetTester tester) async {
      final user = UserModel(
        uid: 'u123',
        name: 'Astrid',
        email: 'astrid@example.com',
        familyId: 'f1',
        role: 'parent',
        color: '#9C27B0',
        viewMode: 'parent',
        energy: 3,
        avatarUrl: null,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FamilyMemberAvatar(
              member: user,
              size: 48,
            ),
          ),
        ),
      );

      expect(find.text('A'), findsOneWidget);
    });
  });
}
