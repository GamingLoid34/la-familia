import 'dart:developer' as developer;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/display_photo_model.dart';
import '../../services/display_photo_service.dart';

/// Hanteringsyta för storskärmens foton i mobilappens inställningar (FAS 4.5 Beslut 2).
class DisplayPhotosPage extends StatefulWidget {
  final String familyId;
  final Color dayColor;

  const DisplayPhotosPage({
    super.key,
    required this.familyId,
    required this.dayColor,
  });

  @override
  State<DisplayPhotosPage> createState() => _DisplayPhotosPageState();
}

class _DisplayPhotosPageState extends State<DisplayPhotosPage> {
  final DisplayPhotoService _service = DisplayPhotoService.instance;
  bool _isUploading = false;
  String _uploadStatus = '';
  double _currentUploadProgress = 0.0;
  String? _deletingPhotoId;
  int? _localIntervalSec;

  Future<void> _pickAndUploadPhotos(int currentCount) async {
    final remainingQuota = DisplayPhotoService.maxPhotosPerFamily - currentCount;
    if (remainingQuota <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Kvot uppnådd: Du kan ha max 50 foton på storskärmen.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final List<XFile> picked = await _service.pickPhotos();
    if (picked.isEmpty || !mounted) return;

    List<XFile> toUpload = picked;
    if (picked.length > remainingQuota) {
      toUpload = picked.take(remainingQuota).toList();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Bara $remainingQuota av ${picked.length} valda foton kan läggas till (max 50 foton).',
          ),
          backgroundColor: Colors.orange.shade800,
        ),
      );
    }

    setState(() {
      _isUploading = true;
      _uploadStatus = 'Förbereder ${toUpload.length} foton…';
      _currentUploadProgress = 0.0;
    });

    var successCount = 0;
    var failCount = 0;

    for (var i = 0; i < toUpload.length; i++) {
      if (!mounted) break;
      final file = toUpload[i];
      final itemIndex = i + 1;

      setState(() {
        _uploadStatus = 'Laddar upp foto $itemIndex av ${toUpload.length}…';
        _currentUploadProgress = 0.0;
      });

      try {
        await _service.uploadPhoto(
          familyId: widget.familyId,
          file: file,
          onProgress: (progress) {
            if (mounted) {
              setState(() => _currentUploadProgress = progress);
            }
          },
        );
        successCount++;
      } catch (e, stack) {
        failCount++;
        developer.log(
          'Kunde inte ladda upp foto $itemIndex',
          name: 'DisplayPhotosPage',
          error: e,
          stackTrace: stack,
        );
      }
    }

    if (!mounted) return;
    setState(() {
      _isUploading = false;
      _uploadStatus = '';
      _currentUploadProgress = 0.0;
    });

    if (successCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$successCount foto(n) uppladdade till storskärmen! ✨'),
          backgroundColor: const Color(0xFF2E7D32),
        ),
      );
    }
    if (failCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$failCount foto(n) kunde inte laddas upp.'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Future<void> _confirmAndDelete(DisplayPhotoModel photo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ta bort foto?'),
        content: const Text(
          'Fotot tas bort permanent från familjens storskärm.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ta bort'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _deletingPhotoId = photo.id);
    try {
      await _service.deletePhoto(
        familyId: widget.familyId,
        docId: photo.id,
        storagePath: photo.storagePath,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Fotot har tagits bort.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e, stack) {
      developer.log(
        'Kunde inte radera foto ${photo.id}',
        name: 'DisplayPhotosPage',
        error: e,
        stackTrace: stack,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Kunde inte ta bort fotot.'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _deletingPhotoId = null);
      }
    }
  }

  void _showPreviewDialog(DisplayPhotoModel photo) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          alignment: Alignment.center,
          children: [
            InteractiveViewer(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: CachedNetworkImage(
                  imageUrl: photo.url,
                  fit: BoxFit.contain,
                  placeholder: (context, url) => const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                  errorWidget: (context, url, error) => Container(
                    padding: const EdgeInsets.all(24),
                    color: Colors.black87,
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.broken_image_rounded,
                            color: Colors.white70, size: 48),
                        SizedBox(height: 8),
                        Text('Kunde inte läsa bilden',
                            style: TextStyle(color: Colors.white70)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: IconButton.filled(
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black54,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
            Positioned(
              bottom: 10,
              right: 10,
              child: IconButton.filled(
                style: IconButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.delete_outline_rounded),
                tooltip: 'Ta bort foto',
                onPressed: () {
                  Navigator.pop(ctx);
                  _confirmAndDelete(photo);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Foton på storskärmen',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: StreamBuilder<List<DisplayPhotoModel>>(
        stream: _service.streamPhotos(widget.familyId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final photos = snapshot.data ?? [];
          final count = photos.length;
          final max = DisplayPhotoService.maxPhotosPerFamily;

          return Column(
            children: [
              // Kvot och uppladdningsbanner
              Container(
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.photo_library_rounded,
                            color: widget.dayColor, size: 22),
                        const SizedBox(width: 8),
                        Text(
                          '$count av $max foton',
                          style: const TextStyle(
                            fontFamily: 'Nunito',
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1A1A2E),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${((count / max) * 100).round()}%',
                          style: TextStyle(
                            fontFamily: 'Nunito',
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (count / max).clamp(0.0, 1.0),
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          count >= max ? Colors.red.shade700 : widget.dayColor,
                        ),
                        minHeight: 6,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Foton visas i bildspelet på storskärmen (scen Foton). '
                      'Bilder komprimeras automatiskt till 1080p för snabb laddning.',
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 13,
                        color: Color(0xFF5C6877),
                        height: 1.3,
                      ),
                    ),
                    if (_isUploading) ...[
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _uploadStatus,
                              style: const TextStyle(
                                fontFamily: 'Nunito',
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF2C3E50),
                              ),
                            ),
                          ),
                          if (_currentUploadProgress > 0)
                            Text(
                              '${(_currentUploadProgress * 100).round()}%',
                              style: const TextStyle(
                                fontFamily: 'Nunito',
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: _currentUploadProgress,
                          backgroundColor: Colors.grey.shade200,
                          minHeight: 4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Bildspelsintervall (FAS 6b)
              _buildIntervalCard(),

              // Rutnät med foton eller tomt-läge
              Expanded(
                child: photos.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  color: widget.dayColor.withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.add_a_photo_outlined,
                                  color: widget.dayColor,
                                  size: 36,
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Inga foton ännu',
                                style: TextStyle(
                                  fontFamily: 'Nunito',
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF1A1A2E),
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Lägg till familjens favoritfoton för att visa dem på väggskärmen.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontFamily: 'Nunito',
                                  fontSize: 14,
                                  color: Color(0xFF6C7A89),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: 1.0,
                        ),
                        itemCount: photos.length,
                        itemBuilder: (context, index) {
                          final photo = photos[index];
                          final isDeleting = _deletingPhotoId == photo.id;

                          return InkWell(
                            onTap: () => _showPreviewDialog(photo),
                            onLongPress: () => _confirmAndDelete(photo),
                            borderRadius: BorderRadius.circular(12),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: CachedNetworkImage(
                                    imageUrl: photo.url,
                                    fit: BoxFit.cover,
                                    placeholder: (context, url) => Container(
                                      color: Colors.grey.shade200,
                                      child: const Center(
                                        child: SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      ),
                                    ),
                                    errorWidget: (context, url, error) => Container(
                                      color: Colors.grey.shade200,
                                      child: const Icon(
                                        Icons.broken_image_rounded,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ),
                                ),
                                if (isDeleting)
                                  Container(
                                    decoration: BoxDecoration(
                                      color: Colors.black45,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Center(
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  ),
                                Positioned(
                                  top: 4,
                                  right: 4,
                                  child: Material(
                                    color: Colors.black45,
                                    shape: const CircleBorder(),
                                    child: InkWell(
                                      customBorder: const CircleBorder(),
                                      onTap: () => _confirmAndDelete(photo),
                                      child: const Padding(
                                        padding: EdgeInsets.all(4),
                                        child: Icon(
                                          Icons.delete_outline_rounded,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),

              // Knapp för att ladda upp foton
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.add_photo_alternate_rounded),
                      label: Text(
                        count >= max ? 'Maxantal uppnått (50)' : 'Lägg till foton',
                        style: const TextStyle(
                          fontFamily: 'Nunito',
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: widget.dayColor,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: (_isUploading || count >= max)
                          ? null
                          : () => _pickAndUploadPhotos(count),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildIntervalCard() {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('families')
          .doc(widget.familyId)
          .collection('display_config')
          .doc('main')
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final fotoMap = data?['foto'] as Map<String, dynamic>?;
        final serverSec = (fotoMap?['intervalSec'] as num?)?.toInt() ?? 45;
        final effectiveSec = _localIntervalSec ?? serverSec;

        return Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.timer_outlined, color: widget.dayColor, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'Bildspelsintervall',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '$effectiveSec sekunder',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: widget.dayColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Slider(
                value: effectiveSec.toDouble().clamp(20.0, 120.0),
                min: 20,
                max: 120,
                divisions: 20,
                activeColor: widget.dayColor,
                label: '$effectiveSec s',
                onChanged: (val) {
                  setState(() => _localIntervalSec = val.round());
                },
                onChangeEnd: (val) async {
                  final newSec = val.round();
                  setState(() => _localIntervalSec = null);
                  await FirebaseFirestore.instance
                      .collection('families')
                      .doc(widget.familyId)
                      .collection('display_config')
                      .doc('main')
                      .set({
                    'foto': {'intervalSec': newSec},
                  }, SetOptions(merge: true));
                },
              ),
              const Text(
                'Tid per foto innan nästa bild visas (20–120 sekunder, standard 45s).',
                style: TextStyle(fontSize: 12, color: Color(0xFF666677)),
              ),
            ],
          ),
        );
      },
    );
  }
}
