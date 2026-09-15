import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/user_model.dart';
import '../../utils/date_utils.dart';
import '../../utils/person_match.dart';
import '../../utils/week_bucketing.dart';

/// Formaterar ett klockslag för Storskärm (FAS 6d.3):
/// Alltid strikt HH:MM med nollutfyllnad:
/// - `9:00` → `09:00`
/// - `9` → `09:00`
/// - `08:15` → `08:15`
/// - `15:00` → `15:00`
/// - `–6:00` → `–06:00`
String formatWallTime(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';

  // Hantera eventuellt inledande bindestreck (t.ex. '–06:00' eller '-6')
  final isPrefixedWithDash = trimmed.startsWith('–') || trimmed.startsWith('-');
  final cleanStr = isPrefixedWithDash ? trimmed.substring(1).trim() : trimmed;
  final prefix = isPrefixedWithDash ? '–' : '';

  final parts = cleanStr.split(':');
  if (parts.isEmpty) return trimmed;

  final h = int.tryParse(parts[0]);
  if (h == null) return trimmed;

  final m = parts.length > 1 ? (int.tryParse(parts[1].trim()) ?? 0) : 0;
  final paddedH = h.toString().padLeft(2, '0');
  final paddedM = m.toString().padLeft(2, '0');

  return '$prefix$paddedH:$paddedM';
}

/// Formaterar ett tidsintervall för Storskärm (FAS 6d.3):
/// Alltid strikt HH:MM–HH:MM med nollutfyllnad:
/// - `08:15–14:00`
/// - `09:00–13:00`
/// - `15:00`
String formatWallRange(String start, [String? end]) {
  final s = start.trim();
  final e = (end ?? '').trim();

  if (e.isNotEmpty) {
    final startFormatted = formatWallTime(s);
    final endFormatted = formatWallTime(e);
    if (startFormatted.isNotEmpty && endFormatted.isNotEmpty) {
      return '$startFormatted–$endFormatted';
    }
    if (startFormatted.isNotEmpty) return startFormatted;
    if (endFormatted.isNotEmpty) return '–$endFormatted';
    return '';
  }

  // Om start innehåller bindestreck ('–' eller '-')
  if (s.contains('–')) {
    final p = s.split('–');
    if (p.length == 2) {
      final p0 = formatWallTime(p[0]);
      final p1 = formatWallTime(p[1]);
      if (p0.isEmpty && p1.isNotEmpty) return '–$p1';
      if (p0.isNotEmpty && p1.isNotEmpty) return '$p0–$p1';
    }
  } else if (s.contains('-') && !s.startsWith('-')) {
    final p = s.split('-');
    if (p.length == 2) {
      final p0 = formatWallTime(p[0]);
      final p1 = formatWallTime(p[1]);
      if (p0.isNotEmpty && p1.isNotEmpty) return '$p0–$p1';
    }
  } else if (s.startsWith('–') || s.startsWith('-')) {
    final after = s.substring(1).trim();
    final f = formatWallTime(after);
    return f.isNotEmpty ? '–$f' : '';
  }

  return formatWallTime(s);
}

/// Bakåtkompatibla alias som pekar på formatWallTime och formatWallRange (FAS 6d.3).
String formatCompactSingleTime(String raw) => formatWallTime(raw);
String formatCompactTime(String start, [String? end]) => formatWallRange(start, end);

/// Returnerar prefix för nästa händelse i display-heron baserat på om plats är angiven (FAS 4.2).
/// - Ifyllt platsfält -> "Ut genom dörren"
/// - Saknar plats / null / tom sträng -> "Härnäst"
String formatHeroPrefix(String? location) {
  if (location != null && location.trim().isNotEmpty) {
    return 'Ut genom dörren';
  }
  return 'Härnäst';
}

/// Resultat av familjefoldning för displaylagret.
class DisplayFoldResult {
  final WeekBucketingResult bucketing;
  final Set<String> foldedDocIds;

  const DisplayFoldResult({
    required this.bucketing,
    required this.foldedDocIds,
  });
}

/// Fäller ihop händelser som rör ALLA familjemedlemmar till Familjen-raden (FAS 1.2).
/// - En händelse vars personUids/persons omfattar samtliga familjemedlemmar
///   tas bort ur personraderna och visas EN gång i Familjen-raden.
/// - Händelser utan personer ligger kvar i Familjen-raden som förut.
/// - En händelse med alla utom en medlem ligger kvar i respektive personrad.
DisplayFoldResult foldFamilyEvents(
  WeekBucketingResult raw,
  List<UserModel> members,
) {
  if (members.length < 2) {
    return DisplayFoldResult(
      bucketing: raw,
      foldedDocIds: const {},
    );
  }

  final foldedDocIds = <String>{};

  final newByMember = <String, Map<String, List<QueryDocumentSnapshot>>>{
    for (final m in members)
      m.uid: {
        for (final day in raw.days)
          dateKey(day): List<QueryDocumentSnapshot>.from(raw.eventsFor(m, day))
      }
  };

  final newFamilyByDay = <String, List<QueryDocumentSnapshot>>{
    for (final day in raw.days)
      dateKey(day): List<QueryDocumentSnapshot>.from(raw.familyFor(day))
  };

  for (final day in raw.days) {
    final k = dateKey(day);

    // Hämta alla unika händelsedokument för medlemmarna denna dag
    final dayDocs = <String, QueryDocumentSnapshot>{};
    for (final m in members) {
      final list = newByMember[m.uid]?[k];
      if (list != null) {
        for (final doc in list) {
          dayDocs[doc.id] = doc;
        }
      }
    }

    for (final doc in dayDocs.values) {
      final d = doc.data() as Map<String, dynamic>;
      if (eventHasNoPersons(d)) continue; // Redan familjegemensam

      if (eventIncludesAllMembers(d, members)) {
        foldedDocIds.add(doc.id);
        // Ta bort från alla medlemmars rader denna dag
        for (final m in members) {
          newByMember[m.uid]?[k]?.removeWhere((x) => x.id == doc.id);
        }
        // Lägg till i Familjen-raden om den inte redan finns där
        if (!newFamilyByDay[k]!.any((x) => x.id == doc.id)) {
          newFamilyByDay[k]!.add(doc);
        }
      }
    }

    // Sortera Familjen-raden kronologiskt
    newFamilyByDay[k]!.sort((a, b) {
      final ta = ((a.data() as Map)['time'] as String? ?? '99:99').trim();
      final tb = ((b.data() as Map)['time'] as String? ?? '99:99').trim();
      return ta.compareTo(tb);
    });
  }

  return DisplayFoldResult(
    bucketing: WeekBucketingResult(
      days: raw.days,
      byMember: newByMember,
      familyByDay: newFamilyByDay,
      shiftsByMember: raw.shiftsByMember,
    ),
    foldedDocIds: foldedDocIds,
  );
}
