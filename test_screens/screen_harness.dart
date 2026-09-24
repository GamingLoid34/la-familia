// Skärmdumpsverktyg för visuell kontroll av vyer utan enhet.
//
// Körs för hand (ligger utanför test/ och körs därför inte av `flutter test`):
//   flutter test test_screens/vardag_screens_test.dart
// PNG-filerna hamnar i build/screens/. Emojier ritas inte (testmiljön saknar
// emojitypsnitt); allt annat ritas med appens riktiga Nunito och Material-ikoner.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:la_familia/app_theme.dart';

Future<void> loadAppFonts() async {
  await initializeDateFormatting('sv_SE', null);
  await initializeDateFormatting('sv', null);
  final nunito = FontLoader('Nunito');
  for (final f in ['Regular', 'SemiBold', 'Bold', 'ExtraBold']) {
    nunito.addFont(
        Future.value(ByteData.sublistView(File('assets/fonts/Nunito-$f.ttf').readAsBytesSync())));
  }
  await nunito.load();
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? 'C:/flutter';
  final icons = FontLoader('MaterialIcons');
  icons.addFont(Future.value(ByteData.sublistView(File(
          '$flutterRoot/bin/cache/artifacts/material_fonts/materialicons-regular.otf')
      .readAsBytesSync())));
  await icons.load();
}

Widget screenApp(Widget home) => MaterialApp(
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('sv', 'SE')],
      locale: const Locale('sv', 'SE'),
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Nunito',
        colorScheme: ColorScheme.fromSeed(
            seedColor: AppTheme.dayPalette().base, brightness: Brightness.light),
        textTheme: AppTheme.appTextTheme(ThemeData.light().textTheme),
      ),
      home: home,
    );

/// Ritar [widget] i en telefonstor yta och sparar som build/screens/[name].png.
Future<void> snap(
  WidgetTester tester,
  String name,
  Widget widget, {
  Size size = const Size(412, 915),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  final key = GlobalKey();
  await tester.pumpWidget(RepaintBoundary(
    key: key,
    child: MediaQuery(
      data: MediaQueryData(
          size: size,
          devicePixelRatio: 2,
          textScaler: TextScaler.linear(textScale),
          padding: const EdgeInsets.only(top: 24)),
      child: widget,
    ),
  ));
  await tester.pump(const Duration(milliseconds: 400));
  // Bilder avkodas asynkront: förladda dem i den riktiga händelseloopen.
  await tester.runAsync(() async {
    for (final e in find.byType(Image).evaluate()) {
      final img = e.widget as Image;
      await precacheImage(img.image, e);
    }
  });
  await tester.pump();
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('build/screens')..createSync(recursive: true);
    File('${dir.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}
