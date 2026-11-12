import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/utils/school_notifications.dart';

/// Vilka poster som ska ge påminnelser. Port av Androids `ScheduleBlocksTest`.
///
/// Beställaren 2026-09-21: varje lektion för varje barn gav notiser — sex lektioner om dagen
/// med tre notiser var, för två barn, blir ett trettiotal dagligen. Rehab och jobb ser
/// likadana ut i datamodellen men betyder något annat, och behåller sina.
void main() {
  Map<String, dynamic> block({
    String? label,
    String? piktogram,
    String? calendarName,
    String title = 'Matematik',
    String? kind = 'schedule',
    String source = 'calendar',
    Map<String, dynamic>? prep,
    List<Object?>? checklist,
  }) =>
      {
        'title': title,
        'source': source,
        'planningImportKind': ?kind,
        'schemaLabel': ?label,
        'piktogram': ?piktogram,
        'calendarName': ?calendarName,
        'lessonPrep': ?prep,
        'checklist': ?checklist,
      };

  group('Vad som är ett importerat schemablock', () {
    test('importerat schema är ett schemablock', () {
      expect(isScheduleBlock(block()), isTrue);
    });

    test('manuell aktivitet är inte ett schemablock', () {
      expect(isScheduleBlock(block(source: 'manual')), isFalse);
    });

    test('importerad aktivitet är inte ett schemablock', () {
      expect(isScheduleBlock(block(kind: 'activity')), isFalse);
    });

    test('saknad kind tolkas som schema', () {
      expect(isScheduleBlock(block(kind: null)), isTrue);
    });
  });

  group('Skola mot rehab och jobb', () {
    test('skolblock känns igen på etiketten', () {
      expect(isSchoolBlock(block(label: 'Skola')), isTrue);
    });

    test('rehab är inte skola', () {
      expect(isSchoolBlock(block(label: 'Rehab')), isFalse);
    });

    test('jobb är inte skola', () {
      expect(isSchoolBlock(block(label: 'Jobb')), isFalse);
    });

    test('piktogram avgör när etiketten saknas', () {
      expect(isSchoolBlock(block(piktogram: '🏥')), isFalse);
      expect(isSchoolBlock(block(piktogram: '💼')), isFalse);
      expect(isSchoolBlock(block(piktogram: '🏫')), isTrue);
    });

    test('kalendernamn med rehab räknas som rehab', () {
      expect(isSchoolBlock(block(calendarName: 'Rehab hösten')), isFalse);
      expect(isSchoolBlock(block(calendarName: 'Kliniken')), isFalse);
    });

    test('omärkt schemablock behandlas som skola', () {
      expect(isSchoolBlock(block()), isTrue);
    });

    test('etiketten vinner över piktogrammet', () {
      expect(isSchoolBlock(block(label: 'Rehab', piktogram: '🏫')), isFalse);
    });
  });

  group('Påminnelser', () {
    test('vanlig lektion ger inga påminnelser', () {
      expect(shouldRemindForEvent(block()), isFalse);
      expect(shouldSkipLessonNotification(block()), isTrue);
    });

    test('rehabpass ger påminnelser', () {
      expect(shouldRemindForEvent(block(label: 'Rehab')), isTrue);
    });

    test('arbetspass ger påminnelser', () {
      expect(shouldRemindForEvent(block(label: 'Jobb')), isTrue);
    });

    test('manuell aktivitet ger påminnelser', () {
      expect(shouldRemindForEvent(block(source: 'manual')), isTrue);
      expect(shouldSkipLessonNotification(block(source: 'manual')), isFalse);
    });

    test('lektion med förberedelse ger påminnelser', () {
      final medPrep = block(
          prep: {'text': 'Packa gympapåsen', 'doneDates': <String>[]});
      expect(shouldRemindForEvent(medPrep), isTrue);
    });

    test('lektion med packlista ger påminnelser', () {
      final medLista = block(checklist: [
        {'item': 'Ta med kamera', 'isDone': false},
      ]);
      expect(shouldRemindForEvent(medLista), isTrue);
    });

    test('tom packlista räknas inte', () {
      expect(shouldRemindForEvent(block(checklist: const [])), isFalse);
    });

    test('packlista med bara tomma rader räknas inte', () {
      final tomma = block(checklist: [
        {'item': '   ', 'isDone': false},
      ]);
      expect(shouldRemindForEvent(tomma), isFalse);
    });

    test('tom förberedelsetext räknas inte', () {
      final tom = block(prep: {'text': '  ', 'doneDates': <String>[]});
      expect(shouldRemindForEvent(tom), isFalse);
    });

    // --- Tillägg i Flutter ---

    test('packlista med ren strängrad räknas', () {
      // Samma format som ChecklistUpdates.textOf godtar på Android.
      expect(shouldRemindForEvent(block(checklist: ['Gympapåse'])), isTrue);
    });

    test('importerad aktivitet ger påminnelser', () {
      expect(shouldRemindForEvent(block(kind: 'activity')), isTrue);
    });
  });
}
