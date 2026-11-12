import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/models/inbox_note.dart';

void main() {
  test(
    'normalizes the same way as Android without flattening distinct lines',
    () {
      expect(
        normalizeNoteText('  HEJ  där\r\n\r\n Nästa\t  rad '),
        'hej där\nnästa rad',
      );
      expect(noteContentHash('  HEJ  där\r\n'), noteContentHash('hej där'));
      expect(noteContentHash(' \n '), isNull);
      expect(noteContentHash('hej\ndär'), isNot(noteContentHash('hej där')));
    },
  );

  test('a note uses the same owner, privacy and interpretation contract', () {
    final note = newInboxNote(
      familyId: 'family',
      uid: 'parent',
      text: ' Hej ',
      isPrivate: true,
      aboutUids: ['child'],
      requestId: 'request',
      createdAt: 'timestamp',
    );
    expect(note['familyId'], 'family');
    expect(note['ownerUid'], 'parent');
    expect(note['visibility'], 'private');
    expect(note['status'], 'saved');
    expect(note['linkedIds'], isEmpty);
    expect(note['aboutUids'], ['child']);
    expect(note['text'], 'Hej');
  });

  test('already linked or dismissed suggestions are never offered again', () {
    final actions = pendingNoteActions({
      'linkedIds': [
        {'actionId': 'done'},
      ],
      'interpretation': {
        'actions': [
          {'id': 'done', 'status': 'pending'},
          {'id': 'dismissed', 'status': 'dismissed'},
          {'id': 'available', 'status': 'pending'},
        ],
      },
    });
    expect(actions.map((a) => a['id']), ['available']);
  });
}
