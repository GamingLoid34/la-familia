import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;

import '../models/user_model.dart';
import 'aktivitet_formular.dart';
import 'checklist_updates.dart';
import 'date_utils.dart';
import 'lesson_prep.dart';

export 'checklist_updates.dart' show PacklistRad;

/// Fälten aktivitetsformuläret skriver till `planner_events`.
///
/// Portad från Android-appen (`util/AktivitetPayload.kt`,
/// `util/AktivitetSparning.kt`). En **ny** aktivitet får exakt samma fält som
/// Android skriver, fält för fält. En **redigering** skriver bara det som
/// faktiskt ändrats, så att ändringar andra gjort medan formuläret stod
/// öppet inte skrivs över:
///
/// - `checklist` skickas aldrig med redigeringen. Är packlistan ändrad
///   ([AktivitetPayload.packlistanAndrad]) sparas den för sig med
///   `saveChecklistEdit` i en transaktion, mot den senaste versionen.
/// - `recurrence` skrivs fältvis (`recurrence.type`, `recurrence.startDate`,
///   `recurrence.endDate`). `recurrence.exceptions` skrivs aldrig vid
///   redigering, så ett tillfälle som tagits bort under tiden inte kommer
///   tillbaka.
/// - `lessonPrep` får bara ny text (`lessonPrep.text`); avbockningarna rörs
///   inte.
/// - Ursprungsfälten ([ursprungsFalt]) skrivs aldrig vid redigering. En
///   importerad aktivitet förblir importerad (`source` blir inte `"manual"`),
///   och skaparen (`createdBy`, `createdByUid`) ändras inte.

/// En aktivitets tid är ett klockslag i formatet `HH:mm`.
String tidNyckel(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Fält som anger varifrån en aktivitet kommer och vem som skapade den.
/// Formuläret skriver dem bara när aktiviteten skapas (`source`,
/// `createdBy`, `createdByUid`), aldrig vid redigering.
const Set<String> ursprungsFalt = {
  'source',
  'createdBy',
  'createdByUid',
  'createdAt',
  'sourceNoteId',
  'planningImportKind',
  'calendarImportId',
  'calendarName',
  'icsKey',
  'schemaLabel',
  'visitBookingId',
  'calendarDescription',
  'description',
  'location',
  'calendarUrl',
  'calendarExtendedProps',
};

/// Det användaren fyllt i, oberoende av hur formuläret ser ut.
///
/// [upprepning] är lagringsvärdet: `"none"`, `"daily"`, `"weekly"`,
/// `"biweekly"` eller `"monthly"` (eller en okänd typ som lästs in och ska
/// bevaras).
@immutable
class AktivitetUtkast {
  final String titel;
  final String piktogram;
  final DateTime datum;
  final Tidslage tidslage;
  final TimeOfDay? starttid;
  final TimeOfDay? sluttid;
  final String upprepning;
  final DateTime? upprepningSlut;
  final List<UserModel> deltagare;
  final List<PacklistRad> packlista;
  final bool forberedelseAktiv;
  final String forberedelseText;

  const AktivitetUtkast({
    required this.titel,
    this.piktogram = '',
    required this.datum,
    this.tidslage = Tidslage.klockslag,
    this.starttid,
    this.sluttid,
    this.upprepning = 'none',
    this.upprepningSlut,
    this.deltagare = const [],
    this.packlista = const [],
    this.forberedelseAktiv = false,
    this.forberedelseText = '',
  });

  AktivitetUtkast copyWith({
    Tidslage? tidslage,
    String? upprepning,
  }) =>
      AktivitetUtkast(
        titel: titel,
        piktogram: piktogram,
        datum: datum,
        tidslage: tidslage ?? this.tidslage,
        starttid: starttid,
        sluttid: sluttid,
        upprepning: upprepning ?? this.upprepning,
        upprepningSlut: upprepningSlut,
        deltagare: deltagare,
        packlista: packlista,
        forberedelseAktiv: forberedelseAktiv,
        forberedelseText: forberedelseText,
      );
}

/// Det som faktiskt ska skrivas.
///
/// [taBort] är fält som ska raderas. De hålls isär från [falt] så att
/// logiken går att testa utan Firestore; [tillFirestore] gör om dem till
/// `FieldValue.delete()` precis innan skrivningen.
@immutable
class AktivitetPayload {
  /// Fälten som skrivs. Vid redigering bara ändrade fält, och nycklar med
  /// punkt (`recurrence.type`) är fältsökvägar för `update()`.
  final Map<String, dynamic> falt;

  /// Fält som ska raderas från dokumentet (bara vid redigering).
  final Set<String> taBort;

  /// Redigering: packlistan i formuläret skiljer sig från den inlästa, och
  /// ska sparas med `saveChecklistEdit`. Alltid falskt för en ny aktivitet,
  /// där `checklist` ligger i [falt].
  final bool packlistanAndrad;

  /// Formulärets packlista, till `saveChecklistEdit`.
  final List<PacklistRad> packlista;

  /// Underlaget till påminnelserna: hela aktiviteten som den ser ut efter
  /// sparningen, utan borttagningar och utan fältsökvägar.
  final Map<String, dynamic> forPaminnelser;

  const AktivitetPayload({
    required this.falt,
    required this.taBort,
    required this.packlistanAndrad,
    required this.packlista,
    required this.forPaminnelser,
  });

  /// Kartan till `set()` (ny) eller `update()` (redigering).
  Map<String, dynamic> tillFirestore() => {
        ...falt,
        for (final f in taBort) f: FieldValue.delete(),
      };

  /// Sant när redigeringen inte ändrar något i själva dokumentet (utöver en
  /// eventuell packlista).
  bool get tomRedigering => falt.isEmpty && taBort.isEmpty;
}

bool _lika(dynamic a, dynamic b) => checklistRowsEqual(a, b);

/// Bygger fälten till `planner_events` ur formuläret.
///
/// - [uid]: den inloggades uid; blir `createdBy` och `createdByUid` när
///   något skapas.
/// - [original]: det befintliga dokumentet vid redigering, annars null.
AktivitetPayload byggAktivitetPayload({
  required AktivitetUtkast utkast,
  required String uid,
  required String familyId,
  Map<String, dynamic>? original,
}) {
  final klockslag = utkast.tidslage == Tidslage.klockslag;
  final starttid = klockslag ? utkast.starttid : null;
  if (klockslag && starttid == null) {
    throw ArgumentError('Klockslagsläget kräver starttid');
  }

  final redigerar = original != null;
  final befintlig = original ?? const <String, dynamic>{};
  final datumNyckel = dateKey(utkast.datum);

  // Hela aktiviteten som Android skriver den, i Androids ordning.
  final hela = <String, dynamic>{
    'title': utkast.titel.trim(),
    'piktogram': utkast.piktogram.isEmpty ? '📅' : utkast.piktogram,
    'type': 'activity',
    'date': datumNyckel,
    // Tom tid för heldag och tid inte bestämd. Påminnelserna avbryter då.
    'time': starttid != null ? tidNyckel(starttid) : '',
    'persons': [for (final m in utkast.deltagare) m.name],
    'personUids': [for (final m in utkast.deltagare) m.uid],
  };
  if (!redigerar) {
    hela['checklist'] = [
      for (final r in utkast.packlista) {'item': r.text, 'isDone': r.klar},
    ];
    hela['source'] = 'manual';
    hela['createdBy'] = uid;
  }
  hela['isPending'] = false;
  hela['familyId'] = familyId;
  if (!redigerar) hela['createdByUid'] = uid;

  final taBort = <String>{};
  final sokvagar = <String, dynamic>{};

  // Förberedelse dagen innan. Avbockade datum bevaras när texten ändras.
  final prepText = utkast.forberedelseText.trim();
  if (utkast.forberedelseAktiv && prepText.isNotEmpty) {
    final prep = LessonPrep.withText(befintlig, prepText);
    hela[LessonPrep.field] = prep;
    if (redigerar && befintlig[LessonPrep.field] is Map) {
      final gammal = (befintlig[LessonPrep.field] as Map)['text'];
      if (gammal is! String || gammal.trim() != prepText) {
        sokvagar[LessonPrep.textPath] = prepText;
      }
    } else if (redigerar) {
      sokvagar[LessonPrep.field] = prep;
    }
  } else if (redigerar && LessonPrep.isEnabled(befintlig)) {
    // Avstängd: fältet tas bort helt.
    taBort.add(LessonPrep.field);
  }

  final sluttid = utkast.sluttid;
  if (klockslag && sluttid != null) {
    hela['endTime'] = tidNyckel(sluttid);
  } else if (redigerar) {
    taBort.add('endTime');
  }

  // timeMode skrivs bara utan klockslag. Med klockslag tas ett gammalt bort,
  // men bara om det finns.
  final lagring = utkast.tidslage.lagring;
  if (lagring != null) {
    hela[Tidslage.falt] = lagring;
  } else if (redigerar && befintlig.containsKey(Tidslage.falt)) {
    taBort.add(Tidslage.falt);
  }

  final upprepas = utkast.upprepning != 'none' && utkast.upprepning.isNotEmpty;
  final slutNyckel =
      utkast.upprepningSlut != null ? dateKey(utkast.upprepningSlut!) : null;
  if (upprepas) {
    final gammalRec = befintlig['recurrence'];
    final undantag = gammalRec is Map && gammalRec['exceptions'] is List
        ? [
            for (final e in gammalRec['exceptions'] as List)
              if (e != null) e.toString(),
          ]
        : <String>[];
    hela['isRecurring'] = true;
    hela['recurrence'] = <String, dynamic>{
      'type': utkast.upprepning,
      'startDate': datumNyckel,
      'endDate': slutNyckel,
      'exceptions': undantag,
    };
    if (redigerar && gammalRec is Map) {
      // Bara de delfält som ändrats; undantagen rörs aldrig.
      final nya = {
        'type': utkast.upprepning,
        'startDate': datumNyckel,
        'endDate': slutNyckel,
      };
      for (final e in nya.entries) {
        if (!_lika(gammalRec[e.key], e.value)) {
          sokvagar['recurrence.${e.key}'] = e.value;
        }
      }
    } else if (redigerar) {
      sokvagar['recurrence'] = hela['recurrence'];
    }
  } else if (redigerar) {
    taBort
      ..add('isRecurring')
      ..add('recurrence');
  }

  final packlistanAndrad =
      redigerar && !listEquals(utkast.packlista, lasPacklista(befintlig));

  final forPaminnelser = Map<String, dynamic>.of(hela)
    ..removeWhere((k, _) => taBort.contains(k));

  if (!redigerar) {
    return AktivitetPayload(
      falt: hela,
      taBort: const {},
      packlistanAndrad: false,
      packlista: utkast.packlista,
      forPaminnelser: forPaminnelser,
    );
  }

  // Redigering: bara det som skiljer sig från dokumentet.
  final falt = <String, dynamic>{};
  for (final e in hela.entries) {
    final k = e.key;
    if (ursprungsFalt.contains(k)) continue;
    if (k == 'checklist' ||
        k == 'recurrence' ||
        k == LessonPrep.field) {
      continue;
    }
    if (k == 'type') {
      // Posttypen ändras aldrig av en vanlig redigering (en importerad post
      // behåller sin typ); den skrivs bara om den saknas, som i Android.
      if (!befintlig.containsKey('type')) falt[k] = e.value;
      continue;
    }
    if (k == 'familyId') {
      // Familjen byts aldrig av formuläret; skrivs bara om den saknas.
      final gammal = befintlig['familyId'];
      if ((gammal is! String || gammal.isEmpty) && familyId.isNotEmpty) {
        falt[k] = familyId;
      }
      continue;
    }
    if (!befintlig.containsKey(k) || !_lika(befintlig[k], e.value)) {
      falt[k] = e.value;
    }
  }
  falt.addAll(sokvagar);
  // En borttagning av ett fält som inte finns behövs inte heller.
  final taBortBehov = {
    for (final f in taBort)
      if (befintlig.containsKey(f)) f,
  };

  return AktivitetPayload(
    falt: falt,
    taBort: taBortBehov,
    packlistanAndrad: packlistanAndrad,
    packlista: utkast.packlista,
    forPaminnelser: forPaminnelser,
  );
}

/// Packlistan som den ligger i dokumentet.
///
/// Läser alla tre radformerna (`{item}`, `{text}`, sträng) och hoppar över
/// rader utan text. Varje rad får sitt index i dokumentets lista som
/// [PacklistRad.ursprungIndex].
List<PacklistRad> lasPacklista(Map<String, dynamic> raw) {
  final rows = raw['checklist'];
  if (rows is! List) return const [];
  return [
    for (var i = 0; i < rows.length; i++)
      if (checklistTextOf(rows[i]) != null)
        PacklistRad(
          checklistTextOf(rows[i])!,
          klar: checklistIsDone(rows[i]),
          ursprungIndex: i,
        ),
  ];
}

/// Mallen som sparas vid ny aktivitet med "Spara som mall" påslaget.
Map<String, dynamic> aktivitetsmall({
  required String titel,
  required String piktogram,
  required List<PacklistRad> packlista,
  required String familyId,
}) =>
    {
      'title': titel.trim(),
      'piktogram': piktogram.isEmpty ? '📅' : piktogram,
      'checklist': [for (final r in packlista) r.text],
      'familyId': familyId,
    };

/// Skriver en ny aktivitet. Id:t skapas lokalt och lämnas till [mottagId]
/// innan väntan på servern, så att det finns även utan nät.
Future<String> skrivNyAktivitet(
  CollectionReference<Map<String, dynamic>> planerEvents,
  AktivitetPayload payload, {
  void Function(String id)? mottagId,
}) async {
  final ref = planerEvents.doc();
  mottagId?.call(ref.id);
  await ref.set(payload.tillFirestore());
  return ref.id;
}

/// Skriver en redigering: först dokumentets ändrade fält med `update()`,
/// sedan packlistan i en transaktion om den ändrats.
///
/// [originalChecklist] är `checklist` som den låg när formuläret öppnades.
/// `update()` fungerar utan nät; transaktionen körs när uppdateringen nått
/// servern och kräver nät.
///
/// Utan nät ([offline]) kan transaktionen inte köras. Då slås packlistan ihop
/// mot den senaste versionen i telefonens cache och skickas i samma köade
/// `update()`, så att ändringen inte försvinner om appen stängs innan nätet
/// kommer tillbaka.
Future<String> skrivRedigering(
  DocumentReference<Map<String, dynamic>> ref,
  AktivitetPayload payload, {
  required List<dynamic> originalChecklist,
  bool offline = false,
}) async {
  if (offline && payload.packlistanAndrad) {
    List<dynamic> latest;
    try {
      final cached = await ref.get(const GetOptions(source: Source.cache));
      latest = checklistRowsOf(cached.data()?['checklist']);
    } catch (_) {
      latest = originalChecklist;
    }
    final merged = mergeChecklist(
      latestRows: latest,
      originalRows: originalChecklist,
      editedRows: payload.packlista,
    );
    await ref.update({...payload.tillFirestore(), 'checklist': merged});
    return ref.id;
  }
  if (!payload.tomRedigering) {
    await ref.update(payload.tillFirestore());
  }
  if (payload.packlistanAndrad) {
    await saveChecklistEdit(
      ref,
      originalRows: originalChecklist,
      editedRows: payload.packlista,
    );
  }
  return ref.id;
}

// ---------------------------------------------------------------------------
// Sparning utan att formuläret hänger (Android `AktivitetSparning`).
// ---------------------------------------------------------------------------

/// Hur det gick när formuläret sparade.
sealed class SparUtfall {
  const SparUtfall();
}

/// Servern har tagit emot aktiviteten.
class SparBekraftat extends SparUtfall {
  final String eventId;
  const SparBekraftat(this.eventId);

  @override
  bool operator ==(Object other) =>
      other is SparBekraftat && other.eventId == eventId;

  @override
  int get hashCode => eventId.hashCode;
}

/// Aktiviteten ligger på telefonen och skickas när nätet finns. [eventId]
/// blir känt så fort id:t finns (direkt vid redigering och, med
/// [skrivNyAktivitet], direkt även för en ny).
class SparLokalt extends SparUtfall {
  final ValueListenable<String?> eventId;
  const SparLokalt(this.eventId);
}

/// Servern nekade medan formuläret väntade. Formuläret står kvar.
class SparNekat extends SparUtfall {
  final String meddelande;
  const SparNekat(this.meddelande);
}

/// Resultatet av skrivningen, så att ett fel aldrig blir ohanterat.
class _Svar {
  final String? id;
  final Object? fel;
  const _Svar(this.id, this.fel);
}

/// Sparar en aktivitet utan att låta formuläret hänga.
///
/// - **Utan nät** väntar formuläret inte alls: [SparLokalt].
/// - **Med nät** väntar det högst [vantaPaServern] på serverns svar. Svar i
///   tid ger [SparBekraftat] eller [SparNekat]; inget svar ger [SparLokalt].
/// - **Ett nekande som kommer efter att formuläret slutat vänta** hamnar i
///   [senaFel] och får inte tystas.
class AktivitetSparning {
  /// Hur länge formuläret väntar på servern när nätet finns.
  static const standardVantan = Duration(seconds: 4);

  /// Nätstatusen ska finnas direkt; det här är bara ett skydd.
  static const _natkoll = Duration(milliseconds: 500);

  /// En delad instans för appen, så sena fel överlever formuläret.
  static final AktivitetSparning instans = AktivitetSparning();

  final Future<bool> Function() _arOnline;
  final Duration vantaPaServern;

  AktivitetSparning({
    Future<bool> Function()? arOnline,
    this.vantaPaServern = standardVantan,
  }) : _arOnline = arOnline ?? _standardNatkoll;

  static Future<bool> _standardNatkoll() async {
    final resultat = await Connectivity().checkConnectivity();
    return resultat.any((r) => r != ConnectivityResult.none);
  }

  /// Nekanden och fel som kom efter att formuläret slutat vänta, äldst
  /// först. Ligger kvar tills de kvitterats med [kvitteraFel].
  final ValueNotifier<List<String>> senaFel = ValueNotifier(const []);

  /// Användaren har sett det äldsta felet.
  void kvitteraFel() {
    if (senaFel.value.isEmpty) return;
    senaFel.value = senaFel.value.sublist(1);
  }

  void _laggTillFel(String text) {
    senaFel.value = [...senaFel.value, text];
  }

  /// - [titel]: aktivitetens namn, så att ett sent fel säger vilken det gäller.
  /// - [kandId]: id:t vid redigering, null för en ny aktivitet.
  /// - [skriv]: själva skrivningen. Får en mottagare för id:t så fort det
  ///   skapats lokalt, och returnerar dokumentets id efter serverns svar.
  /// - [narIdArKant]: påminnelser och mall. Körs en gång, så fort id:t är
  ///   känt. Ett fel här räknas inte som att aktiviteten inte sparades.
  Future<SparUtfall> spara({
    required String titel,
    String? kandId,
    required Future<String> Function(void Function(String id) mottagId) skriv,
    Future<void> Function(String id)? narIdArKant,
  }) async {
    final id = ValueNotifier<String?>(kandId);
    var efterarbeteStartat = false;

    void idArKant(String nyttId) {
      id.value = nyttId;
      if (kandId == null && !efterarbeteStartat) {
        efterarbeteStartat = true;
        _efterarbete(titel, nyttId, narIdArKant);
      }
    }

    final svar = Future<String>.sync(() => skriv(idArKant)).then(
      (v) {
        idArKant(v);
        return _Svar(v, null);
      },
      onError: (Object e) => _Svar(null, e),
    );

    // Vid redigering är id:t känt, så påminnelserna behöver inte vänta.
    if (kandId != null) _efterarbete(titel, kandId, narIdArKant);

    bool online;
    try {
      online = await _arOnline().timeout(_natkoll);
    } catch (_) {
      online = false;
    }
    if (!online) {
      _bevaka(titel, svar);
      return SparLokalt(id);
    }

    try {
      final s = await svar.timeout(vantaPaServern);
      if (s.fel != null) return SparNekat(felText(s.fel));
      return SparBekraftat(s.id!);
    } on TimeoutException {
      _bevaka(titel, svar);
      return SparLokalt(id);
    }
  }

  void _bevaka(String titel, Future<_Svar> svar) {
    svar.then((s) {
      if (s.fel != null) {
        _laggTillFel('"$titel" kunde inte sparas. ${felText(s.fel)}');
      }
    });
  }

  void _efterarbete(
    String titel,
    String id,
    Future<void> Function(String id)? arbete,
  ) {
    if (arbete == null) return;
    Future<void>.sync(() => arbete(id)).catchError((Object e) {
      // Aktiviteten finns, men påminnelse eller mall saknas. Det ska synas.
      _laggTillFel('"$titel" sparades, men något runt den gick fel. '
          '${felText(e)}');
    });
  }

  /// Ett fel från Firestore, i text som går att förstå.
  static String felText(Object? fel) {
    if (fel is ChecklistChangedException) return fel.message;
    final meddelande = fel is FirebaseException
        ? '${fel.code} ${fel.message ?? ''}'.trim()
        : (fel?.toString() ?? '');
    if (meddelande.toUpperCase().contains('PERMISSION_DENIED') ||
        meddelande.contains('permission-denied')) {
      return 'Du saknar behörighet att spara den här aktiviteten.';
    }
    if (meddelande.trim().isEmpty) return 'Försök igen.';
    final utanPrefix = meddelande.startsWith('Exception: ')
        ? meddelande.substring('Exception: '.length)
        : meddelande;
    return 'Kunde inte spara: $utanPrefix';
  }
}
