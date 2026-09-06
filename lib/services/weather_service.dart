import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Daglig prognos från SMHI (min/max + vädersymbol).
class DailyForecast {
  final DateTime date;
  final double? minTemp;
  final double? maxTemp;
  final int? symbol;

  const DailyForecast({
    required this.date,
    this.minTemp,
    this.maxTemp,
    this.symbol,
  });

  String get emoji => WeatherService.symbolEmoji(symbol);
}

/// Timprognos från SMHI.
class HourlyForecast {
  final DateTime time; // lokal tid
  final double? temp; // °C
  final int? symbol; // Wsymb2 1–27
  final double? precipMm; // mm under timmen
  final double? windMs; // m/s
  final double? gustMs; // m/s byvind

  const HourlyForecast({
    required this.time,
    this.temp,
    this.symbol,
    this.precipMm,
    this.windMs,
    this.gustMs,
  });

  String get emoji => WeatherService.symbolEmoji(symbol);
}

/// Aktuellt väder + kommande dagar och timmar.
class WeatherSnapshot {
  final double? currentTemp;
  final int? currentSymbol;
  final List<DailyForecast> daily;
  final List<HourlyForecast> hourly;
  final DateTime fetchedAt;

  const WeatherSnapshot({
    this.currentTemp,
    this.currentSymbol,
    required this.daily,
    required this.hourly,
    required this.fetchedAt,
  });

  String get currentEmoji => WeatherService.symbolEmoji(currentSymbol);
}

/// Ortresultat från geokodning (Open-Meteo, ingen API-nyckel).
class GeoPlace {
  final String name;
  final String? admin1;
  final double lat;
  final double lon;

  const GeoPlace({
    required this.name,
    this.admin1,
    required this.lat,
    required this.lon,
  });

  String get displayLabel {
    if (admin1 != null && admin1!.isNotEmpty) {
      return '$name, $admin1';
    }
    return name;
  }
}

/// SMHI punktprognos + cache (minne + SharedPreferences, max 1/h).
class WeatherService {
  WeatherService._();
  static final WeatherService instance = WeatherService._();

  static const _cacheKey = 'weather_cache_v3';
  static const _cacheDuration = Duration(hours: 1);

  WeatherSnapshot? _memory;
  String? _memoryKey;

  /// SMHI Wsymb2 → emoji (förenklad uppsättning).
  static String symbolEmoji(int? sym) {
    switch (sym) {
      case 1:
        return '☀️';
      case 2:
        return '🌤️';
      case 3:
        return '⛅';
      case 4:
        return '🌥️';
      case 5:
        return '☁️';
      case 6:
        return '☁️';
      case 7:
        return '🌫️';
      case 8:
      case 9:
      case 10:
        return '🌦️';
      case 11:
      case 21:
        return '⛈️';
      case 12:
      case 13:
      case 14:
        return '🌨️';
      case 15:
      case 16:
      case 17:
        return '🌨️';
      case 18:
      case 19:
      case 20:
        return '🌧️';
      case 22:
      case 23:
      case 24:
        return '🌨️';
      case 25:
      case 26:
      case 27:
        return '❄️';
      default:
        return '🌡️';
    }
  }

  String _coordKey(double lat, double lon) =>
      '${lat.toStringAsFixed(4)}_${lon.toStringAsFixed(4)}';

  /// Hämtar väder — returnerar null tyst vid fel eller saknad position.
  Future<WeatherSnapshot?> forecastFor(double lat, double lon) async {
    final key = _coordKey(lat, lon);
    final now = DateTime.now();

    if (_memory != null &&
        _memoryKey == key &&
        now.difference(_memory!.fetchedAt) < _cacheDuration) {
      return _memory;
    }

    final cached = await _loadFromPrefs(key);
    if (cached != null && now.difference(cached.fetchedAt) < _cacheDuration) {
      _memory = cached;
      _memoryKey = key;
      return cached;
    }

    try {
      final fresh = await _fetchFromSmhi(lat, lon);
      if (fresh != null) {
        _memory = fresh;
        _memoryKey = key;
        await _saveToPrefs(key, fresh);
      }
      return fresh ?? cached;
    } catch (e, stack) {
      developer.log('SMHI-väder misslyckades', error: e, stackTrace: stack);
      return cached;
    }
  }

  /// Sök svenska orter via Open-Meteo (gratis, ingen nyckel).
  Future<List<GeoPlace>> searchPlaces(String query) async {
    final q = query.trim();
    if (q.length < 2) return const [];

    final uri = Uri.https('geocoding-api.open-meteo.com', '/v1/search', {
      'name': q,
      'count': '8',
      'language': 'sv',
      'country': 'SE',
    });

    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return const [];
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final results = data['results'] as List<dynamic>? ?? const [];
      return results
          .map((raw) {
            final m = raw as Map<String, dynamic>;
            return GeoPlace(
              name: m['name'] as String? ?? '',
              admin1: m['admin1'] as String?,
              lat: (m['latitude'] as num).toDouble(),
              lon: (m['longitude'] as num).toDouble(),
            );
          })
          .where((p) => p.name.isNotEmpty)
          .toList();
    } catch (e, stack) {
      developer.log('Geokodning misslyckades', error: e, stackTrace: stack);
      return const [];
    }
  }

  Future<WeatherSnapshot?> _fetchFromSmhi(double lat, double lon) async {
    final uri = Uri.parse(
      'https://opendata-download-metfcst.smhi.se/api/category/snow1g/'
      'version/1/geotype/point/lon/${lon.toStringAsFixed(4)}/'
      'lat/${lat.toStringAsFixed(4)}/data.json',
    );

    final res = await http.get(uri).timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) return null;

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final series = data['timeSeries'] as List<dynamic>? ?? const [];
    if (series.isEmpty) return null;

    final localNow = DateTime.now();
    final cutoff48h = localNow.add(const Duration(hours: 48));

    double? currentTemp;
    int? currentSymbol;
    var bestDelta = const Duration(days: 999);

    final byDay = <String, _DayBucket>{};
    final hourlyList = <HourlyForecast>[];

    for (final entry in series) {
      final m = entry as Map<String, dynamic>;
      final validRaw = m['time'] as String? ?? m['validTime'] as String?;
      if (validRaw == null) continue;
      final valid = DateTime.parse(validRaw).toLocal();

      final rawData = m['data'] as Map<String, dynamic>?;
      double? t;
      int? sym;
      double? windMs;
      double? gustMs;
      double? precipMm;

      if (rawData != null) {
        t = _readNum(rawData['air_temperature']);
        sym = _readSymbol(rawData['symbol_code']);
        windMs = _readNum(rawData['wind_speed']);
        gustMs = _readNum(rawData['wind_speed_of_gust']);
        precipMm = _readNum(rawData['precipitation_amount_mean']);
      } else {
        // Fallback: äldre PMP3g-format om det skulle returneras.
        final params = m['parameters'] as List<dynamic>? ?? const [];
        for (final p in params) {
          final pm = p as Map<String, dynamic>;
          final name = pm['name'] as String?;
          final values = pm['values'] as List<dynamic>?;
          if (values == null || values.isEmpty) continue;
          final firstVal = values.first;
          if (name == 't') {
            t = _readNum(firstVal);
          } else if (name == 'Wsymb2') {
            sym = _readSymbol(firstVal);
          } else if (name == 'ws') {
            windMs = _readNum(firstVal);
          } else if (name == 'gust') {
            gustMs = _readNum(firstVal);
          } else if (name == 'pmean') {
            precipMm = _readNum(firstVal);
          }
        }
      }

      if (t == null && sym == null) continue;

      final delta = valid.difference(localNow).abs();
      if (delta < bestDelta) {
        bestDelta = delta;
        if (t != null) currentTemp = t;
        if (sym != null) currentSymbol = sym;
      }

      final dayKey =
          '${valid.year}-${valid.month.toString().padLeft(2, '0')}-${valid.day.toString().padLeft(2, '0')}';
      final bucket = byDay.putIfAbsent(dayKey, () => _DayBucket(valid));
      if (t != null) bucket.addTemp(t);
      if (sym != null) bucket.addSymbol(sym, valid);

      if (valid.isBefore(cutoff48h)) {
        hourlyList.add(HourlyForecast(
          time: valid,
          temp: t,
          symbol: sym,
          precipMm: precipMm,
          windMs: windMs,
          gustMs: gustMs,
        ));
      }
    }

    hourlyList.sort((a, b) => a.time.compareTo(b.time));

    if (currentTemp == null && byDay.isNotEmpty) {
      final todayKey =
          '${localNow.year}-${localNow.month.toString().padLeft(2, '0')}-${localNow.day.toString().padLeft(2, '0')}';
      final today = byDay[todayKey];
      currentTemp = today?.maxTemp ?? today?.minTemp;
      currentSymbol ??= today?.middaySymbol ?? today?.lastSymbol;
    }

    final daily = <DailyForecast>[];
    final start = DateTime(localNow.year, localNow.month, localNow.day);
    for (var i = 0; i < 7; i++) {
      final day = start.add(Duration(days: i));
      final key =
          '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
      final bucket = byDay[key];
      if (bucket == null) {
        daily.add(DailyForecast(date: day));
      } else {
        daily.add(DailyForecast(
          date: day,
          minTemp: bucket.minTemp,
          maxTemp: bucket.maxTemp,
          symbol: bucket.middaySymbol ?? bucket.lastSymbol,
        ));
      }
    }

    return WeatherSnapshot(
      currentTemp: currentTemp,
      currentSymbol: currentSymbol,
      daily: daily,
      hourly: hourlyList,
      fetchedAt: DateTime.now(),
    );
  }

  double? _readNum(dynamic value) {
    if (value == null) return null;
    final n = (value as num).toDouble();
    if (n >= 9990) return null;
    return n;
  }

  int? _readSymbol(dynamic value) {
    if (value == null) return null;
    final s = (value as num).round();
    if (s <= 0 || s >= 9990) return null;
    return s;
  }

  Future<WeatherSnapshot?> _loadFromPrefs(String coordKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null) return null;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      if ((m['coordKey'] as String?) != coordKey) return null;
      final fetched = DateTime.tryParse(m['fetchedAt'] as String? ?? '');
      if (fetched == null) return null;
      final dailyRaw = m['daily'] as List<dynamic>? ?? const [];
      final daily = dailyRaw.map((d) {
        final dm = d as Map<String, dynamic>;
        return DailyForecast(
          date: DateTime.parse(dm['date'] as String),
          minTemp: (dm['minTemp'] as num?)?.toDouble(),
          maxTemp: (dm['maxTemp'] as num?)?.toDouble(),
          symbol: dm['symbol'] as int?,
        );
      }).toList();
      final hourlyRaw = m['hourly'] as List<dynamic>? ?? const [];
      final hourly = <HourlyForecast>[];
      for (final h in hourlyRaw) {
        if (h is Map<String, dynamic>) {
          final timeStr = h['time'] as String?;
          if (timeStr != null) {
            final time = DateTime.tryParse(timeStr)?.toLocal();
            if (time != null) {
              hourly.add(HourlyForecast(
                time: time,
                temp: (h['temp'] as num?)?.toDouble(),
                symbol: h['symbol'] as int?,
                precipMm: (h['precipMm'] as num?)?.toDouble(),
                windMs: (h['windMs'] as num?)?.toDouble(),
                gustMs: (h['gustMs'] as num?)?.toDouble(),
              ));
            }
          }
        }
      }
      return WeatherSnapshot(
        currentTemp: (m['currentTemp'] as num?)?.toDouble(),
        currentSymbol: m['currentSymbol'] as int?,
        daily: daily,
        hourly: hourly,
        fetchedAt: fetched,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveToPrefs(String coordKey, WeatherSnapshot snap) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = {
        'coordKey': coordKey,
        'fetchedAt': snap.fetchedAt.toIso8601String(),
        'currentTemp': snap.currentTemp,
        'currentSymbol': snap.currentSymbol,
        'daily': snap.daily
            .map((d) => {
                  'date': d.date.toIso8601String(),
                  'minTemp': d.minTemp,
                  'maxTemp': d.maxTemp,
                  'symbol': d.symbol,
                })
            .toList(),
        'hourly': snap.hourly
            .map((h) => {
                  'time': h.time.toIso8601String(),
                  'temp': h.temp,
                  'symbol': h.symbol,
                  'precipMm': h.precipMm,
                  'windMs': h.windMs,
                  'gustMs': h.gustMs,
                })
            .toList(),
      };
      await prefs.setString(_cacheKey, jsonEncode(payload));
    } catch (_) {}
  }
}

class _DayBucket {
  _DayBucket(this.sampleDate);

  final DateTime sampleDate;
  double? minTemp;
  double? maxTemp;
  int? lastSymbol;
  int? middaySymbol;

  void addTemp(double t) {
    minTemp = minTemp == null ? t : (t < minTemp! ? t : minTemp);
    maxTemp = maxTemp == null ? t : (t > maxTemp! ? t : maxTemp);
  }

  void addSymbol(int sym, DateTime when) {
    lastSymbol = sym;
    if (when.hour >= 11 && when.hour <= 14) {
      middaySymbol = sym;
    }
  }
}
