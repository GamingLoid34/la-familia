import 'package:flutter/material.dart';
import '../../models/user_model.dart';
import 'display_keymap_page.dart';
import 'display_photos_page.dart';
import 'display_scenes_page.dart';
import 'display_schedule_page.dart';
import 'display_screen_page.dart';
import 'display_skolmat_page.dart';
import 'display_status_card.dart';
import 'display_transit_page.dart';

/// Huvudsida för Storskärmsinställningar i mobilappen (FAS 5.1).
///
/// Navigeringsväg: Inställningar → Storskärm
/// Endast tillgänglig för föräldrar.
class StorskarmSettingsPage extends StatelessWidget {
  final String familyId;
  final Color dayColor;
  final List<UserModel> familyMembers;
  final UserModel? currentUser;

  const StorskarmSettingsPage({
    super.key,
    required this.familyId,
    required this.dayColor,
    required this.familyMembers,
    this.currentUser,
  });

  @override
  Widget build(BuildContext context) {
    final isParent = currentUser?.isParent ?? true;
    if (!isParent) {
      return Scaffold(
        appBar: AppBar(title: const Text('Storskärm')),
        body: const Center(
          child: Text('Endast föräldrar har behörighet till storskärmsinställningar.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Storskärm',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // Driftstatuskort (FAS 6b)
          DisplayStatusCard(
            familyId: familyId,
            dayColor: dayColor,
          ),
          // Info banner
          Container(
            margin: const EdgeInsets.only(bottom: 20),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: dayColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: const Text('🖥️', style: TextStyle(fontSize: 24)),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Väggskärmens innehåll',
                        style: TextStyle(
                          fontFamily: 'Nunito',
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1A1A2E),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Anpassa foton, matsedel och moduler som visas på storskärmen.',
                        style: TextStyle(fontSize: 12, color: Color(0xFF666677)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Menyval 1: Foton
          _buildMenuCard(
            context: context,
            icon: Icons.photo_library_outlined,
            title: 'Foton',
            subtitle: 'Välj och hantera foton för storskärmens fotoramar',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DisplayPhotosPage(
                  familyId: familyId,
                  dayColor: dayColor,
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Menyval 2: Skolmat (endast föräldrar)
          _buildMenuCard(
            context: context,
            icon: Icons.lunch_dining_rounded,
            title: 'Skolmat',
            subtitle: 'Koppla barnen till skola och kommun för skolmatsedel',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DisplaySkolmatPage(
                  familyId: familyId,
                  dayColor: dayColor,
                  familyMembers: familyMembers,
                  currentUser: currentUser,
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Menyval 3: Schema (FAS 6a)
          _buildMenuCard(
            context: context,
            icon: Icons.schedule_rounded,
            title: 'Schema',
            subtitle: 'Styr vilka scener som visas automatiskt över dygnet och veckan',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DisplaySchedulePage(
                  familyId: familyId,
                  dayColor: dayColor,
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Menyval 4: Scener (FAS 6a)
          _buildMenuCard(
            context: context,
            icon: Icons.dashboard_customize_rounded,
            title: 'Scener',
            subtitle: 'Skapa och anpassa skärmens layouter och modulzoner',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DisplayScenesPage(
                  familyId: familyId,
                  dayColor: dayColor,
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Menyval 5: Knappar (FAS 6a)
          _buildMenuCard(
            context: context,
            icon: Icons.keyboard_rounded,
            title: 'Knappar',
            subtitle: 'Mappa sifferknappar 1–9 och visa Stream Deck-lathund',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DisplayKeymapPage(
                  familyId: familyId,
                  dayColor: dayColor,
                  familyMembers: familyMembers,
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Menyval 6: Tåg & bussar (FAS 6b)
          _buildMenuCard(
            context: context,
            icon: Icons.directions_transit_rounded,
            title: 'Tåg & bussar',
            subtitle: 'Hållplatser, gångtider och filter för kollektivtrafik',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DisplayTransitPage(
                  familyId: familyId,
                  dayColor: dayColor,
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Menyval 7: Skärm (FAS 6c)
          _buildMenuCard(
            context: context,
            icon: Icons.palette_outlined,
            title: 'Skärm',
            subtitle: 'Tema (ljust, mörkt eller auto) och skärminställningar',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DisplayScreenPage(
                  familyId: familyId,
                  dayColor: dayColor,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: dayColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: dayColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF666677),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}
