import '../utils/data_tillstand.dart';

/// Ren logik för Min dags lägesrad (UX 02), skild från widgeten så att den går att testa.
///
/// Min dag läser inte alla fem källor i [MinDagKalla]: sjukhusmenyn är dold
/// (`kVisaSjukhusmat = false`, som Androids `VISA_SJUKHUSMAT`) och läses inte alls, och
/// måltidsvalet läses bara när sjukhusmaten visas. En källa som inte läses får inte ge
/// en felrad om en funktion användaren inte ser.

/// Skärmens samlade läge för de källor som faktiskt läses.
///
/// [MinDagTillforlitlighet.bedom] räknar "allt fallerade" mot **alla** fem källor. När
/// Min dag bara läser några av dem blir ett totalt avbrott annars bara [LageDelvis], och
/// "Kontrollera anslutningen." skulle aldrig visas. Här räknas mot källorna i [tillstand].
MinDagLage bedomMinDag(
  Map<MinDagKalla, DataTillstand<Object?>> tillstand, {
  required bool harInnehall,
}) {
  final lage = MinDagTillforlitlighet.bedom(
    tillstand,
    harInnehall: harInnehall,
  );
  if (lage is LageDelvis &&
      !harInnehall &&
      tillstand.isNotEmpty &&
      lage.trasiga.length == tillstand.length) {
    return LageAlltFallerade(lage.trasiga);
  }
  return lage;
}

/// Vilken rad som ska ritas ovanför tidsaxeln.
enum MinDagRadTyp {
  /// Liten spinner och "Hämtar dagen…".
  laddar,

  /// Dagen är hämtad och tom: "Inget inplanerat …".
  tomDag,

  /// ⚠️ med förklaring och "Försök igen". Innehållet under ligger kvar.
  fel,

  /// Ingen rad.
  ingen,
}

/// Raden för [lage], med sin text (null för [MinDagRadTyp.tomDag] och [MinDagRadTyp.ingen]).
///
/// Tom dag visas **bara** när allt faktiskt hämtats — aldrig under laddning och aldrig
/// efter ett läsfel. Förr såg de tre lägena likadana ut.
({MinDagRadTyp typ, String? text}) minDagRad(MinDagLage lage) => switch (lage) {
  LageLaddar() => (
    typ: MinDagRadTyp.laddar,
    text: MinDagTillforlitlighet.laddarText,
  ),
  LageTomDag() => (typ: MinDagRadTyp.tomDag, text: null),
  LageKlart() => (typ: MinDagRadTyp.ingen, text: null),
  LageDelvis() || LageAlltFallerade() => (
    typ: MinDagRadTyp.fel,
    text: MinDagTillforlitlighet.felradText(lage),
  ),
};

/// Texterna i tom dag-banderollen, samma som Android (`EmptyDayBanner`).
({String rubrik, String underrubrik, String emoji}) tomDagTexter({
  required DateTime visadDag,
  required DateTime idag,
}) {
  final v = DateTime(visadDag.year, visadDag.month, visadDag.day);
  final t = DateTime(idag.year, idag.month, idag.day);
  if (v == t) {
    return (
      rubrik: 'Inget inplanerat idag 😌',
      underrubrik: 'Tidsaxeln visar ändå var på dagen du befinner dig.',
      emoji: '😌',
    );
  }
  if (v.isAfter(t)) {
    return (
      rubrik: 'Inget inplanerat 🎈',
      underrubrik: 'Det finns inga schemalagda aktiviteter denna dag.',
      emoji: '😌',
    );
  }
  return (
    rubrik: 'Inget låg på schemat denna dag',
    underrubrik: 'Inga aktiviteter sparades för detta datum.',
    emoji: '📅',
  );
}

/// Nyckeln för dagens källor: dag, person och familj.
///
/// Byts någon av dem ska tidigare svar kasseras — en kvarliggande dag, eller en annan
/// persons måltidsval, ser korrekt ut och är därför värre än ingen alls.
String minDagDagNyckel({
  required String datum,
  required String uid,
  required String familyId,
}) => '$datum|$uid|$familyId';
