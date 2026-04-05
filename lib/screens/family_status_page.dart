import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../models/user_model.dart';
import '../services/family_service.dart';

class FamilyStatusPage extends StatefulWidget {
  const FamilyStatusPage({super.key});
  @override
  State<FamilyStatusPage> createState() => _FamilyStatusPageState();
}

class _FamilyStatusPageState extends State<FamilyStatusPage> {
  List<UserModel> _members = [];
  Map<String, List<QueryDocumentSnapshot>> _memberEvents = {};
  bool _loading = true;

  late final Stream<List<UserModel>> _familyStream;

  @override
  void initState() {
    super.initState();
    _familyStream = FamilyService.getCurrentFamilyStream();
    _loadData();
  }

  DateTime? _parseDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is String) {
      final p = v.split('-');
      if (p.length >= 3) return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
    }
    return null;
  }

  DateTime? _parseDateTime(Map<String, dynamic> d) {
    final base = _parseDate(d['date']);
    if (base == null) return null;
    final timeStr = d['time'] as String? ?? '';
    if (timeStr.isNotEmpty) {
      final tp = timeStr.split(':');
      if (tp.length >= 2) {
        return DateTime(base.year, base.month, base.day, int.parse(tp[0]), int.parse(tp[1]));
      }
    }
    return base;
  }

  Future<void> _loadData() async {
    try {
      final currentUser = await FamilyService.getCurrentUserModel();
      final familyId = currentUser?.familyId;

      final members = await _familyStream.first
          .timeout(const Duration(seconds: 6), onTimeout: () => []);
      if (!mounted) return;

      final now = DateTime.now();
      // Använd samma sträng-format som när vi sparar eventen!
      final todayStr = '${now.year}-${now.month}-${now.day}';

      final Map<String, List<QueryDocumentSnapshot>> eventsMap = {};
      if (familyId != null && familyId.isNotEmpty) {
        for (final m in members) {
          try {
            final snap = await FirebaseFirestore.instance
                .collection('planner_events')
                .where('familyId', isEqualTo: familyId) // <--- HÄR LÄCKTE DATAN
                .where('date', isEqualTo: todayStr)
                .get()
                .timeout(const Duration(seconds: 5));
            
            eventsMap[m.uid] = snap.docs.where((doc) {
              final persons = ((doc.data())['persons'] as List? ?? []).cast<String>();
              return persons.contains(m.name);
            }).toList();
          } catch (_) {
            eventsMap[m.uid] = [];
          }
        }
      }

      if (mounted) {
        setState(() {
          _members = members;
          _memberEvents = eventsMap;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('FamilyStatusPage error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  _MemberStatus _getStatus(UserModel m) {
    final now = DateTime.now();
    final events = _memberEvents[m.uid] ?? [];
    for (final doc in events) {
      final d = doc.data() as Map<String, dynamic>;
      final start = _parseDateTime(d);
      if (start == null) continue;
      final end = start.add(const Duration(hours: 1));
      final title = (d['title'] as String? ?? '').toLowerCase();

      if (start.isBefore(now) && end.isAfter(now)) {
        if (title.contains('möte') || title.contains('outlook')) {
          return _MemberStatus.busy;
        }
        if (title.contains('skola') || title.contains('hemvård') || title.contains('jobb')) {
          return _MemberStatus.canReply;
        }
        return _MemberStatus.canReply;
      }
    }
    return _MemberStatus.free;
  }

  QueryDocumentSnapshot? _getCurrentEvent(UserModel m) {
    final now = DateTime.now();
    final events = _memberEvents[m.uid] ?? [];
    for (final doc in events) {
      final d = doc.data() as Map<String, dynamic>;
      final start = _parseDateTime(d);
      if (start == null) continue;
      final end = start.add(const Duration(hours: 1));
      if (start.isBefore(now) && end.isAfter(now)) return doc;
    }
    for (final doc in events) {
      final d = doc.data() as Map<String, dynamic>;
      final start = _parseDateTime(d);
      if (start != null && start.isAfter(now)) return doc;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final dayColor = AppTheme.getDayAccentColor();
    final textColor = AppTheme.getNpfTextColor(DateTime.now().weekday);

    return Scaffold(
      body: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: Container(
        decoration: AppTheme.getBackground(),
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Container(
                decoration: BoxDecoration(
                  color: dayColor,
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28))),
                padding: const EdgeInsets.fromLTRB(20, 56, 20, 20),
                child: Row(children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Icon(Icons.arrow_back_ios_rounded, color: textColor)),
                  const SizedBox(width: 12),
                  Text('Familjestatus', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: textColor)),
                ]),
              ),
            ),
            if (_loading)
              const SliverToBoxAdapter(child: Center(child: Padding(
                padding: EdgeInsets.all(40),
                child: CircularProgressIndicator())))
            else if (_members.isEmpty)
              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16, 40, 16, 0),
                  padding: const EdgeInsets.all(32),
                  decoration: AppTheme.cardDecoration(),
                  child: Column(children: [
                    const Text('👨‍👩‍👧‍👦', style: TextStyle(fontSize: 48)),
                    const SizedBox(height: 16),
                    Text('Inga familjemedlemmar hittades',
                        style: AppTheme.sectionTitleStyle,
                        textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    Text(
                      'Lägg till via Inställningar → Bjud in.',
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ]),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => _buildMemberCard(_members[i], dayColor),
                  childCount: _members.length,
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ))),
    );
  }

  Widget _buildMemberCard(UserModel m, Color dayColor) {
    final status = _getStatus(m);
    final currentEvent = _getCurrentEvent(m);
    Color mc; try { mc = Color(m.colorValue as int); } catch (_) { mc = dayColor; }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      decoration: AppTheme.cardDecoration(),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Stack(children: [
            CircleAvatar(
              radius: 26, backgroundColor: mc,
              child: Text(m.name.isNotEmpty ? m.name[0].toUpperCase() : '?',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18))),
            Positioned.fill(child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: status.ringColor, width: 3)))),
          ]),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(m.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: status.ringColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10)),
                child: Text(status.label,
                    style: TextStyle(fontSize: 11, color: status.ringColor, fontWeight: FontWeight.w600))),
            ]),
            if (currentEvent != null) ...[
              const SizedBox(height: 4),
              Builder(builder: (_) {
                final d = currentEvent.data() as Map<String, dynamic>;
                final pik = d['piktogram'] as String? ?? '📅';
                final title = d['title'] as String? ?? '';
                final start = _parseDateTime(d);
                final now = DateTime.now();
                final end = start?.add(const Duration(hours: 1));
                String timeInfo = '';
                if (start != null && start.isAfter(now)) {
                  final mins = start.difference(now).inMinutes;
                  timeInfo = 'Om $mins min';
                } else if (end != null && end.isAfter(now)) {
                  final mins = end.difference(now).inMinutes;
                  timeInfo = 'Ledig om $mins min';
                }
                return Row(children: [
                  Text('$pik ', style: const TextStyle(fontSize: 16)),
                  Expanded(child: Text('$title${timeInfo.isNotEmpty ? ' · $timeInfo' : ''}',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade600))),
                ]);
              }),
            ] else
              Text(status == _MemberStatus.free ? 'Ledig 🟢' : '',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
          ])),
        ]),
      ),
    );
  }
}

enum _MemberStatus { free, canReply, busy }

extension _StatusExt on _MemberStatus {
  Color get ringColor {
    switch (this) {
      case _MemberStatus.free: return const Color(0xFF6BAE75);
      case _MemberStatus.canReply: return const Color(0xFFEDD87A);
      case _MemberStatus.busy: return const Color(0xFFD95F4B);
    }
  }

  String get label {
    switch (this) {
      case _MemberStatus.free: return 'Ledig';
      case _MemberStatus.canReply: return 'Kan svara senare';
      case _MemberStatus.busy: return 'Stör ej';
    }
  }
}