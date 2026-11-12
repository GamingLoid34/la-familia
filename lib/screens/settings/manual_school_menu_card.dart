import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/user_model.dart';
import '../../utils/date_utils.dart';
import '../display/display_scene_models.dart';

/// Kort för en manuell skola (FAS 5.1b: Egen matsedel).
///
/// Visar status för innevarande och nästa vecka, knapp för att ladda upp
/// matsedel (bild eller PDF), AI-tolkningsstatus, förhandsgranskning,
/// kandidatval vid `needs_review`, samt möjlighet att radera sparade veckor.
class ManualSchoolMenuCard extends StatefulWidget {
  final DisplaySkolmatSchoolConfig school;
  final String familyId;
  final Color dayColor;
  final List<UserModel> familyMembers;

  const ManualSchoolMenuCard({
    super.key,
    required this.school,
    required this.familyId,
    required this.dayColor,
    required this.familyMembers,
  });

  @override
  State<ManualSchoolMenuCard> createState() => _ManualSchoolMenuCardState();
}

class _ManualSchoolMenuCardState extends State<ManualSchoolMenuCard> {
  bool _isUploading = false;
  String? _uploadStatusText;

  String _formatIsoWeekKey(DateTime date) {
    final year = isoWeekYear(date);
    final week = isoWeekNumber(date);
    return '$year-W${week.toString().padLeft(2, '0')}';
  }

  Future<void> _pickAndUpload() async {
    final source = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Ladda upp matsedel',
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: widget.dayColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.camera_alt_rounded, color: widget.dayColor),
                ),
                title: const Text('Fota matsedel med kameran'),
                subtitle: const Text('Håll kameran rakt över dokumentet'),
                onTap: () => Navigator.pop(ctx, 'camera'),
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF5A7D9A).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.photo_library_rounded, color: Color(0xFF5A7D9A)),
                ),
                title: const Text('Välj bild från galleriet'),
                subtitle: const Text('Skärmdump eller sparat foto (JPEG, PNG)'),
                onTap: () => Navigator.pop(ctx, 'gallery'),
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.picture_as_pdf_rounded, color: Colors.red.shade700),
                ),
                title: const Text('Välj PDF-dokument'),
                subtitle: const Text('Matsedel som PDF (max 8 MB)'),
                onTap: () => Navigator.pop(ctx, 'pdf'),
              ),
            ],
          ),
        ),
      ),
    );

    if (source == null || !mounted) return;

    Uint8List? fileBytes;
    String mimeType = 'image/jpeg';
    String? fileName;

    try {
      if (source == 'camera' || source == 'gallery') {
        final picker = ImagePicker();
        final picked = await picker.pickImage(
          source: source == 'camera' ? ImageSource.camera : ImageSource.gallery,
          maxWidth: 1920,
          maxHeight: 1920,
          imageQuality: 80,
        );
        if (picked == null) return;

        fileBytes = await picked.readAsBytes();
        fileName = picked.name;
        final lower = picked.name.toLowerCase();
        if (lower.endsWith('.png')) {
          mimeType = 'image/png';
        } else if (lower.endsWith('.webp')) {
          mimeType = 'image/webp';
        } else {
          mimeType = 'image/jpeg';
        }
      } else if (source == 'pdf') {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['pdf'],
          withData: true,
        );
        if (result == null || result.files.isEmpty) return;
        final file = result.files.first;
        fileBytes = file.bytes;
        fileName = file.name;
        mimeType = 'application/pdf';
      }
    } catch (e, stack) {
      developer.log('Fel vid val av fil: $e', error: e, stackTrace: stack);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunde inte läsa filen: $e')),
        );
      }
      return;
    }

    if (fileBytes == null || fileBytes.isEmpty) return;

    // Kontrollera filstorlek (max 8 MB)
    if (fileBytes.lengthInBytes > 8 * 1024 * 1024) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Filen är för stor. Max tillåten storlek är 8 MB.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    await _processMenuDocument(
      fileBytes: fileBytes,
      mimeType: mimeType,
      fileName: fileName,
    );
  }

  Future<void> _processMenuDocument({
    required Uint8List fileBytes,
    required String mimeType,
    required String? fileName,
  }) async {
    setState(() {
      _isUploading = true;
      _uploadStatusText = 'Tolkar matsedel med AI... 🔍';
    });

    try {
      final base64Str = base64Encode(fileBytes);
      final callable = FirebaseFunctions.instance.httpsCallable(
        'parseMenuDocument',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 120)),
      );

      final response = await callable.call<dynamic>({
        'schoolId': widget.school.id,
        'familyId': widget.familyId,
        'fileBase64': base64Str,
        'mimeType': mimeType,
        'fileName': fileName,
      });

      if (!mounted) return;

      final data = response.data;
      if (data is! Map) {
        throw Exception('Ogiltigt svar från AI-tjänsten');
      }

      final confidence = data['confidence']?.toString() ?? 'needs_review';

      if (confidence == 'unreadable') {
        final msg = data['message']?.toString() ??
            'Dokumentet var inte läsbart som matsedel. Kontrollera bilden och försök igen.';
        _showUnreadableDialog(msg);
        return;
      }

      if (confidence == 'high') {
        // Skrivning skedde automatiskt på servern
        final weekLabel = data['weekLabel']?.toString() ?? 'Vecka';
        final rawDays = (data['days'] as List?) ?? [];
        _showSuccessPreview(weekLabel, rawDays);
        return;
      }

      // confidence == 'needs_review'
      await _showNeedsReviewDialog(data, fileName);
    } catch (e, stack) {
      developer.log('AI-tolkning misslyckades: $e', error: e, stackTrace: stack);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kunde inte tolka matsedeln: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadStatusText = null;
        });
      }
    }
  }

  void _showUnreadableDialog(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 8),
            Text('Kunde inte läsa matsedeln'),
          ],
        ),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showSuccessPreview(String weekLabel, List rawDays) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$weekLabel sparad! Dagens lunch visas nu på storskärmen. ✅'),
        backgroundColor: const Color(0xFF2E7D32),
      ),
    );
  }

  Future<void> _showNeedsReviewDialog(Map data, String? fileName) async {
    final rawCandidates = (data['weekCandidates'] as List?)?.map((c) => c.toString()).toList() ?? [];
    final detectedWeek = data['isoWeek']?.toString() ?? _formatIsoWeekKey(DateTime.now());
    if (!rawCandidates.contains(detectedWeek)) {
      rawCandidates.insert(0, detectedWeek);
    }

    String selectedWeek = detectedWeek;
    final rawDays = (data['days'] as List?) ?? [];
    final days = rawDays.whereType<Map>().map((d) => Map<String, dynamic>.from(d)).toList();

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final weekNum = int.tryParse(selectedWeek.split('-W').last) ?? 0;
          return AlertDialog(
            title: const Text(
              'Bekräfta vecka och matsedel',
              style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w800),
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'AI:n behöver din bekräftelse på vilken vecka matsedeln gäller:',
                      style: TextStyle(fontSize: 13, color: Color(0xFF555566)),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: selectedWeek,
                      decoration: const InputDecoration(
                        labelText: 'Vecka',
                        border: OutlineInputBorder(),
                      ),
                      items: rawCandidates.map((c) {
                        final num = int.tryParse(c.split('-W').last) ?? 0;
                        return DropdownMenuItem(
                          value: c,
                          child: Text('Vecka $num ($c)'),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() => selectedWeek = val);
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Tolkade maträtter:',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    ...days.map((d) {
                      final dt = d['date']?.toString() ?? '';
                      final lunch = d['lunch']?.toString() ?? 'Ingen mat angiven';
                      final veg = d['vegetarian']?.toString();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF7F8FA),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                dt,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11,
                                  color: Color(0xFF777788),
                                ),
                              ),
                              Text(
                                lunch,
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                              ),
                              if (veg != null && veg.isNotEmpty)
                                Text(
                                  '🌱 Veg: $veg',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.green.shade800,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Avbryt'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('Spara Vecka $weekNum'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed == true && mounted) {
      final weekNum = int.tryParse(selectedWeek.split('-W').last) ?? 0;
      final weekLabel = 'Vecka $weekNum';

      await FirebaseFirestore.instance
          .collection('families')
          .doc(widget.familyId)
          .collection('school_menus')
          .doc(widget.school.id)
          .collection('weeks')
          .doc(selectedWeek)
          .set({
        'days': days,
        'weekLabel': weekLabel,
        'source': 'manual',
        'uploadedBy': FirebaseAuth.instance.currentUser?.uid ?? '',
        'uploadedAt': FieldValue.serverTimestamp(),
        'originalFileName': fileName,
        'confidence': 'high',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$weekLabel sparad via föräldrabekräftelse! ✅'),
            backgroundColor: const Color(0xFF2E7D32),
          ),
        );
      }
    }
  }

  Future<void> _confirmDeleteWeek(String weekId, String weekLabel) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Ta bort $weekLabel?'),
        content: Text(
          'Är du säker på att du vill ta bort den uppladdade matsedeln för $weekLabel ($weekId)? Lunchraden på storskärmen tas bort direkt.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ta bort'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await FirebaseFirestore.instance
            .collection('families')
            .doc(widget.familyId)
            .collection('school_menus')
            .doc(widget.school.id)
            .collection('weeks')
            .doc(weekId)
            .delete();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$weekLabel togs bort.')),
          );
        }
      } catch (e, stack) {
        developer.log('Kunde inte ta bort vecka $weekId: $e', error: e, stackTrace: stack);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Kunde inte ta bort vecka: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final curIsoWeek = _formatIsoWeekKey(now);
    final nextIsoWeek = _formatIsoWeekKey(now.add(const Duration(days: 7)));
    final curNum = int.tryParse(curIsoWeek.split('-W').last) ?? 0;
    final nextNum = int.tryParse(nextIsoWeek.split('-W').last) ?? 0;

    final memberNames = widget.familyMembers
        .where((m) => widget.school.memberUids.contains(m.uid))
        .map((m) => m.name.split(' ').first)
        .join(', ');

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('families')
          .doc(widget.familyId)
          .collection('school_menus')
          .doc(widget.school.id)
          .collection('weeks')
          .snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];
        final hasCur = docs.any((d) => d.id == curIsoWeek);
        final hasNext = docs.any((d) => d.id == nextIsoWeek);

        final curStatus = hasCur ? '✓ uppladdad' : 'saknas';
        final nextStatus = hasNext ? '✓ uppladdad' : 'saknas';
        final statusLine = 'V.$curNum $curStatus · V.$nextNum $nextStatus';

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: widget.dayColor.withValues(alpha: 0.35),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Rubrikrad med ikon och namn
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: widget.dayColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Text('📄', style: const TextStyle(fontSize: 20)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.school.name,
                          style: const TextStyle(
                            fontFamily: 'Nunito',
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1A1A2E),
                          ),
                        ),
                        Text(
                          memberNames.isNotEmpty
                              ? 'Egen matsedel · $memberNames'
                              : 'Egen matsedel',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: widget.dayColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),

              // Veckostatus
              Row(
                children: [
                  Icon(
                    hasCur ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                    size: 18,
                    color: hasCur ? const Color(0xFF2E7D32) : const Color(0xFFE65100),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      statusLine,
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: hasCur ? const Color(0xFF2E7D32) : const Color(0xFFE65100),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Uppladdningsknapp eller spinner
              if (_isUploading)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: widget.dayColor,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _uploadStatusText ?? 'Laddar upp...',
                        style: const TextStyle(
                          fontFamily: 'Nunito',
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                )
              else
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _pickAndUpload,
                  icon: const Icon(Icons.upload_file_rounded),
                  label: const Text(
                    'Ladda upp veckans matsedel',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),

              // Lista med sparade veckor och raderingsknapp
              if (docs.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  'Sparade veckor:',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF666677),
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: docs.map((doc) {
                    final d = doc.data() as Map<String, dynamic>;
                    final label = d['weekLabel']?.toString() ?? doc.id;
                    return Chip(
                      label: Text(
                        label,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      deleteIcon: const Icon(Icons.close_rounded, size: 16),
                      onDeleted: () => _confirmDeleteWeek(doc.id, label),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
