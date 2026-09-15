// ignore_for_file: subtype_of_sealed_class
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/models/user_model.dart';
import 'package:la_familia/providers/family_provider.dart';
import 'package:la_familia/utils/date_utils.dart';
import 'package:la_familia/utils/member_presence.dart';
import 'package:la_familia/utils/schedule_time_utils.dart';

class MockDocSnapshot implements QueryDocumentSnapshot {
  @override
  final String id;
  final Map<String, dynamic> _data;

  MockDocSnapshot(this.id, this._data);

  @override
  Map<String, dynamic> data() => _data;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeFamilyProvider extends Fake implements FamilyProvider {
  @override
  final UserModel? currentUser;
  @override
  final List<UserModel> familyMembers;
  @override
  final List<QueryDocumentSnapshot> todayEvents;
  @override
  final List<QueryDocumentSnapshot> tomorrowEvents;
  @override
  final List<QueryDocumentSnapshot> chores;
  @override
  final bool isLoading;

  FakeFamilyProvider({
    this.currentUser,
    this.familyMembers = const [],
    this.todayEvents = const [],
    this.tomorrowEvents = const [],
    this.chores = const [],
    this.isLoading = false,
  });
}

const mamma = UserModel(
  uid: 'u_mamma',
  familyId: 'fam1',
  name: 'Mamma Anna',
  email: 'anna@test.com',
  role: 'parent',
  viewMode: 'parent',
  energy: 3,
  color: '#E91E63',
);

void main() {

  group('FAS 5.4 — Delade datum-helpers och återkommande serier', () {
    test('parseDateTime tolkar återkommande serie på måldagen istället för startdatum', () {
      final recurringEvent = {
        'title': 'Fotbollsträning',
        'time': '17:00',
        'date': '2026-08-01', // Startdatum för en månad sedan
        'isRecurring': true,
      };

      final targetDay = DateTime(2026, 9, 10);
      final parsed = parseDateTime(recurringEvent, targetDay);

      expect(parsed, isNotNull);
      expect(parsed!.year, 2026);
      expect(parsed.month, 9);
      expect(parsed.day, 10);
      expect(parsed.hour, 17);
      expect(parsed.minute, 0);
    });

    test('parseDateTime tolkar återkommande serie utan explicit måldag till dagens datum', () {
      final recurringEvent = {
        'title': 'Fotbollsträning',
        'time': '17:00',
        'date': '2026-08-01',
        'isRecurring': true,
      };

      final now = DateTime.now();
      final parsed = parseDateTime(recurringEvent);

      expect(parsed, isNotNull);
      expect(parsed!.year, now.year);
      expect(parsed.month, now.month);
      expect(parsed.day, now.day);
      expect(parsed.hour, 17);
      expect(parsed.minute, 0);
    });

    test('plannerTimedStart tolkar återkommande serie på given dag', () {
      final recurringEvent = {
        'title': 'Pianolektion',
        'time': '15:30',
        'date': '2026-07-15',
        'isRecurring': true,
      };

      final today = DateTime(2026, 9, 10);
      final start = plannerTimedStart(recurringEvent, today);

      expect(start, isNotNull);
      expect(start!.year, 2026);
      expect(start.month, 9);
      expect(start.day, 10);
      expect(start.hour, 15);
      expect(start.minute, 30);
    });

    test('plannerTimedEventIsActiveNow känner igen pågående återkommande händelse', () {
      final now = DateTime(2026, 9, 10, 15, 45);
      final recurringEvent = {
        'title': 'Pianolektion',
        'time': '15:30',
        'endTime': '16:15',
        'date': '2026-07-15',
        'isRecurring': true,
      };

      expect(plannerTimedEventIsActiveNow(recurringEvent, now), isTrue);
    });
  });

  group('FAS 5.4 — Mobilens Hem-hero med återkommande händelser', () {
    test('Återkommande händelse idag kl 17:00 beräknas till 6 timmar från kl 11:00', () {
      final now = DateTime(2026, 9, 10, 11, 0);

      final recurringEvent = MockDocSnapshot('ev_rec_17', {
        'title': 'Fotbollsträning',
        'time': '17:00',
        'endTime': '18:15',
        'piktogram': '⚽',
        'date': '2026-08-01', // Dåtid
        'isRecurring': true,
        'persons': ['Mamma Anna'],
      });

      final d = recurringEvent.data();
      final parsed = parseDateTime(d, now);
      expect(parsed, isNotNull);
      expect(parsed!.isAfter(now), isTrue);
      final diffMin = parsed.difference(now).inMinutes;
      expect(diffMin, 360); // 6 timmar
      final heroTag = 'OM ${(diffMin / 60).round()} TIMMAR';
      expect(heroTag, 'OM 6 TIMMAR');
    });

    test('Återkommande händelse i morgon kl 09:00 beräknas korrekt på morgondagen', () {
      final now = DateTime(2026, 9, 10, 11, 0);
      final tomorrow = now.add(const Duration(days: 1));

      final recurringTomorrow = MockDocSnapshot('ev_rec_tom', {
        'title': 'Simskola',
        'time': '09:00',
        'endTime': '10:00',
        'piktogram': '🏊',
        'date': '2026-08-01',
        'isRecurring': true,
        'persons': ['Mamma Anna'],
      });

      final d = recurringTomorrow.data();
      final parsed = parseDateTime(d, tomorrow);
      expect(parsed, isNotNull);
      expect(parsed!.year, 2026);
      expect(parsed.month, 9);
      expect(parsed.day, 11);
      expect(parsed.hour, 9);
      expect(parsed.minute, 0);
    });
  });

  group('FAS 5.4 — Kategori B: Återkommande händelse imorgon utvärderad idag', () {
    test('Sortering för morgondagen med både engångs- och återkommande händelser', () {
      final tomorrow = DateTime(2026, 9, 11);

      // Engångshändelse imorgon kl 08:30
      final oneOffEarly = {
        'title': 'Tandläkare',
        'time': '08:30',
        'date': '2026-09-11',
        'isRecurring': false,
      };

      // Återkommande händelse varje fredag kl 10:00 med startdatum i augusti
      final recurringMid = {
        'title': 'Veckomöte',
        'time': '10:00',
        'date': '2026-08-01',
        'isRecurring': true,
      };

      // Engångshändelse imorgon kl 14:00
      final oneOffLate = {
        'title': 'Utvecklingssamtal',
        'time': '14:00',
        'date': '2026-09-11',
        'isRecurring': false,
      };

      final list = [oneOffLate, recurringMid, oneOffEarly];

      // Sortering med onDay = tomorrow (Kategori B-mönstret i Agenda & Kalender)
      list.sort((a, b) {
        final dA = parseDateTime(a, tomorrow);
        final dB = parseDateTime(b, tomorrow);
        return dA!.compareTo(dB!);
      });

      // Verifiera att sorteringen blir exakt kronologisk på morgondagen
      expect(list[0]['title'], 'Tandläkare'); // 08:30
      expect(list[1]['title'], 'Veckomöte'); // 10:00 (återkommande)
      expect(list[2]['title'], 'Utvecklingssamtal'); // 14:00

      // Verifiera att datumet för den återkommande händelsen blev morgondagen
      final recParsed = parseDateTime(recurringMid, tomorrow);
      expect(recParsed!.day, 11);
      expect(recParsed.month, 9);
      expect(recParsed.year, 2026);
    });

    test('member_presence identifierar kommande återkommande händelse inom 2 timmar', () {
      final now = DateTime(2026, 9, 10, 16, 0);

      // Återkommande händelse kl 17:00 (om 60 minuter, inom 120 min-fönstret)
      final recurringUpcoming = MockDocSnapshot('rec_up', {
        'title': 'Träning',
        'time': '17:00',
        'endTime': '18:00',
        'date': '2026-08-01',
        'isRecurring': true,
        'persons': ['Mamma Anna'],
      });

      final presence = computeMemberPresence(
        mamma,
        memberTodayEvents: [recurringUpcoming],
        familyShiftDocs: const [],
        familyBusyDocs: const [],
        now: now,
      );

      // Ska ge canReply eftersom händelsen börjar om 60 min (< 120 min)
      expect(presence, MemberPresence.canReply);
    });
  });
}
