import 'dart:developer' as developer;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

class CalendarConnectionReturnPage extends StatefulWidget {
  final String ticket;
  final VoidCallback onDone;
  const CalendarConnectionReturnPage({
    super.key,
    required this.ticket,
    required this.onDone,
  });

  @override
  State<CalendarConnectionReturnPage> createState() =>
      _CalendarConnectionReturnPageState();
}

class _CalendarConnectionReturnPageState
    extends State<CalendarConnectionReturnPage> {
  bool _busy = true;
  bool _success = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _finish();
  }

  Future<void> _finish() async {
    try {
      await FirebaseFunctions.instance
          .httpsCallable('finishCalendarConnection')
          .call<dynamic>({'ticket': widget.ticket});
      if (!mounted) return;
      setState(() {
        _success = true;
        _busy = false;
      });
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = e.message ?? 'Kunde inte slutföra anslutningen.';
      });
    } catch (e, stack) {
      developer.log(
        'Kalenderanslutning kunde inte slutföras',
        error: e.runtimeType,
        stackTrace: stack,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message =
            'Kunde inte slutföra anslutningen. Starta anslutningen igen från Vardag.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Anslut kalender')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_busy) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 20),
                const Text('Slutför anslutningen…'),
              ] else ...[
                Icon(
                  _success ? Icons.check_circle_outline : Icons.error_outline,
                  size: 44,
                ),
                const SizedBox(height: 16),
                Text(
                  _success
                      ? 'Kontot är anslutet. Välj nu vilken kalender som ska synkroniseras under Mer → Kalenderkopplingar. Du kan också fortsätta där i Androidappen.'
                      : _message ?? 'Anslutningen kunde inte slutföras.',
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: widget.onDone,
                  child: const Text('Till Vardag'),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
