import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/utils/date_utils.dart';

void main() {
  group('isoWeekNumber', () {
    test('2021-01-01 is week 53 of 2020', () {
      final d = DateTime(2021, 1, 1);
      expect(isoWeekNumber(d), 53);
      expect(isoWeekYear(d), 2020);
    });

    test('2021-01-04 starts week 1 of 2021', () {
      final d = DateTime(2021, 1, 4);
      expect(isoWeekNumber(d), 1);
      expect(isoWeekYear(d), 2021);
    });

    test('2020-12-28 is week 53 of 2020', () {
      final d = DateTime(2020, 12, 28);
      expect(isoWeekNumber(d), 53);
      expect(isoWeekYear(d), 2020);
    });

    test('2026-01-01 Thursday is week 1 of 2026', () {
      final d = DateTime(2026, 1, 1);
      expect(d.weekday, DateTime.thursday);
      expect(isoWeekNumber(d), 1);
      expect(isoWeekYear(d), 2026);
    });

    test('2027-01-01 Friday is week 53 of 2026', () {
      final d = DateTime(2027, 1, 1);
      expect(isoWeekNumber(d), 53);
      expect(isoWeekYear(d), 2026);
    });

    test('mid-year week is stable', () {
      // 2026-06-15 is a Monday
      final d = DateTime(2026, 6, 15);
      expect(isoWeekNumber(d), isoWeekNumber(DateTime(2026, 6, 21)));
      expect(isoWeekNumber(d), 25);
    });
  });
}
