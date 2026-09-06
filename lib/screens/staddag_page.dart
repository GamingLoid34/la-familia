import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../data/stadzoner.dart';
import '../providers/family_provider.dart';
import '../utils/chore_utils.dart';
import '../utils/layout.dart';
import '../widgets/stadskapet_guide_sheet.dart';
import '../widgets/stadzoner_seeder_sheet.dart';
import '../widgets/trasa_chip.dart';
import 'stadlage_page.dart';

/// Paketvy för städdagen (Ronald McDonald Hus-modellen).
///
/// Visar de 7 fasta städzonerna, deras färgkodade trasor och framsteg
/// mot måldatumet (idag om lördag, annars kommande lördag).
class StaddagPage extends StatelessWidget {
  final String? familyId;

  const StaddagPage({
    super.key,
    this.familyId,
  });

  static const List<String> _swedishMonths = [
    '',
    'januari',
    'februari',
    'mars',
    'april',
    'maj',
    'juni',
    'juli',
    'augusti',
    'september',
    'oktober',
    'november',
    'december',
  ];

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FamilyProvider>();
    final user = provider.currentUser;
    final effectiveFamilyId =
        (familyId != null && familyId!.isNotEmpty) ? familyId! : (user?.familyId ?? '');

    final now = DateTime.now();
    final isSaturdayToday = now.weekday == DateTime.saturday;
    final targetDate = isSaturdayToday
        ? DateTime(now.year, now.month, now.day)
        : getNextSaturday(now);

    final dateSubtitle = isSaturdayToday
        ? 'Idag!'
        : 'Lördag ${targetDate.day} ${_swedishMonths[targetDate.month]}';

    final isLowStimuli = AppTheme.lowStimuli;
    final dayColor = AppTheme.getDayAccentColor(now.weekday);
    final maxW = WindowSize.of(context).isExpanded ? WindowSize.settingsMaxWidth : 560.0;

    return Scaffold(
      backgroundColor: isLowStimuli ? const Color(0xFFF0F2F5) : const Color(0xFFF5F7FA),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxW),
            child: effectiveFamilyId.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('chores')
                        .where('familyId', isEqualTo: effectiveFamilyId)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting &&
                          !snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final allDocs = snapshot.data?.docs ?? const [];
                      final stadDocs = allDocs.where((doc) {
                        final d = doc.data();
                        final k = d['stadKey'] as String?;
                        return k != null && k.isNotEmpty;
                      }).toList();

                      if (stadDocs.isEmpty) {
                        return _buildEmptyState(
                          context,
                          effectiveFamilyId: effectiveFamilyId,
                          dayColor: dayColor,
                          isLowStimuli: isLowStimuli,
                        );
                      }

                      return _buildContent(
                        context,
                        stadDocs: stadDocs,
                        effectiveFamilyId: effectiveFamilyId,
                        targetDate: targetDate,
                        dateSubtitle: dateSubtitle,
                        dayColor: dayColor,
                        isLowStimuli: isLowStimuli,
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context, {
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> stadDocs,
    required String effectiveFamilyId,
    required DateTime targetDate,
    required String dateSubtitle,
    required Color dayColor,
    required bool isLowStimuli,
  }) {
    // Knyt dokument till städzon
    final choreByStadKey = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final doc in stadDocs) {
      final k = doc.data()['stadKey'] as String?;
      if (k != null && k.isNotEmpty) {
        choreByStadKey[k] = doc;
      }
    }

    // De 7 fasta zonerna i definierad ordning
    final zoneItems = <({StadZon zon, QueryDocumentSnapshot<Map<String, dynamic>>? doc})>[];
    for (final zon in stadZoner) {
      zoneItems.add((zon: zon, doc: choreByStadKey[zon.key]));
    }

    // Eventuella anpassade städzoner som inte finns i stadZoner
    for (final doc in stadDocs) {
      final k = doc.data()['stadKey'] as String;
      if (stadZonByKey(k) == null) {
        final d = doc.data();
        final title = (d['chore'] as String?) ?? (d['title'] as String?) ?? 'Zon';
        final pik = (d['piktogram'] as String?) ?? '🧹';
        final farg = d['stadFarg'] as String?;
        final customZon = StadZon(
          key: k,
          titel: title,
          piktogram: pik,
          farg: farg,
          fargHex: null,
          trasaLabel: null,
          verktyg: (d['verktyg'] as List? ?? const []).cast<String>(),
          steg: (d['substeps'] as List? ?? const []).map((s) => s['title'] as String? ?? '').toList(),
        );
        zoneItems.add((zon: customZon, doc: doc));
      }
    }

    int doneCount = 0;
    for (final item in zoneItems) {
      if (item.doc != null && choreDoneOnDay(item.doc!.data(), targetDate)) {
        doneCount++;
      }
    }

    final totalZones = zoneItems.length;
    final progress = totalZones == 0 ? 0.0 : doneCount / totalZones;

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        _buildHeader(
          context,
          dateSubtitle: dateSubtitle,
          doneCount: doneCount,
          totalCount: totalZones,
          progress: progress,
          isLowStimuli: isLowStimuli,
        ),
        const SizedBox(height: 16),
        ...zoneItems.map((item) => _buildZoneCard(
              context,
              item: item,
              targetDate: targetDate,
              dayColor: dayColor,
              isLowStimuli: isLowStimuli,
              effectiveFamilyId: effectiveFamilyId,
            )),
        const SizedBox(height: 10),
        _buildGuideLink(context, effectiveFamilyId, isLowStimuli),
      ],
    );
  }

  Widget _buildHeader(
    BuildContext context, {
    required String dateSubtitle,
    required int doneCount,
    required int totalCount,
    required double progress,
    required bool isLowStimuli,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: 'Tillbaka',
              onPressed: () => Navigator.pop(context),
            ),
            const SizedBox(width: 4),
            const Expanded(
              child: Text(
                '🧹 Städdag',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 12, right: 12, top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    dateSubtitle,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: doneCount == totalCount && totalCount > 0
                          ? const Color(0xFFE8F5E9)
                          : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$doneCount av $totalCount klara',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: doneCount == totalCount && totalCount > 0
                            ? const Color(0xFF2E7D32)
                            : Colors.grey.shade800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: const AlwaysStoppedAnimation(Color(0xFF6BAE75)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildZoneCard(
    BuildContext context, {
    required ({StadZon zon, QueryDocumentSnapshot<Map<String, dynamic>>? doc}) item,
    required DateTime targetDate,
    required Color dayColor,
    required bool isLowStimuli,
    required String effectiveFamilyId,
  }) {
    final zon = item.zon;
    final doc = item.doc;
    final docData = doc?.data();
    final isDone = docData != null && choreDoneOnDay(docData, targetDate);

    final zoneColor = zon.color;
    final cardColor = isLowStimuli
        ? Colors.white
        : (zoneColor != null
            ? Color.alphaBlend(zoneColor.withValues(alpha: isDone ? 0.04 : 0.12), Colors.white)
            : Colors.white);

    final borderColor = isLowStimuli
        ? (isDone ? const Color(0xFF6BAE75) : Colors.grey.shade300)
        : (zoneColor != null
            ? zoneColor.withValues(alpha: isDone ? 0.25 : 0.5)
            : Colors.grey.shade300);

    final substeps = (docData?['substeps'] as List? ?? []).cast<Map<String, dynamic>>();
    final doneSubsteps = substeps.where((s) => s['isDone'] == true).length;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: borderColor,
          width: isLowStimuli ? 1.0 : 1.5,
        ),
        boxShadow: isLowStimuli
            ? null
            : [
                BoxShadow(
                  color: (zoneColor ?? Colors.black).withValues(alpha: isDone ? 0.02 : 0.06),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            if (doc != null) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => StadlagePage(
                    choreId: doc.id,
                    accent: zoneColor ?? dayColor,
                    targetDay: targetDate,
                  ),
                ),
              );
            } else {
              _openSeeder(context, effectiveFamilyId);
            }
          },
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: isDone ? 0.7 : 1.0,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TrasaChip.fromZon(zon),
                      if (isDone)
                        const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Klar',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF2E7D32),
                              ),
                            ),
                            SizedBox(width: 4),
                            Icon(
                              Icons.check_circle_rounded,
                              color: Color(0xFF43A047),
                              size: 20,
                            ),
                          ],
                        )
                      else
                        Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.grey.shade400,
                          size: 22,
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: (zoneColor ?? Colors.grey.shade300).withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          zon.piktogram,
                          style: const TextStyle(fontSize: 24),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              zon.titel,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                decoration: isDone ? TextDecoration.lineThrough : null,
                                color: AppTheme.getTextColor(),
                              ),
                            ),
                            const SizedBox(height: 2),
                            if (!isDone && doneSubsteps > 0 && substeps.isNotEmpty)
                              Text(
                                '$doneSubsteps av ${substeps.length} delsteg klara',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: zoneColor ?? Colors.grey.shade700,
                                ),
                              )
                            else
                              Text(
                                '${zon.steg.length} steg · ${zon.points} p',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGuideLink(BuildContext context, String effectiveFamilyId, bool isLowStimuli) {
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 20),
      decoration: BoxDecoration(
        color: isLowStimuli ? Colors.white : Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => StadskapetGuideSheet(familyId: effectiveFamilyId),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFF6BAE75).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: const Text('🧴', style: TextStyle(fontSize: 20)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Städskåpet & Färgguide',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.getTextColor(),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Vilken trasa till vad · Inköpslista för städskåpet',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.grey.shade400,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(
    BuildContext context, {
    required String effectiveFamilyId,
    required Color dayColor,
    required bool isLowStimuli,
  }) {
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: 'Tillbaka',
              onPressed: () => Navigator.pop(context),
            ),
            const SizedBox(width: 4),
            const Expanded(
              child: Text(
                '🧹 Städdag',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey.shade300),
            boxShadow: isLowStimuli
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🧹', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 12),
              const Text(
                'Inga städzoner inlagda',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Skapa de 7 städzonerna för familjen baserat på Ronald McDonald Hus-modellen med färgkodade trasor och tydliga steg.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () => _openSeeder(context, effectiveFamilyId),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Skapa städzoner'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: dayColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _buildGuideLink(context, effectiveFamilyId, isLowStimuli),
      ],
    );
  }

  void _openSeeder(BuildContext context, String effectiveFamilyId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StadzonerSeederSheet(familyId: effectiveFamilyId),
    );
  }
}
