import 'date_utils.dart';

/// Sammanfattar en .ics-fil till ett läsbart namn. Port av Androids
/// `util/IcsSummary.kt`.
///
/// Importerade filer fick tidigare namnet ur textfältet, eller Androids
/// interna dokument-id (`document:884`). Med ett tjugotal filer för en termin
/// blir listan omöjlig att navigera, och en felaktig vecka går inte att hitta
/// för borttagning (beställaren 2026-09-21).
///
/// Filen vet själv vad den innehåller, så namnet byggs ur den: veckonummer och
/// datumintervall ur `DTSTART`.
///
/// Parsningen är avsiktligt grund. Den ska bara hitta datum för ett namn — den
/// riktiga tolkningen sker i `functions/ics_text_import.js`, och en fil som inte
/// går att sammanfatta importeras ändå.
class IcsSummary {
  IcsSummary._();

  /// `DTSTART:20260921T090000`, `DTSTART;VALUE=DATE:20260921`,
  /// `DTSTART;TZID=...:2026...`
  static final RegExp _dtstart = RegExp(
    r'^DTSTART[^:\r\n]*:(\d{8})',
    multiLine: true,
    caseSensitive: false,
  );

  /// Datumen i filen, unika och sorterade. Tom lista när inga hittas.
  static List<DateTime> dates(String icsText) {
    final unika = <DateTime>{};
    for (final m in _dtstart.allMatches(icsText)) {
      final raw = m.group(1)!;
      final y = int.parse(raw.substring(0, 4));
      final mo = int.parse(raw.substring(4, 6));
      final d = int.parse(raw.substring(6, 8));
      final datum = DateTime(y, mo, d);
      // DateTime rullar över ogiltiga datum (månad 13 → nästa år). Kotlins
      // LocalDate.of kastar i stället — ett trasigt datum hoppas över.
      if (datum.year != y || datum.month != mo || datum.day != d) continue;
      unika.add(datum);
    }
    return unika.toList()..sort();
  }

  /// Ett beskrivande namn för importen, eller null när filen saknar läsbara
  /// datum.
  ///
  /// - En vecka: `v. 39 (21 sep–25 sep)`
  /// - Flera veckor: `v. 39–41 (21 sep–9 okt)`
  /// - En dag: `21 sep`
  ///
  /// Veckonumret är ISO, samma som skolan brukar numrera veckor.
  static String? suggestName(String icsText) {
    final datum = dates(icsText);
    if (datum.isEmpty) return null;

    final forsta = datum.first;
    final sista = datum.last;
    if (forsta == sista) return _kortDatum(forsta);

    final v1 = isoWeekNumber(forsta);
    final v2 = isoWeekNumber(sista);
    final intervall = '${_kortDatum(forsta)}–${_kortDatum(sista)}';
    return v1 == v2 ? 'v. $v1 ($intervall)' : 'v. $v1–$v2 ($intervall)';
  }

  /// Namn med ett prefix, till exempel personens namn:
  /// `Céline · v. 39 (21 sep–25 sep)`. Null när filen saknar datum.
  static String? suggestNameWithPrefix(String icsText, String prefix) {
    final kropp = suggestName(icsText);
    if (kropp == null) return null;
    final rent = prefix.trim();
    return rent.isEmpty ? kropp : '$rent · $kropp';
  }

  /// "21 sep". Årtal utelämnas: importlistan visar ändå bara aktuell termin.
  static String _kortDatum(DateTime d) => '${d.day} ${_manader[d.month - 1]}';

  static const _manader = [
    'jan',
    'feb',
    'mar',
    'apr',
    'maj',
    'jun',
    'jul',
    'aug',
    'sep',
    'okt',
    'nov',
    'dec',
  ];
}

/// Standardnamnet när inget annat finns.
const String icsStandardNamn = 'Importerad kalender';

/// Prefixet i importnamnet: det användaren skrev, annars personen importen
/// gäller, annars [icsStandardNamn]. Personen gör listan läsbar när flera har
/// scheman importerade.
String icsNamnPrefix(String inskrivetNamn, String? medlem) {
  final namn = inskrivetNamn.trim();
  if (namn.isNotEmpty) return namn;
  final person = (medlem ?? '').trim();
  if (person.isNotEmpty) return person;
  return icsStandardNamn;
}

/// Filnamnet utan ändelse, eller null när det inte säger något (tomt eller
/// ett internt dokument-id som `document:884`).
String? icsFilnamnReserv(String filnamn) {
  final punkt = filnamn.lastIndexOf('.');
  final bas = (punkt > 0 ? filnamn.substring(0, punkt) : filnamn).trim();
  if (bas.isEmpty || bas.startsWith('document:')) return null;
  return bas;
}

/// Namnet på en importerad fil: ur innehållet, annars filnamnet, annars
/// prefixet. Samma ordning som Androids `importIcsFiles`.
String icsImportNamn({
  required String icsText,
  required String prefix,
  required String filnamn,
}) =>
    IcsSummary.suggestNameWithPrefix(icsText, prefix) ??
    icsFilnamnReserv(filnamn) ??
    (prefix.trim().isEmpty ? icsStandardNamn : prefix.trim());

/// Utfallet för en fil i en import med flera filer.
class IcsFilResultat {
  final String filnamn;

  /// Namnet importen fick i listan.
  final String namn;

  /// Antal importerade händelser, eller null när filen misslyckades.
  final int? antal;

  /// Kort orsak när filen misslyckades, t.ex. "för stor".
  final String? fel;

  const IcsFilResultat.lyckad({
    required this.filnamn,
    required this.namn,
    required int this.antal,
  }) : fel = null;

  const IcsFilResultat.misslyckad({
    required this.filnamn,
    required String this.fel,
  }) : namn = filnamn,
       antal = null;

  bool get lyckades => fel == null;
}

/// Sammanfattningen efter en import av en eller flera filer.
///
/// `"12 händelser från 2 filer."` följt av en rad per fil när de är flera,
/// och `"Misslyckades: a.ics (för stor)"` för det som inte gick igenom. En fil
/// som lästes men saknade kommande händelser räknas inte som misslyckad, men
/// syns med "inga kommande händelser".
String icsImportSammanfattning(List<IcsFilResultat> resultat) {
  final lyckade = resultat.where((r) => r.lyckades).toList();
  final misslyckade = resultat.where((r) => !r.lyckades).toList();
  final handelser = lyckade.fold<int>(0, (s, r) => s + (r.antal ?? 0));

  final rader = <String>[];
  if (lyckade.isNotEmpty && handelser > 0) {
    final filer = lyckade.length == 1 ? 'fil' : 'filer';
    rader.add('$handelser händelser från ${lyckade.length} $filer.');
    if (lyckade.length > 1) {
      for (final r in lyckade) {
        rader.add('• ${r.namn}: ${_antalText(r.antal ?? 0)}');
      }
    }
  } else {
    rader.add('Inga händelser importerades.');
    if (lyckade.isNotEmpty) {
      rader.add(
        lyckade.length == 1
            ? 'Filen innehöll inga kommande händelser.'
            : 'Filerna innehöll inga kommande händelser.',
      );
    }
  }
  if (misslyckade.isNotEmpty) {
    rader.add(
      'Misslyckades: '
      '${misslyckade.map((r) => '${r.filnamn} (${r.fel})').join(', ')}',
    );
  }
  return rader.join('\n');
}

String _antalText(int n) {
  if (n == 0) return 'inga kommande händelser';
  return n == 1 ? '1 händelse' : '$n händelser';
}

/// Läsbar källa för en rad i importlistan. Backendens egna värden
/// (`photo`, `url`, `file`) visas aldrig rått.
String importKallEtikett(Map<String, dynamic> imp) {
  final kind = imp['importKind'];
  final source = imp['source'];
  if (kind == 'photo' || source == 'photo') return 'skannat schema';
  if (source == 'url') return 'prenumererad kalender';
  if (source == 'file') return 'uppladdad fil';
  if (source == 'ics') return 'inklistrad kalender';
  final feed = (imp['feedUrl'] as String?)?.trim() ?? '';
  final url = (imp['url'] as String?)?.trim() ?? '';
  if (feed.isNotEmpty || url.isNotEmpty) return 'prenumererad kalender';
  return 'kalender';
}

/// Om en `planner_events`-post kom från importen [importId]. Äldre poster
/// saknar `calendarImportId` och matchas på `calendarName`.
bool hortTillImport(
  Map<String, dynamic> event, {
  required String importId,
  required String importNamn,
}) {
  if (event['source'] != 'calendar') return false;
  final id = event['calendarImportId'];
  if (id != null) return id == importId;
  return importNamn.isNotEmpty && event['calendarName'] == importNamn;
}
