import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/services/weather_service.dart';
import 'package:la_familia/utils/clothing_advice.dart';

void main() {
  group('ClothingAdvice', () {
    test('returnerar null vid färre än 2 punkter med temp', () {
      final now = DateTime(2026, 8, 24, 10, 0);
      final hourly = [
        HourlyForecast(
          time: DateTime(2026, 8, 24, 8, 0),
          temp: 15.0,
        ),
      ];
      expect(buildClothingAdvice(hourly, now), isNull);
    });

    test('använder Idag 07-17 före kl 15', () {
      final now = DateTime(2026, 8, 24, 14, 0);
      final hourly = [
        HourlyForecast(
          time: DateTime(2026, 8, 24, 8, 0),
          temp: 12.0,
          windMs: 4.0,
        ),
        HourlyForecast(
          time: DateTime(2026, 8, 24, 12, 0),
          temp: 16.0,
          windMs: 3.0,
        ),
      ];
      final advice = buildClothingAdvice(hourly, now);
      expect(advice, isNotNull);
      expect(advice!.windowLabel, 'Idag 07–17');
      expect(advice.text, contains('Idag 07–17: 12° till 16°. Svalt — jacka eller tjock tröja.'));
    });

    test('använder Imorgon 07-17 från kl 15', () {
      final now = DateTime(2026, 8, 24, 15, 30);
      final hourly = [
        HourlyForecast(
          time: DateTime(2026, 8, 25, 8, 0),
          temp: -2.0,
        ),
        HourlyForecast(
          time: DateTime(2026, 8, 25, 14, 0),
          temp: 2.0,
        ),
      ];
      final advice = buildClothingAdvice(hourly, now);
      expect(advice, isNotNull);
      expect(advice!.windowLabel, 'Imorgon 07–17');
      expect(advice.text, contains('Minusgrader — vinterjacka, mössa och vantar'));
    });

    test('inkluderar regnråd vid nederbörd', () {
      final now = DateTime(2026, 8, 24, 9, 0);
      final hourly = [
        HourlyForecast(
          time: DateTime(2026, 8, 24, 8, 0),
          temp: 10.0,
          precipMm: 0.5,
          symbol: 18,
        ),
        HourlyForecast(
          time: DateTime(2026, 8, 24, 12, 0),
          temp: 12.0,
          precipMm: 1.0,
          symbol: 19,
        ),
      ];
      final advice = buildClothingAdvice(hourly, now);
      expect(advice, isNotNull);
      expect(advice!.text, contains('packa regnkläder och stövlar'));
    });

    test('inkluderar snöråd vid snösymbol eller temp <= 1', () {
      final now = DateTime(2026, 8, 24, 9, 0);
      final hourly = [
        HourlyForecast(
          time: DateTime(2026, 8, 24, 8, 0),
          temp: 1.0,
          precipMm: 0.8,
          symbol: 14,
        ),
        HourlyForecast(
          time: DateTime(2026, 8, 24, 12, 0),
          temp: 2.0,
          precipMm: 0.2,
          symbol: 14,
        ),
      ];
      final advice = buildClothingAdvice(hourly, now);
      expect(advice, isNotNull);
      expect(advice!.text, contains('det kan bli snö/slask'));
    });

    test('inkluderar blåst och lager på lager vid stor differens', () {
      final now = DateTime(2026, 8, 24, 9, 0);
      final hourly = [
        HourlyForecast(
          time: DateTime(2026, 8, 24, 8, 0),
          temp: 5.0,
          windMs: 9.0,
        ),
        HourlyForecast(
          time: DateTime(2026, 8, 24, 14, 0),
          temp: 15.0,
          windMs: 8.0,
        ),
      ];
      final advice = buildClothingAdvice(hourly, now);
      expect(advice, isNotNull);
      expect(advice!.text, contains('blåsigt, vindtät jacka'));
      expect(advice.text, contains('lager på lager (stor skillnad över dagen)'));
    });
  });
}
