import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/utils/private_activity.dart';
import 'package:la_familia/utils/move_occurrence.dart';

void main() {
  final full = <String, dynamic>{
    'familyId': 'family',
    'date': '2026-11-09',
    'time': '09:30',
    'endTime': '10:00',
    'title': 'Hemlig titel',
    'piktogram': '🏥',
    'description': 'Hemlig text',
    'location': 'Hemlig plats',
    'checklist': [
      {'item': 'Hemlig sak'},
    ],
    'lessonPrep': {'text': 'Hemlig förberedelse'},
    'persons': ['Someone else'],
    'personUids': ['other'],
  };

  test('family marker contains no private text or symbol', () {
    final marker = privateMarker(full, 'owner', 'Alex');
    expect(marker['title'], 'Privat');
    expect(marker['piktogram'], '🔒');
    expect(marker['personUids'], ['owner']);
    expect(marker.toString(), isNot(contains('Hemlig')));
    expect(marker.containsKey('checklist'), false);
    expect(marker.containsKey('lessonPrep'), false);
  });

  test(
    'private storage stays disabled until the exact activation is present',
    () {
      expect(privateCapabilityEnabled(null), false);
      expect(
        privateCapabilityEnabled({'enabled': true, 'contract': 'old'}),
        false,
      );
      expect(
        privateCapabilityEnabled({
          'enabled': false,
          'contract': privateCapabilityContract,
        }),
        false,
      );
      expect(
        privateCapabilityEnabled({
          'enabled': true,
          'contract': privateCapabilityContract,
        }),
        true,
      );
    },
  );

  test('only the matching owner and family receive the detail overlay', () {
    final marker = privateMarker(full, 'owner', 'Alex');
    final detail = privateDetail(full, 'owner');
    expect(
      overlayPrivateActivity(marker, detail, 'owner')['title'],
      'Hemlig titel',
    );
    expect(overlayPrivateActivity(marker, detail, 'other'), marker);
    expect(
      overlayPrivateActivity(marker, detail, 'owner')['description'],
      'Hemlig text',
    );
    expect(
      overlayPrivateActivity(marker, detail, 'owner')['location'],
      'Hemlig plats',
    );
    expect(
      overlayPrivateActivity(marker, {...detail, 'familyId': 'other'}, 'owner'),
      marker,
    );
    expect(
      overlayPrivateActivity(marker, {...detail, 'ownerUid': 'other'}, 'owner'),
      marker,
    );
    expect(overlayPrivateActivity(marker, null, 'owner'), marker);
  });

  test(
    'shared displays and widgets get the marker even on the owners account',
    () {
      final marker = privateMarker(full, 'owner', 'Alex');
      final visibleToOwner = overlayPrivateActivity(
        marker,
        privateDetail(full, 'owner'),
        'owner',
      );
      final onDisplay = publicActivityData(visibleToOwner);
      expect(onDisplay['title'], 'Privat');
      expect(onDisplay['piktogram'], '🔒');
      expect(onDisplay['time'], '09:30');
      expect(onDisplay.toString(), isNot(contains('Hemlig')));
      expect(onDisplay.containsKey('_privateDetailLoaded'), false);
    },
  );

  test('private update fields cannot leak into public marker', () {
    expect(privatePublicChanges(full).keys.toSet(), {
      'date',
      'time',
      'endTime',
    });
    expect(privateDetailChanges(full)['title'], 'Hemlig titel');
    expect(privateDetailChanges(full).containsKey('date'), false);
  });

  test(
    'moving a private occurrence preserves checklist without publishing it',
    () {
      final source = {
        ...full,
        'source': 'manual',
        'isRecurring': true,
        'recurrence': {
          'type': 'weekly',
          'startDate': '2026-11-09',
          'exceptions': <String>[],
        },
        'lessonPrep': {
          'text': 'Privat förberedelse',
          'doneDates': ['2026-11-09'],
        },
      };
      final moved = detachedOccurrence(
        source,
        'series',
        DateTime(2026, 11, 9),
        '2026-11-10',
        '11:00',
        '12:00',
        'owner',
      );
      final marker = privateMovedMarker(
        moved,
        'owner',
        'Alex',
        'series',
        '2026-11-09',
        '12345678-1234-1234-1234-123456789abc',
      );
      final detail = privateDetail(moved, 'owner');
      expect(marker['originalSeriesId'], 'series');
      expect(marker['originalOccurrenceDate'], '2026-11-09');
      expect(marker.toString(), isNot(contains('Hemlig')));
      expect(marker.containsKey('checklist'), isFalse);
      expect(detail['checklist'], source['checklist']);
      expect((detail['lessonPrep'] as Map)['doneDates'], ['2026-11-10']);
    },
  );
}
