import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/utils/aktivitet_formular.dart';
import 'package:la_familia/utils/ics_summary.dart';

/// Namngivning, sammanfattning och källetiketter för kalenderimporten.
/// Speglar Androids `IcsSummaryTest.kt`.
String ics(List<String> dtstarts) {
  final b = StringBuffer('BEGIN:VCALENDAR\n');
  for (final d in dtstarts) {
    b
      ..writeln('BEGIN:VEVENT')
      ..writeln(d)
      ..writeln('SUMMARY:Matematik')
      ..writeln('END:VEVENT');
  }
  b.writeln('END:VCALENDAR');
  return b.toString();
}

void main() {
  group('IcsSummary.dates', () {
    test('läser datum ur vanlig DTSTART', () {
      expect(IcsSummary.dates(ics(['DTSTART:20260921T090000'])),
          [DateTime(2026, 9, 21)]);
    });

    test('läser datum med VALUE=DATE', () {
      expect(IcsSummary.dates(ics(['DTSTART;VALUE=DATE:20260921'])),
          [DateTime(2026, 9, 21)]);
    });

    test('läser datum med tidszon', () {
      expect(
          IcsSummary.dates(
              ics(['DTSTART;TZID=Europe/Stockholm:20260921T090000'])),
          [DateTime(2026, 9, 21)]);
    });

    test('tål CRLF och gemener', () {
      expect(
          IcsSummary.dates(
              'BEGIN:VEVENT\r\ndtstart:20260921T090000\r\nEND:VEVENT\r\n'),
          [DateTime(2026, 9, 21)]);
    });

    test('dubbletter räknas en gång och sorteras', () {
      expect(
        IcsSummary.dates(ics([
          'DTSTART:20260923T100000',
          'DTSTART:20260921T090000',
          'DTSTART:20260921T130000',
        ])),
        [DateTime(2026, 9, 21), DateTime(2026, 9, 23)],
      );
    });

    test('fil utan datum ger tom lista', () {
      expect(IcsSummary.dates('BEGIN:VCALENDAR\nEND:VCALENDAR'), isEmpty);
    });

    test('trasigt datum hoppas över utan att fälla', () {
      expect(
        IcsSummary.dates(
            ics(['DTSTART:20261345T090000', 'DTSTART:20260921T090000'])),
        [DateTime(2026, 9, 21)],
      );
    });

    test('DTEND räknas inte som start', () {
      expect(
        IcsSummary.dates('BEGIN:VEVENT\nDTSTART:20260921T090000\n'
            'DTEND:20261221T100000\nEND:VEVENT'),
        [DateTime(2026, 9, 21)],
      );
    });
  });

  group('IcsSummary.suggestName', () {
    test('en vecka ger veckonummer och intervall', () {
      expect(
        IcsSummary.suggestName(
            ics(['DTSTART:20260921T090000', 'DTSTART:20260925T140000'])),
        'v. 39 (21 sep–25 sep)',
      );
    });

    test('flera veckor ger intervall i båda ändar', () {
      expect(
        IcsSummary.suggestName(
            ics(['DTSTART:20260921T090000', 'DTSTART:20261009T140000'])),
        'v. 39–41 (21 sep–9 okt)',
      );
    });

    test('en enda dag ger bara datumet', () {
      expect(IcsSummary.suggestName(ics(['DTSTART:20260921T090000'])),
          '21 sep');
    });

    test('månadsskifte skrivs ut korrekt', () {
      expect(
        IcsSummary.suggestName(
            ics(['DTSTART:20260928T090000', 'DTSTART:20261002T140000'])),
        'v. 40 (28 sep–2 okt)',
      );
    });

    test('ISO-vecka vid årsskifte', () {
      // 28 dec 2026 och 1 jan 2027 ligger båda i ISO-vecka 53 (2026).
      expect(
        IcsSummary.suggestName(
            ics(['DTSTART:20261228T090000', 'DTSTART:20270101T090000'])),
        'v. 53 (28 dec–1 jan)',
      );
    });

    test('fil utan datum ger null', () {
      expect(IcsSummary.suggestName('BEGIN:VCALENDAR\nEND:VCALENDAR'), isNull);
    });

    test('prefix sätts före namnet', () {
      expect(
        IcsSummary.suggestNameWithPrefix(
            ics(['DTSTART:20260921T090000']), 'Céline'),
        'Céline · 21 sep',
      );
    });

    test('tomt prefix ger bara namnet', () {
      expect(
        IcsSummary.suggestNameWithPrefix(
            ics(['DTSTART:20260921T090000']), '   '),
        '21 sep',
      );
    });

    test('prefix på fil utan datum ger null', () {
      expect(IcsSummary.suggestNameWithPrefix('BEGIN:VCALENDAR', 'Céline'),
          isNull);
    });
  });

  group('importnamn med reserv', () {
    test('prefix: inskrivet namn, annars medlem, annars standard', () {
      expect(icsNamnPrefix(' Ebba skola ', 'Ebba'), 'Ebba skola');
      expect(icsNamnPrefix('', 'Céline'), 'Céline');
      expect(icsNamnPrefix('  ', null), 'Importerad kalender');
    });

    test('filnamnsreserv tar bort ändelsen och ratar dokument-id', () {
      expect(icsFilnamnReserv('vecka39.ics'), 'vecka39');
      expect(icsFilnamnReserv('schema.v39.ics'), 'schema.v39');
      expect(icsFilnamnReserv('document:884'), isNull);
      expect(icsFilnamnReserv('.ics'), '.ics');
      expect(icsFilnamnReserv(''), isNull);
    });

    test('namnet byggs ur innehållet i första hand', () {
      expect(
        icsImportNamn(
          icsText: ics(['DTSTART:20260921T090000', 'DTSTART:20260925T090000']),
          prefix: 'Céline',
          filnamn: 'export.ics',
        ),
        'Céline · v. 39 (21 sep–25 sep)',
      );
    });

    test('utan datum används filnamnet, sedan prefixet', () {
      expect(
        icsImportNamn(
            icsText: 'BEGIN:VCALENDAR', prefix: 'Céline', filnamn: 'Höst.ics'),
        'Höst',
      );
      expect(
        icsImportNamn(
            icsText: 'BEGIN:VCALENDAR',
            prefix: 'Céline',
            filnamn: 'document:884'),
        'Céline',
      );
      expect(
        icsImportNamn(icsText: '', prefix: ' ', filnamn: ''),
        'Importerad kalender',
      );
    });
  });

  group('icsImportSammanfattning', () {
    test('en fil', () {
      expect(
        icsImportSammanfattning([
          const IcsFilResultat.lyckad(filnamn: 'a.ics', namn: 'v. 39', antal: 7),
        ]),
        '7 händelser från 1 fil.',
      );
    });

    test('flera filer listas med antal per fil', () {
      expect(
        icsImportSammanfattning([
          const IcsFilResultat.lyckad(filnamn: 'a.ics', namn: 'v. 39', antal: 7),
          const IcsFilResultat.lyckad(filnamn: 'b.ics', namn: 'v. 40', antal: 1),
          const IcsFilResultat.lyckad(filnamn: 'c.ics', namn: 'v. 30', antal: 0),
        ]),
        '8 händelser från 3 filer.\n'
        '• v. 39: 7 händelser\n'
        '• v. 40: 1 händelse\n'
        '• v. 30: inga kommande händelser',
      );
    });

    test('misslyckade filer räknas upp sanningsenligt', () {
      expect(
        icsImportSammanfattning([
          const IcsFilResultat.lyckad(filnamn: 'a.ics', namn: 'v. 39', antal: 5),
          const IcsFilResultat.misslyckad(filnamn: 'b.ics', fel: 'för stor'),
          const IcsFilResultat.misslyckad(
              filnamn: 'c.ics', fel: 'Inloggning krävs.'),
        ]),
        '5 händelser från 1 fil.\n'
        'Misslyckades: b.ics (för stor), c.ics (Inloggning krävs.)',
      );
    });

    test('ingenting importerat', () {
      expect(icsImportSammanfattning(const []), 'Inga händelser importerades.');
      expect(
        icsImportSammanfattning([
          const IcsFilResultat.lyckad(filnamn: 'a.ics', namn: 'x', antal: 0),
        ]),
        'Inga händelser importerades.\nFilen innehöll inga kommande händelser.',
      );
      expect(
        icsImportSammanfattning([
          const IcsFilResultat.misslyckad(filnamn: 'a.ics', fel: 'för stor'),
        ]),
        'Inga händelser importerades.\nMisslyckades: a.ics (för stor)',
      );
    });
  });

  group('importKallEtikett', () {
    test('backendens värden visas aldrig rått', () {
      expect(importKallEtikett({'source': 'photo', 'importKind': 'photo'}),
          'skannat schema');
      expect(importKallEtikett({'importKind': 'photo'}), 'skannat schema');
      expect(importKallEtikett({'source': 'url'}), 'prenumererad kalender');
      expect(importKallEtikett({'source': 'file'}), 'uppladdad fil');
      expect(importKallEtikett({'source': 'ics'}), 'inklistrad kalender');
      expect(importKallEtikett({'feedUrl': 'https://x/y.ics'}),
          'prenumererad kalender');
      expect(importKallEtikett({'source': 'konstigt'}), 'kalender');
      expect(importKallEtikett({}), 'kalender');
    });
  });

  group('hortTillImport', () {
    test('matchar på calendarImportId', () {
      final ev = {'source': 'calendar', 'calendarImportId': 'imp1'};
      expect(hortTillImport(ev, importId: 'imp1', importNamn: 'A'), isTrue);
      expect(hortTillImport(ev, importId: 'imp2', importNamn: 'A'), isFalse);
    });

    test('äldre poster matchas på namn, bara utan import-id', () {
      expect(
        hortTillImport({'source': 'calendar', 'calendarName': 'A'},
            importId: 'imp1', importNamn: 'A'),
        isTrue,
      );
      expect(
        hortTillImport(
            {'source': 'calendar', 'calendarName': 'A', 'calendarImportId': 'x'},
            importId: 'imp1',
            importNamn: 'A'),
        isFalse,
      );
      expect(
        hortTillImport({'source': 'calendar', 'calendarName': ''},
            importId: 'imp1', importNamn: ''),
        isFalse,
      );
    });

    test('manuella händelser rörs aldrig', () {
      expect(
        hortTillImport({'calendarImportId': 'imp1', 'source': 'manual'},
            importId: 'imp1', importNamn: 'A'),
        isFalse,
      );
    });
  });

  group('importerade heldagar', () {
    // Så skriver importIcsText och subscribeCalendarFeed en heldag
    // (DTSTART;VALUE=DATE med DTEND nästa dag): tom tid, sluttid 00:00.
    test('formuläret känner igen importens heldagsform', () {
      expect(
        Tidslage.arImporteradHeldag({
          'source': 'calendar',
          'time': '',
          'endTime': '00:00',
          'date': '2026-09-21',
        }),
        isTrue,
      );
    });

    test('heldag utan DTEND blir inte igenkänd (känd lucka i backend)', () {
      expect(
        Tidslage.arImporteradHeldag({'source': 'calendar', 'time': ''}),
        isFalse,
      );
    });
  });
}
