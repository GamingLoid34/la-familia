import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/family_provider.dart';
import '../utils/calendar_connection_ui.dart';

class CalendarConnectionsPage extends StatefulWidget {
  const CalendarConnectionsPage({super.key});
  @override
  State<CalendarConnectionsPage> createState() =>
      _CalendarConnectionsPageState();
}

class _CalendarConnectionsPageState extends State<CalendarConnectionsPage> {
  String? _sessionKey;
  bool _busy = false;
  String? _error;
  String? _message;
  String? _authorizationUrl;
  List<String> _providers = [];
  List<Map<String, dynamic>> _connections = [];
  String? _conflictConnection;
  List<Map<String, dynamic>> _conflicts = [];

  static List<Map<String, dynamic>> _maps(dynamic raw) => raw is List
      ? raw
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList()
      : [];
  static Map<String, dynamic>? _map(dynamic raw) =>
      raw is Map ? Map<String, dynamic>.from(raw) : null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final user = context.watch<FamilyProvider>().currentUser;
    final key =
        calendarAccountSyncEnabled &&
            user != null &&
            canConnectCalendar(user.role)
        ? '${user.uid}/${user.familyId}/${user.role}'
        : null;
    if (key != _sessionKey) {
      _sessionKey = key;
      _providers = [];
      _connections = [];
      _conflicts = [];
      _conflictConnection = null;
      _authorizationUrl = null;
      _busy = false;
      _error = null;
      _message = null;
      if (key != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _sessionKey == key) _run(_load);
        });
      }
    }
  }

  bool _current(String key) => mounted && _sessionKey == key;

  Future<Map<String, dynamic>> _call(
    String key,
    String method, [
    Map<String, dynamic> payload = const {},
  ]) async {
    if (!_current(key)) throw const _ChangedSession();
    final response = await FirebaseFunctions.instance
        .httpsCallable(
          method,
          options: HttpsCallableOptions(timeout: const Duration(seconds: 120)),
        )
        .call<Map<String, dynamic>>(payload);
    if (!_current(key)) throw const _ChangedSession();
    return response.data;
  }

  Future<void> _run(Future<void> Function(String) action) async {
    final key = _sessionKey;
    if (_busy || key == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      await action(key);
    } on _ChangedSession {
      // Results from the previous account must not appear in the new account.
    } on FirebaseFunctionsException catch (error) {
      if (_current(key)) {
        setState(() {
          _error = switch (error.code) {
            'unauthenticated' =>
              'Logga in igen för att hantera dina kalenderkopplingar.',
            'permission-denied' =>
              'Kontot får inte använda den här kalenderkopplingen.',
            'not-found' || 'unimplemented' =>
              'Kalendersynk är inte tillgänglig här ännu. Du kan fortfarande importera och exportera kalenderfiler.',
            _ =>
              'Kunde inte slutföra åtgärden. Kontrollera anslutningen och försök igen. Om kontot behöver anslutas på nytt visas det hos din kalenderleverantör.',
          };
        });
      }
    } catch (_) {
      if (_current(key)) {
        setState(() => _error = 'Kunde inte slutföra åtgärden. Försök igen.');
      }
    } finally {
      if (_current(key)) setState(() => _busy = false);
    }
  }

  Future<void> _load(String key) async {
    final data = await _call(key, 'getCalendarConnections');
    setState(() {
      _providers = _maps(data['providers'])
          .where((item) => item['configured'] == true)
          .map((item) => item['provider'])
          .whereType<String>()
          .where(
            (value) => const {'google', 'outlook', 'icloud'}.contains(value),
          )
          .toList();
      _connections = _maps(data['connections']);
    });
  }

  Future<void> _start(String provider) => _run((key) async {
    final result = await _call(key, 'startCalendarConnection', {
      'provider': provider,
    });
    final url = result['url'];
    if (url is! String || !safeCalendarAuthorizationUrl(url)) {
      throw const FormatException();
    }
    setState(() => _authorizationUrl = url);
  });

  Future<void> _openAuthorization() async {
    final url = _authorizationUrl;
    if (url == null || !safeCalendarAuthorizationUrl(url)) return;
    try {
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
        webOnlyWindowName: '_self',
      );
      if (!mounted) return;
      setState(() {
        if (opened) {
          _authorizationUrl = null;
          _message =
              'Slutför anslutningen i webbläsaren. Återvänd sedan hit och tryck Uppdatera.';
        } else {
          _error = 'Kunde inte öppna webbläsaren. Försök igen.';
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Kunde inte öppna webbläsaren. Försök igen.');
      }
    }
  }

  Future<void> _connectApple() async {
    final key = _sessionKey;
    final credentials = await showDialog<(String, String)>(
      context: context,
      builder: (_) => const _AppleCalendarDialog(),
    );
    if (credentials == null || key == null || !_current(key)) return;
    await _run((key) async {
      await _call(key, 'connectICloudCalendar', {
        'username': credentials.$1,
        'appPassword': credentials.$2,
      });
      await _load(key);
    });
  }

  Future<bool> _confirm(String title, String body, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Avbryt'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _select(
    Map<String, dynamic> connection,
    Map<String, dynamic> calendar,
  ) async {
    final key = _sessionKey;
    if (!await _confirm(
      'Synkronisera ${calendar['name']}?',
      'Händelser hämtas till din privata kalender i Vardag. Dina egna aktiviteter som gäller dig skickas till ${calendar['name']}, där kalenderns andra läsare kan se dem. Ändringar kan därefter föras mellan kalendrarna. Välj en separat, privat kalender om du är osäker på vilka som har åtkomst.',
      'Välj och starta synk',
    )) {
      return;
    }
    if (key == null || !_current(key)) return;
    await _run((key) async {
      await _call(key, 'selectCalendarSyncCalendar', {
        'connectionId': connection['id'],
        'calendarId': calendar['id'],
      });
      try {
        await _call(key, 'syncCalendarNow', {'connectionId': connection['id']});
      } finally {
        if (_current(key)) await _load(key);
      }
      setState(
        () => _message =
            'Kalendern är ansluten och den första synkningen är klar. Granska eventuella konflikter under kontot.',
      );
    });
  }

  Future<void> _sync(String id) => _run((key) async {
    try {
      await _call(key, 'syncCalendarNow', {'connectionId': id});
    } finally {
      if (_current(key)) await _load(key);
    }
    setState(
      () => _message =
          'Synkningen är klar. Se eventuell konflikt eller paus under kontot.',
    );
  });

  Future<void> _disconnect(String id) async {
    final key = _sessionKey;
    if (!await _confirm(
      'Koppla från kalendern?',
      'Synkningen slutar. Aktiviteter som redan finns i Vardag och i din andra kalender behålls.',
      'Koppla från',
    )) {
      return;
    }
    if (key == null || !_current(key)) return;
    await _run((key) async {
      await _call(key, 'disconnectCalendarConnection', {'connectionId': id});
      await _load(key);
      setState(
        () => _message =
            'Kopplingen är borttagen. Aktiviteterna finns kvar i båda kalendrarna.',
      );
    });
  }

  Future<void> _loadConflicts(String key, String id) async {
    final data = await _call(key, 'getCalendarSyncConflicts', {
      'connectionId': id,
    });
    setState(() {
      _conflictConnection = id;
      _conflicts = _maps(data['conflicts']);
    });
  }

  Future<void> _resolve(Map<String, dynamic> conflict, String choice) async {
    final id = _conflictConnection;
    final key = _sessionKey;
    final explanation = choice == 'skip'
        ? 'Aktiviteten behålls som den är i båda kalendrarna. Senare ändringar av just denna aktivitet förs inte mellan dem.'
        : 'Den valda versionen används i båda kalendrarna och ersätter den andra versionen. Om den valda versionen är borttagen tas aktiviteten bort även där.';
    if (!await _confirm('Bekräfta ditt val', explanation, 'Bekräfta')) return;
    if (id == null || key == null || !_current(key)) return;
    await _run((key) async {
      await _call(key, 'resolveCalendarSyncConflict', {
        'connectionId': id,
        'conflictId': conflict['id'],
        'choice': choice,
      });
      await _loadConflicts(key, id);
      await _load(key);
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<FamilyProvider>().currentUser;
    return Scaffold(
      appBar: AppBar(title: const Text('Kalenderkopplingar')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: !canConnectCalendar(user?.role)
                ? [
                    const Text(
                      'Kalenderkopplingar är till för vuxna och ungdomar.',
                    ),
                  ]
                : [
                    const Text(
                      'Använd Vardag tillsammans med din vanliga kalender. Du väljer själv vilket konto och vilken kalender som ska synkroniseras.',
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Aktiviteter från den andra kalendern blir privata i Vardag: familjen ser bara att du är upptagen. Bara aktiviteter som du själv har skapat och som gäller dig skickas från Vardag. Välj gärna en separat kalender som heter Vardag.',
                    ),
                    const SizedBox(height: 16),
                    if (_busy) const LinearProgressIndicator(),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    if (_message != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(_message!),
                      ),
                    OutlinedButton(
                      onPressed: _busy ? null : () => _run(_load),
                      child: const Text('Uppdatera'),
                    ),
                    if (_providers.isEmpty && !_busy)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'Ingen ny kalenderkoppling är tillgänglig just nu. Du kan använda kalenderfiler via Andra kalendrar och Ta med kalendern.',
                        ),
                      ),
                    for (final provider in _providers)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: FilledButton(
                          onPressed: _busy
                              ? null
                              : () => provider == 'icloud'
                                    ? _connectApple()
                                    : _start(provider),
                          child: Text(
                            'Anslut ${calendarProviderName(provider)}',
                          ),
                        ),
                      ),
                    if (_authorizationUrl != null)
                      FilledButton(
                        onPressed: _openAuthorization,
                        child: const Text('Fortsätt i webbläsaren'),
                      ),
                    const SizedBox(height: 16),
                    for (final connection in _connections)
                      _connectionCard(connection),
                    if (_conflictConnection != null) ...[
                      const Divider(),
                      Text(
                        'Ändringar att granska',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      if (_conflicts.isEmpty)
                        const Text('Inga konflikter att granska.'),
                      for (final conflict in _conflicts)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'I Vardag\n${calendarConflictVersion(_map(conflict['local']))}',
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'I den andra kalendern\n${calendarConflictVersion(_map(conflict['remote']))}',
                                ),
                                if (conflict['resolvable'] == true) ...[
                                  TextButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _resolve(conflict, 'keepLocal'),
                                    child: const Text('Använd Vardags version'),
                                  ),
                                  TextButton(
                                    onPressed: _busy
                                        ? null
                                        : () =>
                                              _resolve(conflict, 'keepRemote'),
                                    child: const Text(
                                      'Använd den andra kalenderns version',
                                    ),
                                  ),
                                ],
                                TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _resolve(conflict, 'skip'),
                                  child: const Text(
                                    'Sluta synka den här aktiviteten',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                _conflictConnection = null;
                                _conflicts = [];
                              }),
                        child: const Text('Stäng granskningen'),
                      ),
                    ],
                  ],
          ),
        ),
      ),
    );
  }

  Widget _connectionCard(Map<String, dynamic> connection) {
    final id = connection['id'] as String?;
    if (id == null) return const SizedBox.shrink();
    final status = connection['status'] as String?;
    final calendars = _maps(
      connection['calendars'],
    ).where((calendar) => calendar['writable'] == true).toList();
    final lastSyncAt = connection['lastSyncAt'];
    final conflictCount = (connection['conflictCount'] as num?)?.toInt() ?? 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              calendarProviderName(connection['provider'] as String? ?? ''),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if ((connection['calendarName'] as String? ?? '').isNotEmpty)
              Text(connection['calendarName'] as String),
            Text(calendarConnectionStatus(status)),
            if (lastSyncAt is num)
              Text(
                'Senast synkad ${DateFormat('d MMM HH:mm', 'sv').format(DateTime.fromMillisecondsSinceEpoch(lastSyncAt.toInt()))}',
              ),
            if ((connection['lastError'] as String? ?? '').isNotEmpty)
              Text(
                'Senaste synkningen kunde inte slutföras. Försök igen eller anslut kontot på nytt.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (status == 'authorized') ...[
              const SizedBox(height: 10),
              const Text(
                'Välj en kalender som du kan ändra. Synken startar först när du bekräftar valet.',
              ),
              for (final calendar in calendars)
                OutlinedButton(
                  onPressed: _busy ? null : () => _select(connection, calendar),
                  child: Text(calendar['name'] as String? ?? 'Kalender'),
                ),
              if (calendars.isEmpty)
                const Text(
                  'Ingen skrivbar kalender hittades. Skapa en kalender hos leverantören och anslut kontot på nytt.',
                ),
            ],
            if (const {'connected', 'paused'}.contains(status)) ...[
              OutlinedButton(
                onPressed: _busy ? null : () => _sync(id),
                child: const Text('Synka nu'),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _run((key) => _loadConflicts(key, id)),
                child: Text(
                  conflictCount > 0
                      ? 'Granska $conflictCount konflikter'
                      : 'Granska konflikter',
                ),
              ),
            ],
            if (status != 'disconnected')
              TextButton(
                onPressed: _busy ? null : () => _disconnect(id),
                child: const Text('Koppla från'),
              ),
          ],
        ),
      ),
    );
  }
}

class _ChangedSession implements Exception {
  const _ChangedSession();
}

class _AppleCalendarDialog extends StatefulWidget {
  const _AppleCalendarDialog();
  @override
  State<_AppleCalendarDialog> createState() => _AppleCalendarDialogState();
}

class _AppleCalendarDialogState extends State<_AppleCalendarDialog> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Anslut iCloud'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Använd ditt Apple-konto och ett appspecifikt lösenord som du skapar hos Apple. Ditt vanliga Apple-lösenord ska inte användas här.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _username,
            onChanged: (_) => setState(() {}),
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Apple-konto'),
          ),
          TextField(
            controller: _password,
            onChanged: (_) => setState(() {}),
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            autofillHints: const [],
            decoration: const InputDecoration(
              labelText: 'Appspecifikt lösenord',
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Avbryt'),
      ),
      FilledButton(
        onPressed: _username.text.trim().isEmpty || _password.text.isEmpty
            ? null
            : () {
                final credentials = (_username.text.trim(), _password.text);
                _username.clear();
                _password.clear();
                Navigator.pop(context, credentials);
              },
        child: const Text('Anslut'),
      ),
    ],
  );
}
