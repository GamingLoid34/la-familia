import 'package:cloud_firestore/cloud_firestore.dart';

import 'date_utils.dart';
import 'recurrence.dart';

/// Förberedelse inför en lektion eller aktivitet, avbockad per tillfälle.
///
/// Portad från Android-appen (`util/LessonPrep.kt`). Kvällen före ett
/// tillfälle ska "Inför i morgon" kunna visa till exempel
/// "🎒 Packa gympapåsen · Leandro — Gympa i morgon kl. 09:00".
///
/// Lektionen bär **en** mall, och tillfällena härleds vid läsning ur seriens
/// egen återkomstregel ([eventOccursOnDay]). Slutdatum, undantag och flyttade
/// tillfällen följer därför med automatiskt, och ingenting behöver skapas per
/// tillfälle.
///
/// En bock gäller **ett** tillfälle: `doneDates` är en lista med datumnycklar.
/// Att bocka av tisdagens packning får inte bocka av nästa tisdag, så en
/// återkommande förberedelse blir aldrig klar för gott efter första gången.
///
/// Fältform på `planner_events`-dokumentet:
///
/// ```
/// lessonPrep: {
///   text: "Packa gympapåsen",
///   doneDates: ["2026-09-21", "2026-09-28"]
/// }
/// ```
///
/// Fältet utelämnas helt när förberedelsen är avstängd.
class LessonPrep {
  LessonPrep._();

  /// Fältnamnet på händelsedokumentet.
  static const field = 'lessonPrep';

  static const _text = 'text';
  static const _doneDates = 'doneDates';

  /// Förberedelsens text, eller null när ingen är satt.
  ///
  /// Tom text räknas som ingen förberedelse: en tom rad i "Inför i morgon"
  /// vore värre än ingen rad alls.
  static String? textOf(Map<String, dynamic> raw) {
    final prep = raw[field];
    if (prep is! Map) return null;
    final text = prep[_text];
    if (text is! String) return null;
    final trimmed = text.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Har lektionen en förberedelse alls?
  static bool isEnabled(Map<String, dynamic> raw) => textOf(raw) != null;

  /// Datum där förberedelsen redan är avbockad.
  static List<String> doneDates(Map<String, dynamic> raw) {
    final prep = raw[field];
    if (prep is! Map) return const [];
    final list = prep[_doneDates];
    if (list is! List) return const [];
    return [
      for (final d in list)
        if (d != null) d.toString(),
    ];
  }

  /// Är förberedelsen avbockad för [lessonDay]?
  static bool isDoneOn(Map<String, dynamic> raw, DateTime lessonDay) =>
      doneDates(raw).contains(dateKey(lessonDay));

  /// Fältvärdet efter att [lessonDay] bockats av eller ångrats.
  ///
  /// Samma som Android: hela kartan, med sorterade datum utan dubbletter.
  /// För själva skrivningen, använd hellre [toggleUpdate], som inte skriver
  /// över en avbockning någon annan gjort samtidigt.
  static Map<String, dynamic> toggled(
    Map<String, dynamic> raw,
    DateTime lessonDay, {
    required bool done,
  }) {
    final key = dateKey(lessonDay);
    final current = doneDates(raw).toSet();
    if (done) {
      current.add(key);
    } else {
      current.remove(key);
    }
    return {
      _text: textOf(raw) ?? '',
      _doneDates: current.toList()..sort(),
    };
  }

  /// Fältvärdet när texten sätts eller ändras. Avbockningarna behålls.
  static Map<String, dynamic> withText(
    Map<String, dynamic> raw,
    String text,
  ) =>
      {
        _text: text.trim(),
        _doneDates: doneDates(raw).toList()..sort(),
      };

  /// Fältsökvägen för avbockningarna, för en uppdatering som bara rör dem.
  static const doneDatesPath = '$field.$_doneDates';

  /// Fältsökvägen för texten, för en redigering som bara ändrar texten.
  static const textPath = '$field.$_text';

  /// Uppdateringen när [lessonDay] bockas av eller ångras.
  ///
  /// Avviker medvetet från Android, som skriver om hela kartan: här läggs
  /// bara datumet till eller tas bort med `arrayUnion`/`arrayRemove` på
  /// `lessonPrep.doneDates`. Två som bockar av samtidigt skriver då inte över
  /// varandra, och det fungerar utan nät. Läsarna i båda apparna tål en
  /// osorterad lista. Reglerna tillåter det för alla i familjen, eftersom
  /// bara `lessonPrep` ändras.
  ///
  /// Anropa bara när [isEnabled] är sant; annars saknas texten.
  static Map<String, dynamic> toggleUpdate(
    DateTime lessonDay, {
    required bool done,
  }) {
    final key = dateKey(lessonDay);
    return {
      doneDatesPath: done
          ? FieldValue.arrayUnion([key])
          : FieldValue.arrayRemove([key]),
    };
  }

  /// Bockar av eller ångrar förberedelsen för [lessonDay] på dokumentet [ref].
  static Future<void> setDone(
    DocumentReference<Map<String, dynamic>> ref,
    DateTime lessonDay, {
    required bool done,
  }) =>
      ref.update(toggleUpdate(lessonDay, done: done));

  /// Stabil nyckel för lektions**serien** ett dokument tillhör.
  ///
  /// Importerade scheman är ett dokument per tillfälle, så dokument-id:t
  /// duger inte som seriekoppling. Nyckeln är i stället import + titel +
  /// personer; för en manuellt inlagd serie räcker dokument-id:t.
  static String seriesKey(Map<String, dynamic> raw, String eventId) {
    final importId = raw['calendarImportId'];
    if (importId is! String || importId.trim().isEmpty) return eventId;
    final title = ((raw['title'] as String?) ?? '').trim().toLowerCase();
    final uids = raw['personUids'];
    final persons = uids is List
        ? ([
            for (final u in uids)
              if (u != null && u.toString().trim().isNotEmpty) u.toString(),
          ]..sort())
            .join(',')
        : '';
    return '$importId|$title|$persons';
  }

  /// Ska en förberedelserad visas kvällen före [lessonDay]?
  ///
  /// Förberedelsen måste vara påslagen, lektionen måste infalla den dagen
  /// (slutdatum, undantag och engångslektioner hanteras av
  /// [eventOccursOnDay]) och tillfället får inte redan vara avbockat.
  static bool showsForLesson(Map<String, dynamic> raw, DateTime lessonDay) =>
      isEnabled(raw) &&
      eventOccursOnDay(raw, lessonDay) &&
      !isDoneOn(raw, lessonDay);
}
