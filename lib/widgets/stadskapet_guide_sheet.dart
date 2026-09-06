import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../data/stadzoner.dart';
import '../utils/layout.dart';
import 'trasa_chip.dart';

/// Modal bottom sheet för färgguiden "Städskåpet 🧴" och inköpsflöde.
class StadskapetGuideSheet extends StatefulWidget {
  final String familyId;

  const StadskapetGuideSheet({
    super.key,
    required this.familyId,
  });

  @override
  State<StadskapetGuideSheet> createState() => _StadskapetGuideSheetState();
}

class _StadskapetGuideSheetState extends State<StadskapetGuideSheet> {
  bool _isAddingShopping = false;

  Future<void> _addStarterKitToShopping() async {
    if (widget.familyId.isEmpty || _isAddingShopping) return;
    setState(() => _isAddingShopping = true);

    try {
      final batch = FirebaseFirestore.instance.batch();
      final currentUid = FirebaseAuth.instance.currentUser?.uid;

      for (final item in stadStartkitVaror) {
        final ref =
            FirebaseFirestore.instance.collection('shopping_items').doc();
        batch.set(ref, {
          'title': item,
          'isDone': false,
          'timestamp': FieldValue.serverTimestamp(),
          'familyId': widget.familyId,
          'createdByUid': ?currentUid,
        });
      }

      await batch.commit();

      if (mounted) {
        setState(() => _isAddingShopping = false);
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('${stadStartkitVaror.length} varor till inköpslistan 🛒'),
            backgroundColor: const Color(0xFF6BAE75),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isAddingShopping = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kunde inte lägga till varor: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildColorRow({
    required String farg,
    required String fargHex,
    required String label,
    required String desc,
    required String title,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: TrasaChip(
              farg: farg,
              fargHex: fargHex,
              trasaLabel: label,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                Text(
                  desc,
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final dayColor = AppTheme.getDayAccentColor();
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return wrapBottomSheet(
      context,
      Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.90,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Row(
                children: [
                  const Text('🧴', style: TextStyle(fontSize: 26)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Städskåpet & Färgguide',
                            style: AppTheme.sectionTitleStyle),
                        Text(
                          'Ronald McDonald Hus-modellen: rätt trasa på rätt plats.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 12),
            Expanded(
              child: ListView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                children: [
                  // 1. Färgtabellen
                  Text('FÄRGTABELL FÖR TRASOR',
                      style: AppTheme.sectionLabelStyle),
                  const SizedBox(height: 8),
                  _buildColorRow(
                    farg: 'gul',
                    fargHex: StadFarger.gulHex,
                    label: 'GUL TRASA',
                    title: 'Badrum',
                    desc: 'Handfat, speglar, kranar och dusch.',
                  ),
                  _buildColorRow(
                    farg: 'vit',
                    fargHex: StadFarger.vitHex,
                    label: 'VIT TRASA',
                    title: 'Kök',
                    desc: 'Matbord, köksbänkar, spis och diskho.',
                  ),
                  _buildColorRow(
                    farg: 'bla',
                    fargHex: StadFarger.blaHex,
                    label: 'BLÅ TRASA',
                    title: 'Damm & ytor',
                    desc: 'Hyllor, TV, skärmar, bord och fönsterbrädor.',
                  ),
                  _buildColorRow(
                    farg: 'rod',
                    fargHex: StadFarger.rodHex,
                    label: 'RÖD TRASA',
                    title: 'Toaletten',
                    desc: 'Toalettsits, lock och utsida. Blanda ALDRIG!',
                  ),
                  const SizedBox(height: 16),

                  // 2. Skötselråd
                  Text('SKÖTSEL AV MIKROFIBER',
                      style: AppTheme.sectionLabelStyle),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildBullet(
                            '🧼', 'Tvättas i 60° — tar bort bakterier och fett.'),
                        const SizedBox(height: 6),
                        _buildBullet('🚫',
                            'ALDRIG sköljmedel — det förstör mikrofibern och förmågan att suga upp damm.'),
                        const SizedBox(height: 6),
                        _buildBullet('💨', 'Låt lufttorka i tvättpåse.'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 3. Moppen
                  Text('VILEDA H2PrO-MOPPEN', style: AppTheme.sectionLabelStyle),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildBullet('💧',
                            'Fyll rent vatten och några droppar allrent i övre tanken.'),
                        const SizedBox(height: 6),
                        _buildBullet('🪣',
                            'Smutsvattnet samlas automatiskt i den undre tanken.'),
                        const SizedBox(height: 6),
                        _buildBullet('🚿',
                            'Töm smutsvattnet och skölj moppdynan efter varje pass.'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottomPad),
              child: SizedBox(
                height: 56,
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _isAddingShopping ? null : _addStarterKitToShopping,
                  icon: const Icon(Icons.shopping_cart_outlined, size: 20),
                  label: _isAddingShopping
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Text(
                          'Lägg städ-startkit på inköpslistan 🛒',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                  style: FilledButton.styleFrom(
                    backgroundColor: dayColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBullet(String emoji, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 13, height: 1.3),
          ),
        ),
      ],
    );
  }
}
