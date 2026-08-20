import '../models/user_model.dart';

/// Central person-matchning (ROADMAP Etapp 3).
///
/// Historiskt kopplas events/sysslor/pass till personer via NAMN-strängar
/// (`persons: ['Oscar']`, `who: 'Oscar'`). Det går sönder vid namnbyten.
/// Ny data skriver dessutom uid-fält (`personUids`, `whoUid`) — matchning
/// sker via uid när fältet finns, annars namn (bakåtkompatibelt).
/// Namnen behålls i datat för visning.

/// Uid för ett namn bland familjens medlemmar, eller '' om okänt.
String uidForName(List<UserModel> members, String name) {
  for (final m in members) {
    if (m.name == name) return m.uid;
  }
  return '';
}

/// Första medlem vars namn förekommer i [text], längsta träffen vinner.
/// Används t.ex. för "Emilios skolschema" → Emilio.
UserModel? memberMatchingText(List<UserModel> members, String text) {
  final hay = text.trim().toLowerCase();
  if (hay.isEmpty) return null;
  final hits = members.where((m) {
    final n = m.name.trim();
    return n.isNotEmpty && hay.contains(n.toLowerCase());
  }).toList()
    ..sort((a, b) => b.name.length.compareTo(a.name.length));
  return hits.isEmpty ? null : hits.first;
}

/// Uids för en namnlista — okända namn utelämnas.
List<String> uidsForNames(List<UserModel> members, List<String> names) =>
    names.map((n) => uidForName(members, n)).where((u) => u.isNotEmpty).toList();

/// Är personen kopplad till eventet? Uid-fältet vinner om det finns.
/// OBS: tom `persons`/`personUids` betyder "ingen specifik person" —
/// anroparen avgör om det ska tolkas som "alla".
bool eventIncludesPerson(
  Map<String, dynamic> d, {
  required String uid,
  required String name,
}) {
  final uids = (d['personUids'] as List?)?.cast<String>();
  if (uids != null && uids.isNotEmpty) return uids.contains(uid);
  final persons = (d['persons'] as List? ?? []).cast<String>();
  return persons.contains(name);
}

/// Saknar eventet personkoppling helt?
bool eventHasNoPersons(Map<String, dynamic> d) {
  final uids = (d['personUids'] as List?)?.cast<String>() ?? const [];
  final persons = (d['persons'] as List? ?? []).cast<String>();
  return uids.isEmpty && persons.isEmpty;
}

/// Är sysslan/arbetspasset tilldelat personen? (`whoUid` vinner över `who`.)
bool assignedToPerson(
  Map<String, dynamic> d, {
  required String uid,
  required String name,
}) {
  final whoUid = d['whoUid'] as String? ?? '';
  if (whoUid.isNotEmpty) return whoUid == uid;
  return (d['who'] as String? ?? '') == name;
}
