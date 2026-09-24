import 'package:flutter/material.dart';

import '../screens/aterkommande_page.dart';
import '../screens/calendar_import_page.dart';
import '../screens/inbox_page.dart';
import '../screens/lathund_page.dart';
import '../screens/manage_routines_page.dart';
import '../screens/meal_planner_page.dart';
import '../screens/schedule_scan_page.dart';
import '../screens/shopping_list_page.dart';
import '../screens/staddag_page.dart';
import '../screens/tasks_page.dart';
import '../screens/timer_page.dart';
import '../screens/vardagsplan_page.dart';
import '../screens/work_schedule_page.dart';

/// Undersidor under fliken Mer (Androids `ToolsRoutes`).
enum MerRoute {
  aterkommande,
  tasks,
  inbox,
  timer,
  shopping,
  meals,
  lathund,
  workSchedule,
  vardagsplan,
  scheduleScan,
  calendarImport,
  routines,
}

/// Mål för Kalender-fliken: visa [day] och, om angivet, öppna aktiviteten.
class CalendarTarget {
  final DateTime day;
  final String? eventId;
  const CalendarTarget(this.day, {this.eventId});
}

/// Gemensam navigation mellan huvudflikarna (Hem · Kalender · Sysslor · Mer).
///
/// Genvägar byter till rätt flik och öppnar undersidan där, i stället för att
/// lägga en konkurrerande kopia av en huvudvy ovanpå den flik man stod i.
/// Tillbaka från undersidan landar därför i rätt flik.
class AppNavigation {
  AppNavigation._();

  static const tabHem = 0;
  static const tabKalender = 1;
  static const tabSysslor = 2;
  static const tabMer = 3;

  /// Vald huvudflik. `MainPage` lyssnar och bläddrar till fliken.
  static final ValueNotifier<int> tab = ValueNotifier<int>(tabHem);

  /// Sätts när något vill visa ett datum/en aktivitet i Kalender-fliken.
  /// Kalendern läser av och nollställer värdet.
  static final ValueNotifier<CalendarTarget?> calendarTarget =
      ValueNotifier<CalendarTarget?>(null);

  /// Sant medan flikvyn (`MainPage`) finns. I fokus-/barnläge utan flikfält
  /// öppnas undersidor direkt ovanpå den vy man står i.
  static bool tabsAvailable = false;

  static Widget pageFor(MerRoute route, {bool composeNote = false}) {
    switch (route) {
      case MerRoute.aterkommande:
        return const AterkommandePage();
      case MerRoute.tasks:
        return const TasksPage();
      case MerRoute.inbox:
        return InboxPage(openCompose: composeNote);
      case MerRoute.timer:
        return const TimerPage();
      case MerRoute.shopping:
        return const ShoppingListPage();
      case MerRoute.meals:
        return const MealPlannerPage();
      case MerRoute.lathund:
        return const LathundPage();
      case MerRoute.workSchedule:
        return const WorkSchedulePage();
      case MerRoute.vardagsplan:
        return const VardagsplanPage();
      case MerRoute.scheduleScan:
        return const ScheduleScanPage();
      case MerRoute.calendarImport:
        return const CalendarImportPage();
      case MerRoute.routines:
        return const ManageRoutinesPage();
    }
  }

  /// Lämna eventuella undersidor och gå till fliken [index].
  static void goToTab(BuildContext context, int index) {
    if (tabsAvailable) {
      Navigator.of(context, rootNavigator: true)
          .popUntil((r) => r.isFirst);
    }
    tab.value = index;
  }

  /// Öppna [route] under Mer. Från en annan flik byts först fliken till Mer.
  static Future<void> openInMer(
    BuildContext context,
    MerRoute route, {
    bool composeNote = false,
  }) async {
    final nav = Navigator.of(context, rootNavigator: true);
    if (tabsAvailable) {
      nav.popUntil((r) => r.isFirst);
      tab.value = tabMer;
    }
    await nav.push(MaterialPageRoute<void>(
      builder: (_) => pageFor(route, composeNote: composeNote),
    ));
  }

  /// Städdag hör till Sysslor.
  static Future<void> openStaddag(BuildContext context) async {
    final nav = Navigator.of(context, rootNavigator: true);
    if (tabsAvailable) {
      nav.popUntil((r) => r.isFirst);
      tab.value = tabSysslor;
    }
    await nav.push(MaterialPageRoute<void>(builder: (_) => const StaddagPage()));
  }

  /// Visa [day] (och ev. aktiviteten [eventId]) i den riktiga Kalender-fliken.
  static void showInCalendar(BuildContext context, DateTime day,
      {String? eventId}) {
    if (!tabsAvailable) return;
    Navigator.of(context, rootNavigator: true).popUntil((r) => r.isFirst);
    tab.value = tabKalender;
    calendarTarget.value = CalendarTarget(day, eventId: eventId);
  }
}
