import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/services/weather_service.dart';
import 'package:la_familia/utils/calendar_weather_selection.dart';

/// Väderval för vald kalenderdag (UX 01 B3). Port av Androids
/// `CalendarWeatherSelectionTest`.
///
/// Det viktigaste kravet är negativt: dagvyn får **inte** visa dagens väder som om det
/// gällde ett annat datum.
void main() {
  final idag = DateTime(2026, 9, 20);
  final nu = DateTime.utc(2026, 9, 20, 9);

  DailyForecast dag(DateTime datum,
          {double? max = 18.0, double? min = 9.0, int? symbol = 1}) =>
      DailyForecast(date: datum, minTemp: min, maxTemp: max, symbol: symbol);

  WeatherSnapshot snapshot(List<DailyForecast> dagar, {DateTime? hamtad}) =>
      WeatherSnapshot(
        currentTemp: 15.0,
        currentSymbol: 1,
        daily: dagar,
        hourly: const [],
        fetchedAt: hamtad ?? nu,
      );

  DateTime plus(DateTime d, int dagar) => DateTime(d.year, d.month, d.day + dagar);

  test('utan hemposition ritas ingenting', () {
    final utfall = CalendarWeatherSelection.valjFor(
      snapshot: snapshot([dag(idag)]),
      harHemposition: false,
      valdDag: idag,
      nu: nu,
    );
    expect(utfall, const VaderIngenPosition());
  });

  test('position men ingen hämtad prognos är laddning', () {
    final utfall = CalendarWeatherSelection.valjFor(
      snapshot: null,
      harHemposition: true,
      valdDag: idag,
      nu: nu,
    );
    expect(utfall, const VaderLaddar());
  });

  test('vald dag hämtas ur prognosen, inte första bästa', () {
    final imorgon = plus(idag, 1);
    final utfall = CalendarWeatherSelection.valjFor(
      snapshot: snapshot([dag(idag, max: 18.0), dag(imorgon, max: 22.0)]),
      harHemposition: true,
      valdDag: imorgon,
      nu: nu,
    );
    final traff = utfall as VaderTraff;
    expect(traff.forecast.date, imorgon);
    expect(traff.forecast.maxTemp, closeTo(22.0, 0.001));
  });

  test('passerad dag ger inget underlag i stället för dagens väder', () {
    final igar = plus(idag, -1);
    final utfall = CalendarWeatherSelection.valjFor(
      snapshot: snapshot([dag(idag), dag(plus(idag, 1))]),
      harHemposition: true,
      valdDag: igar,
      nu: nu,
    );
    expect(utfall, const VaderSaknarUnderlag());
  });

  test('dag bortom prognosfönstret ger inget underlag', () {
    final utfall = CalendarWeatherSelection.valjFor(
      snapshot: snapshot([for (var i = 0; i <= 9; i++) dag(plus(idag, i))]),
      harHemposition: true,
      valdDag: plus(idag, 30),
      nu: nu,
    );
    expect(utfall, const VaderSaknarUnderlag());
  });

  test('dag utan värden ger inget underlag', () {
    final utfall = CalendarWeatherSelection.valjFor(
      snapshot: snapshot([dag(idag, max: null, min: null, symbol: null)]),
      harHemposition: true,
      valdDag: idag,
      nu: nu,
    );
    expect(utfall, const VaderSaknarUnderlag());
  });

  test('dag med bara symbol räknas som underlag', () {
    final utfall = CalendarWeatherSelection.valjFor(
      snapshot: snapshot([dag(idag, max: null, min: null, symbol: 3)]),
      harHemposition: true,
      valdDag: idag,
      nu: nu,
    );
    expect(utfall, isA<VaderTraff>());
  });

  test('färsk hämtning flaggas inte som gammal', () {
    final utfall = CalendarWeatherSelection.valjFor(
      snapshot: snapshot([dag(idag)],
          hamtad: nu.subtract(const Duration(minutes: 30))),
      harHemposition: true,
      valdDag: idag,
      nu: nu,
    );
    expect((utfall as VaderTraff).aldrig, isFalse);
  });

  test('gammal cache flaggas', () {
    final utfall = CalendarWeatherSelection.valjFor(
      snapshot:
          snapshot([dag(idag)], hamtad: nu.subtract(const Duration(hours: 20))),
      harHemposition: true,
      valdDag: idag,
      nu: nu,
    );
    expect((utfall as VaderTraff).aldrig, isTrue);
  });

  test('gränsen för gammal cache är inklusive', () {
    final utfall = CalendarWeatherSelection.valjFor(
      snapshot: snapshot([dag(idag)],
          hamtad: nu.subtract(CalendarWeatherSelection.cacheVarningEfter)),
      harHemposition: true,
      valdDag: idag,
      nu: nu,
    );
    expect((utfall as VaderTraff).aldrig, isTrue);
  });

  test('temperaturtexten visar bara det som finns', () {
    expect(CalendarWeatherSelection.temperaturText(dag(idag)), '18°/9°');
    expect(CalendarWeatherSelection.temperaturText(dag(idag, min: null)), '18°');
    expect(CalendarWeatherSelection.temperaturText(dag(idag, max: null)), '9°');
    expect(
        CalendarWeatherSelection.temperaturText(dag(idag, max: null, min: null)),
        isNull);
  });

  test('temperaturen avrundas som Flutter gör', () {
    expect(
        CalendarWeatherSelection.temperaturText(dag(idag, max: 17.6, min: 8.5)),
        '18°/9°');
  });

  // --- Tillägg i Flutter ---

  test('vald dag matchas på datum, inte på klockslag', () {
    // SMHI-dagen kan bära ett klockslag; kalenderns dag är midnatt.
    final utfall = CalendarWeatherSelection.valjFor(
      snapshot: snapshot([dag(DateTime(2026, 9, 21, 12))]),
      harHemposition: true,
      valdDag: DateTime(2026, 9, 21),
      nu: nu,
    );
    expect(utfall, isA<VaderTraff>());
  });

  test('uppläsningen är en enda mening som på Android', () {
    final farsk = VaderTraff(dag(idag), aldrig: false);
    expect(CalendarWeatherSelection.upplasning(farsk, idag: idag),
        'Väder idag, 18°/9°. Tryck för detaljer.');
    final gammal = VaderTraff(dag(plus(idag, 1)), aldrig: true);
    expect(CalendarWeatherSelection.upplasning(gammal, idag: idag),
        'Väder för vald dag, 18°/9°, prognosen kan vara inaktuell. Tryck för detaljer.');
  });
}
