import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:la_familia/screens/display/family_wall.dart';

void main() {
  test('work shifts and activities share chronological order', () {
    final rows = sortWallRows(const [
      WallEntry('Kväll', '20:00–21:00'),
      WallEntry('Arbete', '19:00–07:00'),
      WallEntry('Ledigt', 'Hela dagen'),
    ]);
    expect(rows.map((e) => e.title), ['Ledigt', 'Arbete', 'Kväll']);
  });
  test('rotation shows every row without scrolling and wraps', () {
    final rows = List.generate(13, (i) => i);
    expect([for (var i = 0; i < 3; i++) ...wallPage(rows, 5, i)], rows);
    expect(wallPage(rows, 5, 3), rows.take(5));
    expect(wallPage<int>([], 5, 0), isEmpty);
  });
  for (final size in [
    const Size(1920, 1080),
    const Size(1280, 720),
    const Size(960, 540),
  ]) {
    testWidgets('wall fits $size with a busy family and tasks', (tester) async {
      await initializeDateFormatting('sv_SE');
      final font = FontLoader('Nunito')
        ..addFont(rootBundle.load('assets/fonts/Nunito-Regular.ttf'));
      await font.load();
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final rows = List.generate(
        24,
        (i) => WallEntry(
          'Träning och en ovanligt lång aktivitetstitel $i',
          '07:30–08:30 · Alexander, Elisabeth · Sporthallen',
        ),
      );
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(fontFamily: 'Nunito'),
            home: FamilyWallBoard(
              now: DateTime(2026, 10, 26, 7, 30),
              members: const [
                'Oscar',
                'Sofia',
                'Barn 1',
                'Barn 2',
                'Barn 3',
                'Barn 4',
              ],
              today: rows,
              upcoming: rows,
              tasks: rows,
              showTasks: true,
              status: 'Ansluten · kontrollerad 07:30',
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(Scrollable), findsNothing);
      expect(find.text('07:30'), findsOneWidget);
      final folder = Platform.environment['WALL_SCREENSHOT'];
      if (folder != null) {
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 1);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '$folder/wall-${size.width.toInt()}.png',
          ).writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }
}
