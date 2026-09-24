import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/models/user_model.dart';
import 'package:la_familia/utils/aktivitet_formular.dart';
import 'package:la_familia/utils/aktivitet_payload.dart';
import 'package:la_familia/utils/quick_add_parser.dart';

/// Förval av datum, datumlås, validering, tidslägen, "Skriv eller säg" och
/// bekräftelsetexten. Portad från Androids `AktivitetFormularLogikTest`,
/// `FormularTolkningTest` och `SparBekraftelseTest`.
UserModel _medlem(String uid, String name) => UserModel(
      uid: uid,
      name: name,
      email: '',
      color: 'ff2196f3',
      role: 'parent',
      viewMode: 'parent',
      energy: 3,
    );

void main() {
  final idag = DateTime(2026, 9, 22);
  final torsdag = DateTime(2026, 9, 24);

  FormularRedigering redigering(Map<String, dynamic> overrides) =>
      FormularRedigering('e', {'title': 'Test', 'time': '09:00', ...overrides});

  group('Förval av datum', () {
    test('från Hem är idag förvalt', () {
      expect(forvalDatum(const FormularFranHem(), idag), idag);
    });

    test('från Kalender är vald dag förvald', () {
      expect(forvalDatum(FormularFranKalender(torsdag), idag), torsdag);
    });

    test('redigering ger aktivitetens eget datum', () {
      expect(forvalDatum(redigering({'date': '2026-10-05'}), idag),
          DateTime(2026, 10, 5));
    });

    test('redigering av serie ger seriens startdag', () {
      final e = redigering({
        'date': '2026-09-01',
        'isRecurring': true,
        'recurrence': {'type': 'weekly', 'startDate': '2026-09-03'},
      });
      expect(forvalDatum(e, idag), DateTime(2026, 9, 3));
    });

    test('serie utan startDate faller tillbaka på date', () {
      final e = redigering({
        'date': '2026-09-01',
        'recurrence': {'type': 'weekly'},
      });
      expect(forvalDatum(e, idag), DateTime(2026, 9, 1));
    });

    test('aktivitet utan läsbart datum ger idag', () {
      expect(forvalDatum(redigering({'date': ''}), idag), idag);
      expect(forvalDatum(redigering({'date': 'nej'}), idag), idag);
    });
  });

  group('Datumlås', () {
    test('datumet är låst vid redigering av serie', () {
      expect(
          datumArLast(redigering({
            'recurrence': {'type': 'weekly', 'startDate': '2026-09-03'},
          })),
          isTrue);
    });

    test('datumet går att ändra vid redigering av engångsaktivitet', () {
      expect(datumArLast(redigering({'date': '2026-09-24'})), isFalse);
    });

    test('datumet går att ändra vid ny aktivitet', () {
      expect(datumArLast(const FormularFranHem()), isFalse);
      expect(datumArLast(FormularFranKalender(torsdag)), isFalse);
    });

    test('ett låst datum ändras varken för hand eller av tolkningen', () {
      final f = AktivitetFormularTillstand.redigera(
        oppning: redigering({
          'date': '2026-09-03',
          'recurrence': {'type': 'weekly', 'startDate': '2026-09-03'},
        }),
        idag: idag,
      );
      expect(f.datumLast, isTrue);
      expect(f.medDatum(torsdag).datum, DateTime(2026, 9, 3));
      final tolkad =
          f.tillampa(FormularIfyllnad(titel: 'Gympa', datum: torsdag));
      expect(tolkad.datum, DateTime(2026, 9, 3));
      expect(tolkad.titel, 'Gympa');
    });
  });

  group('Validering', () {
    String? v(String titel, DateTime? datum, Tidslage l, TimeOfDay? t) =>
        valideraAktivitet(titel: titel, datum: datum, tidslage: l, starttid: t);
    const tolv = TimeOfDay(hour: 12, minute: 0);

    test('komplett klockslag är giltigt', () {
      expect(v('Fotboll', torsdag, Tidslage.klockslag,
          const TimeOfDay(hour: 17, minute: 0)), isNull);
    });

    test('titel krävs', () {
      expect(v('  ', torsdag, Tidslage.klockslag, tolv), isNotNull);
    });

    test('datum krävs', () {
      expect(v('Fotboll', null, Tidslage.klockslag, tolv), isNotNull);
    });

    test('klockslagsläget kräver starttid', () {
      expect(v('Fotboll', torsdag, Tidslage.klockslag, null),
          'Välj en starttid.');
    });

    test('heldag kräver ingen starttid', () {
      expect(v('Studiedag', torsdag, Tidslage.heldag, null), isNull);
    });

    test('tid inte bestämd kräver ingen starttid', () {
      expect(v('Tandläkare', torsdag, Tidslage.obestamd, null), isNull);
    });

    test('felen kommer i formulärets ordning', () {
      expect(v('', null, Tidslage.klockslag, null),
          'Skriv vad aktiviteten heter.');
      expect(v('Fotboll', null, Tidslage.klockslag, null), 'Välj ett datum.');
    });
  });

  group('Upprepningsetikett', () {
    test('etiketten följer valt datum', () {
      expect(upprepningsEtikett('weekly', torsdag), 'Varje torsdag');
      expect(upprepningsEtikett('weekly', DateTime(2026, 9, 25)),
          'Varje fredag');
    });

    test('alla upprepningstyper har etikett', () {
      expect(upprepningsEtikett('biweekly', torsdag), 'Varannan torsdag');
      expect(upprepningsEtikett('monthly', torsdag),
          'Varje månad (samma datum)');
      expect(upprepningsEtikett('none', torsdag), 'Engångshändelse');
      expect(upprepningsEtikett('daily', torsdag), 'Varje dag');
    });

    test('en inläst daily-serie finns bland valen och bevaras', () {
      expect(upprepningsVal('weekly'), upprepningsStandardVal);
      expect(upprepningsVal('daily'), [...upprepningsStandardVal, 'daily']);
      final f = AktivitetFormularTillstand.redigera(
        oppning: redigering({
          'date': '2026-09-24',
          'recurrence': {'type': 'daily', 'startDate': '2026-09-24'},
        }),
        idag: idag,
      );
      expect(f.upprepning, 'daily');
      expect(f.upprepningsAlternativ, contains('daily'));
      expect(f.tillUtkast(const []).upprepning, 'daily');
    });
  });

  group('Tidsläget i ett befintligt dokument', () {
    test('timeMode gäller bara när tiden är tom', () {
      final d = {'time': '15:00', 'timeMode': 'allDay'};
      expect(Tidslage.las(d), Tidslage.klockslag);
      expect(Tidslage.visningsetikett(d), isNull);
    });

    test('heldag och tid inte bestämd läses', () {
      expect(Tidslage.las({'time': '', 'timeMode': 'allDay'}), Tidslage.heldag);
      expect(Tidslage.las({'time': '', 'timeMode': 'undecided'}),
          Tidslage.obestamd);
      expect(Tidslage.visningsetikett({'time': '', 'timeMode': 'allDay'}),
          'Hela dagen');
      expect(Tidslage.visningsetikett({'time': '', 'timeMode': 'undecided'}),
          'Tid inte bestämd');
    });

    test('gammal tidlös aktivitet öppnas som tid inte bestämd men visas som förut',
        () {
      final gammal = {'time': ''};
      expect(Tidslage.las(gammal), Tidslage.obestamd);
      expect(Tidslage.visningsetikett(gammal), isNull);
      expect(Tidslage.las({}), Tidslage.obestamd);
    });

    test('okänt timeMode ger ingen etikett', () {
      final okant = {'time': '', 'timeMode': 'morning'};
      expect(Tidslage.las(okant), Tidslage.obestamd);
      expect(Tidslage.visningsetikett(okant), isNull);
    });

    test('lagringsvärdena är Androids', () {
      expect(Tidslage.falt, 'timeMode');
      expect(Tidslage.klockslag.lagring, isNull);
      expect(Tidslage.heldag.lagring, 'allDay');
      expect(Tidslage.obestamd.lagring, 'undecided');
    });
  });

  group('Importerad heldag', () {
    final lovdag = <String, dynamic>{
      'title': 'Höstlov',
      'time': '',
      'endTime': '00:00',
      'source': 'calendar',
    };

    test('importerad heldag förväljs som heldag', () {
      expect(Tidslage.las(lovdag), Tidslage.heldag);
    });

    test('importerad heldag visas som förut tills den sparats', () {
      expect(Tidslage.visningsetikett(lovdag), isNull);
    });

    test('utan importens källa eller sluttid 00:00 blir det inte heldag', () {
      expect(Tidslage.las({...lovdag}..remove('source')), Tidslage.obestamd);
      expect(Tidslage.las({...lovdag, 'source': 'manual'}), Tidslage.obestamd);
      expect(Tidslage.las({...lovdag}..remove('endTime')), Tidslage.obestamd);
      expect(Tidslage.las({...lovdag, 'endTime': '01:00'}), Tidslage.obestamd);
    });

    test('sparat tidsläge går före importens mönster', () {
      expect(Tidslage.las({...lovdag, 'timeMode': 'undecided'}),
          Tidslage.obestamd);
      expect(Tidslage.las({...lovdag, 'time': '08:00'}), Tidslage.klockslag);
    });
  });

  group('Formulärets tillstånd', () {
    test('en tidlös aktivitet förblir tidlös när den öppnas', () {
      final f = AktivitetFormularTillstand.redigera(
        oppning: redigering({'time': '', 'date': '2026-09-24'}),
        idag: idag,
      );
      expect(f.tidslage, Tidslage.obestamd);
      expect(f.starttid, isNull);
      final p = byggAktivitetPayload(
          utkast: f.tillUtkast(const []),
          uid: 'u',
          familyId: 'f',
          original: redigering({'time': '', 'date': '2026-09-24'}).raw);
      expect(p.falt.containsKey('time'), isFalse, reason: 'tom tid står kvar');
      expect(p.forPaminnelser['time'], '');
      expect(p.falt.containsKey('endTime'), isFalse);
      // Som Android: sparad från formuläret får den timeMode "undecided".
      expect(p.falt['timeMode'], 'undecided');
    });

    test('ett valt klockslag tar bort läget utan tid', () {
      final f = AktivitetFormularTillstand.ny(
              oppning: const FormularFranHem(), idag: idag)
          .medTidslage(Tidslage.heldag)
          .medStarttid(const TimeOfDay(hour: 8, minute: 30));
      expect(f.tidslage, Tidslage.klockslag);
      expect(f.starttid, const TimeOfDay(hour: 8, minute: 30));
    });

    test('vald starttid ligger kvar vid byte av läge', () {
      final f = AktivitetFormularTillstand.ny(
              oppning: const FormularFranHem(),
              idag: idag,
              starttid: const TimeOfDay(hour: 9, minute: 0))
          .medTidslage(Tidslage.heldag)
          .medTidslage(Tidslage.klockslag);
      expect(f.starttid, const TimeOfDay(hour: 9, minute: 0));
    });

    test('Fler val-sammanfattningen', () {
      var f = AktivitetFormularTillstand.ny(
          oppning: FormularFranKalender(torsdag), idag: idag);
      expect(f.sammanfattning, isEmpty);
      expect(flerValUnderrad(f.sammanfattning), flerValTomText);
      f = f
          .medUpprepning('weekly')
          .laggTillPackrad(' Kamera ')
          .laggTillPackrad('   ')
          .medForberedelse(aktiv: true, text: 'Packa')
          .medPiktogram('⚽', 'Fotboll')
          .medSparaSomMall(true);
      expect(f.sammanfattning, [
        'Varje torsdag',
        'Packlista (1)',
        'Förbered dagen innan',
        'Symbol ⚽',
        'Sparas som mall',
      ]);
      expect(flerValUnderrad(f.sammanfattning),
          'Varje torsdag · Packlista (1) · Förbered dagen innan · Symbol ⚽ · Sparas som mall');
      expect(f.titel, 'Fotboll', reason: 'tom titel får symbolens etikett');
      expect(f.flerValOppetFranStart, isFalse, reason: 'bara vid redigering');
    });

    test('Fler val är öppet från start vid redigering med innehåll', () {
      final f = AktivitetFormularTillstand.redigera(
        oppning: redigering({
          'date': '2026-09-24',
          'checklist': ['Kamera'],
        }),
        idag: idag,
      );
      expect(f.flerValOppetFranStart, isTrue);
    });

    test('ta bort packrad sker per index, inte per text', () {
      final f = AktivitetFormularTillstand.ny(
              oppning: const FormularFranHem(), idag: idag)
          .laggTillPackrad('Vatten')
          .laggTillPackrad('Vatten')
          .laggTillPackrad('Kex')
          .taBortPackrad(1);
      expect(f.packlista.map((r) => r.text), ['Vatten', 'Kex']);
    });

    test('deltagare läses från personUids, annars från namnen', () {
      final leo = _medlem('leo', 'Leo');
      final nina = _medlem('nina', 'Nina');
      final medUids = AktivitetFormularTillstand.redigera(
        oppning: redigering({
          'personUids': ['nina'],
          'persons': ['Nina'],
        }),
        idag: idag,
        members: [leo, nina],
      );
      expect(medUids.deltagarUids, ['nina']);
      final baraNamn = AktivitetFormularTillstand.redigera(
        oppning: redigering({
          'persons': ['Leo'],
        }),
        idag: idag,
        members: [leo, nina],
      );
      expect(baraNamn.deltagarUids, ['leo']);
      final utkast = baraNamn.vaxlaDeltagare('nina').tillUtkast([leo, nina]);
      expect(utkast.deltagare.map((m) => m.uid), ['leo', 'nina']);
    });

    test('förberedelsen läses in', () {
      final f = AktivitetFormularTillstand.redigera(
        oppning: redigering({
          'lessonPrep': {
            'text': ' Packa gympapåsen ',
            'doneDates': ['2026-09-21'],
          },
        }),
        idag: idag,
      );
      expect(f.forberedelseAktiv, isTrue);
      expect(f.forberedelseText, 'Packa gympapåsen');
    });

    test('en mall sätter symbol, titel och packlista', () {
      final f = AktivitetFormularTillstand.ny(
              oppning: const FormularFranHem(), idag: idag)
          .medMall({
        'title': 'Simning',
        'piktogram': '🏊',
        'checklist': ['Handduk', 7, 'Badmössa'],
      });
      expect(f.titel, 'Simning');
      expect(f.piktogram, '🏊');
      expect(f.packlista, const [PacklistRad('Handduk'), PacklistRad('Badmössa')]);
    });

    test('datumraden och upprepningens slut', () {
      expect(datumRadText(torsdag, idag), 'Torsdag 24 september');
      expect(datumRadText(DateTime(2027, 1, 7), idag), 'Torsdag 7 januari 2027');
      expect(upprepningSlutText(null, idag), 'Slutdatum: tills vidare');
      expect(upprepningSlutText(torsdag, idag), 'Slutar torsdag 24 september');
    });
  });

  group('Skriv eller säg', () {
    final celine = _medlem('celine', 'Céline');
    final leo = _medlem('leo', 'Leo');
    final familj = [celine, leo];
    // Tisdag 22 september 2026 kl 10. "tor" blir då torsdag 24 september.
    final nu = DateTime(2026, 9, 22, 10);

    FormularIfyllnad tolka(String text) {
      final utkast = parseQuickAdd(text, members: familj, now: nu);
      expect(utkast, isNotNull, reason: 'Tolken gav inget för "$text"');
      return formularIfyllnad(utkast!);
    }

    QuickAddDraft utkast(
      String titel, {
      bool uttryckligtDatum = true,
      String tid = '',
      String piktogram = '📅',
      QuickAddIntent intent = QuickAddIntent.activity,
    }) =>
        QuickAddDraft(
          intent: intent,
          title: titel,
          date: DateTime(2026, 9, 24),
          hasExplicitDate: uttryckligtDatum,
          time: tid,
          persons: const [],
          recurrenceType: '',
          piktogram: piktogram,
        );

    test('uppdragets exempel fyller titel, datum, tid och person', () {
      final f = tolka('Tandläkare Céline tor 15');
      expect(f.datum, DateTime(2026, 9, 24));
      expect(f.starttid, const TimeOfDay(hour: 15, minute: 0));
      expect(f.deltagarUids, {'celine'});
      expect(f.titel, 'Tandläkare', reason: 'Talet ska inte ligga kvar i titeln');
    });

    test('naket tal efter dag blir timme', () {
      final f = formularIfyllnad(utkast('Tandläkare 15'));
      expect(f.titel, 'Tandläkare');
      expect(f.starttid, const TimeOfDay(hour: 15, minute: 0));
    });

    test('naket tal utan datum lämnas i titeln', () {
      final f = formularIfyllnad(utkast('Fotboll 11', uttryckligtDatum: false));
      expect(f.titel, 'Fotboll 11');
      expect(f.starttid, isNull);
    });

    test('tolkad tid vinner över naket tal', () {
      final f = formularIfyllnad(utkast('Matte 7', tid: '15:00'));
      expect(f.titel, 'Matte 7');
      expect(f.starttid, const TimeOfDay(hour: 15, minute: 0));
    });

    test('timmar utanför 6 till 22 lämnas i titeln', () {
      for (final titel in ['Matte 5', 'Rum 23', 'Pass 0']) {
        final f = formularIfyllnad(utkast(titel));
        expect(f.titel, titel);
        expect(f.starttid, isNull, reason: '$titel ska inte bli klockslag');
      }
    });

    test('gränserna 6 och 22 räknas', () {
      expect(formularIfyllnad(utkast('Löpning 6')).starttid,
          const TimeOfDay(hour: 6, minute: 0));
      expect(formularIfyllnad(utkast('Film 22')).starttid,
          const TimeOfDay(hour: 22, minute: 0));
    });

    test('tal i ett datum med månadsnamn blir inte klockslag', () {
      final f = tolka('Tandläkare tor 15 okt');
      expect(f.starttid, isNull, reason: '15 är dagen i månaden');
      expect(f.datum, DateTime(2026, 10, 15));
      expect(f.titel.contains('15'), isFalse, reason: f.titel);
    });

    test('tal i ett datum med snedstreck blir inte klockslag', () {
      final f = tolka('Tandläkare 15/10');
      expect(f.starttid, isNull);
      expect(f.datum, DateTime(2026, 10, 15));
      expect(f.titel, 'Tandläkare');
    });

    test('tal över 23 är ingen timme', () {
      final f = formularIfyllnad(utkast('Löpning 42'));
      expect(f.titel, 'Löpning 42');
      expect(f.starttid, isNull);
    });

    test('tal ihopskrivet med ord är ingen timme', () {
      final f = formularIfyllnad(utkast('Fotboll P11'));
      expect(f.titel, 'Fotboll P11');
      expect(f.starttid, isNull);
    });

    test('bara ett tal är ingen titel', () {
      final f = formularIfyllnad(utkast('15'));
      expect(f.titel, '15');
      expect(f.starttid, isNull);
    });

    test('utan datum i texten behålls formulärets datum', () {
      final f = tolka('Fotboll Leo 17:00');
      expect(f.datum, isNull);
      expect(f.starttid, const TimeOfDay(hour: 17, minute: 0));
    });

    test('utan tid i texten behålls formulärets tid', () {
      expect(tolka('Tandläkare tor').starttid, isNull);
    });

    test('utan person i texten behålls formulärets personer', () {
      expect(tolka('Möte tor 15').deltagarUids, isNull);
    });

    test('varje vecka blir upprepning', () {
      expect(tolka('Fotboll varje tisdag 17:00').upprepning, 'weekly');
    });

    test('engångs ger ingen upprepning', () {
      expect(tolka('Tandläkare tor 15').upprepning, isNull);
    });

    test('standardsymbolen förs inte över', () {
      expect(formularIfyllnad(utkast('Möte')).piktogram, isNull);
    });

    test('egen symbol förs över', () {
      expect(
          formularIfyllnad(utkast('Fotboll', tid: '17:00', piktogram: '⚽'))
              .piktogram,
          '⚽');
    });

    test('syssla fyller inte aktivitetsformuläret', () {
      expect(
          () => formularIfyllnad(
              utkast('Diska', intent: QuickAddIntent.chore, piktogram: '🍽️')),
          throwsArgumentError);
    });

    test('klockslag tolkas och ogiltiga ger null', () {
      expect(tolkaKlockslag('09:05'), const TimeOfDay(hour: 9, minute: 5));
      expect(tolkaKlockslag(''), isNull);
      expect(tolkaKlockslag('25:00'), isNull);
      expect(tolkaKlockslag('abc'), isNull);
    });

    test('tolkningen fyller i utan att nolla det meningen inte nämner', () {
      final f = AktivitetFormularTillstand.ny(
        oppning: FormularFranKalender(DateTime(2026, 9, 30)),
        idag: idag,
        starttid: const TimeOfDay(hour: 8, minute: 0),
        deltagarUids: const ['leo'],
      ).medUpprepning('monthly').medPiktogram('⚽', 'Fotboll');
      final efter = f.tillampaTolkning(
          tolkaMening('Qwertyz', members: familj, now: nu));
      expect(efter.titel, 'Qwertyz');
      expect(efter.datum, DateTime(2026, 9, 30));
      expect(efter.starttid, const TimeOfDay(hour: 8, minute: 0));
      expect(efter.deltagarUids, ['leo']);
      expect(efter.upprepning, 'monthly');
      expect(efter.piktogram, '⚽');
    });

    test('ett tolkat klockslag byter till klockslagsläget', () {
      final f = AktivitetFormularTillstand.ny(
              oppning: const FormularFranHem(), idag: idag)
          .medTidslage(Tidslage.heldag)
          .tillampaTolkning(
              tolkaMening('Fotboll Leo tor 17:00', members: familj, now: nu));
      expect(f.tidslage, Tidslage.klockslag);
      expect(f.starttid, const TimeOfDay(hour: 17, minute: 0));
      expect(f.datum, torsdag);
      expect(f.deltagarUids, ['leo']);
    });

    test('en mening tolken inte förstår blir titeln', () {
      final t = tolkaMening('   ', members: familj, now: nu);
      expect(t, isA<OtolkadText>());
      final t2 = tolkaMening('Leo', members: familj, now: nu);
      expect(t2, isA<OtolkadText>());
      final f = AktivitetFormularTillstand.ny(
              oppning: const FormularFranHem(), idag: idag)
          .tillampaTolkning(t2);
      expect(f.titel, 'Leo');
    });

    test('en syssla tolkas som annan typ och ändrar inte formuläret', () {
      final t = tolkaMening('syssla dammsuga imorgon', members: familj, now: nu);
      expect(t, isA<TolkadAnnanTyp>());
      final f = AktivitetFormularTillstand.ny(
          oppning: const FormularFranHem(), idag: idag, titel: 'X');
      expect(f.tillampaTolkning(t).titel, 'X');
    });
  });

  group('Bekräftelsetext', () {
    test('bekräftad sparning visar datum i klartext', () {
      expect(sparBekraftelseText(torsdag, lokalt: false, idag: idag),
          'Sparat i kalendern · torsdag 24 sep');
    });

    test('lokal sparning säger att den skickas senare', () {
      expect(sparBekraftelseText(torsdag, lokalt: true, idag: idag),
          'Sparat på telefonen, skickas när nätet finns · torsdag 24 sep');
    });

    test('sparat och sparat på telefonen skiljer sig', () {
      expect(sparBekraftelseText(torsdag, lokalt: false, idag: idag),
          isNot(sparBekraftelseText(torsdag, lokalt: true, idag: idag)));
    });

    test('månaden förkortas till tre bokstäver', () {
      expect(kortDatum(DateTime(2026, 12, 7), idag), 'måndag 7 dec');
      expect(kortDatum(DateTime(2026, 5, 1), idag), 'fredag 1 maj');
    });

    test('annat år skrivs ut', () {
      expect(kortDatum(DateTime(2027, 1, 7), idag), 'torsdag 7 jan 2027');
    });

    test('veckodagen är gemen', () {
      expect(kortDatum(torsdag, idag).startsWith('torsdag'), isTrue);
    });
  });
}
