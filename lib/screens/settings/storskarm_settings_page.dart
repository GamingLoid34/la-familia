import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/user_model.dart';

class StorskarmSettingsPage extends StatefulWidget {
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
  State<StorskarmSettingsPage> createState() => _StorskarmSettingsPageState();
}

class _StorskarmSettingsPageState extends State<StorskarmSettingsPage> {
  bool tasks = false;
  String get address =>
      'https://la-familia-5d9f5.web.app/?display=1${tasks ? '&tasks=1' : ''}';
  @override
  Widget build(BuildContext context) => widget.currentUser?.isParent != true
      ? Scaffold(appBar: AppBar(title: const Text('Storskärm')), body: const Center(child: Text('Endast föräldrar har behörighet till storskärmsinställningar.')))
      : Scaffold(
    appBar: AppBar(title: const Text('Storskärm')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Icon(Icons.tv_rounded, size: 64),
        const SizedBox(height: 20),
        const Text(
          'Familjens dag, på väggen',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        const Text(
          'Visa dagens kalender, arbetspass och kommande dagar på en TV. Informationen uppdateras när familjen ändrar kalendern. Långa listor växlar sida automatiskt.',
          style: TextStyle(fontSize: 18),
        ),
        const SizedBox(height: 20),
        if (widget.currentUser?.isParent == true)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Visa uppgifter från veckobrev'),
            subtitle: const Text(
              'Kräver vuxeninloggning. Alla framför TV:n kan läsa uppgifternas rubriker.',
            ),
            value: tasks,
            onChanged: (v) => setState(() => tasks = v),
          ),
        const SizedBox(height: 16),
        SelectableText(address),
        const SizedBox(height: 16),
        FilledButton.icon(
          icon: const Icon(Icons.open_in_new),
          label: const Text('Öppna storskärmen'),
          onPressed: () async {
            final opened = await launchUrl(
              Uri.parse(address),
              webOnlyWindowName: '_blank',
            );
            if (!opened && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Kopiera länken och öppna den i webbläsaren.'),
                ),
              );
            }
          },
        ),
        const SizedBox(height: 24),
        const Text(
          'På TV:n',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          '1. Öppna länken i TV:ns webbläsare eller på en dator ansluten till TV:n.\n2. Logga in med ditt vanliga Vardag-konto.\n3. Välj helskärm i webbläsaren (F11 på dator) och stäng av enhetens viloläge.\n\nEn dator med en modern webbläsare är den säkraste starten. TV:ns inbyggda webbläsare behöver provas på just din TV.',
          style: TextStyle(fontSize: 18, height: 1.5),
        ),
      ],
    ),
  );
}
