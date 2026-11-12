import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Packlistan (`checklist`) på `planner_events` utan att skriva över andras
/// avbockningar.
///
/// Portad från Android-appen (`util/ChecklistUpdates.kt`) och utökad med
/// [mergeChecklist] för formulärets redigering.
///
/// Radformatet är inte enhetligt i databasen. Läsarna tål tre varianter: en
/// map med `item`, en map med `text`, och en ren sträng. `planner_events`
/// skrivs normalt med `{item, isDone}`, men allt här tål de andra också. En
/// sträng betraktas som obockad.
///
/// Reglerna för alla skrivningar här:
///
/// - Rader som inte ändrats lämnas orörda, med alla sina extra fält.
/// - `isDone` på en rad någon annan bockat nollställs aldrig.
/// - Ändringen räknas fram mot den **senaste** versionen på servern, inne i
///   en transaktion, så en rad som lagts till under tiden (t.ex. från
///   inkorgen) inte försvinner.
///
/// Transaktioner kräver nät. Det är samma som i Android och accepterat där.

/// En rad i packlistan, som formuläret håller den.
///
/// [ursprungIndex] är radens index i den lista som lästes in när formuläret
/// öppnades (se `lasPacklista`), eller null för en ny rad. Det är så
/// [mergeChecklist] vet vilken rad som är vilken, även om två rader har samma
/// text eller en rad bytt namn.
@immutable
class PacklistRad {
  final String text;
  final bool klar;
  final int? ursprungIndex;

  const PacklistRad(this.text, {this.klar = false, this.ursprungIndex});

  /// Samma rad med ny text, t.ex. efter att användaren rättat en stavning.
  PacklistRad medText(String nyText) =>
      PacklistRad(nyText, klar: klar, ursprungIndex: ursprungIndex);

  @override
  bool operator ==(Object other) =>
      other is PacklistRad &&
      other.text == text &&
      other.klar == klar &&
      other.ursprungIndex == ursprungIndex;

  @override
  int get hashCode => Object.hash(text, klar, ursprungIndex);

  @override
  String toString() =>
      'PacklistRad($text, klar: $klar, ursprungIndex: $ursprungIndex)';
}

/// Packlistan såg annorlunda ut när skrivningen skulle ske. Meddelandet är
/// svensk text som kan visas för användaren som det är.
class ChecklistChangedException implements Exception {
  final String message;
  const ChecklistChangedException(this.message);

  @override
  String toString() => message;
}

/// Radens text, oavsett vilket av de tre formaten raden har. Null om raden
/// saknar text.
String? checklistTextOf(dynamic row) {
  Object? raw;
  if (row is Map) {
    raw = row['item'] ?? row['text'];
  } else if (row is String) {
    raw = row;
  } else {
    return null;
  }
  if (raw == null) return null;
  final text = raw.toString().trim();
  return text.isEmpty ? null : text;
}

/// True om raden redan är bockad. En ren sträng är alltid obockad.
bool checklistIsDone(dynamic row) => row is Map && row['isDone'] == true;

/// Packlistans rader som de ligger i dokumentet, i alla format.
List<dynamic> checklistRowsOf(dynamic raw) =>
    raw is List ? List<dynamic>.of(raw) : <dynamic>[];

/// Raden med [done] satt, med alla andra fält kvar. En ren sträng uppgraderas
/// till map-formatet, annars går bockningen inte att spara.
dynamic _withDone(dynamic row, bool done) {
  if (row is String) return <String, dynamic>{'item': row.trim(), 'isDone': done};
  if (row is Map) {
    return <String, dynamic>{
      for (final e in row.entries) e.key.toString(): e.value,
      'isDone': done,
    };
  }
  return row;
}

void _kravSammaRad(List<dynamic> rows, int index, String expectedText) {
  final current = index >= 0 && index < rows.length ? rows[index] : null;
  if (checklistTextOf(current) != expectedText.trim()) {
    throw const ChecklistChangedException(
        'Packlistan har ändrats. Öppna aktiviteten och försök igen.');
  }
}

/// Bockar raden på [index] i den färska listan (Hem, "Inför i morgon").
///
/// Kastar [ChecklistChangedException] om raden på [index] inte längre har
/// texten användaren såg. Då har någon annan hunnit ändra listan, och trycket
/// får inte bocka en annan rad.
List<dynamic> completeChecklistRow(
  List<dynamic> rows,
  int index,
  String expectedText,
) =>
    setChecklistRowDone(rows, index, expectedText, done: true);

/// Som [completeChecklistRow], men kan också ångra en bock (detaljrutan).
List<dynamic> setChecklistRowDone(
  List<dynamic> rows,
  int index,
  String expectedText, {
  required bool done,
}) {
  _kravSammaRad(rows, index, expectedText);
  return [
    for (var i = 0; i < rows.length; i++)
      i == index ? _withDone(rows[i], done) : rows[i],
  ];
}

/// Raden efter namnbyte, med formatet och alla andra fält kvar.
dynamic _withText(dynamic row, String text) {
  if (row is String) return text;
  if (row is Map) {
    final key = row.containsKey('item')
        ? 'item'
        : (row.containsKey('text') ? 'text' : 'item');
    return <String, dynamic>{
      for (final e in row.entries) e.key.toString(): e.value,
      key: text,
    };
  }
  return row;
}

/// Wrapper så att samma radvärde på två platser hålls isär (identitet).
class _Plats {
  final dynamic value;
  _Plats(this.value);
}

/// Packlistan efter formulärets ändringar, räknad mot [latestRows].
///
/// - [latestRows]: listan som den ligger på servern nu (läst i transaktionen).
/// - [originalRows]: listan som den låg när formuläret öppnades, rått.
/// - [editedRows]: formulärets lista. Rader med [PacklistRad.ursprungIndex]
///   pekar på sin rad i [originalRows].
///
/// Ändringen uttrycks som det minsta som skiljer formuläret från
/// [originalRows], och bara det görs på [latestRows]:
///
/// - **Borttagen** rad tas bort, om den finns kvar.
/// - **Namnbytt** rad får ny text; formatet, `isDone` och alla andra fält
///   behålls. Har någon annan redan tagit bort raden läggs den nya texten
///   till som en ny rad, så det användaren skrev inte går förlorat.
/// - **Ny** rad läggs in på sin plats bland formulärets rader, eller sist.
///   Har någon annan lagt till en rad med samma text under tiden läggs den
///   inte till en gång till.
/// - **Oförändrade** rader rörs inte. Är de borttagna på servern förblir de
///   borttagna.
/// - Rader någon annan lagt till under tiden behålls.
/// - `klar` i formuläret skrivs aldrig; avbockning görs i detaljrutan och på
///   Hem. Ordningsändringar i formuläret görs inte heller.
///
/// En rad i formuläret utan [PacklistRad.ursprungIndex] som har samma text
/// som en rad i [originalRows] som inget annat pekar på räknas som den raden.
/// Det gör att en lista byggd utan index (t.ex. `PacklistRad('Kamera')`)
/// fortfarande inte skriver om oförändrade rader.
List<dynamic> mergeChecklist({
  required List<dynamic> latestRows,
  required List<dynamic> originalRows,
  required List<PacklistRad> editedRows,
}) {
  // 1. Vilken ursprungsrad varje formulärrad är, om någon.
  final origForEdited = List<int?>.filled(editedRows.length, null);
  final claimed = <int>{};
  for (var p = 0; p < editedRows.length; p++) {
    if (editedRows[p].text.trim().isEmpty) continue;
    final i = editedRows[p].ursprungIndex;
    if (i == null || i < 0 || i >= originalRows.length) continue;
    if (checklistTextOf(originalRows[i]) == null) continue;
    if (!claimed.add(i)) continue;
    origForEdited[p] = i;
  }
  for (var p = 0; p < editedRows.length; p++) {
    if (origForEdited[p] != null || editedRows[p].ursprungIndex != null) {
      continue;
    }
    if (editedRows[p].text.trim().isEmpty) continue;
    final text = editedRows[p].text.trim();
    for (var i = 0; i < originalRows.length; i++) {
      if (!claimed.contains(i) && checklistTextOf(originalRows[i]) == text) {
        claimed.add(i);
        origForEdited[p] = i;
        break;
      }
    }
  }

  // 2. Var varje ursprungsrad finns i den senaste listan nu, om kvar.
  final latest = [for (final r in latestRows) _Plats(r)];
  final usedLatest = <int>{};
  final latestForOrig = <int, _Plats>{};
  for (var i = 0; i < originalRows.length; i++) {
    final text = checklistTextOf(originalRows[i]);
    if (text == null) continue;
    int? hit;
    if (i < latest.length &&
        !usedLatest.contains(i) &&
        checklistTextOf(latest[i].value) == text) {
      hit = i;
    } else {
      for (var j = 0; j < latest.length; j++) {
        if (!usedLatest.contains(j) &&
            checklistTextOf(latest[j].value) == text) {
          hit = j;
          break;
        }
      }
    }
    if (hit != null) {
      usedLatest.add(hit);
      latestForOrig[i] = latest[hit];
    }
  }

  // Rader som någon annan lagt till under tiden, för dubblettskyddet.
  final andrasNya = <_Plats>[
    for (var j = 0; j < latest.length; j++)
      if (!usedLatest.contains(j)) latest[j],
  ];

  // 3. Borttagningar och namnbyten på den senaste listan.
  final keptOrig = <int>{for (final i in origForEdited) ?i};
  final removed = <_Plats>{
    for (final e in latestForOrig.entries)
      if (!keptOrig.contains(e.key)) e.value,
  };
  final result = <_Plats>[
    for (final plats in latest)
      if (!removed.contains(plats)) plats,
  ];
  // Formulärradens plats i resultatet, när den har en.
  final platsForEdited = List<_Plats?>.filled(editedRows.length, null);
  final needsInsert = List<bool>.filled(editedRows.length, false);
  for (var p = 0; p < editedRows.length; p++) {
    final i = origForEdited[p];
    final nyText = editedRows[p].text.trim();
    if (nyText.isEmpty) continue;
    if (i == null) {
      needsInsert[p] = true;
      continue;
    }
    final plats = latestForOrig[i];
    final gammalText = checklistTextOf(originalRows[i]);
    if (plats == null) {
      // Borttagen av någon annan. Oförändrad: låt den vara borta.
      // Namnbytt: användaren skrev något nytt, så det läggs till.
      if (nyText != gammalText) needsInsert[p] = true;
      continue;
    }
    if (nyText != gammalText) {
      final ny = _Plats(_withText(plats.value, nyText));
      result[result.indexOf(plats)] = ny;
      platsForEdited[p] = ny;
    } else {
      platsForEdited[p] = plats;
    }
  }

  // 4. Nya rader på sin plats.
  for (var p = 0; p < editedRows.length; p++) {
    if (!needsInsert[p]) continue;
    final text = editedRows[p].text.trim();
    final dubblett = andrasNya.where((x) => checklistTextOf(x.value) == text);
    if (dubblett.isNotEmpty) {
      final x = dubblett.first;
      andrasNya.remove(x);
      if (result.contains(x)) platsForEdited[p] = x;
      continue;
    }
    final ny = _Plats(<String, dynamic>{
      'item': text,
      'isDone': editedRows[p].klar,
    });
    final foljande = [
      for (var q = p + 1; q < editedRows.length; q++)
        if (platsForEdited[q] != null && result.contains(platsForEdited[q]))
          platsForEdited[q]!,
    ];
    if (foljande.isEmpty) {
      result.add(ny);
    } else {
      _Plats? fore;
      for (var q = p - 1; q >= 0; q--) {
        final x = platsForEdited[q];
        if (x != null && result.contains(x)) {
          fore = x;
          break;
        }
      }
      final at =
          fore != null ? result.indexOf(fore) + 1 : result.indexOf(foljande.first);
      result.insert(at, ny);
    }
    platsForEdited[p] = ny;
  }

  return [for (final plats in result) plats.value];
}

/// Djup jämförelse av två packlistor (eller andra Firestore-värden).
bool checklistRowsEqual(dynamic a, dynamic b) {
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!checklistRowsEqual(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key)) return false;
      if (!checklistRowsEqual(a[key], b[key])) return false;
    }
    return true;
  }
  return a == b;
}

/// Bockar en rad från Hem ("Inför i morgon"), i en transaktion.
///
/// Vägrar återkommande aktiviteter, eftersom en bock där skulle gälla alla
/// tillfällen. Kastar [ChecklistChangedException] med svensk text om raden
/// inte längre är den användaren såg, eller om aktiviteten är borta.
Future<void> completeChecklistItem(
  DocumentReference<Map<String, dynamic>> ref,
  int index,
  String expectedText,
) {
  return ref.firestore.runTransaction<void>((tx) async {
    final snap = await tx.get(ref);
    final data = snap.data();
    if (!snap.exists || data == null) {
      throw const ChecklistChangedException('Aktiviteten finns inte längre.');
    }
    if (data['recurrence'] != null || data['isRecurring'] == true) {
      throw const ChecklistChangedException(
          'Öppna aktiviteten för att hantera dess packlista.');
    }
    final rows = checklistRowsOf(data['checklist']);
    tx.update(ref, {'checklist': completeChecklistRow(rows, index, expectedText)});
  });
}

/// Bockar eller ångrar en rad i detaljrutan, i en transaktion.
///
/// Till skillnad från Androids detaljruta skrivs inte den lokala kopian
/// tillbaka: raden kontrolleras mot den färska listan, och alla andra rader
/// (även strängrader och rader tillagda under tiden) lämnas som de är.
Future<void> setChecklistItemDone(
  DocumentReference<Map<String, dynamic>> ref,
  int index,
  String expectedText, {
  required bool done,
}) {
  return ref.firestore.runTransaction<void>((tx) async {
    final snap = await tx.get(ref);
    final data = snap.data();
    if (!snap.exists || data == null) {
      throw const ChecklistChangedException('Aktiviteten finns inte längre.');
    }
    final rows = checklistRowsOf(data['checklist']);
    tx.update(ref, {
      'checklist': setChecklistRowDone(rows, index, expectedText, done: done),
    });
  });
}

/// Sparar formulärets ändrade packlista, i en transaktion (se [mergeChecklist]).
///
/// [originalRows] är `checklist` som den låg i dokumentet när formuläret
/// öppnades, rått. Returnerar true om något skrevs. Anropas bara när
/// packlistan faktiskt ändrats i formuläret (`AktivitetPayload.packlistanAndrad`).
Future<bool> saveChecklistEdit(
  DocumentReference<Map<String, dynamic>> ref, {
  required List<dynamic> originalRows,
  required List<PacklistRad> editedRows,
}) {
  return ref.firestore.runTransaction<bool>((tx) async {
    final snap = await tx.get(ref);
    final data = snap.data();
    if (!snap.exists || data == null) {
      throw const ChecklistChangedException('Aktiviteten finns inte längre.');
    }
    final latest = checklistRowsOf(data['checklist']);
    final merged = mergeChecklist(
      latestRows: latest,
      originalRows: originalRows,
      editedRows: editedRows,
    );
    if (checklistRowsEqual(merged, latest)) return false;
    tx.update(ref, {'checklist': merged});
    return true;
  });
}
