import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../app_theme.dart';
import '../data/hospital_menu.dart';
import '../models/user_model.dart';
import '../providers/family_provider.dart';
import '../screens/min_dag_page.dart';
import '../screens/verktyg_page.dart';
import '../utils/chore_utils.dart';
import '../utils/date_utils.dart';
import '../utils/day_events.dart';
import '../utils/layout.dart';
import '../utils/person_match.dart';
import '../utils/schedule_time_utils.dart';
import 'activity_detail_sheet.dart';
import 'meal_choice_sheet.dart';
import 'today_chores_sheet.dart';
import 'weather_widgets.dart';

/// Delad vy för "Min dag" — proportionell tidsaxel med vandrande NU-linje
/// för tidsorientering, minnesstöd och sjukhusmatsedel efter stroke.
/// Kan köras inbäddad i Hem-fliken (`embedded: true`) eller som helskärm (`embedded: false`).
class MinDagView extends StatefulWidget {
  final bool embedded;

  const MinDagView({
    super.key,
    this.embedded = false,
  });

  @override
  State<MinDagView> createState() => _MinDagViewState();
}

class _MinDagViewState extends State<MinDagView> with WidgetsBindingObserver {
  static const double hourHeight = 110.0;
  static const double gutterWidth = 56.0;
  static const Color nuMarkerColor = Color(0xFF2F3B45);

  Timer? _tickerTimer;
  DateTime _currentTime = DateTime.now();
  late DateTime _viewedDay;
  int _dayChangeDirection = 0; // -1 bakåt, +1 framåt, 0 initial/idag
  int _lastRenderedMinute = -1;
  int _lastRenderedHour = -1;

  final ScrollController _scrollController = ScrollController();
  bool _showReturnToNu = false;
  double _nuScrollTarget = 0.0;
  bool _hasInitialScrolled = false;

  bool get _isViewingToday {
    return _viewedDay.year == _currentTime.year &&
        _viewedDay.month == _currentTime.month &&
        _viewedDay.day == _currentTime.day;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentTime = DateTime.now();
    _viewedDay = DateTime(_currentTime.year, _currentTime.month, _currentTime.day);
    _lastRenderedMinute = _currentTime.minute;
    _lastRenderedHour = _currentTime.hour;

    // Ticker var 1 sekund — kör endast setState när minuten slår om
    _tickerTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now();
      if (now.minute != _lastRenderedMinute || now.hour != _lastRenderedHour) {
        if (mounted) {
          setState(() {
            final wasViewingToday = _isViewingToday;
            _currentTime = now;
            _lastRenderedMinute = now.minute;
            _lastRenderedHour = now.hour;
            if (wasViewingToday) {
              _viewedDay = DateTime(now.year, now.month, now.day);
            }
          });
        }
      }
    });

    _scrollController.addListener(_onScroll);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initialScroll();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tickerTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final now = DateTime.now();
      if (mounted) {
        setState(() {
          final wasViewingToday = _isViewingToday;
          _currentTime = now;
          _lastRenderedMinute = now.minute;
          _lastRenderedHour = now.hour;
          if (wasViewingToday) {
            _viewedDay = DateTime(now.year, now.month, now.day);
          }
        });
      }
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients || !_isViewingToday) return;
    final diff = (_scrollController.offset - _nuScrollTarget).abs();
    final shouldShow = diff > 200.0;
    if (shouldShow != _showReturnToNu) {
      setState(() {
        _showReturnToNu = shouldShow;
      });
    }
  }

  void _initialScroll() {
    if (!mounted || _hasInitialScrolled || !_scrollController.hasClients) return;
    if (_isViewingToday) {
      _scrollToNu(animated: false);
    }
    _hasInitialScrolled = true;
  }

  void _scrollToNu({bool animated = true}) {
    if (!_scrollController.hasClients) return;
    final target = _nuScrollTarget.clamp(0.0, _scrollController.position.maxScrollExtent);
    if (animated) {
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    } else {
      _scrollController.jumpTo(target);
    }
  }

  void _changeDay(int delta) {
    final target = _viewedDay.add(Duration(days: delta));
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = target.difference(today).inDays;
    if (diff < -365 || diff > 365) return;

    setState(() {
      _dayChangeDirection = delta;
      _viewedDay = DateTime(target.year, target.month, target.day);
      _showReturnToNu = false;
    });

    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0.0);
    }
  }

  void _goToToday() {
    setState(() {
      _dayChangeDirection = 0;
      _viewedDay = DateTime(_currentTime.year, _currentTime.month, _currentTime.day);
      _showReturnToNu = false;
    });
    if (_scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToNu(animated: true);
      });
    }
  }

  String _relativeDayLabel(DateTime viewed, DateTime now) {
    final v = DateTime(viewed.year, viewed.month, viewed.day);
    final t = DateTime(now.year, now.month, now.day);
    final diff = v.difference(t).inDays;
    if (diff == 0) return 'IDAG';
    if (diff == 1) return 'I MORGON';
    if (diff == -1) return 'IGÅR';
    if (diff > 1) return 'OM $diff DAGAR';
    return 'FÖR ${-diff} DAGAR SEDAN';
  }

  String _timeGreeting() {
    final hour = _currentTime.hour;
    if (hour >= 5 && hour < 10) return 'God morgon';
    if (hour >= 10 && hour < 12) return 'God förmiddag';
    if (hour >= 12 && hour < 18) return 'God eftermiddag';
    if (hour >= 18 && hour < 23) return 'God kväll';
    return 'God natt';
  }

  int _uncompletedChoresCount(FamilyProvider provider, UserModel? user) {
    final now = DateTime.now();
    final chores = provider.chores.where((doc) {
      final d = doc.data() as Map<String, dynamic>;
      if (!choreOccursOnDay(d, now)) return false;
      if (choreDoneOnDay(d, now)) return false;
      if (user != null) {
        return choreAssignedToOnDay(d, now, uid: user.uid, name: user.name);
      }
      return true;
    }).toList();
    return chores.length;
  }

  List<QueryDocumentSnapshot> _filterMyEvents(
    List<QueryDocumentSnapshot> rawEvents,
    UserModel? me,
  ) {
    if (me == null) return rawEvents;
    return rawEvents.where((doc) {
      final d = doc.data() as Map<String, dynamic>;
      if (eventHasNoPersons(d)) return true;
      return eventIncludesPerson(d, uid: me.uid, name: me.name);
    }).toList();
  }

  DateTime _computeEndTime(DateTime start, Map<String, dynamic> d) {
    final endTimeStr = (d['endTime'] as String? ?? '').trim();
    if (endTimeStr.isNotEmpty) {
      final parts = endTimeStr.split(':');
      if (parts.length >= 2) {
        final eh = int.tryParse(parts[0]);
        final em = int.tryParse(parts[1]);
        if (eh != null && em != null) {
          return DateTime(start.year, start.month, start.day, eh, em);
        }
      }
    }
    return start.add(const Duration(minutes: 60));
  }

  List<({String text, bool isDone})> _extractChecklist(dynamic raw) {
    if (raw is! List) return const [];
    final items = <({String text, bool isDone})>[];
    for (final entry in raw) {
      if (entry is Map) {
        final t = (entry['item'] ?? entry['text'] ?? '').toString().trim();
        final done = entry['isDone'] == true;
        if (t.isNotEmpty) items.add((text: t, isDone: done));
      } else if (entry is String && entry.trim().isNotEmpty) {
        items.add((text: entry.trim(), isDone: false));
      }
    }
    return items;
  }

  bool _isTodayOrFuture(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    return !target.isBefore(today);
  }

  void _openDetail(QueryDocumentSnapshot doc) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ActivityDetailSheet(docSnapshot: doc),
    );
  }

  void _showTransportSheet(
    BuildContext context,
    DocumentReference docRef,
    Map<String, dynamic> data,
    Color dayColor,
  ) {
    final title = data['title'] as String? ?? 'Aktivitet';
    final piktogram = data['piktogram'] as String? ?? '📅';
    final currentTransport = data['transport'] as String?;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return wrapBottomSheet(
          sheetContext,
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text(piktogram, style: const TextStyle(fontSize: 28)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Hur tar du dig dit?',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // Knapp 1: Jag tar mig dit själv
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    backgroundColor: currentTransport == 'sjalv'
                        ? nuMarkerColor.withValues(alpha: 0.15)
                        : const Color(0xFFF1F5F9),
                    foregroundColor: const Color(0xFF1E293B),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: currentTransport == 'sjalv'
                            ? nuMarkerColor
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  icon: const Text('🚶‍♀️', style: TextStyle(fontSize: 22)),
                  label: const Text(
                    'Jag tar mig dit själv',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  onPressed: () => _updateTransport(sheetContext, docRef, 'sjalv'),
                ),
                const SizedBox(height: 12),
                // Knapp 2: De hämtar mig
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    backgroundColor: currentTransport == 'hamtas'
                        ? nuMarkerColor.withValues(alpha: 0.15)
                        : const Color(0xFFF1F5F9),
                    foregroundColor: const Color(0xFF1E293B),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: currentTransport == 'hamtas'
                            ? nuMarkerColor
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  icon: const Text('🤝', style: TextStyle(fontSize: 22)),
                  label: const Text(
                    'De hämtar mig',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  onPressed: () => _updateTransport(sheetContext, docRef, 'hamtas'),
                ),
                if (currentTransport != null && currentTransport.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  // Knapp 3: Ta bort markering
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                      foregroundColor: Colors.red.shade700,
                      side: BorderSide(color: Colors.red.shade200),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: const Icon(Icons.clear_rounded, size: 20),
                    label: const Text(
                      'Ta bort markering',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () => _updateTransport(sheetContext, docRef, null),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _updateTransport(
    BuildContext sheetContext,
    DocumentReference docRef,
    String? transportValue,
  ) async {
    Navigator.pop(sheetContext);
    try {
      if (transportValue == null) {
        await docRef.update({'transport': FieldValue.delete()});
      } else {
        await docRef.update({'transport': transportValue});
      }
    } catch (e, st) {
      developer.log('Fel vid uppdatering av transport: $e', error: e, stackTrace: st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kunde inte spara transportval.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FamilyProvider>();
    final user = provider.currentUser;
    final familyId = user?.familyId ?? provider.currentUser?.familyId ?? '';

    final weekday = _viewedDay.weekday;
    final dayColor = AppTheme.getDayAccentColor(weekday);
    final isLowStimuli = AppTheme.lowStimuli;

    final viewedDateStr = dateKey(_viewedDay);
    final mealChoiceDocId = user != null ? '${user.uid}_$viewedDateStr' : null;

    final mealChoiceStream = mealChoiceDocId != null
        ? FirebaseFirestore.instance
            .collection('meal_choices')
            .doc(mealChoiceDocId)
            .snapshots()
        : null;

    final maxW = WindowSize.of(context).isExpanded
        ? WindowSize.settingsMaxWidth
        : 480.0;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: mealChoiceStream,
      builder: (context, mealSnapshot) {
        final mealData = mealSnapshot.data?.data();
        final lunchChoice = mealData?['lunch'] as Map<String, dynamic>?;
        final middagChoice = mealData?['middag'] as Map<String, dynamic>?;

        return StreamBuilder<QuerySnapshot>(
          stream: dayEventsStream(familyId: familyId, day: _viewedDay),
          builder: (context, eventSnapshot) {
            final dateEvents = eventSnapshot.data?.docs ?? const [];
            final recurringEvents = provider.recurringEvents;

            final mergedEvents = mergeAndDedupDayEvents(
              dateEvents: dateEvents,
              recurringEvents: recurringEvents,
              day: _viewedDay,
            );

            final myEvents = _filterMyEvents(mergedEvents, user);

            final timedItems = <_MinDagTimelineItem>[];
            final untimedEvents =
                <({QueryDocumentSnapshot doc, Map<String, dynamic> data})>[];

            bool hasLunchEvent = false;
            bool hasMiddagEvent = false;

            for (final doc in myEvents) {
              final d = doc.data() as Map<String, dynamic>;
              final parsed = parseDateTime(d);
              final timeStr = (d['time'] as String? ?? '').trim();
              if (parsed != null && timeStr.isNotEmpty) {
                final end = _computeEndTime(parsed, d);
                final titleLower =
                    (d['title'] as String? ?? '').toLowerCase().trim();
                final isLunch = titleLower.startsWith('lunch');
                final isMiddag = titleLower.startsWith('middag');

                if (isLunch) hasLunchEvent = true;
                if (isMiddag) hasMiddagEvent = true;

                timedItems.add(_MinDagTimelineItem(
                  doc: doc,
                  data: d,
                  start: parsed,
                  end: end,
                  mealType: isLunch ? 'lunch' : (isMiddag ? 'middag' : null),
                  mealChoice:
                      isLunch ? lunchChoice : (isMiddag ? middagChoice : null),
                  isSyntheticMeal: false,
                ));
              } else {
                untimedEvents.add((doc: doc, data: d));
              }
            }

            final isTodayOrFutureDay = _isTodayOrFuture(_viewedDay);

            if (!hasLunchEvent && (lunchChoice != null || isTodayOrFutureDay)) {
              final lunchStart = DateTime(
                  _viewedDay.year, _viewedDay.month, _viewedDay.day, 12, 0);
              final lunchEnd = DateTime(
                  _viewedDay.year, _viewedDay.month, _viewedDay.day, 12, 45);
              timedItems.add(_MinDagTimelineItem(
                doc: null,
                data: {
                  'title': 'Lunch',
                  'piktogram': '🍽️',
                  'time': '12:00',
                  'endTime': '12:45',
                },
                start: lunchStart,
                end: lunchEnd,
                mealType: 'lunch',
                mealChoice: lunchChoice,
                isSyntheticMeal: true,
              ));
            }

            if (!hasMiddagEvent &&
                (middagChoice != null || isTodayOrFutureDay)) {
              final middagStart = DateTime(
                  _viewedDay.year, _viewedDay.month, _viewedDay.day, 17, 0);
              final middagEnd = DateTime(
                  _viewedDay.year, _viewedDay.month, _viewedDay.day, 17, 45);
              timedItems.add(_MinDagTimelineItem(
                doc: null,
                data: {
                  'title': 'Middag',
                  'piktogram': '🍽️',
                  'time': '17:00',
                  'endTime': '17:45',
                },
                start: middagStart,
                end: middagEnd,
                mealType: 'middag',
                mealChoice: middagChoice,
                isSyntheticMeal: true,
              ));
            }

            // Sortera tidsatta poster kronologiskt
            timedItems.sort((a, b) => a.start.compareTo(b.start));

            // Axelns tidsspann
            int startHour = _isViewingToday ? min(7, _currentTime.hour) : 7;
            if (timedItems.isNotEmpty) {
              final firstH = timedItems.first.start.hour;
              if (firstH < startHour) startHour = firstH;
            }

            int endHour = _isViewingToday ? max(20, _currentTime.hour + 1) : 20;
            for (final ev in timedItems) {
              final h = ev.end.hour + (ev.end.minute > 0 ? 1 : 0) + 1;
              if (h > endHour) endHour = h;
            }
            if (endHour > 24) endHour = 24;

            final totalHours = max(1, endHour - startHour);
            final timelineHeight = totalHours * hourHeight;

            // Hitta index för nästa kommande (endast relevant idag)
            int? nextUpcomingIndex;
            if (_isViewingToday) {
              for (var i = 0; i < timedItems.length; i++) {
                final ev = timedItems[i];
                if (ev.start.isAfter(_currentTime)) {
                  nextUpcomingIndex = i;
                  break;
                }
              }
            }

            // Beräkna layoutplacering
            final layoutList = _computeLayout(
              timedItems,
              startHour,
              _currentTime,
              nextUpcomingIndex,
              isViewingToday: _isViewingToday,
            );

            // Beräkna position för NU-linjen (endast idag)
            final nuMinutes = (_currentTime.hour - startHour) * 60 +
                _currentTime.minute +
                (_currentTime.second / 60.0);
            final nuTop = (nuMinutes / 60.0) * hourHeight;

            final bottomPadding = widget.embedded
                ? (navSafeBottom(context).bottom + 24)
                : 60.0;

            return Scaffold(
              backgroundColor: isLowStimuli
                  ? const Color(0xFFF0F2F5)
                  : const Color(0xFFF5F7FA),
              floatingActionButton: (_showReturnToNu && _isViewingToday)
                  ? FloatingActionButton.extended(
                      backgroundColor: nuMarkerColor,
                      foregroundColor: Colors.white,
                      elevation: isLowStimuli ? 0 : 4,
                      icon: const Icon(Icons.my_location_rounded, size: 18),
                      label: const Text(
                        'NU',
                        style: TextStyle(
                            fontWeight: FontWeight.w900, letterSpacing: 0.5),
                      ),
                      onPressed: () => _scrollToNu(animated: true),
                    )
                  : null,
              body: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxW),
                  child: Column(
                    children: [
                      _buildHeader(context, provider, user, dayColor, weekday),
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onHorizontalDragEnd: (details) {
                            final vel = details.primaryVelocity;
                            if (vel != null && vel.abs() > 200) {
                              if (vel < 0) {
                                _changeDay(1);
                              } else {
                                _changeDay(-1);
                              }
                            }
                          },
                          child: AnimatedSwitcher(
                            duration: Duration(
                                milliseconds: isLowStimuli ? 150 : 200),
                            transitionBuilder: (child, animation) {
                              if (isLowStimuli) {
                                return FadeTransition(
                                    opacity: animation, child: child);
                              }
                              final beginOffset = _dayChangeDirection > 0
                                  ? const Offset(0.12, 0.0)
                                  : (_dayChangeDirection < 0
                                      ? const Offset(-0.12, 0.0)
                                      : Offset.zero);
                              return FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                          begin: beginOffset, end: Offset.zero)
                                      .animate(animation),
                                  child: child,
                                ),
                              );
                            },
                            child: KeyedSubtree(
                              key: ValueKey(dateKey(_viewedDay)),
                              child: Column(
                                children: [
                                  if (untimedEvents.isNotEmpty)
                                    _buildUntimedSection(
                                        untimedEvents, dayColor, user),
                                  if (timedItems.isEmpty &&
                                      untimedEvents.isEmpty)
                                    _buildEmptyDayBanner(),
                                  Expanded(
                                    child: LayoutBuilder(
                                      builder: (context, constraints) {
                                        final viewportHeight =
                                            constraints.maxHeight;
                                        if (_isViewingToday) {
                                          _nuScrollTarget = max(0.0,
                                              nuTop - (viewportHeight * 0.35));
                                        }

                                        return SingleChildScrollView(
                                          controller: _scrollController,
                                          physics:
                                              const BouncingScrollPhysics(),
                                          padding:
                                              EdgeInsets.only(bottom: bottomPadding),
                                          child: SizedBox(
                                            height: timelineHeight,
                                            width: constraints.maxWidth,
                                            child: Stack(
                                              clipBehavior: Clip.none,
                                              children: [
                                                // 1. Grid- och timlinjer med timetiketter
                                                _buildGridBackground(
                                                  startHour: startHour,
                                                  totalHours: totalHours,
                                                  isLowStimuli: isLowStimuli,
                                                  width: constraints.maxWidth,
                                                ),

                                                // 2. Händelseblock & Måltidsblock
                                                for (final layout in layoutList)
                                                  _buildPositionedEventCard(
                                                    layout: layout,
                                                    totalWidth:
                                                        constraints.maxWidth,
                                                    dayColor: dayColor,
                                                    isLowStimuli: isLowStimuli,
                                                    user: user,
                                                  ),

                                                // 3. Proportionell NU-linje (endast idag)
                                                if (_isViewingToday)
                                                  _buildPositionedNuLine(
                                                    nuTop: nuTop,
                                                    width: constraints.maxWidth,
                                                  ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildHeader(
    BuildContext context,
    FamilyProvider provider,
    UserModel? user,
    Color dayColor,
    int weekday,
  ) {
    final palette = AppTheme.dayPalette(weekday);
    final dateFormatted = DateFormat('EEEE d MMMM', 'sv').format(_viewedDay);
    final capitalizedDate = dateFormatted.isNotEmpty
        ? '${dateFormatted[0].toUpperCase()}${dateFormatted.substring(1)}'
        : dateFormatted;
    final relativeLabel = _relativeDayLabel(_viewedDay, _currentTime);
    final timeStr = DateFormat('HH:mm').format(_currentTime);
    final textColor = AppTheme.getNpfTextColor(weekday);
    final isLowStimuli = AppTheme.lowStimuli;
    final firstName = user?.name.split(' ').first ?? '';
    final hasWeather = provider.hasHomeLocation;
    final uncompletedChores = _uncompletedChoresCount(provider, user);

    return Container(
      decoration: isLowStimuli
          ? BoxDecoration(color: palette.base)
          : AppTheme.headerDecoration(weekday),
      padding: AppTheme.paddingBelowStatusBar(
        context,
        horizontal: 16,
        bottom: 14,
        extraBelowStatus: 4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top action bar
          Row(
            children: [
              if (!widget.embedded) ...[
                IconButton(
                  icon: Icon(Icons.close_rounded, color: textColor, size: 28),
                  padding: const EdgeInsets.all(12),
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  tooltip: 'Stäng Min dag',
                  onPressed: () => Navigator.pop(context),
                ),
                const Spacer(),
              ] else ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('🧭', style: TextStyle(fontSize: 13)),
                      const SizedBox(width: 5),
                      Text(
                        'MIN DAG',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                          color: textColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                if (hasWeather) ...[
                  WeatherHeaderBadge(
                    lat: provider.homeLat!,
                    lon: provider.homeLon!,
                    placeName: provider.homeName,
                    textColor: textColor,
                  ),
                  const SizedBox(width: 4),
                ],
                IconButton(
                  icon: const Text('🧰', style: TextStyle(fontSize: 18)),
                  tooltip: 'Verktyg',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const VerktygPage()),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.fullscreen_rounded, color: textColor, size: 26),
                  tooltip: 'Helskärm',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      fullscreenDialog: true,
                      builder: (_) => const MinDagPage(),
                    ),
                  ),
                ),
              ],
              if (!widget.embedded)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('🧭', style: TextStyle(fontSize: 14)),
                      const SizedBox(width: 6),
                      Text(
                        'MIN DAG',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                          color: textColor,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Dagsnavigator med ‹ och ›
                Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.chevron_left_rounded,
                          color: textColor, size: 32),
                      padding: const EdgeInsets.all(8),
                      constraints:
                          const BoxConstraints(minWidth: 48, minHeight: 48),
                      tooltip: 'Föregående dag',
                      onPressed: () => _changeDay(-1),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            capitalizedDate,
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              color: textColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            relativeLabel,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.8,
                              color: textColor.withValues(alpha: 0.85),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!_isViewingToday) ...[
                      GestureDetector(
                        onTap: _goToToday,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: textColor.withValues(alpha: 0.4),
                              width: 1.5,
                            ),
                          ),
                          child: Text(
                            'Idag',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: textColor,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                    IconButton(
                      icon: Icon(Icons.chevron_right_rounded,
                          color: textColor, size: 32),
                      padding: const EdgeInsets.all(8),
                      constraints:
                          const BoxConstraints(minWidth: 48, minHeight: 48),
                      tooltip: 'Nästa dag',
                      onPressed: () => _changeDay(1),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                // Klockan ljuger aldrig: alltid verklig nutid
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Semantics(
                    label: 'Klockan är $timeStr',
                    child: Text(
                      timeStr,
                      style: TextStyle(
                        fontSize: 44,
                        fontWeight: FontWeight.w900,
                        color: textColor,
                        letterSpacing: -1.0,
                      ),
                    ),
                  ),
                ),
                if (widget.embedded) ...[
                  if (firstName.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        '${_timeGreeting()}, $firstName 👋',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: textColor.withValues(alpha: 0.95),
                        ),
                      ),
                    ),
                  ],
                  if (uncompletedChores > 0) ...[
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () => showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (_) => TodayChoresSheet(
                              onlyAssignedTo: user?.name,
                              onlyAssignedToUid: user?.uid,
                            ),
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: textColor.withValues(alpha: 0.35),
                                width: 1.2,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('✅', style: TextStyle(fontSize: 13)),
                                const SizedBox(width: 6),
                                Text(
                                  '$uncompletedChores ${uncompletedChores == 1 ? 'syssla' : 'sysslor'} idag',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: textColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyDayBanner() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isFuture = _viewedDay.isAfter(today);
    final isPast = _viewedDay.isBefore(today);

    String title;
    String sub;
    if (_isViewingToday) {
      title = 'Inget inplanerat idag 😌';
      sub = 'Tidsaxeln visar ändå var på dagen du befinner dig.';
    } else if (isFuture) {
      title = 'Inget inplanerat 🎈';
      sub = 'Det finns inga schemalagda aktiviteter denna dag.';
    } else {
      title = 'Inget låg på schemat denna dag';
      sub = 'Inga aktiviteter sparades för detta datum.';
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Text(isPast ? '📅' : '😌', style: const TextStyle(fontSize: 26)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Text(
                  sub,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUntimedSection(
    List<({QueryDocumentSnapshot doc, Map<String, dynamic> data})> items,
    Color dayColor,
    UserModel? user,
  ) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.event_note_rounded, size: 16, color: Colors.grey.shade600),
              const SizedBox(width: 6),
              Text(
                'Utan tid',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: items.map((item) {
              final d = item.data;
              final title = d['title'] as String? ?? 'Aktivitet';
              final piktogram = d['piktogram'] as String? ?? '📅';
              final transport = d['transport'] as String?;
              final transportPrefix = transport == 'sjalv'
                  ? '🚶‍♀️ '
                  : (transport == 'hamtas' ? '🤝 ' : '');

              final canEdit = user != null &&
                  (user.isParent ||
                      eventIncludesPerson(d, uid: user.uid, name: user.name) ||
                      eventHasNoPersons(d));

              return ActionChip(
                avatar: Text(piktogram, style: const TextStyle(fontSize: 16)),
                label: Text(
                  '$transportPrefix$title',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                backgroundColor: Colors.grey.shade50,
                side: BorderSide(color: Colors.grey.shade300),
                onPressed: () {
                  if (_isViewingToday && canEdit) {
                    _showTransportSheet(context, item.doc.reference, d, dayColor);
                  } else {
                    _openDetail(item.doc);
                  }
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildGridBackground({
    required int startHour,
    required int totalHours,
    required bool isLowStimuli,
    required double width,
  }) {
    final lineAlpha = isLowStimuli ? 0.10 : 0.18;
    return Stack(
      children: [
        for (var i = 0; i <= totalHours; i++) ...[
          // Timetikett i vänster gutter
          Positioned(
            top: i * hourHeight - 8,
            left: 8,
            width: gutterWidth - 12,
            child: Text(
              '${(startHour + i).toString().padLeft(2, '0')}:00',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          // Horisontell gridlinje över hela bredden
          Positioned(
            top: i * hourHeight,
            left: gutterWidth,
            right: 0,
            child: Container(
              height: 1,
              color: Colors.grey.withValues(alpha: lineAlpha),
            ),
          ),
        ],
        // Vertikal avgränsningslinje efter gutter
        Positioned(
          top: 0,
          bottom: 0,
          left: gutterWidth,
          child: Container(
            width: 1,
            color: Colors.grey.withValues(alpha: lineAlpha),
          ),
        ),
      ],
    );
  }

  Widget _buildPositionedEventCard({
    required _EventLayoutInfo layout,
    required double totalWidth,
    required Color dayColor,
    required bool isLowStimuli,
    required UserModel? user,
  }) {
    final item = layout.item;
    final d = item.data;
    final isMeal = item.mealType != null;
    final mealType = item.mealType;
    final mealChoice = item.mealChoice;

    final rawTitle = d['title'] as String? ?? 'Aktivitet';
    final piktogram = isMeal ? '🍽️' : (d['piktogram'] as String? ?? '📅');
    final timeStr = DateFormat('HH:mm').format(item.start);
    final endTimeStr = (d['endTime'] as String? ?? '').trim();
    final String timeRange;
    if (endTimeStr.isNotEmpty) {
      final dur = durationLabelHm(timeStr, endTimeStr);
      timeRange = dur.isEmpty
          ? '$timeStr–$endTimeStr'
          : '$timeStr–$endTimeStr · $dur';
    } else {
      timeRange = timeStr;
    }
    final checklist = _extractChecklist(d['checklist']);
    final transport = d['transport'] as String?;

    // Måltidsformatering
    String displayTitle = rawTitle;
    String? mealExtras;
    bool hasMealChoice = false;

    if (isMeal) {
      final mealLabel = mealType == 'lunch' ? 'Lunch' : 'Middag';
      if (mealChoice != null && mealChoice['dishId'] != null) {
        hasMealChoice = true;
        final formatted = formatHospitalMealChoice(mealChoice, mealLabel: mealLabel);
        displayTitle = formatted.mainTitle;
        mealExtras = formatted.extras;
      } else {
        if (item.isSyntheticMeal) {
          displayTitle = _isTodayOrFuture(_viewedDay)
              ? '$mealLabel — tryck för att välja'
              : mealLabel;
        } else {
          displayTitle = rawTitle;
          if (_isTodayOrFuture(_viewedDay)) {
            mealExtras = 'Tryck för att välja mat 🍽️';
          }
        }
      }
    }

    // Kolumnplacering (max 3 kolumner)
    final availableWidth = totalWidth - gutterWidth - 16;
    const colSpacing = 6.0;
    final colWidth = (availableWidth - (layout.totalCols - 1) * colSpacing) / layout.totalCols;
    final left = gutterWidth + 8 + layout.colIndex * (colWidth + colSpacing);

    final isOngoing = layout.isOngoing;
    final isPassed = layout.isPassed;
    final isNext = layout.isNext;

    final canEdit = user != null &&
        (user.isParent ||
            eventIncludesPerson(d, uid: user.uid, name: user.name) ||
            eventHasNoPersons(d));

    VoidCallback? onTap;
    if (isMeal) {
      if (_isTodayOrFuture(_viewedDay)) {
        onTap = () {
          showMealChoiceSheet(
            context,
            date: _viewedDay,
            meal: mealType!,
            familyId: user?.familyId ?? '',
            personUid: user?.uid ?? '',
            initialChoice: mealChoice,
          );
        };
      }
    } else if (_isViewingToday && !isPassed && canEdit && item.doc != null) {
      onTap = () => _showTransportSheet(
            context,
            item.doc!.reference,
            d,
            dayColor,
          );
    } else if (item.doc != null) {
      onTap = () => _openDetail(item.doc!);
    }

    // Transportchip-text
    String? transportText;
    if (transport == 'sjalv') {
      transportText = isNext ? '🚶‍♀️ Ta dig dit själv' : '🚶‍♀️ Själv';
    } else if (transport == 'hamtas') {
      transportText = isNext ? '🤝 De hämtar mig' : '🤝 Hämtas';
    }

    return Positioned(
      top: layout.top,
      left: left,
      width: max(80.0, colWidth),
      height: layout.height,
      child: Opacity(
        opacity: isPassed ? 0.45 : 1.0,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: isOngoing
                    ? Colors.white
                    : (isPassed
                        ? Colors.grey.shade100
                        : (isMeal && !hasMealChoice
                            ? const Color(0xFFFBFBFC)
                            : Colors.white)),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isOngoing
                      ? nuMarkerColor
                      : (isNext
                          ? dayColor.withValues(alpha: 0.6)
                          : (isPassed
                              ? Colors.grey.shade300
                              : (isMeal && !hasMealChoice
                                  ? Colors.grey.shade300
                                  : Colors.grey.shade200))),
                  width: isOngoing ? 2.5 : (isNext ? 1.5 : 1.0),
                ),
                boxShadow: isLowStimuli || isPassed
                    ? null
                    : [
                        BoxShadow(
                          color: isOngoing
                              ? nuMarkerColor.withValues(alpha: 0.15)
                              : Colors.black.withValues(alpha: 0.04),
                          blurRadius: isOngoing ? 8 : 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Rad 1: Piktogram + Tid + NU/NÄSTA-brickor
                  Row(
                    children: [
                      Text(piktogram, style: const TextStyle(fontSize: 16)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          timeRange,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isOngoing
                                ? nuMarkerColor
                                : (isPassed
                                    ? Colors.grey.shade600
                                    : Colors.grey.shade800),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isOngoing)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: nuMarkerColor,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'NU',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                          ),
                        )
                      else if (isNext)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: dayColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'NÄSTA',
                            style: TextStyle(
                              color: dayColor,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Rad 2: Titel
                  Text(
                    displayTitle,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight:
                          isOngoing ? FontWeight.w800 : FontWeight.w600,
                      color: isPassed
                          ? Colors.grey.shade700
                          : AppTheme.getTextColor(),
                    ),
                    maxLines: layout.height > 85 ? 3 : 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  // Måltidsextras (tillbehör/dessert/dryck)
                  if (mealExtras != null && layout.height > 65) ...[
                    const SizedBox(height: 2),
                    Text(
                      mealExtras,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: hasMealChoice
                            ? Colors.grey.shade700
                            : dayColor,
                        fontWeight: hasMealChoice
                            ? FontWeight.normal
                            : FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  // Transportchip
                  if (transportText != null && layout.height > 75) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        transportText,
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF334155),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  // Checklista (om ryms)
                  if (checklist.isNotEmpty && layout.height > 95) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.checklist_rounded,
                            size: 13, color: Colors.grey.shade600),
                        const SizedBox(width: 4),
                        Text(
                          '${checklist.where((c) => c.isDone).length}/${checklist.length}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPositionedNuLine({
    required double nuTop,
    required double width,
  }) {
    return Positioned(
      top: nuTop - 10,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: SizedBox(
          height: 20,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              // Horisontell NU-linje
              Positioned(
                left: gutterWidth,
                right: 0,
                child: Container(
                  height: 2.5,
                  color: nuMarkerColor,
                ),
              ),
              // Vänster NU-bricka (ligger i gutter)
              Positioned(
                left: 6,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: nuMarkerColor,
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: const Text(
                    'NU',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ),
              // Höger röd/mörk cirkel-indikator vid tidsaxeln
              Positioned(
                left: gutterWidth - 5,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: nuMarkerColor,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<_EventLayoutInfo> _computeLayout(
    List<_MinDagTimelineItem> items,
    int startHour,
    DateTime now,
    int? nextUpcomingIndex, {
    required bool isViewingToday,
  }) {
    final list = <_EventLayoutInfo>[];

    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final startMin = (item.start.hour - startHour) * 60 + item.start.minute;
      final endMin = (item.end.hour - startHour) * 60 + item.end.minute;
      final durationMin = max(30, endMin - startMin);

      final top = (startMin / 60.0) * hourHeight;
      final height = max(55.0, (durationMin / 60.0) * hourHeight - 4.0);

      final isOngoing = isViewingToday &&
          !now.isBefore(item.start) &&
          now.isBefore(item.end);
      final isPassed = isViewingToday && !now.isBefore(item.end);
      final isNext = isViewingToday && i == nextUpcomingIndex;

      list.add(_EventLayoutInfo(
        item: item,
        top: top,
        height: height,
        isPassed: isPassed,
        isOngoing: isOngoing,
        isNext: isNext,
      ));
    }

    // Klusterberäkning för överlappande händelser (max 3 kolumner)
    var clusterStart = 0;
    while (clusterStart < list.length) {
      var clusterEnd = clusterStart + 1;
      var clusterMaxBottom = list[clusterStart].top + list[clusterStart].height;

      while (clusterEnd < list.length &&
          list[clusterEnd].top < clusterMaxBottom) {
        clusterMaxBottom =
            max(clusterMaxBottom, list[clusterEnd].top + list[clusterEnd].height);
        clusterEnd++;
      }

      final colEnds = <double>[];
      for (var i = clusterStart; i < clusterEnd; i++) {
        final ev = list[i];
        int assignedCol = -1;
        for (var c = 0; c < colEnds.length && c < 3; c++) {
          if (colEnds[c] <= ev.top) {
            assignedCol = c;
            colEnds[c] = ev.top + ev.height;
            break;
          }
        }
        if (assignedCol == -1) {
          if (colEnds.length < 3) {
            assignedCol = colEnds.length;
            colEnds.add(ev.top + ev.height);
          } else {
            var minCol = 0;
            for (var c = 1; c < 3; c++) {
              if (colEnds[c] < colEnds[minCol]) minCol = c;
            }
            assignedCol = minCol;
            colEnds[minCol] = max(colEnds[minCol], ev.top + ev.height);
          }
        }
        ev.colIndex = assignedCol;
      }

      final numCols = min(3, max(1, colEnds.length));
      for (var i = clusterStart; i < clusterEnd; i++) {
        list[i].totalCols = numCols;
      }

      clusterStart = clusterEnd;
    }

    return list;
  }
}

class _MinDagTimelineItem {
  final QueryDocumentSnapshot? doc;
  final Map<String, dynamic> data;
  final DateTime start;
  final DateTime end;
  final String? mealType; // 'lunch' | 'middag'
  final Map<String, dynamic>? mealChoice;
  final bool isSyntheticMeal;

  _MinDagTimelineItem({
    this.doc,
    required this.data,
    required this.start,
    required this.end,
    this.mealType,
    this.mealChoice,
    this.isSyntheticMeal = false,
  });
}

class _EventLayoutInfo {
  final _MinDagTimelineItem item;
  final double top;
  final double height;
  final bool isPassed;
  final bool isOngoing;
  final bool isNext;
  int colIndex = 0;
  int totalCols = 1;

  _EventLayoutInfo({
    required this.item,
    required this.top,
    required this.height,
    required this.isPassed,
    required this.isOngoing,
    required this.isNext,
  });
}
