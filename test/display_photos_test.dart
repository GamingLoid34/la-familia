import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/models/display_photo_model.dart';
import 'package:la_familia/screens/display/display_controller.dart';
import 'package:la_familia/screens/display/display_scene_models.dart';
import 'package:la_familia/screens/display/modules/foto_module.dart';

void main() {
  group('PhotoPlaylist', () {
    final photo1 = DisplayPhotoModel(
      id: 'p1',
      url: 'https://example.com/p1.jpg',
      storagePath: 'families/f1/display_photos/p1.jpg',
      createdAt: DateTime(2026, 1, 1),
      uploadedBy: 'u1',
    );
    final photo2 = DisplayPhotoModel(
      id: 'p2',
      url: 'https://example.com/p2.jpg',
      storagePath: 'families/f1/display_photos/p2.jpg',
      createdAt: DateTime(2026, 1, 2),
      uploadedBy: 'u1',
    );
    final photo3 = DisplayPhotoModel(
      id: 'p3',
      url: 'https://example.com/p3.jpg',
      storagePath: 'families/f1/display_photos/p3.jpg',
      createdAt: DateTime(2026, 1, 3),
      uploadedBy: 'u1',
    );

    test('tom spellista hanteras säkert', () {
      final playlist = PhotoPlaylist(photos: []);
      expect(playlist.isEmpty, isTrue);
      expect(playlist.currentPhoto, isNull);
      expect(playlist.nextPhoto(), isNull);
      expect(playlist.validCount, equals(0));
    });

    test('enstaka foto loopar utan krasch', () {
      final playlist = PhotoPlaylist(photos: [photo1]);
      expect(playlist.isEmpty, isFalse);
      expect(playlist.validCount, equals(1));
      expect(playlist.currentPhoto?.id, equals('p1'));

      final next = playlist.nextPhoto();
      expect(next?.id, equals('p1'));
      expect(playlist.currentPhoto?.id, equals('p1'));
    });

    test('rotation utan omedelbar upprepning vid omgångsslut', () {
      // Skapa spellista med 3 foton och kör genom 60 cykler
      final playlist = PhotoPlaylist(
        photos: [photo1, photo2, photo3],
        random: Random(42),
      );

      var previous = playlist.currentPhoto;
      expect(previous, isNotNull);

      for (int i = 0; i < 60; i++) {
        final current = playlist.nextPhoto();
        expect(current, isNotNull);
        expect(
          current!.id,
          isNot(equals(previous!.id)),
          reason: 'Foto ${current.id} visades omedelbart efter ${previous.id} vid steg $i',
        );
        previous = current;
      }
    });

    test('trasiga URL:er markeras och utesluts ur kön', () {
      final playlist = PhotoPlaylist(
        photos: [photo1, photo2, photo3],
        random: Random(100),
      );

      expect(playlist.validCount, equals(3));

      // Markera photo2 som trasig
      final marked = playlist.markBroken(photo2.url);
      expect(marked, isTrue);
      expect(playlist.brokenUrls.contains(photo2.url), isTrue);
      expect(playlist.validCount, equals(2));

      // Återupprepad markering returnerar false
      expect(playlist.markBroken(photo2.url), isFalse);

      // Verifiera att photo2 aldrig dyker upp vid rotation
      for (int i = 0; i < 20; i++) {
        final current = playlist.nextPhoto();
        expect(current?.id, isNot(equals('p2')));
      }
    });

    test('om alla foton markeras som trasiga blir spellistan tom', () {
      final playlist = PhotoPlaylist(
        photos: [photo1, photo2],
        random: Random(1),
      );

      playlist.markBroken(photo1.url);
      playlist.markBroken(photo2.url);

      expect(playlist.isEmpty, isTrue);
      expect(playlist.currentPhoto, isNull);
      expect(playlist.nextPhoto(), isNull);
    });

    test('updatePhotos uppdaterar kön och bevarar aktivt foto om det finns kvar', () {
      final playlist = PhotoPlaylist(
        photos: [photo1, photo2],
        random: Random(5),
      );

      final activeBefore = playlist.currentPhoto;
      expect(activeBefore, isNotNull);

      // Uppdatera med photo3 tillagd
      playlist.updatePhotos([photo1, photo2, photo3]);

      expect(playlist.validCount, equals(3));
      expect(playlist.currentPhoto?.id, equals(activeBefore!.id));
    });
  });

  group('DisplayConfig v4+ & Fotoscen', () {
    test('defaultConfig har version 10 och innehåller scenen foto', () {
      final config = DisplayConfig.defaultConfig();
      expect(config.version, equals(10));
      expect(config.scenes.containsKey('foto'), isTrue);

      final fotoScene = config.scenes['foto']!;
      expect(fotoScene.id, equals('foto'));
      expect(fotoScene.name, equals('Foton'));
      expect(fotoScene.layout, equals('fullscreen'));
      expect(fotoScene.modules['main'], equals('foto'));
    });

    test('defaultRawMap har version 10 och fotoscen', () {
      final raw = DisplayConfig.defaultRawMap();
      expect(raw['version'], equals(10));
      expect(raw['scenes'], isA<Map>());
      final scenes = raw['scenes'] as Map;
      expect(scenes.containsKey('foto'), isTrue);
      final fotoScene = scenes['foto'] as Map;
      expect(fotoScene['name'], equals('Foton'));
      expect(fotoScene['layout'], equals('fullscreen'));
      expect(fotoScene['modules']['main'], equals('foto'));
    });

    test('parseWithFallback parsar giltig konfig korrekt', () {
      final raw = DisplayConfig.defaultRawMap();
      final parsed = DisplayConfig.parseWithFallback(raw);
      expect(parsed.version, equals(10));
      expect(parsed.scenes.containsKey('foto'), isTrue);
    });

    test('DisplayController hanterar scene:foto med rätt kvittens', () {
      final config = DisplayConfig.defaultConfig();
      final controller = DisplayController(
        nowProvider: () => DateTime(2026, 3, 1, 12, 0),
        configProvider: () => config,
        onReload: ({String? replaceUrl}) {},
      );

      controller.handleCommand('scene:foto');

      expect(controller.feedbackMessage, equals('Foton'));
      expect(controller.effectiveSceneId(DateTime(2026, 3, 1, 12, 0)), equals('foto'));

      controller.dispose();
    });
  });
}
