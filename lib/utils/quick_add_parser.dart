import '../data/piktogram.dart';
import '../models/user_model.dart';

/// Snabbinmatning (ROADMAP Etapp 10): tolkar svensk fritext lokalt —
/// "Fotboll tis 17:00 Liam" → färdigt aktivitetsutkast. Ingen AI, inga
/// nätverksanrop; bara enkla regler som täcker familjevardagen.
/// Vad användaren vill skapa — avgörs av nyckelord i början av texten.
enum QuickAddIntent { activity, chore, meal, shopping }

class QuickAddDraft {
  final QuickAddIntent intent;
  final String title;
  final DateTime date;
  /// Sattes datumet uttryckligen i texten? (Annars default = idag.)
  final bool hasExplicitDate;
  /// `HH:mm` eller tom sträng (ingen tid angiven).
  final String time;
  final List<UserModel> persons;
  /// 'weekly' | 'biweekly' | '' (engångs).
  final String recurrenceType;
  final String piktogram;
  /// Inköpsvaror (endast [QuickAddIntent.shopping]).
  final List<String> items;

  const QuickAddDraft({
    required this.intent,
    required this.title,
    required this.date,
    required this.hasExplicitDate,
    required this.time,
    required this.persons,
    required this.recurrenceType,
    required this.piktogram,
    this.items = const [],
  });
}

/// Normaliserar namn: gemener + viker bort icke-svenska diakriter (å, ä, ö bevaras).
String foldName(String s) {
  var result = s.toLowerCase();
  const from = 'éèêëáàâãíìîïóòôõúùûüçñ';
  const to   = 'eeeeaaaaiiiioooouuuucn';
  final buffer = StringBuffer();
  for (var i = 0; i < result.length; i++) {
    final char = result[i];
    final idx = from.indexOf(char);
    if (idx != -1) {
      buffer.write(to[idx]);
    } else {
      buffer.write(char);
    }
  }
  return buffer.toString();
}

/// Beräknar Levenshtein-avstånd mellan två strängar.
int levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  List<int> v0 = List<int>.generate(b.length + 1, (i) => i);
  List<int> v1 = List<int>.filled(b.length + 1, 0);

  for (int i = 0; i < a.length; i++) {
    v1[0] = i + 1;
    for (int j = 0; j < b.length; j++) {
      final cost = (a[i] == b[j]) ? 0 : 1;
      final insertion = v1[j] + 1;
      final deletion = v0[j + 1] + 1;
      final substitution = v0[j] + cost;
      var min = insertion < deletion ? insertion : deletion;
      if (substitution < min) min = substitution;
      v1[j + 1] = min;
    }
    for (int j = 0; j <= b.length; j++) {
      v0[j] = v1[j];
    }
  }
  return v0[b.length];
}

const Map<String, int> _months = {
  'januari': 1, 'jan': 1,
  'februari': 2, 'feb': 2,
  'mars': 3, 'mar': 3,
  'april': 4, 'apr': 4,
  'maj': 5,
  'juni': 6, 'jun': 6,
  'juli': 7, 'jul': 7,
  'augusti': 8, 'aug': 8,
  'september': 9, 'sept': 9, 'sep': 9,
  'oktober': 10, 'okt': 10,
  'november': 11, 'nov': 11,
  'december': 12, 'dec': 12,
};

const Map<String, int> _weekdays = {
  'måndag': 1, 'måndagar': 1, 'mån': 1,
  'tisdag': 2, 'tisdagar': 2, 'tis': 2,
  'onsdag': 3, 'onsdagar': 3, 'ons': 3,
  'torsdag': 4, 'torsdagar': 4, 'tors': 4, 'tor': 4,
  'fredag': 5, 'fredagar': 5, 'fre': 5,
  'lördag': 6, 'lördagar': 6, 'lör': 6,
  'söndag': 7, 'söndagar': 7, 'sön': 7,
};

/// Nästa förekomst av [weekday] från och med idag.
DateTime _nextWeekday(DateTime from, int weekday) {
  final today = DateTime(from.year, from.month, from.day);
  final diff = (weekday - today.weekday) % 7;
  return DateTime(today.year, today.month, today.day + diff);
}

/// Tolkar [text]. Returnerar null om ingen titel blir kvar efter tolkning.
QuickAddDraft? parseQuickAdd(
  String text, {
  required List<UserModel> members,
  DateTime? now,
}) {
  final n = now ?? DateTime.now();
  var work = ' ${text.trim()} ';
  if (work.trim().isEmpty) return null;

  String recurrence = '';
  DateTime? date;
  String time = '';

  String lower() => work.toLowerCase();

  // 0. Intent: nyckelord styr vart det sparas.
  //    "handla/köp mjölk och bröd"     → inköpslistan
  //    "middag tacos på fredag"        → matsedeln
  //    "syssla dammsuga Liam imorgon"  → syssla
  //    allt annat                      → aktivitet
  var intent = QuickAddIntent.activity;
  final shoppingMatch =
      RegExp(r'^\s*(handla|köp|köpa)\b', caseSensitive: false)
          .firstMatch(work);
  if (shoppingMatch != null) {
    intent = QuickAddIntent.shopping;
    work = work.replaceFirst(shoppingMatch.group(0)!, ' ');
  } else if (RegExp(r'\b(middag|matsedel|kvällsmat)\b', caseSensitive: false)
      .hasMatch(lower())) {
    intent = QuickAddIntent.meal;
    work = work.replaceFirst(
        RegExp(r'\b(middag|matsedel|kvällsmat)\b', caseSensitive: false),
        ' ');
  } else {
    final choreMatch =
        RegExp(r'^\s*syssla\b:?', caseSensitive: false).firstMatch(work);
    if (choreMatch != null) {
      intent = QuickAddIntent.chore;
      work = work.replaceFirst(choreMatch.group(0)!, ' ');
    }
  }

  // Inköp: resten är varor — splitta på komma och "och".
  if (intent == QuickAddIntent.shopping) {
    final items = work
        .split(RegExp(r',|\boch\b', caseSensitive: false))
        .map((s) => s.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((s) => s.isNotEmpty)
        .map((s) => s[0].toUpperCase() + s.substring(1))
        .toList();
    if (items.isEmpty) return null;
    return QuickAddDraft(
      intent: intent,
      title: items.join(', '),
      date: DateTime(n.year, n.month, n.day),
      hasExplicitDate: false,
      time: '',
      persons: const [],
      recurrenceType: '',
      piktogram: '🛒',
      items: items,
    );
  }

  // 1. "varje X" / "varannan X" → upprepning + veckodag.
  for (final entry in _weekdays.entries) {
    for (final prefix in const ['varje', 'varannan']) {
      final pattern = RegExp(
          r'\b' + prefix + r'\s+' + entry.key + r'\b',
          caseSensitive: false);
      if (pattern.hasMatch(lower())) {
        recurrence = prefix == 'varje' ? 'weekly' : 'biweekly';
        date = _nextWeekday(n, entry.value);
        work = work.replaceAll(pattern, ' ');
      }
    }
  }

  // 2. "idag" / "imorgon" / "i morgon".
  if (date == null) {
    if (RegExp(r'\bidag\b', caseSensitive: false).hasMatch(lower())) {
      date = DateTime(n.year, n.month, n.day);
      work = work.replaceFirst(
          RegExp(r'\bidag\b', caseSensitive: false), ' ');
    } else if (RegExp(r'\bi ?morgon\b', caseSensitive: false)
        .hasMatch(lower())) {
      date = DateTime(n.year, n.month, n.day + 1);
      work = work.replaceFirst(
          RegExp(r'\bi ?morgon\b', caseSensitive: false), ' ');
    }
  }

  // 4a. Datum med månadsnamn: "12 oktober", "12:e okt", "12 okt 2027".
  if (date == null) {
    final monthNames = _months.keys.join('|');
    final m = RegExp(
            r'\b(\d{1,2})(?::?e)?\s+(' + monthNames + r')(?:\s+(\d{4}))?\b',
            caseSensitive: false)
        .firstMatch(lower());
    if (m != null) {
      final day = int.parse(m.group(1)!);
      final month = _months[m.group(2)!]!;
      final year = m.group(3) != null ? int.parse(m.group(3)!) : n.year;
      var candidate = DateTime(year, month, day);
      // Utan år: passerat datum i år → anta nästa år (födelsedagar!).
      if (m.group(3) == null &&
          candidate.isBefore(DateTime(n.year, n.month, n.day))) {
        candidate = DateTime(year + 1, month, day);
      }
      if (candidate.month == month && candidate.day == day) {
        date = candidate;
        // Ta bort träffen ur arbets-strängen (matcha mot original-case).
        work = work.replaceFirst(
            RegExp(RegExp.escape(m.group(0)!), caseSensitive: false), ' ');
      }
    }
  }

  // 4b. Datum "12/6" eller "12/6-2026".
  if (date == null) {
    final m = RegExp(r'\b(\d{1,2})/(\d{1,2})(?:-(\d{4}))?\b')
        .firstMatch(work);
    if (m != null) {
      final day = int.parse(m.group(1)!);
      final month = int.parse(m.group(2)!);
      final year = m.group(3) != null ? int.parse(m.group(3)!) : n.year;
      var candidate = DateTime(year, month, day);
      // Utan år: om datumet redan passerat i år, anta nästa år.
      if (m.group(3) == null &&
          candidate.isBefore(DateTime(n.year, n.month, n.day))) {
        candidate = DateTime(year + 1, month, day);
      }
      date = candidate;
      work = work.replaceFirst(m.group(0)!, ' ');
    }
  }

  // 5. Fristående veckodag ("tis", "fredag") → nästa förekomst.
  // Körs EFTER explicita datum så "fre 12 oktober" tar datumet, inte fredagen.
  if (date == null) {
    for (final entry in _weekdays.entries) {
      final pattern =
          RegExp(r'\b' + entry.key + r'\b', caseSensitive: false);
      if (pattern.hasMatch(lower())) {
        date = _nextWeekday(n, entry.value);
        work = work.replaceFirst(pattern, ' ');
        break;
      }
    }
  }

  // 6. Tid: "kl 17", "kl 17.30", "17:00", "17.30".
  final timeMatch = RegExp(
          r'\bkl\.?\s*(\d{1,2})(?:[:.](\d{2}))?\b|\b(\d{1,2})[:.](\d{2})\b',
          caseSensitive: false)
      .firstMatch(work);
  if (timeMatch != null) {
    final h =
        int.parse(timeMatch.group(1) ?? timeMatch.group(3) ?? '0');
    final mnt = int.parse(timeMatch.group(2) ?? timeMatch.group(4) ?? '0');
    if (h >= 0 && h <= 23 && mnt >= 0 && mnt <= 59) {
      time = '${h.toString().padLeft(2, '0')}:'
          '${mnt.toString().padLeft(2, '0')}';
      work = work.replaceFirst(timeMatch.group(0)!, ' ');
    }
  }

  // 6a. Medlemsnamn: exakt matchning på _foldName-form (t.ex. "Celine" matchar "Céline").
  final persons = <UserModel>[];
  final matchedUids = <String>{};
  final wordRegex = RegExp(
      r'\b[a-zA-ZåäöÅÄÖéèêëáàâãíìîïóòôõúùûüçñÉÈÊËÁÀÂÃÍÌÎÏÓÒÔÕÚÙÛÜÇÑ]+\b');

  for (final m in members) {
    if (matchedUids.contains(m.uid)) continue;
    final first = m.name.split(' ').first;
    if (first.isEmpty) continue;
    final foldedFirst = foldName(first);

    final matches = wordRegex.allMatches(work);
    for (final match in matches) {
      final rawWord = match.group(0)!;
      if (foldName(rawWord) == foldedFirst) {
        persons.add(m);
        matchedUids.add(m.uid);
        work = work.replaceFirst(
            RegExp(r'\b' + RegExp.escape(rawWord) + r'\b'), ' ');
        break;
      }
    }
  }

  // 6b. Fuzzy match för kvarvarande ord i work (längd >= 3).
  final remainingWords = wordRegex
      .allMatches(work)
      .map((m) => m.group(0)!)
      .where((w) => w.length >= 3)
      .toList();

  for (final w in remainingWords) {
    if (!RegExp(r'\b' + RegExp.escape(w) + r'\b').hasMatch(work)) continue;

    final foldedW = foldName(w);
    final unmatchedMembers =
        members.where((m) => !matchedUids.contains(m.uid)).toList();

    int? lowestDist;
    final candidates = <UserModel>[];

    for (final m in unmatchedMembers) {
      final first = m.name.split(' ').first;
      if (first.isEmpty) continue;
      final foldedFirst = foldName(first);

      final threshold = foldedFirst.length >= 5
          ? 2
          : (foldedFirst.length >= 3 ? 1 : 0);

      if (threshold == 0) continue;

      final d = levenshtein(foldedW, foldedFirst);
      if (d <= threshold) {
        if (lowestDist == null || d < lowestDist) {
          lowestDist = d;
          candidates.clear();
          candidates.add(m);
        } else if (d == lowestDist) {
          candidates.add(m);
        }
      }
    }

    // Matcha ENDAST om exakt en medlem ligger inom tröskeln OCH är strikt närmast
    if (candidates.length == 1) {
      final matchedMember = candidates.first;
      persons.add(matchedMember);
      matchedUids.add(matchedMember.uid);
      work = work.replaceFirst(
          RegExp(r'\b' + RegExp.escape(w) + r'\b'), ' ');
    }
  }

  // 7. Resten är titeln.
  final title = work
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (title.isEmpty) return null;

  // 8. Auto-piktogram: matcha titelord mot piktogrambiblioteket.
  var pik = switch (intent) {
    QuickAddIntent.meal => '🍽️',
    QuickAddIntent.chore => '✅',
    _ => '📅',
  };
  final titleLower = title.toLowerCase();
  if (intent != QuickAddIntent.meal) {
    for (final item in piktogramLibrary) {
      final label = item.label.toLowerCase();
      if (titleLower.contains(label) || label.contains(titleLower)) {
        pik = item.emoji;
        break;
      }
    }
  }

  return QuickAddDraft(
    intent: intent,
    title: title[0].toUpperCase() + title.substring(1),
    date: date ?? DateTime(n.year, n.month, n.day),
    hasExplicitDate: date != null,
    time: time,
    persons: persons,
    recurrenceType: recurrence,
    piktogram: pik,
  );
}
