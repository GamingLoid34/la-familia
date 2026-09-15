import 'dart:async';
import 'dart:developer' as developer;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import '../../utils/date_utils.dart';
import 'display_log.dart';
import 'display_scene_models.dart';

/// Formaterar ISO-8601 veckosträng 'YYYY-Www' för ett givet datum (FAS 5.1b).
String formatIsoWeek(DateTime date) {
  final year = isoWeekYear(date);
  final week = isoWeekNumber(date);
  return '$year-W${week.toString().padLeft(2, '0')}';
}

/// Kontrollerar om en text eller del av rätt är salladsbuffé eller tillbehör (FAS 6d Beslut 5).
bool isSaladBuffetDish(String text) {
  final clean = text.trim().toLowerCase();
  if (clean.isEmpty) return false;
  if (clean.contains('alltid på buffén') ||
      clean.contains('alltid pa buffen') ||
      clean.contains('salladsbuffé') ||
      clean.contains('salladsbuffe') ||
      clean.contains('sallad efter säsong') ||
      clean.contains('sallad efter sasong')) {
    return true;
  }
  if (clean == 'buffé' || clean == 'buffe' || clean == 'sallad') {
    return true;
  }
  final words = clean.split(RegExp(r'[\s,.:;!?-]+'));
  return words.contains('sallad') ||
      words.contains('salladsbuffé') ||
      words.contains('salladsbuffe') ||
      words.contains('buffé') ||
      words.contains('buffe');
}

/// Rensar bort salladsbuffé/tillbehör från en sammansatt sträng (t.ex. "Nötkebab · Salladsbuffé" -> "Nötkebab").
String filterSaladBuffet(String text) {
  final parts = text
      .split(' · ')
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty && !isSaladBuffetDish(p))
      .toList();
  return parts.join(' · ');
}

/// Rensar bort rubrikprefix som "Lunch 1:", "Lunch 2:", "Dagens 1:", "Dagens:", "Lunch:" etc. (FAS 5.7)
/// och filtrerar bort salladsbuffé/tillbehör (FAS 6d Beslut 5).
String cleanDishTitle(String text) {
  var cleaned = text.trim();
  final regex = RegExp(
    r'^(?:lunch\s*\d+|dagens\s*\d+|dagens\s*rätt\s*\d+|alternativ\s*\d+|lunch|dagens)\s*[:.-]\s*',
    caseSensitive: false,
  );
  cleaned = cleaned.replaceFirst(regex, '').trim();
  return filterSaladBuffet(cleaned);
}

/// Kontrollerar om ett vegetariskt alternativ är distinkt från huvudrätten (FAS 6d.4).
/// Returnerar false om veg saknas, är tomt eller är identiskt med huvudrätten.
bool hasDistinctVegetarian(String? lunch, String? veg) {
  if (veg == null || veg.trim().isEmpty) return false;
  if (lunch == null || lunch.trim().isEmpty) return true;
  final cleanL = cleanDishTitle(lunch).trim().toLowerCase();
  final cleanV = cleanDishTitle(veg).trim().toLowerCase();
  return cleanV.isNotEmpty && cleanV != cleanL;
}

/// Formaterar kompakt lunch för idag_nu-raden (FAS 5.7, 6d):
/// Returnerar alltid exakt en rätt utan prefix:
/// den klassade huvudrätten, eller vid sammansatt text första rätten utan prefix.
/// Aldrig "Lunch 1:/Lunch 2:"-rubriker och aldrig salladsbuffé/tillbehör.
String formatCompactLunch(String? raw) {
  if (raw == null || raw.trim().isEmpty) return '';
  final text = raw.trim();
  if (text.startsWith('Matsedel saknas')) return text;
  final parts = text
      .split(' · ')
      .map((p) => cleanDishTitle(p))
      .where((p) => p.isNotEmpty && !isSaladBuffetDish(p))
      .toList();
  return parts.isNotEmpty ? parts.first : '';
}

/// En enskild dags skolmatsedel (FAS 5.1, 6d).
class DayMenu {
  final String date; // 'YYYY-MM-DD'
  final String? lunch;
  final String? vegetarian;
  final String? note;

  const DayMenu({
    required this.date,
    this.lunch,
    this.vegetarian,
    this.note,
  });

  factory DayMenu.fromMap(Map<String, dynamic> map) {
    return DayMenu(
      date: (map['date'] as String? ?? '').trim(),
      lunch: (map['lunch'] as String?)?.trim(),
      vegetarian: (map['vegetarian'] as String?)?.trim(),
      note: (map['note'] as String?)?.trim(),
    );
  }

  Map<String, dynamic> toMap() => {
        'date': date,
        if (lunch != null) 'lunch': lunch,
        if (vegetarian != null) 'vegetarian': vegetarian,
        if (note != null) 'note': note,
      };
}

/// En skolas veckomatsedel (FAS 5.1).
class SchoolMenu {
  final String schoolId;
  final String schoolName;
  final List<DayMenu> days;

  const SchoolMenu({
    required this.schoolId,
    required this.schoolName,
    required this.days,
  });

  factory SchoolMenu.fromMap(Map<String, dynamic> map) {
    final rawDays = map['days'] as List? ?? [];
    return SchoolMenu(
      schoolId: (map['schoolId'] as String? ?? '').trim(),
      schoolName: (map['schoolName'] as String? ?? '').trim(),
      days: rawDays
          .whereType<Map>()
          .map((d) => DayMenu.fromMap(Map<String, dynamic>.from(d)))
          .toList(),
    );
  }

  DayMenu? dayFor(DateTime date) {
    final ymd =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    for (final day in days) {
      if (day.date == ymd) return day;
    }
    return null;
  }
}

/// Information om en medlems lunch för en specifik dag (FAS 5.1, 5.1b, 6d).
class LunchInfo {
  final String schoolName;
  final String? lunch;
  final String? vegetarian;
  final String? note;
  final bool isNudge;

  const LunchInfo({
    required this.schoolName,
    this.lunch,
    this.vegetarian,
    this.note,
    this.isNudge = false,
  });
}

/// Beräknar backoff i minuter vid fel: 5 min -> 15 min -> 60 min.
int computeSchoolMenuBackoffMinutes(int consecutiveErrors) {
  if (consecutiveErrors <= 1) return 5;
  if (consecutiveErrors == 2) return 15;
  return 60;
}

/// Klientcache och hämtare för skolmatsedel (FAS 5.1 & 5.1b).
///
/// - Mateo-skolor: Hämtar veckans matsedlar via Cloud Function displaySchoolMenu.
/// - Manuella skolor: Lyssnar i realtid på Firestore under
///   `families/{familyId}/school_menus/{schoolId}/weeks/{isoWeek}`.
/// - Väggnudge: På söndagar fr.o.m. 16:00 visas nudge om nästa veckas meny saknas;
///   på vardagar visas nudge om innevarande dags/veckas meny saknas.
class DisplaySchoolMenuData extends ChangeNotifier {
  static final DisplaySchoolMenuData instance = DisplaySchoolMenuData._internal();

  factory DisplaySchoolMenuData() => instance;

  DisplaySchoolMenuData._internal();

  Map<String, SchoolMenu> _menus = {};
  Map<String, SchoolMenu> _nextWeekMenus = {};
  final Map<String, StreamSubscription<DocumentSnapshot>> _manualSubscriptions = {};
  String? _currentFamilyId;

  bool _isLoading = false;
  String? _error;
  DateTime? _lastFetchTime;
  String? _lastFetchDateStr;
  int _consecutiveErrors = 0;
  DateTime? _nextRetryTime;

  Map<String, SchoolMenu> get menus => _menus;
  Map<String, SchoolMenu> get nextWeekMenus => _nextWeekMenus;
  bool get isLoading => _isLoading;
  String? get error => _error;
  int get consecutiveErrors => _consecutiveErrors;
  DateTime? get nextRetryTime => _nextRetryTime;

  /// Letar upp lunch för en familjemedlem och givet datum via [DisplaySkolmatConfig].
  ///
  /// För manuella skolor appliceras väggnudge om matsedel saknas:
  /// - Söndag >= 16:00 om nästa vecka saknas.
  /// - Vardag (mån–fre) om dagens meny saknas.
  /// - För Mateo-skolor visas ingen nudge (tyst hantering).
  LunchInfo? lunchFor(
    String memberUid,
    DateTime date,
    DisplaySkolmatConfig config, {
    DateTime? nowRef,
  }) {
    final school = config.schoolForMember(memberUid);
    if (school == null) return null;

    final now = nowRef ?? date;

    if (school.isManual) {
      final isSundayLate = now.weekday == DateTime.sunday && now.hour >= 16;
      final isWeekday =
          now.weekday >= DateTime.monday && now.weekday <= DateTime.friday;

      if (isSundayLate) {
        // Söndag från 16:00: kontrollera nästa veckas dokument
        final nextMenu = _nextWeekMenus[school.id];
        final hasNextWeek = nextMenu != null && nextMenu.days.isNotEmpty;
        if (!hasNextWeek) {
          return LunchInfo(
            schoolName: school.name,
            lunch: 'Matsedel saknas — ladda upp i appen',
            isNudge: true,
          );
        }
        return null;
      }

      if (isWeekday) {
        final menu = _menus[school.id];
        final day = menu?.dayFor(date);
        if (day == null || day.lunch == null || day.lunch!.isEmpty) {
          return LunchInfo(
            schoolName: school.name,
            lunch: 'Matsedel saknas — ladda upp i appen',
            isNudge: true,
          );
        }
        return LunchInfo(
          schoolName: school.name,
          lunch: day.lunch,
          vegetarian: day.vegetarian,
          note: day.note,
          isNudge: false,
        );
      }

      // Helg (lördag eller söndag före 16:00): visa lunch om den finns, annars null (ingen nudge)
      final menu = _menus[school.id];
      final day = menu?.dayFor(date);
      if (day != null && day.lunch != null && day.lunch!.isNotEmpty) {
        return LunchInfo(
          schoolName: school.name,
          lunch: day.lunch,
          vegetarian: day.vegetarian,
          note: day.note,
          isNudge: false,
        );
      }
      return null;
    }

    // Mateo-skolor: tyst hantering, aldrig nudge
    final menu = _menus[school.id];
    if (menu == null) return null;

    final day = menu.dayFor(date);
    if (day == null || day.lunch == null || day.lunch!.isEmpty) return null;

    return LunchInfo(
      schoolName: school.name,
      lunch: day.lunch,
      vegetarian: day.vegetarian,
      note: day.note,
      isNudge: false,
    );
  }

  /// Returnerar hel veckomeny för en skola om tillgänglig.
  SchoolMenu? menuForSchool(String schoolId) => _menus[schoolId];

  /// Hämtar matsedel om nödvändigt (vid start, dygnsbyte, eller efter backoff).
  Future<void> fetchIfNeeded(
    DisplaySkolmatConfig config,
    DateTime now, {
    String? familyId,
  }) async {
    if (familyId != null && familyId.isNotEmpty) {
      _currentFamilyId = familyId;
      _syncManualSubscriptions(config, now);
    }

    if (config.schools.isEmpty) return;

    final todayStr =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    // Nytt dygn -> nollställ felräknare så vi provar direkt
    if (_lastFetchDateStr != null && _lastFetchDateStr != todayStr) {
      _consecutiveErrors = 0;
      _nextRetryTime = null;
    }

    // Backoff aktiv vid tidigare fel?
    if (_nextRetryTime != null && now.isBefore(_nextRetryTime!)) {
      return;
    }

    final mateoSchools = config.schools.where((s) => !s.isManual).toList();
    if (mateoSchools.isEmpty) return;

    // Redan hämtat idag och inte passerat 6 timmar sedan senaste lyckade hämtning?
    final hasMissingSchools =
        mateoSchools.any((s) => !_menus.containsKey(s.id));
    if (_lastFetchDateStr == todayStr &&
        _lastFetchTime != null &&
        _error == null &&
        !hasMissingSchools) {
      final diff = now.difference(_lastFetchTime!);
      if (diff < const Duration(hours: 6)) {
        return;
      }
    }

    if (_isLoading) return;

    await fetchMenus(config, now);
  }

  /// Startar eller uppdaterar Firestore-prenumerationer för manuella skolor.
  void _syncManualSubscriptions(DisplaySkolmatConfig config, DateTime now) {
    final fid = _currentFamilyId;
    if (fid == null || fid.isEmpty) return;

    final manualSchools = config.schools.where((s) => s.isManual).toList();
    final curIsoWeek = formatIsoWeek(now);
    final nextIsoWeek = formatIsoWeek(now.add(const Duration(days: 7)));

    final activeKeys = <String>{};

    for (final school in manualSchools) {
      final curKey = '${school.id}:$curIsoWeek';
      final nextKey = '${school.id}:$nextIsoWeek';
      activeKeys.add(curKey);
      activeKeys.add(nextKey);

      // 1. Innevarande vecka
      if (!_manualSubscriptions.containsKey(curKey)) {
        final docRef = FirebaseFirestore.instance
            .collection('families')
            .doc(fid)
            .collection('school_menus')
            .doc(school.id)
            .collection('weeks')
            .doc(curIsoWeek);

        _manualSubscriptions[curKey] = docRef.snapshots().listen(
          (snap) {
            if (snap.exists && snap.data() != null) {
              final data = snap.data()!;
              final rawDays = data['days'] as List? ?? [];
              final days = rawDays
                  .whereType<Map>()
                  .map((d) => DayMenu.fromMap(Map<String, dynamic>.from(d)))
                  .toList();
              _menus[school.id] = SchoolMenu(
                schoolId: school.id,
                schoolName: school.name,
                days: days,
              );
            } else {
              _menus.remove(school.id);
            }
            notifyListeners();
          },
          onError: (e) {
            developer.log(
              'DisplaySchoolMenuData: fel vid lyssning på manuell meny ($curKey): $e',
              error: e,
            );
          },
        );
      }

      // 2. Nästa vecka (för söndagsnudge)
      if (!_manualSubscriptions.containsKey(nextKey)) {
        final docRef = FirebaseFirestore.instance
            .collection('families')
            .doc(fid)
            .collection('school_menus')
            .doc(school.id)
            .collection('weeks')
            .doc(nextIsoWeek);

        _manualSubscriptions[nextKey] = docRef.snapshots().listen(
          (snap) {
            if (snap.exists && snap.data() != null) {
              final data = snap.data()!;
              final rawDays = data['days'] as List? ?? [];
              final days = rawDays
                  .whereType<Map>()
                  .map((d) => DayMenu.fromMap(Map<String, dynamic>.from(d)))
                  .toList();
              _nextWeekMenus[school.id] = SchoolMenu(
                schoolId: school.id,
                schoolName: school.name,
                days: days,
              );
            } else {
              _nextWeekMenus.remove(school.id);
            }
            notifyListeners();
          },
          onError: (e) {
            developer.log(
              'DisplaySchoolMenuData: fel vid lyssning på manuell meny ($nextKey): $e',
              error: e,
            );
          },
        );
      }
    }

    // Avbryt gamla prenumerationer som inte längre är aktiva
    final staleKeys = _manualSubscriptions.keys
        .where((k) => !activeKeys.contains(k))
        .toList();
    for (final k in staleKeys) {
      _manualSubscriptions[k]?.cancel();
      _manualSubscriptions.remove(k);
    }
  }

  /// Hämtar matsedlar från Cloud Function displaySchoolMenu (endast för Mateo-skolor).
  Future<void> fetchMenus(DisplaySkolmatConfig config, [DateTime? nowRef]) async {
    if (_isLoading) return;

    final mateoSchools = config.schools.where((s) => !s.isManual).toList();
    if (mateoSchools.isEmpty) return;

    final now = nowRef ?? DateTime.now();
    final todayStr =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    _isLoading = true;
    notifyListeners();

    try {
      DisplayLog.instance.log(
        'skolmat',
        'Hämtar skolmatsedel för ${mateoSchools.length} Mateo-skolor...',
      );

      final callable =
          FirebaseFunctions.instance.httpsCallable('displaySchoolMenu');
      final response = await callable.call<dynamic>({
        'action': 'menu',
        'schools': mateoSchools
            .map((s) => {
                  'id': s.id,
                  'name': s.name,
                  'municipality': s.municipality,
                })
            .toList(),
      });

      final data = response.data;
      if (data is Map) {
        final rawMenus = data['schools'] ?? data['menus'];
        if (rawMenus is List) {
          for (final item in rawMenus) {
            if (item is Map) {
              final menu =
                  SchoolMenu.fromMap(Map<String, dynamic>.from(item));
              if (menu.schoolId.isNotEmpty) {
                _menus[menu.schoolId] = menu;
              }
            }
          }
        }
        _lastFetchTime = now;
        _lastFetchDateStr = todayStr;
        _consecutiveErrors = 0;
        _nextRetryTime = null;
        _error = null;

        final totalDays = _menus.values.fold<int>(
          0,
          (prev, m) => prev + m.days.length,
        );
        DisplayLog.instance.log(
          'skolmat',
          'Skolmatsedel mottagen för ${_menus.length} skolor ($totalDays matdagar totalt)',
        );
      } else {
        throw Exception('Ogiltigt svar från displaySchoolMenu: ej karta');
      }
    } catch (e, stack) {
      _consecutiveErrors++;
      final backoffMin = computeSchoolMenuBackoffMinutes(_consecutiveErrors);
      _nextRetryTime = now.add(Duration(minutes: backoffMin));
      _error = e.toString();

      developer.log(
        'DisplaySchoolMenuData: hämtning misslyckades',
        error: e,
        stackTrace: stack,
      );
      DisplayLog.instance.log(
        'skolmat',
        'Kunde inte hämta matsedel: $e (försök igen om $backoffMin min)',
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  @visibleForTesting
  void setMockMenus(Map<String, SchoolMenu> menus) {
    _menus = Map.from(menus);
    _error = null;
    notifyListeners();
  }

  @visibleForTesting
  void setMockNextWeekMenus(Map<String, SchoolMenu> menus) {
    _nextWeekMenus = Map.from(menus);
    notifyListeners();
  }

  @visibleForTesting
  void reset() {
    for (final sub in _manualSubscriptions.values) {
      sub.cancel();
    }
    _manualSubscriptions.clear();
    _menus = {};
    _nextWeekMenus = {};
    _currentFamilyId = null;
    _isLoading = false;
    _error = null;
    _lastFetchTime = null;
    _lastFetchDateStr = null;
    _consecutiveErrors = 0;
    _nextRetryTime = null;
    notifyListeners();
  }
}

