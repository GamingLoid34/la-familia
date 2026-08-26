import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';
import '../services/weather_service.dart';

/// Bottom sheet: sök ort eller ange lat/long, spara på familjedokumentet.
Future<void> showHomeLocationSheet(
  BuildContext context, {
  required String familyId,
  String? currentName,
  double? currentLat,
  double? currentLon,
  required VoidCallback onSaved,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _HomeLocationSheet(
      familyId: familyId,
      currentName: currentName,
      currentLat: currentLat,
      currentLon: currentLon,
      onSaved: onSaved,
    ),
  );
}

class _HomeLocationSheet extends StatefulWidget {
  final String familyId;
  final String? currentName;
  final double? currentLat;
  final double? currentLon;
  final VoidCallback onSaved;

  const _HomeLocationSheet({
    required this.familyId,
    this.currentName,
    this.currentLat,
    this.currentLon,
    required this.onSaved,
  });

  @override
  State<_HomeLocationSheet> createState() => _HomeLocationSheetState();
}

class _HomeLocationSheetState extends State<_HomeLocationSheet> {
  final _searchCtrl = TextEditingController();
  final _latCtrl = TextEditingController();
  final _lonCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();

  List<GeoPlace> _results = const [];
  bool _searching = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.currentName != null) {
      _nameCtrl.text = widget.currentName!;
    }
    if (widget.currentLat != null) {
      _latCtrl.text = widget.currentLat!.toStringAsFixed(4);
    }
    if (widget.currentLon != null) {
      _lonCtrl.text = widget.currentLon!.toStringAsFixed(4);
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _latCtrl.dispose();
    _lonCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _runSearch() async {
    setState(() {
      _searching = true;
      _error = null;
    });
    final results =
        await WeatherService.instance.searchPlaces(_searchCtrl.text);
    if (!mounted) return;
    setState(() {
      _searching = false;
      _results = results;
      if (results.isEmpty && _searchCtrl.text.trim().length >= 2) {
        _error = 'Inga träffar — prova en annan ort eller ange koordinater.';
      }
    });
  }

  void _pickPlace(GeoPlace place) {
    setState(() {
      _nameCtrl.text = place.displayLabel;
      _latCtrl.text = place.lat.toStringAsFixed(4);
      _lonCtrl.text = place.lon.toStringAsFixed(4);
      _results = const [];
      _error = null;
    });
  }

  Future<void> _save() async {
    final lat = double.tryParse(_latCtrl.text.trim().replaceAll(',', '.'));
    final lon = double.tryParse(_lonCtrl.text.trim().replaceAll(',', '.'));
    final name = _nameCtrl.text.trim();

    if (lat == null || lon == null) {
      setState(() => _error = 'Ange giltiga latitud- och longitudvärden.');
      return;
    }
    if (name.isEmpty) {
      setState(() => _error = 'Ange ett namn för hempositionen.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await FirebaseFirestore.instance
          .collection('families')
          .doc(widget.familyId)
          .update({
        'homeLat': lat,
        'homeLon': lon,
        'homeName': name,
      });
      if (!mounted) return;
      widget.onSaved();
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Kunde inte spara — försök igen.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final dayColor = AppTheme.getDayAccentColor();

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Hemposition',
                    style: AppTheme.cardTitleStyle.copyWith(fontSize: 18)),
                const SizedBox(height: 4),
                Text(
                  'Används för väder på Hem och i Planering.',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    labelText: 'Sök ort',
                    hintText: 't.ex. Uppsala',
                    suffixIcon: IconButton(
                      icon: _searching
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: dayColor,
                              ),
                            )
                          : Icon(Icons.search_rounded, color: dayColor),
                      onPressed: _searching ? null : _runSearch,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _runSearch(),
                ),
                if (_results.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ..._results.map(
                    (p) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.place_outlined, color: dayColor),
                      title: Text(p.displayLabel,
                          style: const TextStyle(fontSize: 14)),
                      onTap: () => _pickPlace(p),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _nameCtrl,
                  decoration: InputDecoration(
                    labelText: 'Namn',
                    hintText: 'Hem',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _latCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true, signed: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'^-?\d*[.,]?\d*')),
                        ],
                        decoration: InputDecoration(
                          labelText: 'Latitud',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _lonCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true, signed: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'^-?\d*[.,]?\d*')),
                        ],
                        decoration: InputDecoration(
                          labelText: 'Longitud',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      style: TextStyle(color: Colors.red.shade700, fontSize: 13)),
                ],
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: dayColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Spara hemposition',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
