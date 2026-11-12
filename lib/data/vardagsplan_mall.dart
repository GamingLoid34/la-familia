import '../models/user_model.dart';

/// Vardagsplanen — ett komplett, redigerbart förslag på hur vardagen ska
/// rulla: morgon-/kvällsrutiner per person, återkommande veckouppdrag och
/// en rullande matvecka.
///
/// Filosofi (samma som rutinerna): planen är trygghet, inte krav.
/// Förslaget genereras utifrån familjens medlemmar och deras profil
/// (Barn / Tonåring / Vuxen), justeras fritt i [VardagsplanPage] och
/// skrivs sedan in i appens VANLIGA collections:
///
///   * `routines`        — morgon/kväll per person (dagsåterställning finns)
///   * `planner_events`  — veckouppdrag som återkommande händelser
///   * `meals`           — matveckan, 14 dagar framåt
///
/// Allt taggas med `source: 'vardagsplan'` (+ `vardagsplanKey` på events)
/// så att planen kan aktiveras om och om igen utan dubbletter.

enum PlanProfil { barn, tonaring, vuxen }

String planProfilLabel(PlanProfil p) {
  switch (p) {
    case PlanProfil.barn:
      return 'Barn';
    case PlanProfil.tonaring:
      return 'Tonåring';
    case PlanProfil.vuxen:
      return 'Vuxen';
  }
}

/// Bästa gissning utifrån roll/vyläge — går alltid att ändra på sidan.
PlanProfil gissaProfil(UserModel m) {
  if (m.isParent) return PlanProfil.vuxen;
  if (m.role == 'youth' || m.viewMode == 'youth') return PlanProfil.tonaring;
  return PlanProfil.barn;
}

/// Ett steg i en rutin — mappar rakt mot `routines.steps[]`.
class PlanSteg {
  String piktogram;
  String titel;
  PlanSteg(this.piktogram, this.titel);

  Map<String, dynamic> toRoutineStep() =>
      {'title': titel, 'piktogram': piktogram};
}

/// En morgon- eller kvällsrutin för en person.
class PlanRutin {
  final String ownerUid;
  final String ownerName;
  final String typ; // 'morning' | 'evening'
  final List<PlanSteg> steg;

  PlanRutin({
    required this.ownerUid,
    required this.ownerName,
    required this.typ,
    required this.steg,
  });
}

/// Ett återkommande veckouppdrag — blir en weekly `planner_events`-händelse.
class PlanUppdrag {
  String titel;
  String piktogram;
  int veckodag; // 1 = måndag … 7 = söndag
  String tid; // 'HH:mm'
  List<String> personUids;
  List<String> checklista;

  /// Stabil nyckel för idempotent upsert (`vardagsplanKey` på eventet).
  final String nyckel;

  PlanUppdrag({
    required this.titel,
    required this.piktogram,
    required this.veckodag,
    required this.tid,
    required this.personUids,
    this.checklista = const [],
    String? nyckel,
  }) : nyckel = nyckel ?? _slug(titel, veckodag);

  static String _slug(String titel, int veckodag) {
    final t = titel
        .toLowerCase()
        .replaceAll(RegExp(r'[åä]'), 'a')
        .replaceAll('ö', 'o')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return 'v$veckodag-$t';
  }
}

/// En rad i matveckan — blir `meals`-dokument 14 dagar framåt.
class PlanMaltid {
  final int veckodag; // 1 = måndag … 7 = söndag
  String titel;
  String emoji;
  PlanMaltid(this.veckodag, this.emoji, this.titel);
}

class Vardagsplan {
  final List<PlanRutin> rutiner;
  final List<PlanUppdrag> uppdrag;
  final List<PlanMaltid> matvecka;

  Vardagsplan({
    required this.rutiner,
    required this.uppdrag,
    required this.matvecka,
  });
}

const List<String> veckodagsNamn = [
  '', 'Måndag', 'Tisdag', 'Onsdag', 'Torsdag', 'Fredag', 'Lördag', 'Söndag',
];

/// Piktogram-snabbval för mat (matveckan).
const List<String> matEmojis = [
  '🍝', '🥘', '🍗', '🥞', '🌮', '🍕', '🍲', '🐟', '🍛', '🥗', '🍔', '🍽️',
];

// ─── DE FYRA KÖKSROLLERNA (dagliga, blir rutinsteg) ────────────────────────
//
// Fördelas i ordning över alla barn → tonåringar. Roller som saknar person
// hamnar hos första vuxna som steg i driftschemat.

class _Koksroll {
  final String piktogram;
  final String titel;
  final bool morgon; // annars kvällssteg
  const _Koksroll(this.piktogram, this.titel, {this.morgon = false});
}

const List<_Koksroll> _koksroller = [
  _Koksroll('🍽️', 'Duka bordet'),
  _Koksroll('🧹', 'Duka av & torka bordet'),
  _Koksroll('🧽', 'Tömma diskmaskinen', morgon: true),
  _Koksroll('🧽', 'Fylla & starta diskmaskinen'),
];

/// Städzoner till Städtimmen — cyklas över medlemmarna.
const List<String> _stadzoner = [
  'Hallen — skor, jackor, plocka',
  'Dammsuga vardagsrummet',
  'Badrummet',
  'Köket — golv & ytor',
  'Sovrum & tvättstuga',
  'Fönster & dammtorkning',
];

/// Bygger hela förslaget utifrån medlemmar + valda profiler.
Vardagsplan byggVardagsplan(
  List<UserModel> medlemmar,
  Map<String, PlanProfil> profiler,
) {
  PlanProfil profil(UserModel m) => profiler[m.uid] ?? gissaProfil(m);

  final barn = medlemmar.where((m) => profil(m) == PlanProfil.barn).toList()
    ..sort((a, b) => a.name.compareTo(b.name));
  final tonaringar =
      medlemmar.where((m) => profil(m) == PlanProfil.tonaring).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
  final vuxna = medlemmar.where((m) => profil(m) == PlanProfil.vuxen).toList()
    ..sort((a, b) => a.name.compareTo(b.name));

  // Köksroller: barn först, sedan tonåringar. Blir max 4 st.
  final rollbarare = [...barn, ...tonaringar];
  final rollFor = <String, List<_Koksroll>>{}; // uid → roller
  final oplaceradeRoller = <_Koksroll>[];
  for (var i = 0; i < _koksroller.length; i++) {
    if (rollbarare.isEmpty) {
      oplaceradeRoller.add(_koksroller[i]);
    } else {
      final m = rollbarare[i % rollbarare.length];
      rollFor.putIfAbsent(m.uid, () => []).add(_koksroller[i]);
    }
  }

  // ── Rutiner ──────────────────────────────────────────────────────────────
  final rutiner = <PlanRutin>[];

  for (final m in barn) {
    final roller = rollFor[m.uid] ?? const [];
    final morgonroller = roller.where((r) => r.morgon);
    final kvallsroller = roller.where((r) => !r.morgon);

    rutiner.add(PlanRutin(
      ownerUid: m.uid,
      ownerName: m.name,
      typ: 'morning',
      steg: [
        PlanSteg('😴', 'Vakna'),
        PlanSteg('👕', 'Klä på dig'),
        PlanSteg('🥣', 'Frukost'),
        for (final r in morgonroller) PlanSteg(r.piktogram, r.titel),
        PlanSteg('🪥', 'Borsta tänderna'),
        PlanSteg('🎒', 'Packa väskan'),
        PlanSteg('🧦', 'Skor & jacka'),
      ],
    ));
    rutiner.add(PlanRutin(
      ownerUid: m.uid,
      ownerName: m.name,
      typ: 'evening',
      steg: [
        for (final r in kvallsroller) PlanSteg(r.piktogram, r.titel),
        PlanSteg('📚', 'Läxa eller lugn lek'),
        PlanSteg('🚿', 'Dusch'),
        PlanSteg('👕', 'Pyjamas'),
        PlanSteg('📖', 'Läsa en stund'),
        PlanSteg('🪥', 'Borsta tänderna'),
        PlanSteg('😴', 'Släcka och sova'),
      ],
    ));
  }

  for (final m in tonaringar) {
    final roller = rollFor[m.uid] ?? const [];
    final morgonroller = roller.where((r) => r.morgon);
    final kvallsroller = roller.where((r) => !r.morgon);

    rutiner.add(PlanRutin(
      ownerUid: m.uid,
      ownerName: m.name,
      typ: 'morning',
      steg: [
        PlanSteg('😴', 'Uppe i tid'),
        PlanSteg('🥣', 'Frukost'),
        for (final r in morgonroller) PlanSteg(r.piktogram, r.titel),
        PlanSteg('🪥', 'Borsta tänderna'),
        PlanSteg('📚', 'Kolla dagens agenda'),
      ],
    ));
    rutiner.add(PlanRutin(
      ownerUid: m.uid,
      ownerName: m.name,
      typ: 'evening',
      steg: [
        for (final r in kvallsroller) PlanSteg(r.piktogram, r.titel),
        PlanSteg('🎒', 'Packa väskan för imorgon'),
        PlanSteg('🪥', 'Borsta tänderna'),
        PlanSteg('😴', 'Skärm av — mobilen på laddning'),
      ],
    ));
  }

  for (final m in vuxna) {
    rutiner.add(PlanRutin(
      ownerUid: m.uid,
      ownerName: m.name,
      typ: 'evening',
      steg: [
        for (final r in oplaceradeRoller) PlanSteg(r.piktogram, r.titel),
        PlanSteg('🧽', 'Kolla att diskmaskinen är igång'),
        PlanSteg('🧺', 'Tvättmaskin på vid behov'),
        PlanSteg('📚', 'Kolla morgondagen i agendan'),
        PlanSteg('🥣', 'Ta fram mat ur frysen vid behov'),
        PlanSteg('😴', 'Egen läggtid — sömn är infrastruktur'),
      ],
    ));
  }

  // ── Veckouppdrag ─────────────────────────────────────────────────────────
  final allaUids = medlemmar.map((m) => m.uid).toList();
  final soporPerson = rollbarare.length > 1
      ? rollbarare[1]
      : (rollbarare.isNotEmpty
          ? rollbarare.first
          : (vuxna.isNotEmpty ? vuxna.first : null));

  final uppdrag = <PlanUppdrag>[
    if (soporPerson != null) ...[
      PlanUppdrag(
        titel: 'Sopor & återvinning',
        piktogram: '🗑️',
        veckodag: 2,
        tid: '17:30',
        personUids: [soporPerson.uid],
      ),
      PlanUppdrag(
        titel: 'Sopor & återvinning',
        piktogram: '🗑️',
        veckodag: 5,
        tid: '17:30',
        personUids: [soporPerson.uid],
      ),
    ],
    if (vuxna.isNotEmpty)
      PlanUppdrag(
        titel: 'Tvättmaskin på',
        piktogram: '🧺',
        veckodag: 1,
        tid: '18:00',
        personUids: [vuxna.first.uid],
      ),
    if (tonaringar.isNotEmpty)
      PlanUppdrag(
        titel: 'Tvätta ditt eget',
        piktogram: '🧺',
        veckodag: 4,
        tid: '18:00',
        personUids: tonaringar.map((m) => m.uid).toList(),
      ),
    PlanUppdrag(
      titel: 'Städtimmen — alla samtidigt, musik på!',
      piktogram: '🧹',
      veckodag: 6,
      tid: '10:00',
      personUids: allaUids,
      checklista: [
        'Eget rum — alla bäddar och plockar',
        for (var i = 0; i < medlemmar.length; i++)
          '${_stadzoner[i % _stadzoner.length]} — ${medlemmar[i].name}',
      ],
    ),
    if (vuxna.isNotEmpty)
      PlanUppdrag(
        titel: 'Storhandla (eller e-handla)',
        piktogram: '🛒',
        veckodag: 7,
        tid: '11:00',
        personUids: [vuxna.first.uid],
      ),
    PlanUppdrag(
      titel: 'Familjemöte — 15 minuter',
      piktogram: '🤝',
      veckodag: 7,
      tid: '17:00',
      personUids: allaUids,
      checklista: const [
        'Gå igenom Familjeveckan tillsammans',
        'Besök & skjutsar denna vecka',
        'Vem lagar vad',
        'Skriv "Veckans info" som familjenotis',
      ],
    ),
    if (tonaringar.isNotEmpty)
      PlanUppdrag(
        titel: '${tonaringar.first.name} lagar middag',
        piktogram: '🍳',
        veckodag: 2,
        tid: '17:00',
        personUids: [tonaringar.first.uid],
        nyckel: 'v2-kock',
      ),
    if (tonaringar.length > 1)
      PlanUppdrag(
        titel: '${tonaringar[1].name} lagar middag',
        piktogram: '🍳',
        veckodag: 4,
        tid: '17:00',
        personUids: [tonaringar[1].uid],
        nyckel: 'v4-kock',
      ),
  ];

  // ── Matveckan ────────────────────────────────────────────────────────────
  final matvecka = <PlanMaltid>[
    PlanMaltid(1, '🍝', 'Pasta med köttfärssås (dubbel sats → frysen)'),
    PlanMaltid(2, '🥘', 'Korv stroganoff med ris'),
    PlanMaltid(3, '🍗', 'Kyckling & klyftpotatis i ugnen'),
    PlanMaltid(4, '🥞', 'Pannkakor & soppa'),
    PlanMaltid(5, '🌮', 'Tacos — alla hjälps åt'),
    PlanMaltid(6, '🍕', 'Enkelt: pizza eller rester'),
    PlanMaltid(7, '🥘', 'Storkok till frysen'),
  ];

  return Vardagsplan(rutiner: rutiner, uppdrag: uppdrag, matvecka: matvecka);
}
