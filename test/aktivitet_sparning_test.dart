import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/utils/aktivitet_payload.dart';

/// Att formuläret inte hänger utan nät, och att ett sent nekande inte tystas.
///
/// Portad från Androids `AktivitetSparningTest`. Testerna låtsas vara en
/// server som svarar, nekar eller aldrig svarar alls. Väntetiden är kort här
/// (i appen 4 s) så att testerna går fort.
void main() {
  const vantan = Duration(milliseconds: 80);

  AktivitetSparning sparning({required bool online}) => AktivitetSparning(
        arOnline: () async => online,
        vantaPaServern: vantan,
      );

  Future<void> vantaLite() => Future<void>.delayed(const Duration(milliseconds: 20));

  test('utan nät stängs formuläret direkt', () async {
    final s = sparning(online: false);
    final aldrig = Completer<String>();
    final utfall = await s.spara(titel: 'Tandläkare', skriv: (_) => aldrig.future);
    expect(utfall, isA<SparLokalt>());
    expect((utfall as SparLokalt).eventId.value, isNull,
        reason: 'En ny aktivitet har inget id förrän det skapats');
  });

  test('server som aldrig svarar låter inte formuläret hänga', () async {
    final s = sparning(online: true);
    final aldrig = Completer<String>();
    final klocka = Stopwatch()..start();
    final utfall = await s.spara(titel: 'Tandläkare', skriv: (_) => aldrig.future);
    klocka.stop();
    expect(utfall, isA<SparLokalt>());
    expect(klocka.elapsed, greaterThanOrEqualTo(vantan));
    expect(klocka.elapsed, lessThan(const Duration(seconds: 2)));
  });

  test('nekad skrivning ger synligt fel', () async {
    final s = sparning(online: true);
    final utfall = await s.spara(
      titel: 'Tandläkare',
      skriv: (_) async =>
          throw StateError('PERMISSION_DENIED: Missing or insufficient permissions.'),
    );
    expect(utfall, isA<SparNekat>());
    expect((utfall as SparNekat).meddelande,
        'Du saknar behörighet att spara den här aktiviteten.');
    await vantaLite();
    expect(s.senaFel.value, isEmpty, reason: 'felet visades redan i formuläret');
  });

  test('bekräftad sparning ger id och kör efterarbetet', () async {
    final s = sparning(online: true);
    String? efterarbeteFor;
    final utfall = await s.spara(
      titel: 'Fotboll',
      skriv: (_) async => 'ny-id',
      narIdArKant: (id) async => efterarbeteFor = id,
    );
    await vantaLite();
    expect(utfall, const SparBekraftat('ny-id'));
    expect(efterarbeteFor, 'ny-id');
  });

  test('sent nekande efter offline tystas inte', () async {
    final s = sparning(online: false);
    final svar = Completer<String>();
    final utfall = await s.spara(titel: 'Tandläkare', skriv: (_) => svar.future);
    expect(utfall, isA<SparLokalt>());
    expect(s.senaFel.value, isEmpty, reason: 'Inget fel än');

    svar.completeError(StateError('PERMISSION_DENIED'));
    await vantaLite();

    expect(s.senaFel.value, hasLength(1));
    expect(s.senaFel.value.single, contains('Tandläkare'));
  });

  test('id blir känt när servern svarat efter offline', () async {
    final s = sparning(online: false);
    final svar = Completer<String>();
    final utfall = await s.spara(titel: 'Tandläkare', skriv: (_) => svar.future)
        as SparLokalt;
    expect(utfall.eventId.value, isNull);
    svar.complete('sent-id');
    await vantaLite();
    expect(utfall.eventId.value, 'sent-id');
  });

  test('utan nät är lokalt skapat id känt direkt och påminner direkt', () async {
    final s = sparning(online: false);
    var paminnelser = 0;
    final aldrig = Completer<String>();
    final utfall = await s.spara(
      titel: 'Tandläkare',
      skriv: (mottag) {
        mottag('lokalt-id');
        return aldrig.future;
      },
      narIdArKant: (_) async => paminnelser++,
    );
    await vantaLite();
    expect((utfall as SparLokalt).eventId.value, 'lokalt-id');
    expect(paminnelser, 1);
  });

  test('efterarbetet körs en gång även när servern sedan svarar', () async {
    final s = sparning(online: true);
    var paminnelser = 0;
    final utfall = await s.spara(
      titel: 'Tandläkare',
      skriv: (mottag) async {
        mottag('id');
        return 'id';
      },
      narIdArKant: (_) async => paminnelser++,
    );
    await vantaLite();
    expect(utfall, const SparBekraftat('id'));
    expect(paminnelser, 1);
  });

  test('redigering utan nät har id direkt och påminner direkt', () async {
    final s = sparning(online: false);
    String? paminnelseFor;
    final aldrig = Completer<String>();
    final utfall = await s.spara(
      titel: 'Fotboll',
      kandId: 'befintlig',
      skriv: (_) => aldrig.future,
      narIdArKant: (id) async => paminnelseFor = id,
    );
    await vantaLite();
    expect((utfall as SparLokalt).eventId.value, 'befintlig');
    expect(paminnelseFor, 'befintlig');
  });

  test('fel i efterarbetet syns men räknas inte som misslyckad sparning',
      () async {
    final s = sparning(online: true);
    final utfall = await s.spara(
      titel: 'Fotboll',
      skriv: (_) async => 'id',
      narIdArKant: (_) async => throw StateError('mallen'),
    );
    await vantaLite();
    expect(utfall, const SparBekraftat('id'));
    expect(s.senaFel.value, hasLength(1));
    expect(s.senaFel.value.single, contains('sparades'));
  });

  test('lyckad bekräftad sparning ger inga sena fel', () async {
    final s = sparning(online: true);
    await s.spara(titel: 'Fotboll', skriv: (_) async => 'id');
    await vantaLite();
    expect(s.senaFel.value, isEmpty);
  });

  test('sent fel ligger kvar tills det kvitterats', () async {
    final s = sparning(online: false);
    final svar = Completer<String>();
    await s.spara(titel: 'Tandläkare', skriv: (_) => svar.future);
    svar.completeError(StateError('PERMISSION_DENIED'));
    await vantaLite();
    expect(s.senaFel.value, hasLength(1));
    s.kvitteraFel();
    expect(s.senaFel.value, isEmpty);
  });

  test('en nätkoll som kastar räknas som offline', () async {
    final s = AktivitetSparning(
      arOnline: () async => throw StateError('ingen koll'),
      vantaPaServern: vantan,
    );
    final aldrig = Completer<String>();
    expect(await s.spara(titel: 'X', skriv: (_) => aldrig.future),
        isA<SparLokalt>());
  });

  test('feltexter är begripliga', () {
    expect(AktivitetSparning.felText(StateError('PERMISSION_DENIED: nej')),
        'Du saknar behörighet att spara den här aktiviteten.');
    expect(AktivitetSparning.felText(null), 'Försök igen.');
    expect(AktivitetSparning.felText(Exception('timeout')),
        'Kunde inte spara: timeout');
  });

  group('Återställning vid nekande (granskning 2026-09-25, punkt 4)', () {
    test('omedelbart nekande återställer', () async {
      final s = sparning(online: true);
      var aterstallt = 0;
      final utfall = await s.spara(
        titel: 'Tandläkare',
        skriv: (_) async => throw StateError('PERMISSION_DENIED'),
        aterstall: () async => aterstallt++,
      );
      expect(utfall, isA<SparNekat>());
      expect(aterstallt, 1);
    });

    test('sent nekande efter väntetiden återställer också', () async {
      final s = sparning(online: true);
      var aterstallt = 0;
      final server = Completer<String>();
      final utfall = await s.spara(
        titel: 'Tandläkare',
        kandId: 'e1',
        skriv: (_) => server.future,
        aterstall: () async => aterstallt++,
      );
      expect(utfall, isA<SparLokalt>());
      expect(aterstallt, 0, reason: 'inget nekande än');
      server.completeError(StateError('PERMISSION_DENIED'));
      await vantaLite();
      expect(aterstallt, 1);
      expect(s.senaFel.value.single, contains('kunde inte sparas'));
    });

    test('sent nekande utan nät återställer också', () async {
      final s = sparning(online: false);
      var aterstallt = 0;
      final server = Completer<String>();
      await s.spara(
        titel: 'Tandläkare',
        skriv: (_) => server.future,
        aterstall: () async => aterstallt++,
      );
      server.completeError(StateError('PERMISSION_DENIED'));
      await vantaLite();
      expect(aterstallt, 1);
    });

    test('lyckad sparning återställer inte', () async {
      final s = sparning(online: true);
      var aterstallt = 0;
      await s.spara(
        titel: 'Tandläkare',
        skriv: (_) async => 'e1',
        aterstall: () async => aterstallt++,
      );
      await vantaLite();
      expect(aterstallt, 0);
    });
  });

  group('Samordning med påminnelsearbetet (granskning omgång 3, punkt 4)', () {
    test('återställningen väntar in påminnelsearbetet', () async {
      final s = sparning(online: true);
      final handelser = <String>[];
      final arbete = Completer<void>();
      final utfall = await s.spara(
        titel: 'Tandläkare',
        kandId: 'e1',
        skriv: (_) async => throw StateError('PERMISSION_DENIED'),
        narIdArKant: (_) async {
          await arbete.future; // påminnelserna läggs upp långsamt
          handelser.add('påminnelser upplagda');
        },
        aterstall: () async => handelser.add('återställt'),
      ).timeout(const Duration(milliseconds: 50), onTimeout: () => const SparNekat('väntar'));
      // Återställningen får inte ha körts före arbetet.
      expect(handelser, isEmpty);
      arbete.complete();
      await vantaLite();
      expect(utfall, isA<SparNekat>());
      expect(handelser, ['påminnelser upplagda', 'återställt']);
    });

    test('sent nekande väntar också in arbetet', () async {
      final s = sparning(online: false);
      final handelser = <String>[];
      final arbete = Completer<void>();
      final server = Completer<String>();
      await s.spara(
        titel: 'Tandläkare',
        kandId: 'e1',
        skriv: (_) => server.future,
        narIdArKant: (_) async {
          await arbete.future;
          handelser.add('påminnelser upplagda');
        },
        aterstall: () async => handelser.add('återställt'),
      );
      server.completeError(StateError('PERMISSION_DENIED'));
      await vantaLite();
      expect(handelser, isEmpty);
      arbete.complete();
      await vantaLite();
      expect(handelser, ['påminnelser upplagda', 'återställt']);
    });
  });

  group('Köad packlista redovisas som lokal', () {
    test('PacklistaKoad ger SparLokalt, ingen återställning, inget fel', () async {
      final s = sparning(online: true);
      var aterstallt = 0;
      final utfall = await s.spara(
        titel: 'Fotboll',
        kandId: 'e1',
        skriv: (_) async => throw const PacklistaKoad(),
        aterstall: () async => aterstallt++,
      );
      expect(utfall, isA<SparLokalt>());
      await vantaLite();
      expect(aterstallt, 0);
      expect(s.senaFel.value, isEmpty);
    });

    test('sent PacklistaKoad ger inget fel', () async {
      final s = sparning(online: false);
      final server = Completer<String>();
      await s.spara(titel: 'Fotboll', kandId: 'e1', skriv: (_) => server.future);
      server.completeError(const PacklistaKoad());
      await vantaLite();
      expect(s.senaFel.value, isEmpty);
    });
  });
}
