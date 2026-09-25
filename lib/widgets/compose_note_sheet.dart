import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/user_model.dart';
import 'vardag_header.dart';

/// Reglernas tak för en anteckning (`notes.text`).
const maxNoteLength = 10000;

/// Resultatet av formuläret "Ny anteckning" / "Ändra anteckning".
class ComposedNote {
  final String text;
  final bool isPrivate;
  final List<String> aboutUids;
  const ComposedNote(this.text, this.isPrivate, this.aboutUids);
}

/// Öppnar formuläret och returnerar det användaren sparade, eller null.
/// [autoFocus] fäller upp tangentbordet direkt (snabbvägen från Hem).
Future<ComposedNote?> showComposeNoteSheet(
  BuildContext context, {
  required List<UserModel> people,
  String title = 'Ny anteckning',
  String initialText = '',
  bool initialPrivate = false,
  List<String> initialAboutUids = const [],
  String? hint,
  bool autoFocus = false,
  String? errorText,
}) =>
    showProtectedSheet<ComposedNote>(
      context,
      builder: (_) => ComposeNoteSheet(
        people: people,
        title: title,
        initialText: initialText,
        initialPrivate: initialPrivate,
        initialAboutUids: initialAboutUids,
        hint: hint,
        autoFocus: autoFocus,
        errorText: errorText,
      ),
    );

/// Formuläret stängs innan sparningen, så ett nekande får inte kasta texten.
/// Öppnar formuläret, kör [save] och — om den kastar — öppnar det igen med
/// utkastet kvar och felet överst, tills sparningen lyckas eller användaren
/// stänger. [save] returnerar false om användaren själv avbröt (t.ex. vid
/// dubblettfrågan). Returnerar det som sparades, eller null.
Future<ComposedNote?> composeUntilSaved(
  BuildContext context, {
  required List<UserModel> people,
  required Future<bool> Function(ComposedNote note) save,
  required String Function(Object error) describeError,
  String title = 'Ny anteckning',
  String initialText = '',
  bool initialPrivate = false,
  List<String> initialAboutUids = const [],
  String? hint,
  bool autoFocus = false,
}) async {
  var draft = ComposedNote(initialText, initialPrivate, initialAboutUids);
  String? error;
  while (context.mounted) {
    final note = await showComposeNoteSheet(
      context,
      people: people,
      title: title,
      initialText: draft.text,
      initialPrivate: draft.isPrivate,
      initialAboutUids: draft.aboutUids,
      hint: hint,
      autoFocus: autoFocus,
      errorText: error,
    );
    if (note == null) return null;
    try {
      return await save(note) ? note : null;
    } catch (e) {
      draft = note;
      error = '${describeError(e)} Texten finns kvar — försök igen.';
    }
  }
  return null;
}

/// Androids `ComposeNoteSheet`: originaltext, "Vem gäller det?" med hela
/// familjen (även vuxna) och gemensam som standard, med möjlighet till privat.
class ComposeNoteSheet extends StatefulWidget {
  final List<UserModel> people;
  final String title;
  final String initialText;
  final bool initialPrivate;
  final List<String> initialAboutUids;
  final String? hint;
  final bool autoFocus;

  /// Varför förra sparningen misslyckades, visas överst.
  final String? errorText;

  const ComposeNoteSheet({
    super.key,
    required this.people,
    this.title = 'Ny anteckning',
    this.initialText = '',
    this.initialPrivate = false,
    this.initialAboutUids = const [],
    this.hint,
    this.autoFocus = false,
    this.errorText,
  });

  @override
  State<ComposeNoteSheet> createState() => _ComposeNoteSheetState();
}

class _ComposeNoteSheetState extends State<ComposeNoteSheet> {
  late final TextEditingController _text;
  late bool _private;
  late final Set<String> _about;
  bool _sent = false;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.initialText)
      ..addListener(() => setState(() {}));
    _private = widget.initialPrivate;
    _about = {...widget.initialAboutUids};
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _save() {
    // Ett dubbeltryck får inte skicka två anteckningar.
    if (_sent ||
        _text.text.trim().isEmpty ||
        _text.text.trim().length > maxNoteLength) {
      return;
    }
    _sent = true;
    Navigator.of(context).pop(ComposedNote(_text.text, _private, _about.toList()));
  }

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.colors();
    final tooLong = _text.text.trim().length > maxNoteLength;
    final canSave = _text.text.trim().isNotEmpty && !tooLong;
    return SheetFrame(
      title: widget.title,
      // Spara ligger i rubrikraden så att en lång inklistring inte trycker
      // knappen utanför skärmen.
      actions: [
        FilledButton(
          onPressed: canSave ? _save : null,
          style: FilledButton.styleFrom(backgroundColor: c.accent),
          child: const Text('Spara'),
        ),
      ],
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.errorText != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(widget.errorText!,
                    style: const TextStyle(
                        color: Color(0xFFB3261E), fontWeight: FontWeight.w700)),
              ),
            if (widget.hint != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(widget.hint!,
                    style: TextStyle(fontSize: 13, color: c.onCardSecondary)),
              ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: TextField(
                controller: _text,
                autofocus: widget.autoFocus,
                minLines: 5,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'Klistra in eller skriv',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            if (tooLong)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Texten får vara högst 10 000 tecken (nu ${_text.text.trim().length}).',
                  style: const TextStyle(
                      color: Color(0xFFB3261E), fontWeight: FontWeight.w700),
                ),
              ),
            if (widget.people.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('VEM GÄLLER DET?',
                  style: AppTheme.sectionLabelStyle
                      .copyWith(color: c.onCardPrimary)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final m in widget.people)
                    FilterChip(
                      label: Text(m.name.split(' ').first),
                      selected: _about.contains(m.uid),
                      selectedColor: c.accent.withValues(alpha: 0.18),
                      checkmarkColor: c.accent,
                      onSelected: (sel) => setState(
                          () => sel ? _about.add(m.uid) : _about.remove(m.uid)),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Väljer du ingen får du frågan efteråt, om texten inte säger vem.',
                style: TextStyle(fontSize: 12, color: c.onCardSecondary),
              ),
            ],
            const SizedBox(height: 16),
            Wrap(spacing: 8, children: [
              ChoiceChip(
                label: const Text('Familjen ser texten'),
                selected: !_private,
                onSelected: (_) => setState(() => _private = false),
              ),
              ChoiceChip(
                avatar: const Text('🔒'),
                label: const Text('Bara jag ser texten'),
                selected: _private,
                onSelected: (_) => setState(() => _private = true),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
