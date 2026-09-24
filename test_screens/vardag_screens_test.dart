// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_familia/app_theme.dart';
import 'package:la_familia/models/note_model.dart';
import 'package:la_familia/models/task_model.dart';
import 'package:la_familia/models/user_model.dart';
import 'package:la_familia/providers/family_provider.dart';
import 'package:la_familia/screens/inbox_page.dart';
import 'package:la_familia/screens/tasks_page.dart';
import 'package:la_familia/theme/app_colors.dart';
import 'package:la_familia/widgets/add_event_sheet.dart';
import 'package:la_familia/widgets/mer_sections.dart';
import 'package:la_familia/widgets/tomorrow_overview_section.dart';
import 'package:la_familia/screens/aterkommande_page.dart';
import 'package:la_familia/widgets/vardag_header.dart';
import 'package:provider/provider.dart';

import 'screen_harness.dart';

UserModel _u(String uid, String name, String role) => UserModel(
    uid: uid,
    name: name,
    email: '$uid@test',
    color: 'ff2A6F97',
    role: role,
    viewMode: role,
    energy: 3,
    familyId: 'f1');

final _members = [
  _u('p1', 'Anna Test', 'parent'),
  _u('p2', 'Bo Test', 'parent'),
  _u('c1', 'Cia Test', 'child'),
  _u('y1', 'Dan Test', 'youth'),
];

FamilyProvider _provider() => FamilyProvider.fixed(
      currentUser: _members.first,
      members: _members,
      tasks: [
        const TaskModel(
            id: 't1', familyId: 'f1', title: 'Boka tandläkare', dueDate: '2026-09-20',
            assigneeUid: 'p1'),
        const TaskModel(
            id: 't2', familyId: 'f1', title: 'Köp present till kalaset',
            dueDate: '2026-09-27', dueTime: '17:00', hasTime: true),
        const TaskModel(
            id: 't3', familyId: 'f1', title: 'Packa gympapåse', eventId: 'e1',
            occurrenceDate: '2026-09-26'),
        TaskModel(
            id: 't4', familyId: 'f1', title: 'Ringa skolan', status: 'done',
            doneAt: DateTime(2026, 9, 22)),
      ],
      notes: [
        NoteModel(
          id: 'n1',
          familyId: 'f1',
          ownerUid: 'p1',
          text: 'Veckobrev v39\nUtflykt torsdag, ta med matsäck.\nFotografering fredag.',
          status: NoteModel.statusNeedsReview,
          createdAt: DateTime(2026, 9, 24, 8, 12),
          interpretation: const NoteInterpretation(revision: 1, actions: [
            NoteAction(id: 'a1', type: 'create_event', title: 'Utflykt',
                summary: 'Torsdag 26 sep'),
            NoteAction(id: 'a2', type: 'add_checklist_item', title: 'Matsäck',
                blockedReason: 'Hittade ingen aktivitet som stämmer.'),
            NoteAction(id: 'a3', type: 'info', title: 'Fotografering fredag'),
          ]),
        ),
        NoteModel(
          id: 'n2', familyId: 'f1', ownerUid: 'p1', visibility: 'private',
          text: 'Hämta badkarsbräda Vasagatan 3 före 15',
          status: NoteModel.statusFailed, createdAt: DateTime(2026, 9, 23, 18),
        ),
        NoteModel(
          id: 'n3', familyId: 'f1', ownerUid: 'p2',
          text: 'Tandläkare Cia 3 okt kl 9', status: NoteModel.statusConfirmed,
          createdAt: DateTime(2026, 9, 22, 12),
          linkedIds: const [NoteLink(actionId: 'x', type: 'event', targetId: 'e9')],
        ),
      ],
    );

Widget _withProvider(Widget child) => ChangeNotifierProvider<FamilyProvider>.value(
    value: _provider(), child: screenApp(child));

Widget _merMock() => Builder(builder: (context) {
      final c = AppTheme.colors();
      return Scaffold(
        backgroundColor: c.pageBackground,
        body: ListView(padding: EdgeInsets.zero, children: const [
          VardagTitleHeader(title: 'Mer'),
          MerSections(isParent: true),
          VardagSectionLabel('INSTÄLLNINGAR',
              padding: EdgeInsets.fromLTRB(20, 24, 20, 0)),
        ]),
      );
    });

void main() {
  setUpAll(loadAppFonts);

  for (final weekday in [1, 4, 5]) {
    testWidgets('Mer, veckodag $weekday', (tester) async {
      AppTheme.colorMode = ColorMode.weekday;
      AppTheme.lowStimuli = false;
      AppTheme.weekdayOverride = weekday;
      await snap(tester, 'mer_dag$weekday', _withProvider(_merMock()));
      AppTheme.weekdayOverride = null;
    });
  }

  testWidgets('Mer, lågstimuli och neutral', (tester) async {
    AppTheme.lowStimuli = true;
    await snap(tester, 'mer_lagstimuli', _withProvider(_merMock()));
    AppTheme.lowStimuli = false;
    AppTheme.colorMode = ColorMode.neutral;
    await snap(tester, 'mer_neutral', _withProvider(_merMock()));
    AppTheme.colorMode = ColorMode.weekday;
  });

  testWidgets('Uppgifter', (tester) async {
    await snap(tester, 'uppgifter', _withProvider(const TasksPage()));
    await snap(tester, 'uppgifter_stortext', _withProvider(const TasksPage()),
        textScale: 1.6);
  });

  testWidgets('Aktivitetsformulär', (tester) async {
    await snap(
        tester,
        'formular_ny',
        _withProvider(Scaffold(
          backgroundColor: Colors.black54,
          body: Align(
            alignment: Alignment.bottomCenter,
            child: AddEventSheet(
              selectedDay: DateTime(2026, 9, 25),
              familyMembers: _members,
              familyId: 'f1',
              initialTitle: 'Fotboll',
              initialTime: '17:00',
              initialPersonUids: const ['c1'],
            ),
          ),
        )));
  });

  testWidgets('Inför i morgon', (tester) async {
    final p = FamilyProvider.fixed(
      currentUser: _u('p1', 'Anna Test', 'parent').copyWith(familyId: ''),
      members: _members,
      tasks: [
        const TaskModel(
            id: 't1', familyId: 'f1', title: 'Boka tandläkare',
            dueDate: '2026-09-24', assigneeUid: 'p1'),
        const TaskModel(
            id: 't2', familyId: 'f1', title: 'Köp present till kalaset',
            dueDate: '2026-09-26', dueTime: '17:00', hasTime: true),
      ],
      notes: [
        NoteModel(
          id: 'n1', familyId: 'f1', ownerUid: 'p1',
          text: 'Veckobrev v39', status: NoteModel.statusNeedsReview,
          createdAt: DateTime(2026, 9, 24, 8),
        ),
        NoteModel(
          id: 'n2', familyId: 'f1', ownerUid: 'p1',
          text: 'Info om fotografering', status: NoteModel.statusConfirmed,
          validFrom: '2026-09-25', validTo: '2026-09-27',
          interpretation: const NoteInterpretation(revision: 1, actions: [
            NoteAction(id: 'i', type: 'info', title: 'Skolfotografering fredag'),
          ]),
        ),
      ],
    );
    await snap(
        tester,
        'infor_i_morgon',
        ChangeNotifierProvider<FamilyProvider>.value(
          value: p,
          child: screenApp(Scaffold(
            backgroundColor: AppTheme.colors().pageBackground,
            body: ListView(children: [
              TomorrowOverviewSection(now: DateTime(2026, 9, 25, 19, 0)),
            ]),
          )),
        ));
  });

  testWidgets('Återkommande (tom)', (tester) async {
    await snap(tester, 'aterkommande_tom', _withProvider(const AterkommandePage()));
  });

  testWidgets('Inkorg', (tester) async {
    await snap(tester, 'inkorg', _withProvider(const InboxPage()));
    await snap(tester, 'inkorg_bred', _withProvider(const InboxPage()),
        size: const Size(1000, 800));
  });
}
