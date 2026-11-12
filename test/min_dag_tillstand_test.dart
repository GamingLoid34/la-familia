import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/utils/data_tillstand.dart';
import 'package:la_familia/widgets/min_dag_tillstand.dart';

/// Min dags lägesrad (UX 02): vilken rad som visas för vilket läge, med de källor Min dag
/// faktiskt läser (aktiviteter, återkommande, sysslor — sjukhusmenyn och måltidsvalet är
/// dolda).
void main() {
  const aktiviteter = MinDagKalla.aktiviteter;
  const aterkommande = MinDagKalla.aterkommande;
  const sysslor = MinDagKalla.sysslor;

  Map<MinDagKalla, DataTillstand<Object?>> karta({
    DataTillstand<Object?> a = const DataFinns<Object?>(<Object>[]),
    DataTillstand<Object?> r = const DataFinns<Object?>(<Object>[]),
    DataTillstand<Object?> s = const DataFinns<Object?>(<Object>[]),
  }) =>
      {aktiviteter: a, aterkommande: r, sysslor: s};

  group('bedomMinDag', () {
    test('allt laddar ger laddar, aldrig tom dag', () {
      final lage = bedomMinDag(
        karta(
          a: const DataLaddar<Object?>(),
          r: const DataLaddar<Object?>(),
          s: const DataLaddar<Object?>(),
        ),
        harInnehall: false,
      );
      expect(lage, const LageLaddar());
      expect(minDagRad(lage).typ, MinDagRadTyp.laddar);
      expect(minDagRad(lage).text, 'Hämtar dagen…');
    });

    test('en källa laddar fortfarande och inget innehåll ger laddar', () {
      final lage = bedomMinDag(
        karta(r: const DataLaddar<Object?>()),
        harInnehall: false,
      );
      expect(lage, const LageLaddar());
    });

    test('allt hämtat och tomt ger tom dag', () {
      final lage = bedomMinDag(karta(), harInnehall: false);
      expect(lage, const LageTomDag());
      expect(minDagRad(lage).typ, MinDagRadTyp.tomDag);
    });

    test('innehåll ger ingen rad', () {
      final lage = bedomMinDag(karta(), harInnehall: true);
      expect(lage, const LageKlart());
      expect(minDagRad(lage).typ, MinDagRadTyp.ingen);
    });

    test('ett läsfel med innehåll ger delvis med förklaring', () {
      final lage = bedomMinDag(
        karta(s: const DataFel<Object?>('permission-denied')),
        harInnehall: true,
      );
      expect(lage, isA<LageDelvis>());
      final rad = minDagRad(lage);
      expect(rad.typ, MinDagRadTyp.fel);
      expect(rad.text, 'Sysslorna kunde inte hämtas.');
    });

    test('ett läsfel utan innehåll är inte en tom dag', () {
      final lage = bedomMinDag(
        karta(a: const DataFel<Object?>('fel')),
        harInnehall: false,
      );
      expect(lage, isNot(const LageTomDag()));
      expect(minDagRad(lage).typ, MinDagRadTyp.fel);
      expect(minDagRad(lage).text, 'Aktiviteterna kunde inte hämtas.');
    });

    test('alla lästa källor fallerade utan innehåll ger allt fallerat', () {
      final lage = bedomMinDag(
        karta(
          a: const DataFel<Object?>('x'),
          r: const DataFel<Object?>('x'),
          s: const DataFel<Object?>('x'),
        ),
        harInnehall: false,
      );
      expect(lage, isA<LageAlltFallerade>());
      expect(
        minDagRad(lage).text,
        'Aktiviteterna, återkommande aktiviteter och sysslorna kunde inte '
        'hämtas. Kontrollera anslutningen.',
      );
    });

    test('alla fallerade men gammal data visas ger delvis', () {
      final lage = bedomMinDag(
        karta(
          a: const DataInaktuell<Object?>(<Object>['gammal'], 'x'),
          r: const DataFel<Object?>('x'),
          s: const DataFel<Object?>('x'),
        ),
        harInnehall: true,
      );
      expect(lage, isA<LageDelvis>());
      expect(minDagRad(lage).text, isNot(contains('Kontrollera')));
    });

    test('tom karta (ingen familj ännu) ger tom dag', () {
      expect(bedomMinDag(const {}, harInnehall: false), const LageTomDag());
    });
  });

  group('tomDagTexter', () {
    final idag = DateTime(2026, 9, 25, 14, 30);

    test('idag', () {
      final t = tomDagTexter(visadDag: DateTime(2026, 9, 25), idag: idag);
      expect(t.rubrik, 'Inget inplanerat idag 😌');
    });

    test('framtid', () {
      final t = tomDagTexter(visadDag: DateTime(2026, 9, 26), idag: idag);
      expect(t.rubrik, 'Inget inplanerat 🎈');
    });

    test('dåtid använder Androids text', () {
      final t = tomDagTexter(visadDag: DateTime(2026, 9, 24), idag: idag);
      expect(t.rubrik, 'Inget låg på schemat denna dag');
      expect(t.underrubrik, 'Inga aktiviteter sparades för detta datum.');
      expect(t.emoji, '📅');
    });
  });

  test('dagnyckeln skiljer dag, person och familj', () {
    final a = minDagDagNyckel(datum: '2026-09-25', uid: 'u1', familyId: 'f');
    expect(a,
        isNot(minDagDagNyckel(datum: '2026-09-26', uid: 'u1', familyId: 'f')));
    expect(a,
        isNot(minDagDagNyckel(datum: '2026-09-25', uid: 'u2', familyId: 'f')));
    expect(a,
        isNot(minDagDagNyckel(datum: '2026-09-25', uid: 'u1', familyId: 'g')));
  });
}
