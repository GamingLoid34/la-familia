import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/user_model.dart';
import '../screens/display/display_scene_models.dart';
import '../screens/display/display_school_menu_data.dart';
import '../utils/date_utils.dart';

/// Skollunch i Min dag (spec 4.2). Port av Androids `SchoolMenuLookup` och
/// `MinDagViewModel.subscribeSchoolMenus`.
///
/// Matsedeln lagras per vecka i `families/{id}/school_menus/{schoolId}/weeks/{isoVecka}`
/// med `days` som en lista där varje post har `date`, `lunch` och valfritt `vegetarian`
/// och `note`. Vilket barn som går på vilken skola står i
/// `families/{id}/display_config/main` under `skolmat.schools[]`.
///
/// **Begränsning, samma som Android:** bara sparade veckor i Firestore läses. För
/// Mateo-skolor finns matsedeln bara via `displaySchoolMenu`-funktionen (storskärmen), så
/// i praktiken visas skollunch bara för skolor med "Egen matsedel".

/// En dags skollunch.
class SkolLunch {
  final String ratt;
  final String? vegetarisk;
  final String? notering;

  const SkolLunch({required this.ratt, this.vegetarisk, this.notering});
}

/// Veckonyckeln `YYYY-Www` för [dag], med ISO-året (1 januari kan höra till vecka 52/53).
String skolmatVeckonyckel(DateTime dag) => formatIsoWeek(dag);

String? _rensad(Object? v) {
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}

/// Dagens lunch ur [dagar], eller null när dagen saknas.
///
/// Tom rätt räknas som ingen lunch: en tom rad i dagvyn vore värre än ingen rad alls.
SkolLunch? skolLunchFor(List<Map<String, dynamic>> dagar, DateTime dag) {
  final nyckel = dateKey(dag);
  for (final rad in dagar) {
    if (_rensad(rad['date']) != nyckel) continue;
    final ratt = _rensad(rad['lunch']);
    if (ratt == null) return null;
    return SkolLunch(
      ratt: ratt,
      vegetarisk: _rensad(rad['vegetarian']),
      notering: _rensad(rad['note']),
    );
  }
  return null;
}

/// Kort rad för dagvyn. Vegetariskt läggs till när det finns; noteringen utelämnas.
String skolLunchKortEtikett(SkolLunch lunch) => lunch.vegetarisk != null
    ? '${lunch.ratt} · veg: ${lunch.vegetarisk}'
    : lunch.ratt;

/// Det som läses för en dag: skolorna och deras sparade vecka.
class SkolmatDag {
  final DisplaySkolmatConfig config;

  /// Veckans dagar per skol-id. Saknad skola betyder att ingen vecka finns.
  final Map<String, List<Map<String, dynamic>>> veckor;

  const SkolmatDag({required this.config, this.veckor = const {}});
}

/// Ett skollunchblock på tidsaxeln.
class SkolLunchBlock {
  final String titel;
  final DateTime start;
  final DateTime slut;

  const SkolLunchBlock({
    required this.titel,
    required this.start,
    required this.slut,
  });

  static const String piktogram = '🍎';
  static const String tid = '11:00';
  static const String slutTid = '11:45';

  /// Samma fält som en händelse, så blocket kan ritas som ett vanligt kort.
  Map<String, dynamic> get data => {
    'title': titel,
    'piktogram': piktogram,
    'time': tid,
    'endTime': slutTid,
  };
}

/// Skollunchblocken för [dag]: ett per barn vars skola har en lunch den dagen.
///
/// Som Android visas luncherna i **alla** användares Min dag och filtreras inte på den
/// som tittar. Titeln är "Förnamn: rätt", 11:00–11:45. Blocket är inget matval och går
/// inte att trycka på.
List<SkolLunchBlock> byggSkolLunchBlock({
  required SkolmatDag? skolmat,
  required List<UserModel> medlemmar,
  required DateTime dag,
}) {
  if (skolmat == null || skolmat.config.schools.isEmpty) return const [];
  final start = DateTime(dag.year, dag.month, dag.day, 11, 0);
  final slut = DateTime(dag.year, dag.month, dag.day, 11, 45);
  final block = <SkolLunchBlock>[];
  for (final medlem in medlemmar) {
    final skola = skolmat.config.schoolForMember(medlem.uid);
    if (skola == null) continue;
    final dagar = skolmat.veckor[skola.id];
    if (dagar == null) continue;
    final lunch = skolLunchFor(dagar, dag);
    if (lunch == null) continue;
    final fornamn = medlem.name.trim().split(' ').first;
    final namn = fornamn.isEmpty ? medlem.name : fornamn;
    block.add(
      SkolLunchBlock(
        titel: '$namn: ${skolLunchKortEtikett(lunch)}',
        start: start,
        slut: slut,
      ),
    );
  }
  return block;
}

/// Läser skolorna och veckans matsedlar för [dag].
///
/// En läsning per skola, inte per barn: syskon på samma skola delar dokument. Veckorna
/// läses en gång per konfigurationsändring (som Androids `.first()`). Ett läsfel på en
/// vecka sväljs medvetet — en utebliven skollunch är en saknad rad, inte ett fel som
/// användaren behöver agera på.
Stream<SkolmatDag> skolmatDagStream({
  required String familyId,
  required DateTime dag,
  FirebaseFirestore? db,
}) {
  if (familyId.isEmpty) return const Stream.empty();
  final firestore = db ?? FirebaseFirestore.instance;
  final familj = firestore.collection('families').doc(familyId);
  final vecka = skolmatVeckonyckel(dag);
  return familj.collection('display_config').doc('main').snapshots().asyncMap((
    snap,
  ) async {
    final raw = snap.data()?['skolmat'];
    final config = raw is Map
        ? DisplaySkolmatConfig.fromMap(Map<String, dynamic>.from(raw))
        : const DisplaySkolmatConfig();
    final veckor = <String, List<Map<String, dynamic>>>{};
    for (final skola in config.schools) {
      if (skola.id.isEmpty || skola.memberUids.isEmpty) continue;
      if (veckor.containsKey(skola.id)) continue;
      try {
        final doc = await familj
            .collection('school_menus')
            .doc(skola.id)
            .collection('weeks')
            .doc(vecka)
            .get();
        final dagar = doc.data()?['days'];
        if (dagar is List) {
          veckor[skola.id] = [
            for (final d in dagar)
              if (d is Map) Map<String, dynamic>.from(d),
          ];
        }
      } catch (e, st) {
        developer.log(
          'Min dag: kunde inte läsa skolmatsedel ${skola.id}/$vecka',
          error: e,
          stackTrace: st,
        );
      }
    }
    return SkolmatDag(config: config, veckor: veckor);
  });
}
