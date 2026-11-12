import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/utils/data_tillstand.dart';

/// Min dags tillförlitlighet (UX 02). Port av Androids `MinDagTillforlitlighetTest` och
/// `DataTillstandAterforsokTest`, plus tester för [kombinera] och [KallSamlare].
void main() {
  const alla = MinDagKalla.values;

  /// Källor som inte nämns antas ha lyckats med tom data.
  Map<MinDagKalla, DataTillstand<Object?>> karta(
      [Map<MinDagKalla, DataTillstand<Object?>> par = const {}]) {
    return {
      for (final k in alla) k: const DataFinns<Object?>(<String>[]),
      ...par,
    };
  }

  Map<MinDagKalla, DataTillstand<Object?>> start() =>
      {for (final k in alla) k: const DataLaddar<Object?>()};

  MinDagLage bedom(Map<MinDagKalla, DataTillstand<Object?>> t, bool innehall) =>
      MinDagTillforlitlighet.bedom(t, harInnehall: innehall);

  group('DataTillstand', () {
    test('läsfel med tidigare data ger Inaktuell, inte Fel', () {
      const nuvarande = DataFinns<List<String>>(['post']);
      final nasta = DataTillstand.vidFel(nuvarande, 'behörighet nekad');
      expect(nasta, isA<DataInaktuell<List<String>>>());
      expect(nasta.visatVarde, ['post']);
      expect(nasta.harFel, isTrue);
    });

    test('läsfel utan tidigare data ger Fel, inte tom dag', () {
      final nasta =
          DataTillstand.vidFel(const DataLaddar<List<String>>(), 'index saknas');
      expect(nasta, isA<DataFel<List<String>>>());
      expect(nasta.visatVarde, isNull);
    });

    test('upprepat läsfel behåller det senast kända innehållet', () {
      final forsta =
          DataTillstand.vidFel(const DataFinns<List<String>>(['a']), 'fel 1');
      final andra = DataTillstand.vidFel(forsta, 'fel 2');
      expect(andra.visatVarde, ['a']);
      expect((andra as DataInaktuell).orsak, 'fel 2');
    });

    test('Laddar har varken värde eller fel', () {
      const laddar = DataTillstand<Object?>.laddar();
      expect(laddar.visatVarde, isNull);
      expect(laddar.harFel, isFalse);
    });
  });

  group('Nyckelkravet: rätt person och datum', () {
    test('data för fel dag visas inte', () {
      const gammal = NycklatTillstand<String, List<String>>(
          '2026-09-19', DataFinns(['gårdagens pass']));
      expect(gammal.forNyckel('2026-09-20'), const DataLaddar<Object?>());
    });

    test('data för rätt dag visas', () {
      const aktuell = NycklatTillstand<String, List<String>>(
          '2026-09-20', DataFinns(['dagens pass']));
      expect(aktuell.forNyckel('2026-09-20').visatVarde, ['dagens pass']);
    });

    test('byte av användare kasserar föregående användares data', () {
      const annans = NycklatTillstand<String, Map<String, String>>(
          'uid-noomi', DataFinns({'lunch': '3'}));
      expect(annans.forNyckel('uid-oscar'), const DataLaddar<Object?>());
    });

    test('okänd nyckel kasserar data', () {
      const nagon =
          NycklatTillstand<String, List<String>>('fam-1', DataFinns(['x']));
      expect(nagon.forNyckel(null), const DataLaddar<Object?>());
    });

    test('även ett fel kasseras när nyckeln inte stämmer', () {
      const gammaltFel =
          NycklatTillstand<String, List<String>>('2026-09-19', DataFel('nekad'));
      expect(gammaltFel.forNyckel('2026-09-20'), const DataLaddar<Object?>());
    });
  });

  group('Skärmens samlade läge', () {
    test('inget svar än ger Laddar', () {
      expect(bedom(start(), false), const LageLaddar());
    });

    test('allt hämtat utan innehåll ger TomDag', () {
      expect(bedom(karta(), false), const LageTomDag());
    });

    test('allt hämtat med innehåll ger Klart', () {
      expect(bedom(karta(), true), const LageKlart());
    });

    test('tom dag och allt fallerat är INTE samma sak', () {
      final tom = bedom(karta(), false);
      final trasigt = bedom(
          {for (final k in alla) k: const DataFel<Object?>('nekad')}, false);
      expect(tom, const LageTomDag());
      expect(trasigt, isA<LageAlltFallerade>());
      expect(tom == trasigt, isFalse);
    });

    test('en trasig källa med innehåll kvar ger Delvis', () {
      final lage = bedom(
          karta({MinDagKalla.sysslor: const DataFel('nekad')}), true);
      final delvis = lage as LageDelvis;
      expect(delvis.trasiga, [MinDagKalla.sysslor]);
      expect(delvis.harNagotInnehall, isTrue);
    });

    test('aktiviteterna visas även när sysslorna fallerar', () {
      final lage = bedom(
        karta({
          MinDagKalla.aktiviteter: const DataFinns(['Rehab 07:30']),
          MinDagKalla.sysslor: const DataFel('index saknas'),
        }),
        true,
      );
      expect(lage, isA<LageDelvis>());
      expect(MinDagTillforlitlighet.forklaring((lage as LageDelvis).trasiga),
          'Sysslorna kunde inte hämtas.');
    });

    test('en Inaktuell källa räknas som trasig', () {
      final lage = bedom(
        karta({
          MinDagKalla.aktiviteter: const DataInaktuell(['gammalt'], 'nät'),
        }),
        true,
      );
      expect(lage, isA<LageDelvis>());
      expect((lage as LageDelvis).trasiga, [MinDagKalla.aktiviteter]);
    });

    test('allt trasigt men med gammalt innehåll ger Delvis, inte AlltFallerade',
        () {
      final lage = bedom({
        for (final k in alla)
          k: const DataInaktuell<Object?>(['gammalt'], 'nät'),
      }, true);
      expect(lage, isA<LageDelvis>());
    });

    test('en källa kvar att ladda med innehåll visat ger Klart', () {
      final lage =
          bedom(karta({MinDagKalla.meny: const DataLaddar()}), true);
      expect(lage, const LageKlart());
    });
  });

  group('Förklaringstexten', () {
    test('förklaringen namnger vad som saknas', () {
      expect(MinDagTillforlitlighet.forklaring([MinDagKalla.sysslor]),
          'Sysslorna kunde inte hämtas.');
    });

    test('två källor binds med och', () {
      expect(
          MinDagTillforlitlighet.forklaring(
              [MinDagKalla.aktiviteter, MinDagKalla.sysslor]),
          'Aktiviteterna och sysslorna kunde inte hämtas.');
    });

    test('tre källor får komma och och', () {
      expect(
          MinDagTillforlitlighet.forklaring([
            MinDagKalla.aktiviteter,
            MinDagKalla.sysslor,
            MinDagKalla.maltidsval,
          ]),
          'Aktiviteterna, sysslorna och måltidsvalet kunde inte hämtas.');
    });

    test('ingen trasig ger tom text', () {
      expect(MinDagTillforlitlighet.forklaring([]), '');
    });

    // Tillägg i Flutter: radtexten som Android bygger i MinDagScreen.
    test('felradens text per läge', () {
      expect(
          MinDagTillforlitlighet.felradText(
              const LageDelvis([MinDagKalla.sysslor], harNagotInnehall: true)),
          'Sysslorna kunde inte hämtas.');
      expect(
          MinDagTillforlitlighet.felradText(
              const LageAlltFallerade([MinDagKalla.aktiviteter])),
          'Aktiviteterna kunde inte hämtas. Kontrollera anslutningen.');
      expect(MinDagTillforlitlighet.felradText(const LageKlart()), isNull);
      expect(MinDagTillforlitlighet.felradText(const LageTomDag()), isNull);
      expect(MinDagTillforlitlighet.felradText(const LageLaddar()), isNull);
    });
  });

  group('Återförsök och dagbyte (DataTillstandAterforsokTest)', () {
    test('återförsök går från Fel till Laddar till Data', () {
      DataTillstand<List<String>> t = const DataLaddar();
      t = DataTillstand.vidFel(t, 'nekad');
      expect(t, isA<DataFel<List<String>>>());
      t = const DataLaddar();
      expect(t.harFel, isFalse);
      t = const DataFinns(['Rehab 07:30']);
      expect(t.visatVarde, ['Rehab 07:30']);
      expect(t.harFel, isFalse);
    });

    test('återförsök som misslyckas igen syns fortfarande', () {
      DataTillstand<List<String>> t = const DataFel('nekad');
      t = const DataLaddar();
      t = DataTillstand.vidFel(t, 'nekad igen');
      expect(t.harFel, isTrue);
      expect((t as DataFel).orsak, 'nekad igen');
    });

    test('återförsök från Inaktuell behåller innehållet om det misslyckas', () {
      const DataTillstand<List<String>> medData =
          DataInaktuell(['pass'], 'nät');
      final efter = DataTillstand.vidFel(medData, 'nät igen');
      expect(efter.visatVarde, ['pass']);
      expect(efter, isA<DataInaktuell<List<String>>>());
    });

    test('en lyckad källa rörs inte av att en annan återförsöks', () {
      final t = {
        ...start(),
        MinDagKalla.aktiviteter: const DataFinns<Object?>(['möte']),
        MinDagKalla.sysslor: const DataFel<Object?>('nekad'),
      };
      final efter = {...t, MinDagKalla.sysslor: const DataLaddar<Object?>()};
      expect(efter[MinDagKalla.aktiviteter]?.visatVarde, ['möte']);
      expect(efter[MinDagKalla.sysslor], const DataLaddar<Object?>());
    });

    test('dagbyte nollställer innan ny data kommer', () {
      var t = {
        ...start(),
        MinDagKalla.aktiviteter: const DataFinns<Object?>(['gårdagens pass']),
      };
      t = {...t, MinDagKalla.aktiviteter: const DataLaddar<Object?>()};
      expect(t[MinDagKalla.aktiviteter], const DataLaddar<Object?>());
      expect(bedom(t, false), const LageLaddar());
    });

    test('ett sent svar för fel dag kasseras', () {
      const sentSvar = NycklatTillstand<String, List<String>>(
          '2026-09-19', DataFinns(['gårdagens']));
      expect(sentSvar.forNyckel('2026-09-20'), const DataLaddar<Object?>());
    });

    test('ett sent svar för fel person kasseras', () {
      const sent = NycklatTillstand<String, Map<String, String>>(
          'noomi_2026-09-20', DataFinns({'lunch': '3'}));
      expect(sent.forNyckel('oscar_2026-09-20'), const DataLaddar<Object?>());
    });

    test('hela cykeln för ett dagbyte med fel och återförsök', () {
      var t = karta();

      t = {...t, MinDagKalla.aktiviteter: const DataFinns<Object?>(['möte'])};
      expect(bedom(t, true), const LageKlart());

      t = {...t, MinDagKalla.aktiviteter: const DataLaddar<Object?>()};
      expect(bedom(t, false), const LageLaddar());

      t = {
        ...t,
        MinDagKalla.aktiviteter:
            DataTillstand.vidFel(const DataLaddar<Object?>(), 'nät'),
      };
      expect(bedom(t, false), isA<LageDelvis>());

      t = {
        ...t,
        MinDagKalla.aktiviteter: const DataFinns<Object?>(['nytt möte']),
      };
      expect(bedom(t, true), const LageKlart());
    });
  });

  group('kombinera', () {
    int summa(Map<String, Object?> v) =>
        v.values.fold<int>(0, (s, x) => s + (x as int));

    test('allt hämtat ger Data med sammansatt värde', () {
      final r = kombinera<String, int>(
          {'a': const DataFinns(1), 'b': const DataFinns(2)}, summa);
      expect(r, const DataFinns<int>(3));
    });

    test('något laddar ger Laddar', () {
      final r = kombinera<String, int>(
          {'a': const DataFinns(1), 'b': const DataLaddar()}, summa);
      expect(r, const DataLaddar<int>());
    });

    test('fel utan data ger Fel, även om en annan laddar', () {
      final r = kombinera<String, int>(
          {'a': const DataFel('nekad'), 'b': const DataLaddar()}, summa);
      expect(r, const DataFel<int>('nekad'));
    });

    test('fel med kvarliggande data överallt ger Inaktuell', () {
      final r = kombinera<String, int>({
        'a': const DataInaktuell(1, 'nät'),
        'b': const DataFinns(2),
      }, summa);
      expect(r, const DataInaktuell<int>(3, 'nät'));
    });

    test('orsakerna sätts ihop i källornas ordning', () {
      final r = kombinera<String, int>({
        'a': const DataFel('nekad'),
        'b': const DataInaktuell(2, 'nät'),
      }, summa);
      expect(r, const DataFel<int>('nekad; nät'));
    });

    test('tom lista är data, inte laddning', () {
      final r = kombinera<String, List<Object?>>(
          {'a': const DataFinns(<String>[])}, (v) => v.values.toList());
      expect(r.visatVarde, [<String>[]]);
      expect(r.harFel, isFalse);
    });
  });

  group('KallSamlare', () {
    late KallSamlare<MinDagKalla, String> samlare;
    setUp(() => samlare = KallSamlare<MinDagKalla, String>());
    tearDown(() => samlare.dispose());

    test('startar i Laddar för alla källor', () {
      final a = StreamController<Object?>();
      final b = StreamController<Object?>();
      samlare.lyssna('2026-09-20', {
        MinDagKalla.aktiviteter: () => a.stream,
        MinDagKalla.sysslor: () => b.stream,
      });
      expect(samlare.aktuellt.values, everyElement(const DataLaddar<Object?>()));
      a.close();
      b.close();
    });

    test('data och läsfel hamnar per källa', () async {
      final a = StreamController<Object?>();
      final b = StreamController<Object?>();
      samlare.lyssna('2026-09-20', {
        MinDagKalla.aktiviteter: () => a.stream,
        MinDagKalla.sysslor: () => b.stream,
      });
      a.add(['möte']);
      b.addError('permission-denied');
      await pumpEventQueue();
      expect(samlare.visat<List<String>>(MinDagKalla.aktiviteter), ['möte']);
      expect(samlare.tillstandFor(MinDagKalla.sysslor),
          const DataFel<Object?>('permission-denied'));
      expect(samlare.harFel, isTrue);
      await a.close();
      await b.close();
    });

    test('läsfel efter data ger Inaktuell med kvarliggande innehåll', () async {
      final a = StreamController<Object?>();
      samlare.lyssna('2026-09-20', {MinDagKalla.aktiviteter: () => a.stream});
      a.add(['möte']);
      await pumpEventQueue();
      a.addError('unavailable');
      await pumpEventQueue();
      final t = samlare.tillstandFor(MinDagKalla.aktiviteter);
      expect(t, isA<DataInaktuell<Object?>>());
      expect(t.visatVarde, ['möte']);
      expect((t as DataInaktuell).orsak, 'unavailable');
      await a.close();
    });

    test('nyckelbyte nollställer innan ny data kommer', () async {
      final igar = StreamController<Object?>();
      final idag = StreamController<Object?>();
      samlare.lyssna('2026-09-19', {MinDagKalla.aktiviteter: () => igar.stream});
      igar.add(['gårdagens pass']);
      await pumpEventQueue();
      expect(samlare.visat<List<String>>(MinDagKalla.aktiviteter),
          ['gårdagens pass']);

      samlare.lyssna('2026-09-20', {MinDagKalla.aktiviteter: () => idag.stream});
      expect(samlare.nyckel, '2026-09-20');
      expect(samlare.tillstandFor(MinDagKalla.aktiviteter),
          const DataLaddar<Object?>());
      await igar.close();
      await idag.close();
    });

    test('ett sent svar för den gamla nyckeln kasseras', () async {
      // En broadcast-ström levererar även efter att en ny lyssnare lagts till; den
      // gamla prenumerationen är avslutad och svaret får inte synas.
      final delad = StreamController<Object?>.broadcast();
      final idag = StreamController<Object?>();
      samlare.lyssna('2026-09-19', {MinDagKalla.aktiviteter: () => delad.stream});
      samlare.lyssna('2026-09-20', {MinDagKalla.aktiviteter: () => idag.stream});
      delad.add(['gårdagens']);
      delad.addError('gammalt fel');
      await pumpEventQueue();
      expect(samlare.tillstandFor(MinDagKalla.aktiviteter),
          const DataLaddar<Object?>());

      idag.add(['dagens']);
      await pumpEventQueue();
      expect(samlare.visat<List<String>>(MinDagKalla.aktiviteter), ['dagens']);
      await delad.close();
      await idag.close();
    });

    test('ett sent svar kasseras även när strömmen inte avbryts', () async {
      // Strömmen struntar i cancel och fortsätter leverera (som ett Future som redan
      // är på väg). Generationskontrollen måste ändå stoppa svaret.
      final gammal = _Envis();
      final ny = StreamController<Object?>();
      samlare.lyssna('uid-noomi', {MinDagKalla.maltidsval: () => gammal.stream});
      samlare.lyssna('uid-oscar', {MinDagKalla.maltidsval: () => ny.stream});
      gammal.skicka({'lunch': '3'});
      await pumpEventQueue();
      expect(samlare.tillstandFor(MinDagKalla.maltidsval),
          const DataLaddar<Object?>());
      await ny.close();
    });

    test('samma nyckel och källor startar inte om strömmarna', () async {
      var starter = 0;
      final a = StreamController<Object?>.broadcast();
      Stream<Object?> fabrik() {
        starter++;
        return a.stream;
      }

      samlare.lyssna('k', {MinDagKalla.aktiviteter: fabrik});
      samlare.lyssna('k', {MinDagKalla.aktiviteter: fabrik});
      expect(starter, 1);
      await a.close();
    });

    test('återförsök startar bara om de trasiga källorna', () async {
      final starter = <MinDagKalla, int>{};
      final strommar = <MinDagKalla, StreamController<Object?>>{};
      Stream<Object?> Function() fabrik(MinDagKalla k) => () {
            starter[k] = (starter[k] ?? 0) + 1;
            final c = StreamController<Object?>();
            strommar[k] = c;
            return c.stream;
          };

      samlare.lyssna('2026-09-20', {
        MinDagKalla.aktiviteter: fabrik(MinDagKalla.aktiviteter),
        MinDagKalla.sysslor: fabrik(MinDagKalla.sysslor),
      });
      strommar[MinDagKalla.aktiviteter]!.add(['möte']);
      strommar[MinDagKalla.sysslor]!.addError('nekad');
      await pumpEventQueue();

      expect(samlare.forsokIgen(), isTrue);
      expect(starter[MinDagKalla.aktiviteter], 1);
      expect(starter[MinDagKalla.sysslor], 2);
      expect(samlare.visat<List<String>>(MinDagKalla.aktiviteter), ['möte']);
      expect(samlare.tillstandFor(MinDagKalla.sysslor),
          const DataLaddar<Object?>());

      strommar[MinDagKalla.sysslor]!.add(['diska']);
      await pumpEventQueue();
      expect(samlare.harFel, isFalse);
      expect(samlare.forsokIgen(), isFalse);
      for (final c in strommar.values) {
        await c.close();
      }
    });

    test('sent svar från en ersatt prenumeration efter återförsök kasseras',
        () async {
      final gammal = _Envis();
      final ny = StreamController<Object?>();
      var forsta = true;
      samlare.lyssna('k', {
        MinDagKalla.sysslor: () {
          if (forsta) {
            forsta = false;
            return gammal.stream;
          }
          return ny.stream;
        },
      });
      gammal.fel('nekad');
      await pumpEventQueue();
      samlare.forsokIgen();
      gammal.skicka(['gammalt svar']);
      await pumpEventQueue();
      expect(samlare.tillstandFor(MinDagKalla.sysslor),
          const DataLaddar<Object?>());
      await ny.close();
    });

    test('samlat med bedom ger Delvis när en källa fallerar', () async {
      final a = StreamController<Object?>();
      final b = StreamController<Object?>();
      samlare.lyssna('2026-09-20', {
        MinDagKalla.aktiviteter: () => a.stream,
        MinDagKalla.sysslor: () => b.stream,
      });
      a.add(['Rehab 07:30']);
      b.addError('index saknas');
      await pumpEventQueue();
      final lage = MinDagTillforlitlighet.bedom(
          {...karta(), ...samlare.aktuellt},
          harInnehall: true);
      expect(lage,
          const LageDelvis([MinDagKalla.sysslor], harNagotInnehall: true));
      await a.close();
      await b.close();
    });

    test('lyssnare meddelas vid varje ändring', () async {
      var antal = 0;
      samlare.addListener(() => antal++);
      final a = StreamController<Object?>();
      samlare.lyssna('k', {MinDagKalla.aktiviteter: () => a.stream});
      expect(antal, 1);
      a.add(['x']);
      await pumpEventQueue();
      expect(antal, 2);
      await a.close();
    });
  });
}

/// En ström som fortsätter leverera efter att prenumerationen avslutats (som ett svar
/// som redan är på väg), för att pröva att samlaren själv kasserar sena svar.
class _Envis {
  final List<_EnvisPrenumeration> _prenumerationer = [];

  Stream<Object?> get stream => _EnvisStrom(this);

  void skicka(Object? v) {
    for (final p in _prenumerationer) {
      p.onDataFn?.call(v);
    }
  }

  void fel(Object e) {
    for (final p in _prenumerationer) {
      final f = p.onErrorFn;
      if (f is void Function(Object, StackTrace)) {
        f(e, StackTrace.current);
      } else if (f is void Function(Object)) {
        f(e);
      }
    }
  }
}

class _EnvisStrom extends Stream<Object?> {
  final _Envis kalla;
  _EnvisStrom(this.kalla);

  @override
  StreamSubscription<Object?> listen(void Function(Object?)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    final p = _EnvisPrenumeration()
      ..onDataFn = onData
      ..onErrorFn = onError;
    kalla._prenumerationer.add(p);
    return p;
  }
}

/// Struntar medvetet i [cancel].
class _EnvisPrenumeration implements StreamSubscription<Object?> {
  void Function(Object?)? onDataFn;
  Function? onErrorFn;

  @override
  Future<void> cancel() async {}
  @override
  void onData(void Function(Object?)? handleData) => onDataFn = handleData;
  @override
  void onError(Function? handleError) => onErrorFn = handleError;
  @override
  void onDone(void Function()? handleDone) {}
  @override
  void pause([Future<void>? resumeSignal]) {}
  @override
  void resume() {}
  @override
  bool get isPaused => false;
  @override
  Future<E> asFuture<E>([E? futureValue]) => Completer<E>().future;
}
