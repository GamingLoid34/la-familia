import '../services/weather_service.dart';

/// Väljer väder för en **vald** kalenderdag. Port av Androids `CalendarWeatherSelection.kt`.
///
/// Kalenderns dagvy ritade tidigare hela prognosraden — alla dagar sida vid sida — oavsett
/// vilken dag användaren stod på. Bläddrade man till en passerad dag visades ändå kommande
/// dagars väder, vilket lätt läses som att det gällde den dagen.
///
/// Reglerna följer UX 01 B3: visa väder för vald dag **endast** när det finns underlag för
/// just den dagen, och tydliggör gammal cache i stället för att dölja den. Ingenting hittas
/// på: saknas dagen i prognosen blir svaret [VaderSaknarUnderlag].
abstract final class CalendarWeatherSelection {
  /// Hur gammal en hämtning får vara innan användaren bör få veta det.
  ///
  /// Sex timmar är valt så att en prognos hämtad på morgonen inte flaggas mitt på dagen,
  /// medan gårdagens cache alltid gör det.
  static const Duration cacheVarningEfter = Duration(hours: 6);

  /// Kort text på raden när hämtningen är gammal. Ingen tidsstämpel: appen vet när den
  /// hämtade, men inte hur färskt SMHI:s underlag var.
  static const String kanVaraInaktuell = 'Kan vara inaktuell';

  /// [snapshot] är senaste hämtade prognosen (null om ingen hämtats), [harHemposition] om
  /// familjen har en hemposition sparad, [valdDag] dagen kalendern står på och [nu] verklig
  /// tidpunkt för åldersbedömningen.
  static VaderUtfall valjFor({
    required WeatherSnapshot? snapshot,
    required bool harHemposition,
    required DateTime valdDag,
    required DateTime nu,
  }) {
    if (!harHemposition) return const VaderIngenPosition();
    if (snapshot == null) return const VaderLaddar();

    DailyForecast? dagen;
    for (final d in snapshot.daily) {
      if (_sammaDag(d.date, valdDag)) {
        dagen = d;
        break;
      }
    }
    if (dagen == null) return const VaderSaknarUnderlag();

    // En prognos utan min, max och symbol saknar det som raden ska visa. Att rita en tom
    // ruta ger sken av underlag som inte finns.
    if (dagen.maxTemp == null && dagen.minTemp == null && dagen.symbol == null) {
      return const VaderSaknarUnderlag();
    }

    final alder = nu.difference(snapshot.fetchedAt);
    return VaderTraff(dagen, aldrig: alder >= cacheVarningEfter);
  }

  /// Kort text för temperaturen ("18°/9°"), eller null när underlag saknas.
  ///
  /// Returnerar bara det som faktiskt finns: har dagen bara maxvärde visas det ensamt i
  /// stället för att gissa ett minvärde.
  static String? temperaturText(DailyForecast forecast) {
    final max = forecast.maxTemp?.round();
    final min = forecast.minTemp?.round();
    if (max != null && min != null) return '$max°/$min°';
    if (max != null) return '$max°';
    if (min != null) return '$min°';
    return null;
  }

  /// Ett enda uppläst namn för hela väderraden, som på Android:
  /// "Väder idag, 18°/9°, prognosen kan vara inaktuell. Tryck för detaljer."
  ///
  /// [idag] avgör om det står "idag" eller "för vald dag".
  static String upplasning(VaderTraff traff, {required DateTime idag}) {
    final b = StringBuffer('Väder ')
      ..write(_sammaDag(traff.forecast.date, idag) ? 'idag' : 'för vald dag');
    final temp = temperaturText(traff.forecast);
    if (temp != null) b.write(', $temp');
    if (traff.aldrig) b.write(', prognosen kan vara inaktuell');
    b.write('. Tryck för detaljer.');
    return b.toString();
  }

  static bool _sammaDag(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

/// Utfallet av [CalendarWeatherSelection.valjFor]. Bara [VaderTraff] ritar något.
sealed class VaderUtfall {
  const VaderUtfall();
}

/// Ingen hemposition satt — vädret är inte konfigurerat. Rita ingenting.
final class VaderIngenPosition extends VaderUtfall {
  const VaderIngenPosition();
  @override
  bool operator ==(Object other) => other is VaderIngenPosition;
  @override
  int get hashCode => (VaderIngenPosition).hashCode;
}

/// Position finns men ingen prognos är hämtad ännu.
final class VaderLaddar extends VaderUtfall {
  const VaderLaddar();
  @override
  bool operator ==(Object other) => other is VaderLaddar;
  @override
  int get hashCode => (VaderLaddar).hashCode;
}

/// Prognosen saknar den valda dagen.
///
/// Vanligast för passerade datum (SMHI ger bara framåt) och för dagar bortom
/// prognosfönstret. Dagvyn ritar då ingen väderrad alls — hellre inget än fel dags väder.
final class VaderSaknarUnderlag extends VaderUtfall {
  const VaderSaknarUnderlag();
  @override
  bool operator ==(Object other) => other is VaderSaknarUnderlag;
  @override
  int get hashCode => (VaderSaknarUnderlag).hashCode;
}

/// Väder finns för dagen. [aldrig] är true när hämtningen är äldre än
/// [CalendarWeatherSelection.cacheVarningEfter].
final class VaderTraff extends VaderUtfall {
  final DailyForecast forecast;
  final bool aldrig;
  const VaderTraff(this.forecast, {required this.aldrig});
}
