/// Semantisk typ för en schemapost (FAS 6d.2).
enum ScheduleSemanticType {
  lesson,
  rast,
  lunch,
  ombyte,
}

/// Tabell över de 22 specificerade grundskoleförkortningarna i delade verktyg.
/// En sanning för hela projektet (väggen nu, mobilen senare).
const Map<String, String> schoolSubjectAbbrMap = {
  'idh': 'Idrott och hälsa',
  'sv': 'Svenska',
  'sva': 'Svenska som andraspråk',
  'sv/sva': 'Svenska',
  'ma': 'Matematik',
  'en': 'Engelska',
  'mu': 'Musik',
  'bl': 'Bild',
  'sl': 'Slöjd',
  'hkk': 'Hem- och konsumentkunskap',
  'tk': 'Teknik',
  'no': 'Naturorienterande ämnen',
  'so': 'Samhällsorienterande ämnen',
  'fy': 'Fysik',
  'ke': 'Kemi',
  'bi': 'Biologi',
  'ge': 'Geografi',
  'hi': 'Historia',
  're': 'Religionskunskap',
  'sh': 'Samhällskunskap',
  'mspr': 'Moderna språk',
  'm2': 'Moderna språk',
  'ev': 'Elevens val',
  'ment': 'Mentorstid',
};

/// Tvättar bort prefix såsom "Lektion " och "Lektion: " (skiftlägesokänsligt).
String cleanLessonTitle(String rawTitle) {
  var title = rawTitle.trim();
  if (title.toLowerCase().startsWith('lektion:')) {
    title = title.substring('lektion:'.length).trim();
  } else if (title.toLowerCase().startsWith('lektion ')) {
    title = title.substring('lektion '.length).trim();
  }
  return title;
}

/// Klassificerar semantiken för en post utifrån dess tvättade titel (FAS 6d.2).
ScheduleSemanticType classifyScheduleSemantic(String title) {
  final cleaned = cleanLessonTitle(title).trim().toLowerCase();

  if (cleaned == 'rast' || cleaned == 'paus' || cleaned.startsWith('rast ') || cleaned.startsWith('paus ')) {
    return ScheduleSemanticType.rast;
  }
  if (cleaned == 'lunch' || cleaned.startsWith('lunch ')) {
    return ScheduleSemanticType.lunch;
  }
  if (cleaned == 'ombyte' || cleaned.startsWith('ombyte ')) {
    return ScheduleSemanticType.ombyte;
  }
  return ScheduleSemanticType.lesson;
}

/// Expanderar förkortade ämnestitlar via [schoolSubjectAbbrMap].
/// Okända titlar förblir oförändrade.
String expandSchoolSubjectTitle(String rawTitle, {String? calendarDescription}) {
  final cleaned = cleanLessonTitle(rawTitle).trim();
  if (cleaned.isEmpty) return 'Lektion';

  // Kontrollera om calendarDescription bär kursnamn som skiljer sig från koden
  if (calendarDescription != null && calendarDescription.trim().isNotEmpty) {
    final desc = calendarDescription.trim();
    // Exempel: "Kurs: Kursnamn" eller liknande struktur
    final match = RegExp(r'^(kurs|ämne):\s*(.+)$', caseSensitive: false).firstMatch(desc);
    if (match != null) {
      final name = match.group(2)?.trim() ?? '';
      if (name.isNotEmpty && !name.toLowerCase().contains(cleaned.toLowerCase())) {
        return name;
      }
    }
  }

  final lower = cleaned.toLowerCase();
  if (schoolSubjectAbbrMap.containsKey(lower)) {
    return schoolSubjectAbbrMap[lower]!;
  }

  // Fallback: specialfall för kombinerade förkortningar som "Mspr/M2"
  if (lower == 'mspr/m2' || lower == 'm2/mspr') {
    return 'Moderna språk';
  }

  return cleaned;
}

/// Resultat av tvätt och expansion av schematitel (FAS 6d.4).
class CleanedLessonSubject {
  final String subject;
  final String? classCode;

  const CleanedLessonSubject({
    required this.subject,
    this.classCode,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CleanedLessonSubject &&
          runtimeType == other.runtimeType &&
          subject == other.subject &&
          classCode == other.classCode;

  @override
  int get hashCode => Object.hash(subject, classCode);

  @override
  String toString() => 'CleanedLessonSubject(subject: $subject, classCode: $classCode)';
}

/// Tvättar och expanderar schematitlar, särskilt för gymnasiekoder (FAS 6d.4).
/// - "_" -> mellanslag
/// - Avslutande klasskod (t.ex. "tek2", "TE24b" - bokstäver+siffror efter sista mellanslaget/understrecket)
///   extraheras som [classCode] och dämpas som sal-text istället för att ingå i ämnet.
/// - Första bokstaven versal ("mentorstid_tek2" -> "Mentorstid" + "tek2").
/// - Okänt mönster -> oförändrat.
CleanedLessonSubject cleanAndExpandSubjectTitle(
  String rawTitle, {
  String? calendarDescription,
}) {
  final cleaned = cleanLessonTitle(rawTitle).trim();
  if (cleaned.isEmpty) return const CleanedLessonSubject(subject: 'Lektion');

  // Hitta sista separator (_ eller mellanslag)
  final lastUnderscore = cleaned.lastIndexOf('_');
  final lastSpace = cleaned.lastIndexOf(' ');
  final lastSep = lastUnderscore > lastSpace ? lastUnderscore : lastSpace;

  if (lastSep > 0 && lastSep < cleaned.length - 1) {
    final candidateCode = cleaned.substring(lastSep + 1).trim();

    // Klasskod: bokstäver + siffror (t.ex. tek2, TE24b)
    // Kräver minst en bokstav och minst en siffra, och endast alfanumeriska tecken.
    // Börjar med bokstäver följt av siffror (skiljer från kurskoder som "2c" i "Matematik 2c")
    final classCodeRegex = RegExp(r'^[a-zA-ZåäöÅÄÖ]+\d+[a-zA-ZåäöÅÄÖ0-9]*$');
    if (classCodeRegex.hasMatch(candidateCode)) {
      final rawSubjectPart = cleaned.substring(0, lastSep).replaceAll('_', ' ').trim();
      if (rawSubjectPart.isNotEmpty) {
        final expanded = expandSchoolSubjectTitle(rawSubjectPart, calendarDescription: calendarDescription);
        final capitalized = expanded.isNotEmpty
            ? (expanded[0].toUpperCase() + expanded.substring(1))
            : expanded;
        return CleanedLessonSubject(subject: capitalized, classCode: candidateCode);
      }
    }
  }

  // Ingen klasskod identifierad: ersätt understreck med mellanslag och expandera
  final replaced = cleaned.replaceAll('_', ' ').trim();
  final expanded = expandSchoolSubjectTitle(replaced, calendarDescription: calendarDescription);
  final capitalized = expanded.isNotEmpty
      ? (expanded[0].toUpperCase() + expanded.substring(1))
      : expanded;
  return CleanedLessonSubject(subject: capitalized, classCode: null);
}
