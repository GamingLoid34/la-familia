import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;

import '../models/user_model.dart';
import 'aktivitet_payload.dart';
import 'date_utils.dart';
import 'lesson_prep.dart';
import 'person_match.dart';
import 'quick_add_parser.dart';

/// Aktivitetsformulärets regler, utan widgetar.
///
/// Portad från Android-appen (`util/AktivitetFormularLogik.kt`,
/// `util/FormularTolkning.kt`, `util/SparBekraftelse.kt` och formulärets
/// vymodell): förvalt datum, datumlås för serier, tre tidslägen, validering,
/// "Fler val"-sammanfattningen, "Skriv eller säg" och bekräftelsetexten.

const _veckodagar = [
  '',
  'måndag',
  'tisdag',
  'onsdag',
  'torsdag',
  'fredag',
  'lördag',
  'söndag',
];

const _manader = [
  '',
  'januari',
  'februari',
  'mars',
  'april',
  'maj',
  'juni',
  'juli',
  'augusti',
  'september',
  'oktober',
  'november',
  'december',
];

DateTime _dag(DateTime d) => DateTime(d.year, d.month, d.day);

String _versal(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// De tre sätt en aktivitets tid kan vara bestämd på.
///
/// Lagras i `planner_events` som `timeMode` (samma värden som Android):
///
/// - **Klockslag** skriver inget `timeMode` och tar bort ett gammalt.
/// - **Heldag** (`"allDay"`) och **tid inte bestämd** (`"undecided"`) skriver
///   `time: ""`, `timeMode` och ingen `endTime`.
/// - **`timeMode` gäller bara när `time` är tom.** Har aktiviteten ett
///   klockslag är den tidsatt, vad `timeMode` än säger.
enum Tidslage {
  /// Starttid krävs, sluttid valfri.
  klockslag(null, null, 'Klockslag'),

  /// Hela dagen, till exempel studiedag eller lov.
  heldag('allDay', 'Hela dagen', 'Heldag'),

  /// Klockslaget är inte känt än.
  obestamd('undecided', 'Tid inte bestämd', 'Inte bestämd');

  /// Värdet i `timeMode`, eller null när fältet inte ska finnas.
  final String? lagring;

  /// Texten i detaljrutan, där klockslaget annars står.
  final String? etikett;

  /// Texten på formulärets val.
  final String valText;

  const Tidslage(this.lagring, this.etikett, this.valText);

  /// Fältnamnet på dokumentet.
  static const falt = 'timeMode';

  /// Förklaringen under valen, eller null för klockslag.
  String? get forklaring => switch (this) {
        Tidslage.klockslag => null,
        Tidslage.heldag =>
          'Gäller hela dagen. Visas under Utan tid, utan påminnelse.',
        Tidslage.obestamd =>
          'Visas under Utan tid tills tiden är bestämd, utan påminnelse.',
      };

  /// Tidsläget för ett befintligt dokument, som formuläret öppnas med.
  ///
  /// En tidlös aktivitet utan `timeMode` öppnas som [obestamd]; en
  /// importerad heldag som [heldag]. Bara förvalet: dokumentet ändras först
  /// om användaren sparar.
  static Tidslage las(Map<String, dynamic> raw) {
    if (((raw['time'] as String?) ?? '').trim().isNotEmpty) return klockslag;
    if (raw[falt] == heldag.lagring) return heldag;
    if (raw[falt] == null && arImporteradHeldag(raw)) return heldag;
    return obestamd;
  }

  /// Så ser en heldag ut efter kalenderimporten: `source: "calendar"`, tom
  /// `time` och `endTime: "00:00"`, inget `timeMode`.
  static bool arImporteradHeldag(Map<String, dynamic> raw) =>
      raw['source'] == 'calendar' &&
      ((raw['time'] as String?) ?? '').trim().isEmpty &&
      (raw['endTime'] as String?)?.trim() == '00:00';

  /// Etiketten i detaljrutan för en aktivitet utan klockslag, eller null.
  /// Bara när `timeMode` faktiskt finns.
  static String? visningsetikett(Map<String, dynamic> raw) {
    if (((raw['time'] as String?) ?? '').trim().isNotEmpty) return null;
    for (final l in Tidslage.values) {
      if (l.lagring != null && l.lagring == raw[falt]) return l.etikett;
    }
    return null;
  }
}

/// Varifrån aktivitetsformuläret öppnades.
sealed class FormularOppning {
  const FormularOppning();
}

/// Lägg till på Hem. Idag är förvalt.
class FormularFranHem extends FormularOppning {
  const FormularFranHem();
}

/// Lägg till i Kalendern eller från en dags ark. Dagen man tittar på är
/// förvald.
class FormularFranKalender extends FormularOppning {
  final DateTime dag;
  const FormularFranKalender(this.dag);
}

/// Redigering av en befintlig aktivitet.
class FormularRedigering extends FormularOppning {
  final String eventId;
  final Map<String, dynamic> raw;
  const FormularRedigering(this.eventId, this.raw);
}

/// Datumet formuläret öppnas med.
///
/// Vid redigering av en återkommande aktivitet är det seriens startdag, inte
/// det tillfälle man råkade trycka på.
DateTime forvalDatum(FormularOppning oppning, DateTime idag) =>
    switch (oppning) {
      FormularFranHem() => _dag(idag),
      FormularFranKalender(:final dag) => _dag(dag),
      FormularRedigering(:final raw) => _dag(
          _serieStart(raw) ?? _parseDatum(raw['date']) ?? idag,
        ),
    };

DateTime? _parseDatum(dynamic v) {
  if (v is String && v.trim().isEmpty) return null;
  if (v is String) {
    final p = v.split('-');
    if (p.length < 3 ||
        int.tryParse(p[0]) == null ||
        int.tryParse(p[1]) == null ||
        int.tryParse(p[2]) == null) {
      return null;
    }
  }
  return parseDate(v);
}

DateTime? _serieStart(Map<String, dynamic> raw) {
  final rec = raw['recurrence'];
  return rec is Map ? _parseDatum(rec['startDate']) : null;
}

/// Datumet går inte att ändra när en befintlig återkommande aktivitet
/// redigeras: seriens startdag styr alla tillfällen och undantag.
bool datumArLast(FormularOppning oppning) =>
    oppning is FormularRedigering && oppning.raw['recurrence'] != null;

/// Förklaringen under ett låst datum.
const datumLastForklaring =
    'Seriens startdag ändras inte här. Ändra ett enskilt tillfälle via ⋮ i kalendern.';

/// Vad som saknas för att formuläret ska gå att spara, eller null. En sak i
/// taget, i formulärets ordning.
String? valideraAktivitet({
  required String titel,
  required DateTime? datum,
  required Tidslage tidslage,
  required TimeOfDay? starttid,
}) {
  if (titel.trim().isEmpty) return 'Skriv vad aktiviteten heter.';
  if (datum == null) return 'Välj ett datum.';
  if (tidslage == Tidslage.klockslag && starttid == null) {
    return 'Välj en starttid.';
  }
  return null;
}

/// Etiketten på ett upprepningsval, till exempel "Varje torsdag". Veckodagen
/// tas från formulärets datum.
String upprepningsEtikett(String typ, DateTime datum) {
  final veckodag = _veckodagar[datum.weekday];
  return switch (typ) {
    'daily' => 'Varje dag',
    'weekly' => 'Varje $veckodag',
    'biweekly' => 'Varannan $veckodag',
    'monthly' => 'Varje månad (samma datum)',
    'none' || '' => 'Engångshändelse',
    _ => 'Upprepas',
  };
}

/// Standardvalen för upprepning i formuläret.
const upprepningsStandardVal = ['none', 'weekly', 'biweekly', 'monthly'];

/// Valen formuläret visar. En inläst typ som formuläret inte erbjuder (t.ex.
/// `"daily"`) läggs till, så att serien inte tappar sin upprepning när den
/// sparas.
List<String> upprepningsVal(String nuvarande) => [
      ...upprepningsStandardVal,
      if (nuvarande.isNotEmpty && !upprepningsStandardVal.contains(nuvarande))
        nuvarande,
    ];

/// "Torsdag 24 september", med årtal när det inte är innevarande år.
String datumRadText(DateTime datum, DateTime idag) {
  final ar = datum.year != idag.year ? ' ${datum.year}' : '';
  return '${_versal(_veckodagar[datum.weekday])} ${datum.day} '
      '${_manader[datum.month]}$ar';
}

/// Raden för upprepningens slut: "Slutdatum: tills vidare" eller
/// "Slutar torsdag 24 september".
String upprepningSlutText(DateTime? slut, DateTime idag) {
  if (slut == null) return 'Slutdatum: tills vidare';
  final ar = slut.year != idag.year ? ' ${slut.year}' : '';
  return 'Slutar ${_veckodagar[slut.weekday]} ${slut.day} '
      '${_manader[slut.month]}$ar';
}

/// Underraden under "Fler val" när inget är ifyllt.
const flerValTomText = 'Upprepning, packlista, förberedelse, symbol och mall';

/// Det som är ifyllt under Fler val, i klartext och ordning.
List<String> flerValSammanfattning({
  required String upprepning,
  required DateTime datum,
  required int antalPackrader,
  required bool forberedelseAktiv,
  required String forberedelseText,
  required String piktogram,
  required bool sparaSomMall,
}) =>
    [
      if (upprepning != 'none' && upprepning.isNotEmpty)
        upprepningsEtikett(upprepning, datum),
      if (antalPackrader > 0) 'Packlista ($antalPackrader)',
      if (forberedelseAktiv && forberedelseText.trim().isNotEmpty)
        'Förbered dagen innan',
      if (piktogram.isNotEmpty && piktogram != '📅') 'Symbol $piktogram',
      if (sparaSomMall) 'Sparas som mall',
    ];

/// Underraden under "Fler val".
String flerValUnderrad(List<String> sammanfattning) =>
    sammanfattning.isEmpty ? flerValTomText : sammanfattning.join(' · ');

// ---------------------------------------------------------------------------
// "Skriv eller säg" (Android `FormularTolkning`).
// ---------------------------------------------------------------------------

/// Vad en tolkad mening ska fylla i formuläret med. Fält som är null ändras
/// inte.
@immutable
class FormularIfyllnad {
  final String titel;
  final DateTime? datum;
  final TimeOfDay? starttid;
  final Set<String>? deltagarUids;

  /// `"weekly"` eller `"biweekly"`; null när meningen inte sa något.
  final String? upprepning;
  final String? piktogram;

  const FormularIfyllnad({
    required this.titel,
    this.datum,
    this.starttid,
    this.deltagarUids,
    this.upprepning,
    this.piktogram,
  });
}

/// Bara dagtid räknas som ett naket klockslag (beslut 2026-09-23).
const _timmarMin = 6;
const _timmarMax = 22;

final _nakenTimme = RegExp(r'^(.*\S)\s+(\d{1,2})$');

/// "14:30" → 14:30, annars null.
TimeOfDay? tolkaKlockslag(String text) {
  final delar = text.trim().split(':');
  if (delar.length < 2) return null;
  final timme = int.tryParse(delar[0]);
  final minut = int.tryParse(delar[1]);
  if (timme == null || minut == null) return null;
  if (timme < 0 || timme > 23 || minut < 0 || minut > 59) return null;
  return TimeOfDay(hour: timme, minute: minut);
}

/// Ett ensamt tal 6–22 sist i titeln, tolkat som timme: "Tandläkare 15" →
/// 15:00. Bara när tolken inte hittade någon tid och meningen hade ett
/// uttryckligt datum. Returnerar (titel utan talet, klockslaget) eller null.
(String, TimeOfDay)? nakenTimmeSist(QuickAddDraft utkast) {
  if (utkast.time.trim().isNotEmpty || !utkast.hasExplicitDate) return null;
  final traff = _nakenTimme.firstMatch(utkast.title.trim());
  if (traff == null) return null;
  final timme = int.tryParse(traff.group(2)!);
  if (timme == null || timme < _timmarMin || timme > _timmarMax) return null;
  return (traff.group(1)!, TimeOfDay(hour: timme, minute: 0));
}

/// Översätter ett tolkat utkast till formulärfält. Bara för aktiviteter.
FormularIfyllnad formularIfyllnad(QuickAddDraft utkast) {
  if (utkast.intent != QuickAddIntent.activity) {
    throw ArgumentError(
        'Bara aktiviteter fyller i aktivitetsformuläret, fick ${utkast.intent}');
  }
  final naken = nakenTimmeSist(utkast);
  final uids = {for (final p in utkast.persons) p.uid};
  return FormularIfyllnad(
    titel: naken?.$1 ?? utkast.title,
    // Tolken sätter alltid ett datum (idag när inget sades); det får inte
    // ersätta formulärets.
    datum: utkast.hasExplicitDate ? _dag(utkast.date) : null,
    starttid: tolkaKlockslag(utkast.time) ?? naken?.$2,
    deltagarUids: uids.isEmpty ? null : uids,
    upprepning:
        utkast.recurrenceType.trim().isEmpty ? null : utkast.recurrenceType,
    // Tolkens standardsymbol är 📅; bara ett eget val förs över.
    piktogram: utkast.piktogram.trim().isNotEmpty && utkast.piktogram != '📅'
        ? utkast.piktogram
        : null,
  );
}

/// Vad "Skriv eller säg" gav.
sealed class Tolkning {
  const Tolkning();
}

/// En aktivitet: fyll i formuläret, spara inte.
class TolkadAktivitet extends Tolkning {
  final FormularIfyllnad ifyllnad;
  const TolkadAktivitet(this.ifyllnad);
}

/// En syssla, middag eller inköp. Sparas i sitt eget flöde.
class TolkadAnnanTyp extends Tolkning {
  final QuickAddDraft utkast;
  const TolkadAnnanTyp(this.utkast);
}

/// Tolken förstod inte meningen. Texten läggs som titel, så inget skrivet
/// går förlorat.
class OtolkadText extends Tolkning {
  final String text;
  const OtolkadText(this.text);
}

/// Tolkar en skriven eller sagd mening för aktivitetsformuläret.
Tolkning tolkaMening(
  String text, {
  required List<UserModel> members,
  DateTime? now,
}) {
  final utkast = parseQuickAdd(text, members: members, now: now);
  if (utkast == null) return OtolkadText(text.trim());
  if (utkast.intent != QuickAddIntent.activity) return TolkadAnnanTyp(utkast);
  return TolkadAktivitet(formularIfyllnad(utkast));
}

// ---------------------------------------------------------------------------
// Formulärets tillstånd.
// ---------------------------------------------------------------------------

/// Formulärets tillstånd. Varje ändring ger ett nytt tillstånd; widgeten
/// håller det i sin `State`.
@immutable
class AktivitetFormularTillstand {
  final bool redigerar;
  final String titel;
  final String piktogram;
  final DateTime datum;
  final bool datumLast;
  final Tidslage tidslage;

  /// Vald starttid. Ligger kvar när man byter läge, men sparas bara i
  /// klockslagsläget.
  final TimeOfDay? starttid;
  final TimeOfDay? sluttid;
  final String upprepning;
  final DateTime? upprepningSlut;
  final List<String> deltagarUids;
  final List<PacklistRad> packlista;
  final bool forberedelseAktiv;
  final String forberedelseText;
  final bool sparaSomMall;

  /// Upprepningstypen som lästes in, så att den finns bland valen.
  final String inlastUpprepning;

  const AktivitetFormularTillstand({
    required this.redigerar,
    required this.titel,
    required this.piktogram,
    required this.datum,
    required this.datumLast,
    required this.tidslage,
    required this.starttid,
    required this.sluttid,
    required this.upprepning,
    required this.upprepningSlut,
    required this.deltagarUids,
    required this.packlista,
    required this.forberedelseAktiv,
    required this.forberedelseText,
    required this.sparaSomMall,
    required this.inlastUpprepning,
  });

  /// Ny aktivitet från Hem eller Kalendern, med anroparens förifyllnad.
  factory AktivitetFormularTillstand.ny({
    required FormularOppning oppning,
    required DateTime idag,
    String titel = '',
    TimeOfDay? starttid,
    List<String> deltagarUids = const [],
  }) =>
      AktivitetFormularTillstand(
        redigerar: false,
        titel: titel,
        piktogram: '',
        datum: forvalDatum(oppning, idag),
        datumLast: datumArLast(oppning),
        tidslage: Tidslage.klockslag,
        starttid: starttid,
        sluttid: null,
        upprepning: 'none',
        upprepningSlut: null,
        deltagarUids: List.unmodifiable(deltagarUids),
        packlista: const [],
        forberedelseAktiv: false,
        forberedelseText: '',
        sparaSomMall: false,
        inlastUpprepning: 'none',
      );

  /// Redigering av ett befintligt dokument.
  ///
  /// [members] används bara när dokumentet saknar `personUids` (äldre
  /// aktiviteter med bara namn i `persons`).
  factory AktivitetFormularTillstand.redigera({
    required FormularRedigering oppning,
    required DateTime idag,
    List<UserModel> members = const [],
  }) {
    final raw = oppning.raw;
    final rec = raw['recurrence'];
    final typ = rec is Map && rec['type'] is String && (rec['type'] as String).isNotEmpty
        ? rec['type'] as String
        : 'none';
    final uids = [
      for (final u in (raw['personUids'] as List?) ?? const [])
        if (u != null && u.toString().isNotEmpty) u.toString(),
    ];
    final persons = [
      for (final p in (raw['persons'] as List?) ?? const [])
        if (p != null) p.toString(),
    ];
    return AktivitetFormularTillstand(
      redigerar: true,
      titel: (raw['title'] as String?) ?? '',
      piktogram: (raw['piktogram'] as String?) ?? '📅',
      datum: forvalDatum(oppning, idag),
      datumLast: datumArLast(oppning),
      tidslage: Tidslage.las(raw),
      starttid: tolkaKlockslag((raw['time'] as String?) ?? ''),
      sluttid: tolkaKlockslag((raw['endTime'] as String?) ?? ''),
      upprepning: typ,
      upprepningSlut: rec is Map ? _parseDatum(rec['endDate']) : null,
      deltagarUids: List.unmodifiable(
          uids.isNotEmpty ? uids : uidsForNames(members, persons)),
      packlista: List.unmodifiable(lasPacklista(raw)),
      forberedelseAktiv: LessonPrep.isEnabled(raw),
      forberedelseText: LessonPrep.textOf(raw) ?? '',
      sparaSomMall: false,
      inlastUpprepning: typ,
    );
  }

  AktivitetFormularTillstand _med({
    String? titel,
    String? piktogram,
    DateTime? datum,
    Tidslage? tidslage,
    TimeOfDay? starttid,
    TimeOfDay? Function()? sluttid,
    String? upprepning,
    DateTime? Function()? upprepningSlut,
    List<String>? deltagarUids,
    List<PacklistRad>? packlista,
    bool? forberedelseAktiv,
    String? forberedelseText,
    bool? sparaSomMall,
  }) =>
      AktivitetFormularTillstand(
        redigerar: redigerar,
        titel: titel ?? this.titel,
        piktogram: piktogram ?? this.piktogram,
        datum: datum ?? this.datum,
        datumLast: datumLast,
        tidslage: tidslage ?? this.tidslage,
        starttid: starttid ?? this.starttid,
        sluttid: sluttid != null ? sluttid() : this.sluttid,
        upprepning: upprepning ?? this.upprepning,
        upprepningSlut:
            upprepningSlut != null ? upprepningSlut() : this.upprepningSlut,
        deltagarUids: deltagarUids != null
            ? List.unmodifiable(deltagarUids)
            : this.deltagarUids,
        packlista:
            packlista != null ? List.unmodifiable(packlista) : this.packlista,
        forberedelseAktiv: forberedelseAktiv ?? this.forberedelseAktiv,
        forberedelseText: forberedelseText ?? this.forberedelseText,
        sparaSomMall: sparaSomMall ?? this.sparaSomMall,
        inlastUpprepning: inlastUpprepning,
      );

  AktivitetFormularTillstand medTitel(String t) => _med(titel: t);

  /// Ignoreras när datumet är låst.
  AktivitetFormularTillstand medDatum(DateTime d) =>
      datumLast ? this : _med(datum: _dag(d));

  AktivitetFormularTillstand medTidslage(Tidslage l) => _med(tidslage: l);

  /// Ett valt klockslag tar bort läget utan tid.
  AktivitetFormularTillstand medStarttid(TimeOfDay t) =>
      _med(starttid: t, tidslage: Tidslage.klockslag);

  AktivitetFormularTillstand medSluttid(TimeOfDay? t) => _med(sluttid: () => t);

  AktivitetFormularTillstand medUpprepning(String typ) =>
      _med(upprepning: typ.isEmpty ? 'none' : typ);

  AktivitetFormularTillstand medUpprepningSlut(DateTime? d) =>
      _med(upprepningSlut: () => d == null ? null : _dag(d));

  AktivitetFormularTillstand vaxlaDeltagare(String uid) => _med(
        deltagarUids: deltagarUids.contains(uid)
            ? [for (final u in deltagarUids) if (u != uid) u]
            : [...deltagarUids, uid],
      );

  /// Tom text ignoreras.
  AktivitetFormularTillstand laggTillPackrad(String text) {
    final t = text.trim();
    if (t.isEmpty) return this;
    return _med(packlista: [...packlista, PacklistRad(t)]);
  }

  /// Tar bort raden på [index] (inte första raden med samma text).
  AktivitetFormularTillstand taBortPackrad(int index) {
    if (index < 0 || index >= packlista.length) return this;
    return _med(packlista: [...packlista]..removeAt(index));
  }

  /// Byter text på raden på [index]; raden behåller sin koppling.
  AktivitetFormularTillstand bytTextPackrad(int index, String text) {
    final t = text.trim();
    if (index < 0 || index >= packlista.length || t.isEmpty) return this;
    return _med(packlista: [...packlista]..[index] = packlista[index].medText(t));
  }

  AktivitetFormularTillstand medForberedelse({bool? aktiv, String? text}) =>
      _med(forberedelseAktiv: aktiv, forberedelseText: text);

  /// Val av symbol sätter titeln till symbolens etikett om titeln är tom.
  AktivitetFormularTillstand medPiktogram(String emoji, String etikett) =>
      _med(piktogram: emoji, titel: titel.trim().isEmpty ? etikett : titel);

  AktivitetFormularTillstand medSparaSomMall(bool pa) => _med(sparaSomMall: pa);

  /// En mall sätter symbol, titel och packlista (bara strängrader).
  AktivitetFormularTillstand medMall(Map<String, dynamic> mall) => _med(
        piktogram: (mall['piktogram'] as String?) ?? '📅',
        titel: (mall['title'] as String?) ?? '',
        packlista: [
          for (final r in (mall['checklist'] as List?) ?? const [])
            if (r is String && r.trim().isNotEmpty) PacklistRad(r.trim()),
        ],
      );

  /// Fyller i det en tolkad mening nämnde. Sparar aldrig.
  AktivitetFormularTillstand tillampa(FormularIfyllnad f) => _med(
        titel: f.titel,
        datum: datumLast || f.datum == null ? null : _dag(f.datum!),
        starttid: f.starttid,
        // Nämner meningen ett klockslag gäller det, även från heldag.
        tidslage: f.starttid != null ? Tidslage.klockslag : null,
        deltagarUids: f.deltagarUids?.toList(),
        upprepning: f.upprepning,
        piktogram: f.piktogram,
      );

  /// Tillämpar "Skriv eller säg". En [TolkadAnnanTyp] ändrar inget här; den
  /// sparas i sitt eget flöde.
  AktivitetFormularTillstand tillampaTolkning(Tolkning t) => switch (t) {
        TolkadAktivitet(:final ifyllnad) => tillampa(ifyllnad),
        OtolkadText(:final text) => text.isEmpty ? this : medTitel(text),
        TolkadAnnanTyp() => this,
      };

  /// Valen för upprepning, inklusive en inläst typ formuläret inte erbjuder.
  List<String> get upprepningsAlternativ => upprepningsVal(inlastUpprepning);

  List<String> get sammanfattning => flerValSammanfattning(
        upprepning: upprepning,
        datum: datum,
        antalPackrader: packlista.length,
        forberedelseAktiv: forberedelseAktiv,
        forberedelseText: forberedelseText,
        piktogram: piktogram,
        sparaSomMall: sparaSomMall,
      );

  /// Fler val är öppet från start vid redigering när något är ifyllt där.
  bool get flerValOppetFranStart => redigerar && sammanfattning.isNotEmpty;

  String? validera() => valideraAktivitet(
        titel: titel,
        datum: datum,
        tidslage: tidslage,
        starttid: starttid,
      );

  /// Utkastet till [byggAktivitetPayload]. Deltagarna i samma ordning som
  /// [members].
  AktivitetUtkast tillUtkast(List<UserModel> members) => AktivitetUtkast(
        titel: titel,
        piktogram: piktogram,
        datum: datum,
        tidslage: tidslage,
        starttid: starttid,
        sluttid: sluttid,
        upprepning: upprepning,
        upprepningSlut: upprepningSlut,
        deltagare: [
          for (final m in members)
            if (deltagarUids.contains(m.uid)) m,
        ],
        packlista: packlista,
        forberedelseAktiv: forberedelseAktiv,
        forberedelseText: forberedelseText,
      );
}

// ---------------------------------------------------------------------------
// Bekräftelsen efter sparning (Android `SparBekraftelse`).
// ---------------------------------------------------------------------------

/// "Sparat i kalendern · torsdag 24 sep", eller
/// "Sparat på telefonen, skickas när nätet finns · torsdag 24 sep".
String sparBekraftelseText(
  DateTime datum, {
  required bool lokalt,
  required DateTime idag,
}) {
  final borjan = lokalt
      ? 'Sparat på telefonen, skickas när nätet finns'
      : 'Sparat i kalendern';
  return '$borjan · ${kortDatum(datum, idag)}';
}

/// "torsdag 24 sep", med årtal när det inte är innevarande år.
String kortDatum(DateTime datum, DateTime idag) {
  final ar = datum.year != idag.year ? ' ${datum.year}' : '';
  return '${_veckodagar[datum.weekday]} ${datum.day} '
      '${_manader[datum.month].substring(0, 3)}$ar';
}
