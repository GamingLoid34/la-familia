import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'checklist_updates.dart';

/// Packlisteändringar som väntar på att kunna sparas mot serverns senaste
/// version.
///
/// En packlista får aldrig skrivas som en hel lista från telefonens kopia:
/// en avbockning som någon gjort i Android under tiden skulle då skrivas
/// över när nätet kommer tillbaka. Ändringen sparas därför bara i en
/// transaktion som slår ihop mot den färska listan ([ChecklistServer]).
/// Transaktioner kräver nät, så ändringen läggs först i en lokal kö och tas
/// bort när transaktionen lyckats.
///
/// Varje post har ett eget operations-id och är bunden till den användare
/// och familj som gjorde ändringen. Bara den aktiva användarens poster körs,
/// och bara den genomförda operationen tas bort. Alla läsningar och
/// skrivningar av kön görs i tur och ordning (ett lås), så att samtidiga
/// operationer inte skriver över varandra.
class PendingChecklistEdits {
  PendingChecklistEdits({
    required ChecklistEditStore store,
    required ChecklistServer server,
    String Function()? newId,
    DateTime Function()? now,
  })  : _store = store,
        _server = server,
        _newId = newId ?? _randomId,
        _now = now ?? DateTime.now;

  /// Appens kö: SharedPreferences + Firestore-transaktionen.
  static final PendingChecklistEdits instance = PendingChecklistEdits(
    store: PrefsChecklistEditStore(),
    server: firestoreChecklistServer,
  );

  final ChecklistEditStore _store;
  final ChecklistServer _server;
  final String Function() _newId;
  final DateTime Function() _now;

  Future<void> _tail = Future.value();
  final Set<String> _inFlight = {};
  bool _flushing = false;

  static String _randomId() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'))
        .join();
  }

  /// Kör [f] när alla tidigare köoperationer är klara.
  Future<T> _locked<T>(Future<T> Function() f) {
    final result = _tail.then((_) => f());
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<List<PendingChecklistEdit>> _readAll() async =>
      PendingChecklistEdit.decodeAll(await _store.read());

  Future<void> _writeAll(List<PendingChecklistEdit> all) =>
      _store.write(all.isEmpty ? null : PendingChecklistEdit.encodeAll(all));

  /// Tar bort just operationen [opId] — aldrig en nyare post för samma
  /// aktivitet.
  Future<void> _remove(String opId) => _locked(() async {
        final all = await _readAll();
        final kept = [for (final e in all) if (e.opId != opId) e];
        if (kept.length != all.length) await _writeAll(kept);
      });

  /// Väntande poster för [uid] i [familyId], äldst först.
  Future<List<PendingChecklistEdit>> pendingFor(String uid, String familyId) =>
      _locked(() async {
        final all = await _readAll();
        return [
          for (final e in all)
            if (e.uid == uid && e.familyId == familyId) e,
        ]..sort((a, b) => a.createdAtMs.compareTo(b.createdAtMs));
      });

  /// Aktiviteter som har en packlisteändring under arbete i den här
  /// processen (köläggning, serveranrop eller uppspelning).
  final Set<String> _activeEvents = {};

  /// Finns en packlisteändring från [uid] för aktiviteten som inte är
  /// färdigsparad — i kön eller under arbete just nu?
  Future<bool> hasPending(String eventId, {required String uid}) async {
    if (_activeEvents.contains(eventId)) return true;
    try {
      final all = await _locked(_readAll);
      return all.any((e) => e.eventId == eventId && e.uid == uid);
    } catch (_) {
      return false;
    }
  }

  /// Steg 1: reserverar aktiviteten och lägger ändringen i kön — atomärt,
  /// under låset. En aktivitet kan bara ha **en** packlisteändring i taget
  /// från samma användare: en ny ändring skulle annars utgå från en lista
  /// där den förra saknas, och två namnbyten av samma rad blev då två rader.
  /// Kastar [PacklistaVantar] i så fall, innan något skrivits.
  Future<ChecklistTicket> enqueue({
    required String eventId,
    required String uid,
    required String familyId,
    required List<dynamic> originalRows,
    required List<PacklistRad> editedRows,
  }) =>
      _locked(() async {
        List<PendingChecklistEdit> all;
        Object? storeError;
        try {
          all = await _readAll();
        } catch (e) {
          all = const [];
          storeError = e;
        }
        if (_activeEvents.contains(eventId) ||
            all.any((e) => e.eventId == eventId && e.uid == uid)) {
          throw const PacklistaVantar();
        }
        _activeEvents.add(eventId);
        final entry = PendingChecklistEdit(
          opId: _newId(),
          eventId: eventId,
          uid: uid,
          familyId: familyId,
          createdAtMs: _now().millisecondsSinceEpoch,
          original: originalRows,
          edited: editedRows,
        );
        if (storeError == null) {
          try {
            await _writeAll([...all, entry]);
          } catch (e) {
            storeError = e;
          }
        }
        if (storeError != null) {
          developer.log('Kunde inte lägga packlistan i kö', error: storeError);
        }
        return ChecklistTicket._(entry, storeError);
      });

  /// Steg 2: skickar den köade ändringen till servern.
  ///
  /// - [ChecklistSaveOutcome.confirmed]: servern har tagit emot den.
  /// - [ChecklistSaveOutcome.queued]: servern nåddes inte, men ändringen
  ///   ligger säkert i kön och sparas senare.
  /// - Kastar om ändringen inte går att spara alls (aktiviteten borta,
  ///   nekad) — posten tas då bort — eller om servern inte nåddes **och**
  ///   kön inte gick att skriva: då finns ändringen ingenstans.
  ///
  /// [stillActive] säger om samma session fortfarande är inloggad. Har den
  /// bytts räknas ett behörighetsfel inte som permanent, och posten behålls.
  Future<ChecklistSaveOutcome> send(
    ChecklistTicket ticket, {
    bool Function()? stillActive,
  }) async {
    final entry = ticket.entry;
    bool active() => stillActive?.call() ?? true;
    ChecklistSaveOutcome keep() {
      if (!ticket.queued) {
        throw PacklistaEjSparad(
            'Packlistan kunde varken sparas eller läggas i kö: ${ticket.storeError}');
      }
      return ChecklistSaveOutcome.queued;
    }

    _inFlight.add(entry.opId);
    try {
      if (!active()) return keep();
      try {
        await _server(entry.eventId, entry.original, entry.edited);
      } catch (e) {
        if (isPermanent(e) && active()) {
          if (ticket.queued) await _removeQuietly(entry.opId);
          rethrow;
        }
        return keep();
      }
      if (ticket.queued) await _removeQuietly(entry.opId);
      return ChecklistSaveOutcome.confirmed;
    } finally {
      _inFlight.remove(entry.opId);
      _activeEvents.remove(entry.eventId);
    }
  }

  /// [enqueue] följt av [send].
  Future<ChecklistSaveOutcome> save({
    required String eventId,
    required String uid,
    required String familyId,
    required List<dynamic> originalRows,
    required List<PacklistRad> editedRows,
    bool Function()? stillActive,
  }) async =>
      send(
        await enqueue(
          eventId: eventId,
          uid: uid,
          familyId: familyId,
          originalRows: originalRows,
          editedRows: editedRows,
        ),
        stillActive: stillActive,
      );

  Future<void> _removeQuietly(String opId) async {
    try {
      await _remove(opId);
    } catch (e) {
      // Posten ligger kvar; nästa flush kör den igen, vilket är ofarligt
      // (sammanslagningen lägger inte till samma rad två gånger).
      developer.log('Kunde inte ta bort köpost', error: e);
    }
  }

  /// Fel som inte går över av sig själv — ändringen kan aldrig sparas.
  static bool isPermanent(Object e) =>
      e is ChecklistChangedException ||
      (e is FirebaseException &&
          (e.code == 'permission-denied' || e.code == 'not-found'));

  /// Kör [uid]:s väntande ändringar i [familyId], äldst först. Andra
  /// användares och familjers poster rörs inte.
  ///
  /// [stillActive] kontrolleras före varje serveranrop: byts sessionen mitt
  /// i uppspelningen avbryts den, och ett behörighetsfel som kommer efter
  /// bytet raderar ingenting. [onFailed] får ett begripligt fel för en
  /// ändring som inte går att spara och därför släpps.
  Future<void> flush({
    required String uid,
    required String familyId,
    required bool Function() stillActive,
    void Function(String message)? onFailed,
  }) async {
    if (uid.isEmpty || familyId.isEmpty || _flushing) return;
    _flushing = true;
    try {
      for (final e in await pendingFor(uid, familyId)) {
        if (!stillActive()) break;
        if (_inFlight.contains(e.opId) || _activeEvents.contains(e.eventId)) {
          continue;
        }
        _inFlight.add(e.opId);
        _activeEvents.add(e.eventId);
        try {
          await _server(e.eventId, e.original, e.edited);
          await _removeQuietly(e.opId);
        } catch (err) {
          if (isPermanent(err)) {
            if (!stillActive()) break; // felet kan höra till den nya sessionen
            await _removeQuietly(e.opId);
            onFailed?.call(err is ChecklistChangedException
                ? 'En packlisteändring kunde inte sparas: ${err.message}'
                : 'En packlisteändring kunde inte sparas: du saknar behörighet.');
          }
          // Tillfälligt fel (t.ex. inget nät): ligger kvar till nästa försök.
        } finally {
          _inFlight.remove(e.opId);
          _activeEvents.remove(e.eventId);
        }
      }
    } catch (e) {
      developer.log('Kunde inte köra väntande packlistor', error: e);
    } finally {
      _flushing = false;
    }
  }
}

/// En reserverad och (om möjligt) köad ändring, att skicka med [PendingChecklistEdits.send].
class ChecklistTicket {
  final PendingChecklistEdit entry;
  final Object? storeError;
  const ChecklistTicket._(this.entry, this.storeError);
  bool get queued => storeError == null;
}

/// En tidigare packlisteändring för samma aktivitet är inte färdigsparad.
class PacklistaVantar implements Exception {
  const PacklistaVantar();
  String get message =>
      'En tidigare ändring av packlistan är inte färdigsparad. Vänta tills den '
      'syns (det kräver nät), öppna sedan aktiviteten igen och gör om ändringen.';
  @override
  String toString() => message;
}

enum ChecklistSaveOutcome { confirmed, queued }

/// Packlistan finns varken på servern eller i kön.
class PacklistaEjSparad implements Exception {
  final String message;
  const PacklistaEjSparad(this.message);
  @override
  String toString() => message;
}

/// Kön ligger som en sträng (JSON) i en lagring.
abstract class ChecklistEditStore {
  Future<String?> read();
  Future<void> write(String? value);
}

class PrefsChecklistEditStore implements ChecklistEditStore {
  static const _key = 'pendingChecklistEdits.v2';

  @override
  Future<String?> read() async =>
      (await SharedPreferences.getInstance()).getString(_key);

  @override
  Future<void> write(String? value) async {
    final prefs = await SharedPreferences.getInstance();
    final ok = value == null
        ? await prefs.remove(_key)
        : await prefs.setString(_key, value);
    if (!ok) throw StateError('Lagringen avvisade skrivningen.');
  }
}

/// Transaktionen mot serverns senaste version.
typedef ChecklistServer = Future<void> Function(
    String eventId, List<dynamic> originalRows, List<PacklistRad> editedRows);

Future<void> firestoreChecklistServer(
        String eventId, List<dynamic> originalRows, List<PacklistRad> editedRows) =>
    saveChecklistEdit(
      FirebaseFirestore.instance.collection('planner_events').doc(eventId),
      originalRows: originalRows,
      editedRows: editedRows,
    );

/// En post i kön.
class PendingChecklistEdit {
  final String opId;
  final String eventId;
  final String uid;
  final String familyId;
  final int createdAtMs;
  final List<dynamic> original;
  final List<PacklistRad> edited;

  const PendingChecklistEdit({
    required this.opId,
    required this.eventId,
    required this.uid,
    required this.familyId,
    required this.createdAtMs,
    required this.original,
    required this.edited,
  });

  static Object? _enc(Object? v) {
    if (v is Timestamp) return {'__ts': v.millisecondsSinceEpoch};
    if (v is Map) return {for (final e in v.entries) e.key.toString(): _enc(e.value)};
    if (v is List) return [for (final x in v) _enc(x)];
    if (v == null || v is String || v is num || v is bool) return v;
    return v.toString();
  }

  static Object? _dec(Object? v) {
    if (v is Map) {
      if (v.length == 1 && v['__ts'] is int) {
        return Timestamp.fromMillisecondsSinceEpoch(v['__ts'] as int);
      }
      return <String, dynamic>{for (final e in v.entries) e.key.toString(): _dec(e.value)};
    }
    if (v is List) return [for (final x in v) _dec(x)];
    return v;
  }

  Map<String, Object?> toJson() => {
        'opId': opId,
        'eventId': eventId,
        'uid': uid,
        'familyId': familyId,
        'createdAt': createdAtMs,
        'original': _enc(original),
        'edited': [
          for (final r in edited)
            {'text': r.text, 'klar': r.klar, 'index': r.ursprungIndex},
        ],
      };

  static PendingChecklistEdit? fromJson(Object? v) {
    if (v is! Map) return null;
    final opId = v['opId'], eventId = v['eventId'], uid = v['uid'], fid = v['familyId'];
    if (opId is! String || eventId is! String || uid is! String || fid is! String) {
      return null;
    }
    final original = _dec(v['original']);
    return PendingChecklistEdit(
      opId: opId,
      eventId: eventId,
      uid: uid,
      familyId: fid,
      createdAtMs: v['createdAt'] is int ? v['createdAt'] as int : 0,
      original: original is List ? original : const [],
      edited: [
        for (final r in (v['edited'] as List? ?? const []))
          if (r is Map && r['text'] is String)
            PacklistRad(r['text'] as String,
                klar: r['klar'] == true, ursprungIndex: r['index'] as int?),
      ],
    );
  }

  static String encodeAll(List<PendingChecklistEdit> all) =>
      jsonEncode([for (final e in all) e.toJson()]);

  /// Oläsbar lagring ger en tom kö i stället för en krasch; poster utan
  /// ägare (äldre format) hoppas över.
  static List<PendingChecklistEdit> decodeAll(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return [];
      return [for (final v in list) ?fromJson(v)];
    } catch (e) {
      developer.log('Väntande packlistor kunde inte läsas', error: e);
      return [];
    }
  }
}
