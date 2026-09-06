import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/screens/kalender_page.dart';

void main() {
  group('FAS V3 — KalenderLage 3-modes and migration', () {
    test('KalenderLage has exactly 3 modes: dag, vecka, manad', () {
      expect(KalenderLage.values.length, equals(3));
      expect(KalenderLage.values, contains(KalenderLage.dag));
      expect(KalenderLage.values, contains(KalenderLage.vecka));
      expect(KalenderLage.values, contains(KalenderLage.manad));
    });

    test('Migration maps legacy "agenda" string to KalenderLage.dag', () {
      KalenderLage parseSavedLage(String? saved) {
        if (saved == 'agenda') {
          return KalenderLage.dag;
        }
        for (final e in KalenderLage.values) {
          if (e.name == saved) {
            return e;
          }
        }
        return KalenderLage.dag;
      }

      expect(parseSavedLage('agenda'), equals(KalenderLage.dag));
      expect(parseSavedLage('dag'), equals(KalenderLage.dag));
      expect(parseSavedLage('vecka'), equals(KalenderLage.vecka));
      expect(parseSavedLage('manad'), equals(KalenderLage.manad));
      expect(parseSavedLage('unknown_value'), equals(KalenderLage.dag));
    });

    test('Focus mode allowed modes are dag and vecka only', () {
      List<KalenderLage> getModeList({required bool isFocus}) {
        return isFocus
            ? const [KalenderLage.dag, KalenderLage.vecka]
            : KalenderLage.values;
      }

      final focusModes = getModeList(isFocus: true);
      expect(focusModes.length, equals(2));
      expect(focusModes, contains(KalenderLage.dag));
      expect(focusModes, contains(KalenderLage.vecka));
      expect(focusModes.contains(KalenderLage.manad), isFalse);

      final normalModes = getModeList(isFocus: false);
      expect(normalModes.length, equals(3));
    });

    test('Dev mode 7-tap toggle logic', () {
      int count = 0;
      bool devMode = false;

      void registerTap({required void Function(bool next) onToggle}) {
        count++;
        if (count >= 7) {
          count = 0;
          devMode = !devMode;
          onToggle(devMode);
        }
      }

      bool toggled = false;
      for (int i = 0; i < 6; i++) {
        registerTap(onToggle: (_) => toggled = true);
      }
      expect(toggled, isFalse);
      expect(devMode, isFalse);

      registerTap(onToggle: (_) => toggled = true);
      expect(toggled, isTrue);
      expect(devMode, isTrue);

      toggled = false;
      for (int i = 0; i < 7; i++) {
        registerTap(onToggle: (_) => toggled = true);
      }
      expect(toggled, isTrue);
      expect(devMode, isFalse);
    });
  });
}
