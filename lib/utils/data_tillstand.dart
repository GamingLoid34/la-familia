import 'dart:async';

import 'package:flutter/foundation.dart';

/// Tillståndet för **en** datakälla (UX 02). Port av Androids `DataTillstand.kt`.
///
/// Min dag läser flera oberoende strömmar. Tidigare sväljdes läsfel tyst, så ett
/// behörighets- eller indexfel visade sig som en tom dag — användaren såg "Inget låg på
/// schemat denna dag" och trodde att dagen var fri.
///
/// Tillståndet hålls per källa och inte per skärm, eftersom aktiviteter och sysslor kommer
/// från olika collections med olika regler. Att den ena fallerar säger ingenting om den
/// andra.
///
/// **Tre saker som inte får blandas ihop:**
///
/// | Begrepp | Betydelse | Hur appen vet |
/// | --- | --- | --- |
/// | Cacheursprung | Datan kom från Firestores lokala cache | `metadata.isFromCache` |
/// | Läsfel | Strömmen fallerade | `onError` i lyssnaren |
/// | Ålder | Hur gammal datan är | **Vet appen inte** |
///
/// De är oberoende. [DataInaktuell] utlöses därför av ett **läsfel**, aldrig av tidens gång.
sealed class DataTillstand<T> {
  const DataTillstand();

  /// Första hämtningen pågår. Inget att visa ännu.
  const factory DataTillstand.laddar() = DataLaddar<T>;

  /// Data finns och senaste uppdateringen lyckades.
  const factory DataTillstand.data(T varde) = DataFinns<T>;

  /// Senast kända data visas, men uppdateringen har misslyckats.
  const factory DataTillstand.inaktuell(T varde, String orsak) =
      DataInaktuell<T>;

  /// Ingen data att visa.
  const factory DataTillstand.fel(String orsak) = DataFel<T>;

  /// Det som ska ritas, eller null när ingenting finns.
  T? get visatVarde => switch (this) {
        DataFinns<T>(:final varde) => varde,
        DataInaktuell<T>(:final varde) => varde,
        DataLaddar<T>() || DataFel<T>() => null,
      };

  /// Har källan misslyckats, oavsett om något gammalt finns kvar att visa?
  bool get harFel => this is DataFel<T> || this is DataInaktuell<T>;

  /// Nästa tillstånd när en ström fallerar.
  ///
  /// Finns tidigare data blir det [DataInaktuell] — innehållet får ligga kvar, men felet
  /// ska synas. Finns ingen blir det [DataFel], vilket är skillnaden mot en tom dag.
  static DataTillstand<T> vidFel<T>(DataTillstand<T> nuvarande, String orsak) {
    final tidigare = nuvarande.visatVarde;
    return tidigare != null
        ? DataInaktuell<T>(tidigare, orsak)
        : DataFel<T>(orsak);
  }
}

/// Första hämtningen pågår.
final class DataLaddar<T> extends DataTillstand<T> {
  const DataLaddar();

  // Typparametern spelar ingen roll för likhet: "laddar" är "laddar".
  @override
  bool operator ==(Object other) => other is DataLaddar;

  @override
  int get hashCode => (DataLaddar).hashCode;

  @override
  String toString() => 'DataLaddar';
}

/// Data finns och senaste uppdateringen lyckades.
final class DataFinns<T> extends DataTillstand<T> {
  final T varde;
  const DataFinns(this.varde);

  @override
  bool operator ==(Object other) => other is DataFinns && other.varde == varde;

  @override
  int get hashCode => Object.hash(DataFinns, varde);

  @override
  String toString() => 'DataFinns($varde)';
}

/// Senast kända data visas, men uppdateringen har misslyckats.
///
/// [varde] är det sista som lyckades hämtas, [orsak] varför uppdateringen misslyckades.
final class DataInaktuell<T> extends DataTillstand<T> {
  final T varde;
  final String orsak;
  const DataInaktuell(this.varde, this.orsak);

  @override
  bool operator ==(Object other) =>
      other is DataInaktuell && other.varde == varde && other.orsak == orsak;

  @override
  int get hashCode => Object.hash(DataInaktuell, varde, orsak);

  @override
  String toString() => 'DataInaktuell($varde, $orsak)';
}

/// Ingen data att visa, och läsningen misslyckades.
final class DataFel<T> extends DataTillstand<T> {
  final String orsak;
  const DataFel(this.orsak);

  @override
  bool operator ==(Object other) => other is DataFel && other.orsak == orsak;

  @override
  int get hashCode => Object.hash(DataFel, orsak);

  @override
  String toString() => 'DataFel($orsak)';
}

/// En datakälla med den nyckel dess innehåll gäller för.
///
/// Vid byte av dag, användare eller familj får tidigare information **inte** ligga kvar som
/// om den hörde till den nya vyn. En felaktigt kvarliggande dag är värre än ingen dag alls,
/// eftersom den ser korrekt ut. Därför bär varje värde sin nyckel, och [forNyckel] kasserar
/// det som inte stämmer i stället för att visa det märkt.
class NycklatTillstand<K, T> {
  final K? nyckel;
  final DataTillstand<T> tillstand;

  const NycklatTillstand(this.nyckel, this.tillstand);

  factory NycklatTillstand.laddar(K? nyckel) =>
      NycklatTillstand<K, T>(nyckel, DataLaddar<T>());

  /// Tillståndet **om** det gäller [aktuellNyckel], annars [DataLaddar].
  ///
  /// Att svara "laddar" och inte "fel" är avsiktligt: att nyckeln inte stämmer betyder att
  /// en ny prenumeration är på väg, inte att något gått sönder.
  DataTillstand<T> forNyckel(K? aktuellNyckel) =>
      nyckel == aktuellNyckel ? tillstand : DataLaddar<T>();

  @override
  bool operator ==(Object other) =>
      other is NycklatTillstand &&
      other.nyckel == nyckel &&
      other.tillstand == tillstand;

  @override
  int get hashCode => Object.hash(nyckel, tillstand);
}

/// Sammanställer Min dags datakällor till ett begripligt skärmtillstånd (UX 02).
/// Port av Androids `MinDagTillforlitlighet.kt`.
///
/// Det svåra är att skilja fyra lägen som tidigare såg likadana ut:
///
/// | Läge | Vad användaren ska förstå |
/// | --- | --- |
/// | Laddar | Vänta, data är på väg |
/// | Tom dag | Dagen är faktiskt fri |
/// | Delvis | Det här stämmer, men något saknas — och du får veta vad |
/// | Allt fallerade | Ingenting kunde hämtas |
abstract final class MinDagTillforlitlighet {
  /// Raden medan dagen hämtas.
  static const String laddarText = 'Hämtar dagen…';

  /// Knappen på felraden.
  static const String forsokIgenText = 'Försök igen';

  /// Läggs till förklaringen när ingenting gick att hämta.
  static const String kontrolleraAnslutningen = 'Kontrollera anslutningen.';

  /// Skärmens samlade läge.
  ///
  /// [tillstand] är tillståndet per källa. [harInnehall] anger om det som faktiskt gick att
  /// hämta ger något att visa. Den skickas in av anroparen eftersom "innehåll" beror på mer
  /// än källorna — en dag utan poster men med syntetiska måltidsblock är inte tom.
  static MinDagLage bedom(
    Map<MinDagKalla, DataTillstand<Object?>> tillstand, {
    required bool harInnehall,
  }) {
    const alla = MinDagKalla.values;
    final trasiga =
        alla.where((k) => tillstand[k]?.harFel == true).toList();
    final laddar = alla.where((k) => tillstand[k] is DataLaddar).toList();

    // Ingen har svarat än.
    if (trasiga.isEmpty && laddar.length == alla.length) {
      return const LageLaddar();
    }

    if (trasiga.isEmpty) {
      // Fortfarande något på väg, men inte allt: visa det som finns hellre än en
      // spinner över hela skärmen.
      if (harInnehall) return const LageKlart();
      return laddar.isNotEmpty ? const LageLaddar() : const LageTomDag();
    }

    // Något fallerade. Skillnaden mellan Delvis och AlltFallerade är om det finns
    // NÅGOT att visa — annars är "delvis tillgänglig" ett tomt löfte.
    final allaTrasiga = trasiga.length == alla.length;
    if (allaTrasiga && !harInnehall) return LageAlltFallerade(trasiga);
    return LageDelvis(trasiga, harNagotInnehall: harInnehall);
  }

  /// Förklaringstext för trasiga källor.
  ///
  /// Säger **vad** som saknas, inte att "ett fel uppstod". Svensk uppräkning med "och"
  /// före sista.
  static String forklaring(List<MinDagKalla> trasiga) {
    if (trasiga.isEmpty) return '';
    final namn = trasiga.map((k) => k.etikett).toList();
    final String lista;
    switch (namn.length) {
      case 1:
        lista = namn[0];
      case 2:
        lista = '${namn[0]} och ${namn[1]}';
      default:
        lista =
            '${namn.sublist(0, namn.length - 1).join(', ')} och ${namn.last}';
    }
    return '${lista[0].toUpperCase()}${lista.substring(1)} kunde inte hämtas.';
  }

  /// Texten på tillförlitlighetsraden, eller null när ingen rad ska visas.
  ///
  /// [LageDelvis] ger förklaringen, [LageAlltFallerade] förklaringen följd av
  /// "Kontrollera anslutningen." Övriga lägen har ingen felrad.
  static String? felradText(MinDagLage lage) => switch (lage) {
        LageDelvis(:final trasiga) => forklaring(trasiga),
        LageAlltFallerade(:final trasiga) =>
          '${forklaring(trasiga)} $kontrolleraAnslutningen',
        _ => null,
      };
}

/// Källorna Min dag läser, i den ordning de nämns för användaren.
enum MinDagKalla {
  aktiviteter('aktiviteterna'),
  aterkommande('återkommande aktiviteter'),
  sysslor('sysslorna'),
  maltidsval('måltidsvalet'),
  meny('sjukhusmenyn');

  final String etikett;
  const MinDagKalla(this.etikett);
}

/// Min dags samlade läge.
sealed class MinDagLage {
  const MinDagLage();
}

/// Ingen källa har svarat ännu.
final class LageLaddar extends MinDagLage {
  const LageLaddar();
  @override
  bool operator ==(Object other) => other is LageLaddar;
  @override
  int get hashCode => (LageLaddar).hashCode;
}

/// Allt hämtades, dagen är tom.
final class LageTomDag extends MinDagLage {
  const LageTomDag();
  @override
  bool operator ==(Object other) => other is LageTomDag;
  @override
  int get hashCode => (LageTomDag).hashCode;
}

/// Allt hämtades och det finns innehåll.
final class LageKlart extends MinDagLage {
  const LageKlart();
  @override
  bool operator ==(Object other) => other is LageKlart;
  @override
  int get hashCode => (LageKlart).hashCode;
}

/// Något hämtades, något fallerade.
final class LageDelvis extends MinDagLage {
  /// Källorna som inte gick att läsa.
  final List<MinDagKalla> trasiga;

  /// Om det finns innehåll att visa trots felet.
  final bool harNagotInnehall;

  const LageDelvis(this.trasiga, {required this.harNagotInnehall});

  @override
  bool operator ==(Object other) =>
      other is LageDelvis &&
      listEquals(other.trasiga, trasiga) &&
      other.harNagotInnehall == harNagotInnehall;
  @override
  int get hashCode => Object.hash(Object.hashAll(trasiga), harNagotInnehall);
}

/// Ingen källa gick att läsa och inget gammalt finns kvar.
final class LageAlltFallerade extends MinDagLage {
  final List<MinDagKalla> trasiga;
  const LageAlltFallerade(this.trasiga);

  @override
  bool operator ==(Object other) =>
      other is LageAlltFallerade && listEquals(other.trasiga, trasiga);
  @override
  int get hashCode => Object.hashAll(trasiga);
}

/// Slår ihop flera källor till **ett** tillstånd, för en vy som bara behöver veta om
/// helheten går att lita på.
///
/// Reglerna, i tur och ordning:
///
/// - Har någon källa fel och saknar något att visa → [DataFel]. Helheten kan inte byggas.
/// - Har någon källa fel men alla har något att visa → [DataInaktuell] med det sammansatta
///   värdet. Innehållet får ligga kvar, men felet ska synas.
/// - Laddar någon källa fortfarande → [DataLaddar].
/// - Annars → [DataFinns] med det sammansatta värdet.
///
/// Orsakerna från de trasiga källorna sätts ihop med "; " i källornas ordning.
///
/// Min dag, som vill visa det som finns även när en källa fallerat, använder i stället
/// [MinDagTillforlitlighet.bedom] direkt på kartan.
DataTillstand<R> kombinera<K, R>(
  Map<K, DataTillstand<Object?>> kallor,
  R Function(Map<K, Object?> varden) sammansatt,
) {
  final orsaker = <String>[];
  var allaHarVarde = true;
  var nagonLaddar = false;
  for (final t in kallor.values) {
    switch (t) {
      case DataFel(:final orsak):
        orsaker.add(orsak);
        allaHarVarde = false;
      case DataInaktuell(:final orsak):
        orsaker.add(orsak);
      case DataLaddar():
        nagonLaddar = true;
        allaHarVarde = false;
      case DataFinns():
        break;
    }
  }
  if (orsaker.isNotEmpty) {
    final orsak = orsaker.join('; ');
    if (!allaHarVarde) return DataFel<R>(orsak);
    return DataInaktuell<R>(sammansatt(_varden(kallor)), orsak);
  }
  if (nagonLaddar) return DataLaddar<R>();
  return DataFinns<R>(sammansatt(_varden(kallor)));
}

Map<K, Object?> _varden<K>(Map<K, DataTillstand<Object?>> kallor) =>
    {for (final e in kallor.entries) e.key: e.value.visatVarde};

/// Prenumererar på flera strömmar under **en** nyckel (dag, användare, familj) och håller
/// ett [DataTillstand] per källa.
///
/// Det som skiljer den från en vanlig `StreamBuilder` per källa:
///
/// - **Nyckelbyte** ([lyssna] med ny nyckel) avslutar alla prenumerationer och sätter alla
///   källor till [DataLaddar] **innan** de nya startar. Ett sent svar som hör till den gamla
///   nyckeln kasseras — även om det av någon anledning skulle nå hit efter bytet.
/// - **Läsfel** går genom [DataTillstand.vidFel]: med tidigare data blir källan
///   [DataInaktuell], utan blir den [DataFel]. Aldrig en tyst tom lista.
/// - **Återförsök** ([forsokIgen]) startar bara om de källor som har fel.
///
/// Cacheursprung används inte; bara läsfel ger varning.
///
/// ```dart
/// final samlare = KallSamlare<MinDagKalla, String>();
/// samlare.lyssna(dateKey(dag), {
///   MinDagKalla.aktiviteter: () => dayEventsStream(familyId: f, day: dag),
///   MinDagKalla.sysslor: () => choresStream(f),
/// });
/// // I build: ListenableBuilder(listenable: samlare, builder: ...)
/// final lage = MinDagTillforlitlighet.bedom(samlare.aktuellt, harInnehall: ...);
/// ```
class KallSamlare<K, N> extends ChangeNotifier {
  N? _nyckel;
  int _generation = 0;
  final Map<K, Stream<Object?> Function()> _fabriker = {};
  final Map<K, NycklatTillstand<N, Object?>> _tillstand = {};
  final Map<K, StreamSubscription<Object?>> _prenumerationer = {};
  final Map<K, int> _kallGeneration = {};
  bool _stangd = false;

  /// Nyckeln som visas just nu.
  N? get nyckel => _nyckel;

  /// Tillståndet per källa för den aktuella nyckeln. Källor som hör till en annan nyckel
  /// rapporteras som [DataLaddar].
  Map<K, DataTillstand<Object?>> get aktuellt => {
        for (final k in _fabriker.keys)
          k: (_tillstand[k] ?? NycklatTillstand<N, Object?>.laddar(null))
              .forNyckel(_nyckel),
      };

  /// Tillståndet för en enskild källa.
  DataTillstand<Object?> tillstandFor(K kalla) =>
      aktuellt[kalla] ?? const DataLaddar<Object?>();

  /// Det som ska ritas för [kalla], typat, eller null när ingenting finns.
  T? visat<T>(K kalla) {
    final v = tillstandFor(kalla).visatVarde;
    return v is T ? v : null;
  }

  /// Har någon källa fel just nu?
  bool get harFel => aktuellt.values.any((t) => t.harFel);

  /// Byter till [nyckel] och prenumererar på [strommar].
  ///
  /// Med samma nyckel och samma källor som redan lyssnas på görs ingenting, så anropet kan
  /// ligga i `didUpdateWidget` eller `build` utan att starta om strömmarna.
  void lyssna(N nyckel, Map<K, Stream<Object?> Function()> strommar) {
    if (_stangd) return;
    if (nyckel == _nyckel &&
        _prenumerationer.isNotEmpty &&
        _sammaKallor(strommar.keys)) {
      return;
    }
    _avslutaAlla();
    _nyckel = nyckel;
    _fabriker
      ..clear()
      ..addAll(strommar);
    _tillstand.clear();
    for (final k in _fabriker.keys) {
      _tillstand[k] = NycklatTillstand<N, Object?>.laddar(nyckel);
    }
    notifyListeners();
    for (final k in _fabriker.keys) {
      _starta(k);
    }
  }

  /// Startar om de källor som har fel. Övriga rörs inte.
  ///
  /// Returnerar true om något startades om.
  bool forsokIgen() {
    if (_stangd) return false;
    final trasiga = [
      for (final e in aktuellt.entries)
        if (e.value.harFel) e.key,
    ];
    if (trasiga.isEmpty) return false;
    for (final k in trasiga) {
      _prenumerationer.remove(k)?.cancel();
      _tillstand[k] = NycklatTillstand<N, Object?>.laddar(_nyckel);
    }
    notifyListeners();
    for (final k in trasiga) {
      _starta(k);
    }
    return true;
  }

  void _starta(K kalla) {
    final fabrik = _fabriker[kalla];
    if (fabrik == null) return;
    final nyckel = _nyckel;
    final generation = ++_generation;
    _kallGeneration[kalla] = generation;

    // Ett svar räknas bara om både nyckeln och prenumerationen fortfarande är aktuella.
    bool inaktuellt() =>
        _stangd || _nyckel != nyckel || _kallGeneration[kalla] != generation;

    final Stream<Object?> strom;
    try {
      strom = fabrik();
    } catch (e) {
      _tillstand[kalla] = NycklatTillstand<N, Object?>(
        nyckel,
        DataTillstand.vidFel(_nuvarande(kalla), e.toString()),
      );
      notifyListeners();
      return;
    }
    _prenumerationer[kalla] = strom.listen(
      (varde) {
        if (inaktuellt()) return;
        _tillstand[kalla] =
            NycklatTillstand<N, Object?>(nyckel, DataFinns<Object?>(varde));
        notifyListeners();
      },
      onError: (Object e, StackTrace _) {
        if (inaktuellt()) return;
        _tillstand[kalla] = NycklatTillstand<N, Object?>(
          nyckel,
          DataTillstand.vidFel(_nuvarande(kalla), e.toString()),
        );
        notifyListeners();
      },
    );
  }

  DataTillstand<Object?> _nuvarande(K kalla) =>
      (_tillstand[kalla] ?? NycklatTillstand<N, Object?>.laddar(null))
          .forNyckel(_nyckel);

  bool _sammaKallor(Iterable<K> nya) {
    final a = nya.toSet();
    return a.length == _fabriker.length && a.containsAll(_fabriker.keys);
  }

  void _avslutaAlla() {
    for (final p in _prenumerationer.values) {
      p.cancel();
    }
    _prenumerationer.clear();
    _kallGeneration.clear();
  }

  @override
  void dispose() {
    _stangd = true;
    _avslutaAlla();
    super.dispose();
  }
}
