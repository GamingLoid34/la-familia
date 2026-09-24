import 'package:flutter/foundation.dart';

import '../models/user_model.dart';
import 'chore_utils.dart';
import 'recurrence.dart';

/// Listan "Återkommande": allt som upprepas, aktiviteter och sysslor
/// tillsammans.
///
/// Portad från Android-appen (`util/AterkommandeLista.kt`). "Emilio lagar
/// middag" och "Tvätta ditt eget" gick inte att hitta, eftersom det ena var
/// en återkommande aktivitet och det andra en syssla — och de tas bort på
/// olika ställen. Här syns båda på samma sätt, och typen står bara som en
/// liten etikett.
///
/// Data: `planner_events` där `familyId == X` och `isRecurring == true`, plus
/// familjens alla sysslor (`chores`), och familjens medlemmar.

/// Vad raden är.
enum AterkommandeTyp {
  aktivitet('Aktivitet'),
  syssla('Syssla');

  final String etikett;
  const AterkommandeTyp(this.etikett);
}

/// En rad i listan.
@immutable
class AterkommandeRad {
  final AterkommandeTyp typ;
  final String id;
  final String titel;
  final String piktogram;

  /// Vem det gäller, i klartext, eller "Hela familjen".
  final String vem;

  /// T.ex. "Varje torsdag 17:00".
  final String nar;
  final Map<String, dynamic> raw;

  const AterkommandeRad({
    required this.typ,
    required this.id,
    required this.titel,
    required this.piktogram,
    required this.vem,
    required this.nar,
    required this.raw,
  });
}

/// Rubrik, ingress och tom text på skärmen.
const aterkommandeRubrik = 'Återkommande';
const aterkommandeIngress =
    'Allt som upprepas, både aktiviteter och sysslor. Ta bort tar bort alla gånger.';
const aterkommandeTom = 'Inget upprepas just nu.';

String _forNamn(String namn) => namn.trim().split(' ').first;

String _strang(dynamic v) => v is String ? v : '';

List<String> _strangar(dynamic v) => [
      for (final x in (v is List ? v : const []))
        if (x != null) x.toString(),
    ];

String? _namnFor(List<UserModel> members, String uid) {
  for (final m in members) {
    if (m.uid == uid) return m.name;
  }
  return null;
}

String _vemText(
  List<String> persons,
  List<String> uids,
  List<UserModel> members,
) {
  var namn = [for (final p in persons) if (p.trim().isNotEmpty) p];
  if (namn.isEmpty) {
    namn = [
      for (final u in uids) ?_namnFor(members, u),
    ];
  }
  return namn.isEmpty ? 'Hela familjen' : namn.map(_forNamn).join(', ');
}

String _narText(Map<String, dynamic> raw, String time) {
  final etikett = recurrenceLabel(raw);
  final upprepning = etikett.trim().isEmpty ? 'Upprepas' : etikett;
  final tid = time.trim();
  return tid.isEmpty ? upprepning : '$upprepning $tid';
}

/// Bygger listan av [events] (`planner_events`) och [chores] (`chores`),
/// båda som (dokument-id, data).
///
/// Aktiviteter tas med när de har `recurrence`, sysslor när
/// [choreIsRecurring]. Samma dokument två gånger visas en gång. Sorterat på
/// titel (skiftlägesokänsligt) och sedan id.
List<AterkommandeRad> byggAterkommandeLista({
  required List<(String, Map<String, dynamic>)> events,
  required List<(String, Map<String, dynamic>)> chores,
  required List<UserModel> members,
}) {
  final rader = <AterkommandeRad>[];

  final settaEvents = <String>{};
  for (final (id, raw) in events) {
    if (raw['recurrence'] is! Map) continue;
    if (!settaEvents.add(id)) continue;
    final titel = _strang(raw['title']);
    final pik = _strang(raw['piktogram']);
    rader.add(AterkommandeRad(
      typ: AterkommandeTyp.aktivitet,
      id: id,
      titel: titel.trim().isEmpty ? 'Aktivitet' : titel,
      piktogram: pik.trim().isEmpty ? '📅' : pik,
      vem: _vemText(
          _strangar(raw['persons']), _strangar(raw['personUids']), members),
      nar: _narText(raw, _strang(raw['time'])),
      raw: raw,
    ));
  }

  final settaSysslor = <String>{};
  for (final (id, raw) in chores) {
    if (!choreIsRecurring(raw)) continue;
    if (!settaSysslor.add(id)) continue;
    final chore = _strang(raw['chore']);
    final titel = chore.trim().isEmpty ? _strang(raw['title']) : chore;
    final pik = _strang(raw['piktogram']);
    final rotation = [
      for (final u in _strangar(raw['rotationUids'])) ?_namnFor(members, u),
    ];
    final who = _strang(raw['who']);
    rader.add(AterkommandeRad(
      typ: AterkommandeTyp.syssla,
      id: id,
      titel: titel.trim().isEmpty ? 'Syssla' : titel,
      piktogram: pik.trim().isEmpty ? '🧹' : pik,
      vem: rotation.length > 1
          ? 'Turas om: ${rotation.map(_forNamn).join(', ')}'
          : (who.trim().isNotEmpty ? _forNamn(who) : 'Hela familjen'),
      nar: _narText(raw, _strang(raw['dueTime'])),
      raw: raw,
    ));
  }

  rader.sort((a, b) {
    final t = a.titel.toLowerCase().compareTo(b.titel.toLowerCase());
    return t != 0 ? t : a.id.compareTo(b.id);
  });
  return rader;
}

const _kortaManader = [
  'jan', 'feb', 'mar', 'apr', 'maj', 'jun',
  'jul', 'aug', 'sep', 'okt', 'nov', 'dec',
];

const _veckodagar = [
  '', 'måndag', 'tisdag', 'onsdag', 'torsdag', 'fredag', 'lördag', 'söndag',
];

/// Knappen för ett enskilt tillfälle i Ta bort-dialogen: "Bara idag",
/// "Bara i morgon", annars t.ex. "Bara tisdag 29 sep".
String baraDagEtikett(DateTime dag, DateTime idag) {
  final d = DateTime(dag.year, dag.month, dag.day);
  final i = DateTime(idag.year, idag.month, idag.day);
  if (d == i) return 'Bara idag';
  if (d == DateTime(i.year, i.month, i.day + 1)) return 'Bara i morgon';
  return 'Bara ${_veckodagar[d.weekday]} ${d.day} ${_kortaManader[d.month - 1]}';
}
