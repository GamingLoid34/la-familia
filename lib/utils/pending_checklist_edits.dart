import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'checklist_updates.dart';

/// Packlisteändringar som väntar på att kunna sparas mot serverns senaste
/// version.
///
/// En packlista får aldrig skrivas som en hel lista från telefonens kopia:
/// en avbockning som någon gjort i Android under tiden skulle då skrivas
/// över när nätet kommer tillbaka. Ändringen sparas därför bara i en
/// transaktion ([saveChecklistEdit]) som slår ihop mot den färska listan.
/// Transaktioner kräver nät, så ändringen läggs först här (ursprunglig lista
/// + formulärets lista) och tas bort när transaktionen lyckats. Finns den
/// kvar — appen stängdes innan nätet kom — körs den vid nästa [flush].
class PendingChecklistEdits {
  PendingChecklistEdits._();

  static const _prefsKey = 'pendingChecklistEdits';
  static final Set<String> _inFlight = {};
  static bool _flushing = false;

  // ─── Lagringsformat (rena funktioner, testade) ─────────────────────────
  static Object? _encodeValue(Object? v) {
    if (v is Timestamp) return {'__ts': v.millisecondsSinceEpoch};
    if (v is Map) {
      return {for (final e in v.entries) e.key.toString(): _encodeValue(e.value)};
    }
    if (v is List) return [for (final x in v) _encodeValue(x)];
    if (v == null || v is String || v is num || v is bool) return v;
    return v.toString();
  }

  static Object? _decodeValue(Object? v) {
    if (v is Map) {
      if (v.length == 1 && v['__ts'] is int) {
        return Timestamp.fromMillisecondsSinceEpoch(v['__ts'] as int);
      }
      return <String, dynamic>{
        for (final e in v.entries) e.key.toString(): _decodeValue(e.value),
      };
    }
    if (v is List) return [for (final x in v) _decodeValue(x)];
    return v;
  }

  static String encode(Map<String, ({List<dynamic> original, List<PacklistRad> edited})> m) =>
      jsonEncode({
        for (final e in m.entries)
          e.key: {
            'original': _encodeValue(e.value.original),
            'edited': [
              for (final r in e.value.edited)
                {'text': r.text, 'klar': r.klar, 'index': r.ursprungIndex},
            ],
          },
      });

  static Map<String, ({List<dynamic> original, List<PacklistRad> edited})> decode(
      String? raw) {
    final out = <String, ({List<dynamic> original, List<PacklistRad> edited})>{};
    if (raw == null || raw.isEmpty) return out;
    try {
      final m = jsonDecode(raw);
      if (m is! Map) return out;
      for (final e in m.entries) {
        final v = e.value;
        if (v is! Map) continue;
        final original = _decodeValue(v['original']);
        final edited = <PacklistRad>[
          for (final r in (v['edited'] as List? ?? const []))
            if (r is Map && r['text'] is String)
              PacklistRad(r['text'] as String,
                  klar: r['klar'] == true, ursprungIndex: r['index'] as int?),
        ];
        out[e.key.toString()] = (
          original: original is List ? original : const [],
          edited: edited,
        );
      }
    } catch (e) {
      developer.log('Väntande packlistor kunde inte läsas', error: e);
    }
    return out;
  }

  // ─── Lagring ───────────────────────────────────────────────────────────
  static Future<Map<String, ({List<dynamic> original, List<PacklistRad> edited})>>
      _read() async {
    final prefs = await SharedPreferences.getInstance();
    return decode(prefs.getString(_prefsKey));
  }

  static Future<void> _write(
      Map<String, ({List<dynamic> original, List<PacklistRad> edited})> m) async {
    final prefs = await SharedPreferences.getInstance();
    if (m.isEmpty) {
      await prefs.remove(_prefsKey);
    } else {
      await prefs.setString(_prefsKey, encode(m));
    }
  }

  /// Finns en väntande packlisteändring för aktiviteten?
  static Future<bool> hasPending(String eventId) async {
    try {
      return (await _read()).containsKey(eventId);
    } catch (_) {
      return false;
    }
  }

  /// Sparar packlisteändringen: först lokalt, sedan transaktionen. Lyckas
  /// transaktionen tas den lokala posten bort. Saknas nät ligger posten kvar
  /// och körs vid nästa [flush] — det är inget fel. Går ändringen inte att
  /// spara alls (aktiviteten borta, nekad) tas posten bort och felet kastas.
  static Future<void> save(
    DocumentReference<Map<String, dynamic>> ref, {
    required List<dynamic> originalRows,
    required List<PacklistRad> editedRows,
  }) async {
    _inFlight.add(ref.id);
    try {
      try {
        final m = await _read();
        m[ref.id] = (original: originalRows, edited: editedRows);
        await _write(m);
      } catch (e) {
        developer.log('Kunde inte lägga packlistan i kö', error: e);
      }
      try {
        await saveChecklistEdit(ref,
            originalRows: originalRows, editedRows: editedRows);
        await _remove(ref.id);
      } on ChecklistChangedException {
        await _remove(ref.id);
        rethrow;
      } on FirebaseException catch (e) {
        if (isPermanent(e)) {
          await _remove(ref.id);
          rethrow;
        }
        // Tillfälligt (inget nät m.m.): ligger kvar till nästa flush.
      }
    } finally {
      _inFlight.remove(ref.id);
    }
  }

  /// Fel som inte går över av sig själv — ändringen kan aldrig sparas.
  static bool isPermanent(FirebaseException e) =>
      e.code == 'permission-denied' || e.code == 'not-found';

  static Future<void> _remove(String id) async {
    try {
      final m = await _read();
      if (m.remove(id) != null) await _write(m);
    } catch (e) {
      developer.log('Kunde inte ta bort väntande packlista', error: e);
    }
  }

  /// Kör väntande packlisteändringar (vid start, återkomst och när nätet
  /// kommer tillbaka). [onFailed] får ett begripligt fel för en ändring som
  /// inte går att spara och därför släpps (aktiviteten borttagen, nekad).
  static Future<void> flush({void Function(String message)? onFailed}) async {
    if (_flushing) return;
    _flushing = true;
    try {
      final m = await _read();
      for (final e in m.entries) {
        if (_inFlight.contains(e.key)) continue;
        final ref =
            FirebaseFirestore.instance.collection('planner_events').doc(e.key);
        try {
          await saveChecklistEdit(ref,
              originalRows: e.value.original, editedRows: e.value.edited);
          await _remove(e.key);
        } on ChecklistChangedException catch (err) {
          await _remove(e.key);
          onFailed?.call('En packlisteändring kunde inte sparas: ${err.message}');
        } on FirebaseException catch (err) {
          if (isPermanent(err)) {
            await _remove(e.key);
            onFailed?.call(
                'En packlisteändring kunde inte sparas: du saknar behörighet.');
          }
          // Övriga fel (t.ex. inget nät): ligger kvar till nästa försök.
        } catch (err) {
          developer.log('Väntande packlista misslyckades', error: err);
        }
      }
    } catch (e) {
      developer.log('Kunde inte köra väntande packlistor', error: e);
    } finally {
      _flushing = false;
    }
  }
}
