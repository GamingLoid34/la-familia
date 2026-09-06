import '../services/weather_service.dart';

/// Klädråd baserat på väderprognos för skoldagen (07:00–17:00).
class ClothingAdvice {
  final String windowLabel; // 'Idag 07–17' eller 'Imorgon 07–17'
  final String text; // 1–2 korta meningar

  const ClothingAdvice({
    required this.windowLabel,
    required this.text,
  });
}

/// Bygger ett regelbaserat klädråd för barnens skoldag (07:00–17:00).
ClothingAdvice? buildClothingAdvice(List<HourlyForecast> hourly, DateTime now) {
  final isTomorrow = now.hour >= 15;
  final targetDate = isTomorrow
      ? DateTime(now.year, now.month, now.day + 1)
      : DateTime(now.year, now.month, now.day);
  final windowLabel = isTomorrow ? 'Imorgon 07–17' : 'Idag 07–17';

  final windowPoints = hourly.where((h) {
    return h.time.year == targetDate.year &&
        h.time.month == targetDate.month &&
        h.time.day == targetDate.day &&
        h.time.hour >= 7 &&
        h.time.hour <= 17;
  }).toList();

  final pointsWithTemp = windowPoints.where((h) => h.temp != null).toList();
  if (pointsWithTemp.length < 2) return null;

  var minT = pointsWithTemp.first.temp!;
  var maxT = pointsWithTemp.first.temp!;
  for (final p in pointsWithTemp) {
    if (p.temp! < minT) minT = p.temp!;
    if (p.temp! > maxT) maxT = p.temp!;
  }

  String baseAdvice;
  if (minT <= -10) {
    baseAdvice = 'Riktigt kallt — overall/vinterjacka, mössa och vantar';
  } else if (minT <= 0) {
    baseAdvice = 'Minusgrader — vinterjacka, mössa och vantar';
  } else if (minT <= 8) {
    baseAdvice = 'Kyligt — varm jacka';
  } else if (minT <= 15) {
    baseAdvice = 'Svalt — jacka eller tjock tröja';
  } else {
    baseAdvice = 'Milt — tunna kläder räcker';
  }

  final additions = <String>[];

  var precipSum = 0.0;
  for (final p in windowPoints) {
    if (p.precipMm != null) {
      precipSum += p.precipMm!;
    }
  }

  if (precipSum >= 0.3) {
    final hasSnowSymbol = windowPoints.any((h) =>
        h.symbol != null &&
        ((h.symbol! >= 12 && h.symbol! <= 17) ||
            (h.symbol! >= 22 && h.symbol! <= 27)));
    if (hasSnowSymbol || minT <= 1) {
      additions.add('det kan bli snö/slask');
    } else {
      additions.add('packa regnkläder och stövlar');
    }
  }

  var maxWind = 0.0;
  var maxGust = 0.0;
  for (final p in windowPoints) {
    if (p.windMs != null && p.windMs! > maxWind) maxWind = p.windMs!;
    if (p.gustMs != null && p.gustMs! > maxGust) maxGust = p.gustMs!;
  }

  if (maxWind >= 8 || maxGust >= 14) {
    additions.add('blåsigt, vindtät jacka');
  }

  if (maxT - minT >= 8) {
    additions.add('lager på lager (stor skillnad över dagen)');
  }

  final minTRound = minT.round();
  final maxTRound = maxT.round();
  final body = additions.isEmpty
      ? baseAdvice
      : '$baseAdvice — ${additions.join(' — ')}';
  final text = '$windowLabel: $minTRound° till $maxTRound°. $body.';

  return ClothingAdvice(
    windowLabel: windowLabel,
    text: text,
  );
}
