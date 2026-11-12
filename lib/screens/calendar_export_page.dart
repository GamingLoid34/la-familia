import 'dart:convert';
import 'dart:developer' as developer;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/family_provider.dart';

/// Exporten hämtas med serverkontrollerad behörighet. Privata innehåll lagras
/// bara i denna sidas minne fram till att användaren väljer att spara filen.
class CalendarExportPage extends StatefulWidget {
  const CalendarExportPage({super.key});

  @override
  State<CalendarExportPage> createState() => _CalendarExportPageState();
}

class _CalendarExportPageState extends State<CalendarExportPage> {
  String _scope = 'personal';
  String? _sessionKey;
  bool _busy = false;
  Map<String, dynamic>? _file;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final user = context.watch<FamilyProvider>().currentUser;
    final key = user == null ? null : '${user.uid}/${user.familyId}';
    if (key != _sessionKey) {
      _sessionKey = key;
      _file = null;
      _error = null;
      _busy = false;
      _scope = 'personal';
    }
  }

  Future<void> _prepare() async {
    final key = _sessionKey;
    if (key == null || _busy) return;
    setState(() {
      _busy = true;
      _file = null;
      _error = null;
    });
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable(
            'exportCalendar',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 90)),
          )
          .call<Map<String, dynamic>>({
            'scope': _scope,
            'includeImported': false,
          });
      if (!mounted || _sessionKey != key) return;
      if (result.data['ics'] is! String || result.data['filename'] is! String) {
        throw const FormatException('Ogiltigt kalenderfilssvar');
      }
      setState(() => _file = result.data);
    } on FirebaseFunctionsException catch (e) {
      if (mounted && _sessionKey == key) {
        setState(
          () => _error =
              e.message ?? 'Kunde inte skapa kalenderfilen. Försök igen.',
        );
      }
    } catch (e, stack) {
      developer.log(
        'Kalenderexport misslyckades',
        error: e.runtimeType,
        stackTrace: stack,
      );
      if (mounted && _sessionKey == key) {
        setState(() => _error = 'Kunde inte skapa kalenderfilen. Försök igen.');
      }
    } finally {
      if (mounted && _sessionKey == key) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final file = _file;
    final key = _sessionKey;
    if (file == null || key == null || _busy) return;
    final rawName = file['filename'] as String;
    final name = RegExp(r'^[a-zA-Z0-9_.-]+\.ics$').hasMatch(rawName)
        ? rawName
        : 'vardag.ics';
    setState(() => _busy = true);
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Spara kalenderfil',
        fileName: name,
        type: FileType.custom,
        allowedExtensions: ['ics'],
        bytes: Uint8List.fromList(utf8.encode(file['ics'] as String)),
      );
      if (!mounted || _sessionKey != key) return;
      if (kIsWeb || path != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              kIsWeb
                  ? 'Kalenderfilen har skickats till webbläsarens nedladdning.'
                  : 'Kalenderfilen har sparats.',
            ),
          ),
        );
      }
    } catch (e, stack) {
      developer.log(
        'Kunde inte spara kalenderfil',
        error: e.runtimeType,
        stackTrace: stack,
      );
      if (mounted && _sessionKey == key) {
        setState(() => _error = 'Kunde inte spara filen. Försök igen.');
      }
    } finally {
      if (mounted && _sessionKey == key) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<FamilyProvider>().currentUser;
    final warnings =
        (_file?['warnings'] as List?)?.whereType<String>().toList() ?? [];
    return Scaffold(
      appBar: AppBar(title: const Text('Ta med kalendern')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Spara en kalenderfil som du kan importera i Google Kalender, Apple Kalender eller Outlook. Aktiviteterna finns kvar där även om du slutar använda Vardag.',
              ),
              const SizedBox(height: 20),
              _choice(
                'personal',
                'Mina aktiviteter',
                'Dina och familjens gemensamma aktiviteter, dina arbetspass och dina egna privata aktiviteter.',
              ),
              if (user?.isParent == true)
                _choice(
                  'family',
                  'Familjens aktiviteter',
                  'Familjens aktiviteter och arbetspass. Inga privata aktiviteter följer med.',
                ),
              const SizedBox(height: 12),
              if (_scope == 'personal')
                const Text(
                  'Filen kan innehålla privata uppgifter. Spara den där bara du kan läsa den.',
                ),
              const SizedBox(height: 12),
              const Text(
                'Importerade kalendrar följer inte med, eftersom de redan finns hos sin källa. Packlistor och förberedelser följer med som text. Filen är en kopia och uppdateras inte automatiskt.',
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy || user == null ? null : _prepare,
                child: Text(_busy ? 'Arbetar…' : 'Förbered kalenderfil'),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (_file != null) ...[
                const SizedBox(height: 20),
                Text(
                  '${_file!["eventCount"]} kalenderposter är klara. Återkommande aktiviteter sparas som serier.',
                ),
                for (final warning in warnings)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(warning),
                  ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy ? null : _save,
                  icon: const Icon(Icons.download),
                  label: const Text('Spara kalenderfil'),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Öppna sedan din andra kalenders importfunktion och välj filen. Importera helst i en ny kalender som heter Vardag, så blir kopian enkel att hitta. Om du importerar samma fil flera gånger kan den andra appen skapa dubletter.',
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _choice(String value, String title, String subtitle) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Card(
      child: ListTile(
        leading: Icon(
          _scope == value ? Icons.radio_button_checked : Icons.radio_button_off,
        ),
        title: Text(title),
        subtitle: Text(subtitle),
        onTap: _busy
            ? null
            : () => setState(() {
                _scope = value;
                _file = null;
                _error = null;
              }),
      ),
    ),
  );
}
