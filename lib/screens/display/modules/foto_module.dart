import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../models/display_photo_model.dart';
import '../../../providers/family_provider.dart';
import '../../../services/display_photo_service.dart';
import '../../../app_theme.dart';
import '../display_log.dart';
import '../display_module_registry.dart';

/// Spellogik för storskärmens bildvisning (FAS 4.5).
///
/// Hanterar:
/// - Slumpad ordning (shuffle)
/// - Garanti mot omedelbar upprepning vid omgångsslut (om > 1 foto)
/// - Dynamisk uteslutning av trasiga bild-URL:er
class PhotoPlaylist {
  List<DisplayPhotoModel> _originalPhotos;
  final Set<String> _brokenUrls;
  final Random _random;

  List<DisplayPhotoModel> _queue = [];
  int _index = -1;

  PhotoPlaylist({
    List<DisplayPhotoModel> photos = const [],
    Set<String>? brokenUrls,
    Random? random,
  })  : _originalPhotos = List.unmodifiable(photos),
        _brokenUrls = brokenUrls ?? <String>{},
        _random = random ?? Random() {
    _initQueue();
  }

  /// Aktuell kö med giltiga foton i spelordning.
  List<DisplayPhotoModel> get queue => List.unmodifiable(_queue);

  /// Nuvarande index i kön.
  int get currentIndex => _index;

  /// Kända trasiga URL:er.
  Set<String> get brokenUrls => Set.unmodifiable(_brokenUrls);

  /// Returnerar det foto som visas nu, eller null om spellistan är tom.
  DisplayPhotoModel? get currentPhoto {
    if (_index >= 0 && _index < _queue.length) {
      return _queue[_index];
    }
    return null;
  }

  /// Totalt antal giltiga foton.
  int get validCount => _queue.length;

  /// Sant om inga giltiga foton finns i spellistan.
  bool get isEmpty => _queue.isEmpty;

  void _initQueue({String? previousLastId}) {
    final valid = _originalPhotos
        .where((p) => p.url.isNotEmpty && !_brokenUrls.contains(p.url))
        .toList();

    if (valid.isEmpty) {
      _queue = [];
      _index = -1;
      return;
    }

    valid.shuffle(_random);

    // Garanti mot omedelbar upprepning: om första fotot i nya cykeln är samma
    // som sista fotot i föregående cykel, swappar vi med ett annat element.
    if (previousLastId != null &&
        valid.length > 1 &&
        valid.first.id == previousLastId) {
      final swapIdx = 1 + _random.nextInt(valid.length - 1);
      final temp = valid[0];
      valid[0] = valid[swapIdx];
      valid[swapIdx] = temp;
    }

    _queue = valid;
    _index = 0;
  }

  /// Uppdaterar spellistan med en ny lista foton från databasen.
  void updatePhotos(List<DisplayPhotoModel> newPhotos) {
    final currentId = currentPhoto?.id;
    _originalPhotos = List.unmodifiable(newPhotos);

    final valid = _originalPhotos
        .where((p) => p.url.isNotEmpty && !_brokenUrls.contains(p.url))
        .toList();

    if (valid.isEmpty) {
      _queue = [];
      _index = -1;
      return;
    }

    // Om vi redan hade en kö och det aktuella fotot fortfarande finns,
    // behåll det och lägg resten i kön bakom.
    if (currentId != null && valid.any((p) => p.id == currentId)) {
      final current = valid.firstWhere((p) => p.id == currentId);
      final remaining = valid.where((p) => p.id != currentId).toList()
        ..shuffle(_random);
      _queue = [current, ...remaining];
      _index = 0;
    } else {
      _initQueue();
    }
  }

  /// Flyttar till nästa foto i spellistan och returnerar det.
  DisplayPhotoModel? nextPhoto() {
    if (_queue.isEmpty) return null;

    _index++;
    if (_index >= _queue.length) {
      final lastId = _queue.last.id;
      _initQueue(previousLastId: lastId);
    }

    return currentPhoto;
  }

  /// Markerar en bild-URL som trasig.
  /// Returnerar true om URL:en var ny och lades till i trasig-listan.
  bool markBroken(String url) {
    if (!_brokenUrls.add(url)) {
      return false; // Redan känd som trasig
    }

    final currentId = currentPhoto?.id;
    _queue.removeWhere((p) => p.url == url);

    if (_queue.isEmpty) {
      _index = -1;
    } else {
      // Om det aktiva fotot togs bort, säkerställ giltigt index
      if (_index >= _queue.length) {
        _index = 0;
      } else if (currentId != null && currentPhoto?.id != currentId) {
        // Nuvarande har skiftat, clamp
        _index = _index.clamp(0, _queue.length - 1);
      }
    }

    return true;
  }
}

/// Modul för fullskärmsbildspel med diskret klocka (FAS 4.5).
class FotoModule extends StatefulWidget {
  final DisplayModuleContext moduleContext;

  const FotoModule({super.key, required this.moduleContext});

  @override
  State<FotoModule> createState() => _FotoModuleState();
}

class _FotoModuleState extends State<FotoModule> {
  static const Duration crossfadeDuration = Duration(milliseconds: 800);

  Duration get _rotationInterval {
    final sec = widget.moduleContext.fotoConfig?.intervalSec ?? 45;
    return Duration(seconds: sec);
  }

  final PhotoPlaylist _playlist = PhotoPlaylist();
  Timer? _rotationTimer;
  StreamSubscription<List<DisplayPhotoModel>>? _photosSub;
  String _currentFamilyId = '';
  bool _hasLoggedInitialCount = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkFamilySubscription();
  }

  @override
  void didUpdateWidget(covariant FotoModule oldWidget) {
    super.didUpdateWidget(oldWidget);
    _checkFamilySubscription();
    if (oldWidget.moduleContext.fotoConfig?.intervalSec !=
        widget.moduleContext.fotoConfig?.intervalSec) {
      DisplayLog.instance.log(
        'foto',
        'Fotointervall uppdaterat till ${widget.moduleContext.fotoConfig?.intervalSec ?? 45}s',
      );
      _startTimer();
    }
  }

  void _checkFamilySubscription() {
    final familyId = widget.moduleContext.familyId ??
        context.watch<FamilyProvider>().currentUser?.familyId ??
        '';

    if (familyId != _currentFamilyId) {
      _currentFamilyId = familyId;
      _photosSub?.cancel();
      _hasLoggedInitialCount = false;

      if (familyId.isNotEmpty) {
        _photosSub = DisplayPhotoService.instance
            .streamPhotos(familyId)
            .listen(_onPhotosUpdated);
      }
    }
  }

  void _onPhotosUpdated(List<DisplayPhotoModel> photos) {
    if (!_hasLoggedInitialCount) {
      _hasLoggedInitialCount = true;
      DisplayLog.instance.log(
        'foto',
        'Fotomodul startad med ${photos.length} foton',
      );
    }

    if (mounted) {
      setState(() {
        _playlist.updatePhotos(photos);
      });
    }
  }

  void _startTimer() {
    _rotationTimer?.cancel();
    _rotationTimer = Timer.periodic(_rotationInterval, (_) {
      if (mounted && !_playlist.isEmpty) {
        setState(() {
          _playlist.nextPhoto();
        });
      }
    });
  }

  void _onImageError(String url) {
    if (_playlist.markBroken(url)) {
      DisplayLog.instance.log(
        'foto-fel',
        'Kunde inte ladda foto: $url',
      );
      if (mounted) {
        setState(() {});
      }
    }
  }

  @override
  void dispose() {
    _rotationTimer?.cancel();
    _photosSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photo = _playlist.currentPhoto;
    final now = widget.moduleContext.now;
    final isLowStimuli = AppTheme.lowStimuli;

    // Inbränningsförskjutning per timme
    final dx = ((now.hour * 37) % 70) - 35.0;
    final dy = ((now.hour * 19) % 50) - 25.0;

    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Bildspel med mjuk övertoning (eller direkt klipp i lågstimuli)
          AnimatedSwitcher(
            duration: isLowStimuli ? Duration.zero : crossfadeDuration,
            switchInCurve: Curves.easeInOut,
            switchOutCurve: Curves.easeInOut,
            layoutBuilder: (currentChild, previousChildren) {
              return Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  ...previousChildren,
                  ?currentChild,
                ],
              );
            },
            child: photo != null
                ? SizedBox.expand(
                    key: ValueKey(photo.id),
                    child: Image.network(
                      photo.url,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _onImageError(photo.url);
                        });
                        return const SizedBox.shrink();
                      },
                    ),
                  )
                : _buildEmptyState(),
          ),

          // Diskret klocka i nedre högra hörnet med inbränningsförskjutning
          Positioned(
            bottom: 32 + dy,
            right: 40 + dx,
            child: _buildCornerClock(now),
          ),
        ],
      ),
    );
  }

  Widget _buildCornerClock(DateTime now) {
    final timeStr = DateFormat('HH:mm').format(now);
    final rawDate = DateFormat('EEEE d MMMM', 'sv_SE').format(now);
    final dateStr = rawDate.isNotEmpty
        ? rawDate[0].toUpperCase() + rawDate.substring(1)
        : rawDate;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.40),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
          width: 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            timeStr,
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 52,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.5,
              color: Colors.white.withValues(alpha: 0.88),
              height: 1.0,
              shadows: [
                Shadow(
                  color: Colors.black.withValues(alpha: 0.8),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            dateStr,
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.75),
              shadows: [
                Shadow(
                  color: Colors.black.withValues(alpha: 0.8),
                  blurRadius: 8,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      key: const ValueKey('empty_state'),
      color: const Color(0xFF0F1218),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.photo_library_outlined,
                size: 44,
                color: Colors.white.withValues(alpha: 0.35),
              ),
            ),
            const SizedBox(height: 22),
            Text(
              'Inga foton ännu',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: Colors.white.withValues(alpha: 0.80),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Lägg till foton under Inställningar → Storskärm i appen',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.white.withValues(alpha: 0.45),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
