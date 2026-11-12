import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/utils/calendar_connection_return.dart';

void main() {
  test(
    'accepts only the fixed completion route and a complete opaque ticket',
    () {
      final ticket = 'a' * 43;
      expect(
        calendarConnectionTicket(
          Uri.parse('https://example.org/#/calendar-connect?ticket=$ticket'),
        ),
        ticket,
      );
      expect(
        calendarConnectionTicket(
          Uri.parse('https://example.org/?ticket=$ticket'),
        ),
        isNull,
      );
      expect(
        calendarConnectionTicket(
          Uri.parse('https://example.org/#/other?ticket=$ticket'),
        ),
        isNull,
      );
      expect(
        calendarConnectionTicket(
          Uri.parse('https://example.org/#/calendar-connect?ticket=short'),
        ),
        isNull,
      );
      expect(
        calendarConnectionTicket(
          Uri.parse(
            'https://example.org/#/calendar-connect?ticket=${'a' * 42}%2F',
          ),
        ),
        isNull,
      );
    },
  );
}
