// Portade från Android-appens TaskDraftTest, NoteContentHashTest och
// NoteEditTest, så att båda klienterna skriver och känner igen samma data.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/models/note_model.dart';
import 'package:la_familia/models/task_model.dart';
import 'package:la_familia/services/note_service.dart';

void main() {
  group('TaskDraft (Androids TaskDraftTest)', () {
    final friday = DateTime(2026, 9, 18);

    test('en titel krävs', () {
      expect(const TaskDraft().validate(), 'Skriv vad som ska göras.');
      expect(const TaskDraft(title: '   ').validate(), 'Skriv vad som ska göras.');
    });

    test('ett klockslag utan datum avvisas', () {
      expect(const TaskDraft(title: 'Ringa', dueTime: '09:00').validate(),
          'Välj ett datum för klockslaget.');
    });

    test('felaktigt tidsformat avvisas', () {
      final d = TaskDraft(title: 'Ringa', dueDate: friday, dueTime: '9');
      expect(d.validate(), 'Tiden ska skrivas som HH:MM.');
      expect(TaskDraft(title: 'Ringa', dueDate: friday, dueTime: '25:00').validate(),
          'Tiden ska skrivas som HH:MM.');
      expect(TaskDraft(title: 'Ringa', dueDate: friday, dueTime: '09:30').validate(),
          isNull);
    });

    test('visningsdatum efter deadline avvisas', () {
      expect(
          TaskDraft(
                  title: 'Ringa',
                  dueDate: friday,
                  showFromDate: friday.add(const Duration(days: 3)))
              .validate(),
          'Uppgiften kan inte börja visas efter sin deadline.');
      expect(
          TaskDraft(
                  title: 'Ringa',
                  dueDate: friday,
                  showFromDate: friday.subtract(const Duration(days: 3)))
              .validate(),
          isNull);
    });

    test('för lång titel avvisas', () {
      expect(TaskDraft(title: 'x' * 501).validate(), contains('högst'));
    });

    test('en giltig uppgift blir ett dokument reglerna godkänner', () {
      final task = TaskDraft(
              title: '  Boka tandläkare  ',
              dueDate: friday,
              dueTime: '09:30',
              assigneeUid: 'adult')
          .toTask(familyId: 'f1', myUid: 'me');
      expect(task.title, 'Boka tandläkare');
      expect(task.dueDate, '2026-09-18');
      expect(task.dueTime, '09:30');
      expect(task.hasTime, isTrue);
      expect(task.createdByUid, 'me');
      expect(task.status, TaskModel.statusOpen);
      final map = task.toFirestoreMap();
      expect(map['doneAt'], isNull);
      expect(map.containsKey('eventId'), isFalse);
      expect(map.containsKey('occurrenceDate'), isFalse);
      // Alla nycklar som reglernas hasAll kräver.
      expect(
          map.keys,
          containsAll(<String>[
            'familyId', 'title', 'dueDate', 'dueTime', 'hasTime',
            'showFromDate', 'assigneeUid', 'aboutUids', 'status',
            'sourceNoteId', 'createdByUid', 'doneAt',
          ]));
    });

    test('radbrytning i titeln blir mellanslag (reglerna avvisar radbrytning)', () {
      final t = const TaskDraft(title: '  Köp mjölk\n  och bröd \r\n')
          .toTask(familyId: 'f1', myUid: 'me');
      expect(t.title, 'Köp mjölk och bröd');
      expect(RegExp(r'^.*[^\s].*$').hasMatch(t.title), isTrue);
    });

    test('tid utan datum skrivs aldrig till dokumentet', () {
      final task = const TaskDraft(title: 'Ringa', dueTime: '09:00')
          .toTask(familyId: 'f1', myUid: 'me');
      expect(task.dueTime, isNull);
      expect(task.hasTime, isFalse);
      expect(task.toFirestoreMap()['dueTime'], isNull);
    });

    test('redigering bevarar skapare, klarstatus och källkoppling', () {
      const existing = TaskModel(
        id: 't1',
        familyId: 'f1',
        title: 'Gammal',
        status: TaskModel.statusDone,
        createdByUid: 'someone',
        sourceNoteId: 'note1',
        eventId: 'e1',
        occurrenceDate: '2026-09-18',
      );
      final draft = TaskDraft.from(existing);
      final task = TaskDraft(
        title: 'Ny',
        dueDate: draft.dueDate,
        showFromDate: draft.showFromDate,
      ).toTask(familyId: 'f1', myUid: 'me', existing: existing);
      expect(task.id, 't1');
      expect(task.createdByUid, 'someone');
      expect(task.status, TaskModel.statusDone);
      expect(task.sourceNoteId, 'note1');
      expect(task.toFirestoreMap()['eventId'], 'e1');
      expect(task.toFirestoreMap()['occurrenceDate'], '2026-09-18');
    });

    test('from och toTask är varandras motsats', () {
      final original = TaskDraft(
        title: 'Boka',
        dueDate: friday,
        dueTime: '09:30',
        showFromDate: friday.subtract(const Duration(days: 2)),
        assigneeUid: 'adult',
      );
      final back = TaskDraft.from(original.toTask(familyId: 'f1', myUid: 'me'));
      expect(back.title, original.title);
      expect(back.dueDate, original.dueDate);
      expect(back.dueTime, original.dueTime);
      expect(back.showFromDate, original.showFromDate);
      expect(back.assigneeUid, original.assigneeUid);
    });

    test('klar uppgift har doneAt som Timestamp, öppen har null', () {
      final done = const TaskModel(familyId: 'f', title: 't')
          .copyWith(status: TaskModel.statusDone, doneAt: DateTime(2026, 9, 1));
      expect(done.toFirestoreMap()['doneAt'], isA<Timestamp>());
      final reopened =
          done.copyWith(status: TaskModel.statusOpen, clearDoneAt: true);
      expect(reopened.toFirestoreMap()['doneAt'], isNull);
    });

    test('fromMap: tomma strängar blir null och status öppen', () {
      final t = TaskModel.fromMap('x', {
        'familyId': 'f',
        'title': 'T',
        'dueDate': '',
        'assigneeUid': ' ',
        'status': '',
        'aboutUids': ['a', 3, 'b'],
      });
      expect(t.dueDate, isNull);
      expect(t.assigneeUid, isNull);
      expect(t.status, TaskModel.statusOpen);
      expect(t.aboutUids, ['a', 'b']);
    });

    test('försenad bara när öppen och deadline passerad', () {
      const t = TaskModel(familyId: 'f', title: 't', dueDate: '2026-09-10');
      expect(t.isOverdue('2026-09-11'), isTrue);
      expect(t.isOverdue('2026-09-10'), isFalse);
      expect(
          t.copyWith(status: TaskModel.statusDone).isOverdue('2026-09-11'), isFalse);
    });
  });

  group('NoteContentHash (Androids NoteContentHashTest)', () {
    test('samma text ger samma hash', () {
      const text = 'Utflykt på torsdag. Ta med matsäck.';
      expect(NoteContentHash.of(text), NoteContentHash.of(text));
    });

    test('radslut och indrag påverkar inte hashen', () {
      expect(NoteContentHash.of('Hej!\r\n\r\n  Utflykt torsdag.\r\n'),
          NoteContentHash.of('Hej!\nUtflykt torsdag.'));
    });

    test('upprepade blanksteg inuti en rad slås ihop', () {
      expect(NoteContentHash.of('Ta   med\tmatsäck'),
          NoteContentHash.of('Ta med matsäck'));
    });

    test('skiftläge ignoreras även för svenska tecken', () {
      expect(NoteContentHash.of('ÅKA SKRIDSKOR'),
          NoteContentHash.of('åka skridskor'));
    });

    test('olika brev ger olika hash', () {
      expect(NoteContentHash.of('Utflykt torsdag, ta med matsäck.'),
          isNot(NoteContentHash.of('Utflykt fredag, ta med matsäck.')));
    });

    test('tom text har ingen hash', () {
      expect(NoteContentHash.of(''), isNull);
      expect(NoteContentHash.of('   \n\t  \r\n '), isNull);
    });

    test('hashen är 64 gemena hexadecimaler', () {
      final h = NoteContentHash.of('Utflykt')!;
      expect(h.length, 64);
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(h), isTrue);
    });

    test('normalize behåller radernas ordning och innehåll', () {
      expect(NoteContentHash.normalize('  Hej!  \n\n\n  Utflykt   torsdag.  '),
          'hej!\nutflykt torsdag.');
    });

    test('kända hashar (SHA-256 av normaliserad UTF-8-text)', () {
      // Referensvärden räknade separat (Node crypto), samma algoritm som
      // Kotlins MessageDigest i Android-appen.
      expect(NoteContentHash.of('  Utflykt '),
          'f5bcfb53d32c1c33a1b7d85253800119126aa61792953925aa3956111b250b68');
      expect(NoteContentHash.of('  Hej!  \r\n\r\n  Utflykt   torsdag.  '),
          '8a287e0caec4e4d158c116390bc9665e04ed809718f1703f5320ebb537aca79a');
    });

    test('hårt mellanslag trimmas i kanten men slås inte ihop inuti (som JVM)', () {
      // Kotlin trim() tar bort U+00A0 i kanterna; JVM:s \s matchar inte U+00A0.
      expect(NoteContentHash.normalize(' Ta  med '),
          'ta  med');
    });
  });

  group('NoteEdit (Androids NoteEditTest)', () {
    const note = NoteModel(
      id: 'n1',
      text: 'Hämta badkarsbräda Vasagatan 3 före 15',
      visibility: NoteModel.visibilityFamily,
      aboutUids: ['a', 'b'],
    );

    test('samma text, synlighet och personer är ingen ändring', () {
      expect(
          NoteEdit.isUnchanged(note,
              text: note.text, isPrivate: false, aboutUids: ['a', 'b']),
          isTrue);
    });

    test('mellanslag runt texten och personernas ordning räknas inte', () {
      expect(
          NoteEdit.isUnchanged(note,
              text: '  ${note.text}\n', isPrivate: false, aboutUids: ['b', 'a']),
          isTrue);
    });

    test('ändrad text är en ändring', () {
      expect(
          NoteEdit.isUnchanged(note,
              text: 'Hämta badkarsbräda Vasagatan 5 före 15',
              isPrivate: false,
              aboutUids: ['a', 'b']),
          isFalse);
    });

    test('privat är en ändring', () {
      expect(
          NoteEdit.isUnchanged(note,
              text: note.text, isPrivate: true, aboutUids: ['a', 'b']),
          isFalse);
    });

    test('andra personer är en ändring', () {
      expect(
          NoteEdit.isUnchanged(note,
              text: note.text, isPrivate: false, aboutUids: ['a']),
          isFalse);
    });
  });

  group('NoteModel', () {
    test('fromMap: standardvärden, tolkning och länkar', () {
      final n = NoteModel.fromMap('n', {
        'familyId': 'f',
        'ownerUid': 'u',
        'text': 'Rad ett\nRad två',
        'status': 'needs_review',
        'interpretation': {
          'revision': 2.0,
          'question': '',
          'actions': [
            {'id': 'a1', 'type': 'create_task', 'title': 'Köp', 'payload': {}},
            {'type': 'info'}, // saknar id → tas bort
          ],
        },
        'linkedIds': [
          {'actionId': 'a1', 'type': 'task', 'targetId': 't1'},
          {'actionId': 'x', 'type': 'task'}, // saknar targetId → tas bort
        ],
      });
      expect(n.visibility, NoteModel.visibilityFamily);
      expect(n.needsReview, isTrue);
      expect(n.interpretation!.revision, 2);
      expect(n.interpretation!.question, isNull);
      expect(n.interpretation!.actions.single.id, 'a1');
      expect(n.linkedIds.single.targetId, 't1');
      expect(n.firstLine(), 'Rad ett');
    });

    test('fast tolkning efter fem minuter', () {
      final now = DateTime(2026, 9, 24, 12);
      final n = NoteModel(
        status: NoteModel.statusInterpreting,
        interpretingSince: now.subtract(const Duration(minutes: 6)),
      );
      expect(n.isStuck(now), isTrue);
      expect(NoteStatusMachine.requestBlockedReason(n, now), isNull);
      final busy = NoteModel(
        status: NoteModel.statusInterpreting,
        interpretingSince: now.subtract(const Duration(minutes: 1)),
      );
      expect(NoteStatusMachine.requestBlockedReason(busy, now),
          'Tolkningen pågår redan.');
    });

    test('coversDay följer giltigheten och borttagning', () {
      const n = NoteModel(validFrom: '2026-09-20', validTo: '2026-09-25');
      expect(n.coversDay('2026-09-19'), isFalse);
      expect(n.coversDay('2026-09-20'), isTrue);
      expect(n.coversDay('2026-09-25'), isTrue);
      expect(n.coversDay('2026-09-26'), isFalse);
      final gone = NoteModel(
          validFrom: '2026-09-20', deletedAt: DateTime(2026, 9, 21));
      expect(gone.coversDay('2026-09-22'), isFalse);
    });

    test('statustext som i Android', () {
      expect(noteStatusText(const NoteModel(status: 'failed')),
          'Tolkningen gick inte igenom.');
      expect(noteStatusText(const NoteModel(status: 'interpreting')),
          'Tolkas just nu…');
      expect(noteStatusText(const NoteModel(status: 'needs_review')),
          'Väntar på att du går igenom förslagen.');
      expect(
          noteStatusText(const NoteModel(status: 'confirmed', linkedIds: [
            NoteLink(actionId: 'a', type: 'task', targetId: 't'),
            NoteLink(actionId: 'b', type: 'event', targetId: 'e'),
          ])),
          'Behandlad. 2 saker skapades.');
      expect(noteStatusText(const NoteModel(status: 'confirmed')), 'Behandlad.');
    });

    test('mergeNotes: unika id och nyast först, väntande stämpel överst', () {
      final a = [
        NoteModel(id: '1', createdAt: DateTime(2026, 9, 1)),
        NoteModel(id: '2', createdAt: DateTime(2026, 9, 3)),
      ];
      final b = [
        NoteModel(id: '2', createdAt: DateTime(2026, 9, 3)),
        const NoteModel(id: '3'),
      ];
      expect(NoteService.mergeNotes(a, b).map((n) => n.id), ['3', '2', '1']);
    });
  });

  group('ConfirmResult', () {
    test('meddelande som i Android', () {
      final r = ConfirmResult.fromResponse({
        'applied': [
          {'actionId': 'a', 'targetId': 't'},
          {'actionId': 'b', 'targetId': 't2', 'alreadyDone': true},
        ],
        'skipped': [
          {'actionId': 'c', 'reason': 'Vem gäller det?'},
        ],
      });
      expect(r.summary().message, '1 sparade. 1 fanns redan. Vem gäller det?');
      expect(r.summary().isError, isFalse);
    });

    test('inget sparat är ett fel', () {
      final r = ConfirmResult.fromResponse({
        'applied': [],
        'skipped': [
          {'actionId': 'c'},
        ],
      });
      expect(r.summary().message, 'Förslaget kunde inte sparas.');
      expect(r.summary().isError, isTrue);
      expect(ConfirmResult.fromResponse('konstigt').summary().message,
          'Inget kunde sparas.');
    });
  });
}
