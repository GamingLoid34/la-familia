import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_theme.dart';
import '../services/weather_service.dart';
import '../utils/clothing_advice.dart';

/// Visar detaljerad timprognos i en bottom sheet.
Future<void> showWeatherDetailSheet(
  BuildContext context, {
  required double lat,
  required double lon,
  String? placeName,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _WeatherDetailSheet(
      lat: lat,
      lon: lon,
      placeName: placeName,
    ),
  );
}

class _WeatherDetailSheet extends StatefulWidget {
  final double lat;
  final double lon;
  final String? placeName;

  const _WeatherDetailSheet({
    required this.lat,
    required this.lon,
    this.placeName,
  });

  @override
  State<_WeatherDetailSheet> createState() => _WeatherDetailSheetState();
}

class _WeatherDetailSheetState extends State<_WeatherDetailSheet> {
  WeatherSnapshot? _snap;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final snap = await WeatherService.instance
          .forecastFor(widget.lat, widget.lon);
      if (mounted) {
        setState(() {
          _snap = snap;
          _loading = false;
        });
      }
    } catch (e, stack) {
      developer.log('Kunde inte läsa väderdetaljer',
          error: e, stackTrace: stack);
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dayColor = AppTheme.getDayAccentColor();
    final maxHeight = MediaQuery.of(context).size.height * 0.85;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: SafeArea(
        top: false,
        child: _buildBody(context, dayColor),
      ),
    );
  }

  Widget _buildBody(BuildContext context, Color dayColor) {
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.all(40),
        child: Center(
          child: CircularProgressIndicator(color: dayColor),
        ),
      );
    }

    final snap = _snap;
    if (snap == null || snap.hourly.isEmpty) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 16),
          _buildDragHandle(),
          const SizedBox(height: 32),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Kunde inte hämta prognosen just nu.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      );
    }

    final now = DateTime.now();
    final advice = buildClothingAdvice(snap.hourly, now);

    final temp = snap.currentTemp?.round() ??
        snap.hourly.firstOrNull?.temp?.round();
    final emoji = snap.currentSymbol != null
        ? snap.currentEmoji
        : (snap.hourly.firstOrNull?.emoji ?? '🌡️');

    final title = (widget.placeName != null && widget.placeName!.trim().isNotEmpty)
        ? widget.placeName!.trim()
        : 'Vädret';

    final items = _buildListItems(snap.hourly, now);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        _buildDragHandle(),
        const SizedBox(height: 16),

        // 1) Rubrikrad
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: AppTheme.cardTitleStyle.copyWith(fontSize: 18),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 28)),
                  if (temp != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      '$temp°',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),

        // 2) Klädrådskort
        if (advice != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: dayColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('🧥', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${advice.windowLabel}: ',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Color(0xFF1A1A2E),
                            ),
                          ),
                          TextSpan(
                            text: advice.text.startsWith('${advice.windowLabel}: ')
                                ? advice.text.substring(advice.windowLabel.length + 2)
                                : advice.text,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF1A1A2E),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],

        const SizedBox(height: 12),

        // 3) Timlistan
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              if (item.isHeader) {
                return Padding(
                  padding: const EdgeInsets.only(top: 14, bottom: 6, left: 4),
                  child: Text(
                    item.headerText!,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade600,
                      letterSpacing: 0.5,
                    ),
                  ),
                );
              }

              final h = item.forecast!;
              final isCurrentHour = now.year == h.time.year &&
                  now.month == h.time.month &&
                  now.day == h.time.day &&
                  now.hour == h.time.hour;

              return Container(
                margin: const EdgeInsets.symmetric(vertical: 2),
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                decoration: BoxDecoration(
                  color: isCurrentHour
                      ? dayColor.withValues(alpha: 0.10)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    // HH:mm
                    SizedBox(
                      width: 48,
                      child: Text(
                        DateFormat('HH:mm').format(h.time),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF1A1A2E),
                        ),
                      ),
                    ),
                    // Symbol emoji
                    Text(h.emoji, style: const TextStyle(fontSize: 18)),
                    const SizedBox(width: 8),
                    // Temperatur
                    Expanded(
                      child: Text(
                        h.temp != null ? '${h.temp!.round()}°' : '-',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A1A2E),
                        ),
                      ),
                    ),
                    // Nederbörd
                    if (h.precipMm != null && h.precipMm! >= 0.1) ...[
                      Text(
                        '${h.precipMm!.toStringAsFixed(1).replaceAll('.', ',')} mm',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.blue.shade600,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    // Vind
                    if (h.windMs != null) ...[
                      Text(
                        h.gustMs != null && h.gustMs! >= 12
                            ? '${h.windMs!.round()} (${h.gustMs!.round()}) m/s'
                            : '${h.windMs!.round()} m/s',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),

        // 4) Footer
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            'Källa: SMHI · uppdaterad ${DateFormat('HH:mm').format(snap.fetchedAt)}',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDragHandle() {
    return Center(
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.grey.shade300,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  List<_SheetListItem> _buildListItems(
      List<HourlyForecast> hourly, DateTime now) {
    final items = <_SheetListItem>[];
    DateTime? lastDate;
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    for (final h in hourly) {
      final itemDate = DateTime(h.time.year, h.time.month, h.time.day);
      if (lastDate == null || itemDate != lastDate) {
        String headerTitle;
        if (itemDate == today) {
          headerTitle = 'IDAG';
        } else if (itemDate == tomorrow) {
          headerTitle = 'IMORGON';
        } else {
          String formatted;
          try {
            formatted = DateFormat('EEEE d/M', 'sv').format(itemDate);
          } catch (_) {
            formatted = DateFormat('EEEE d/M').format(itemDate);
          }
          headerTitle = formatted.toUpperCase();
        }
        items.add(_SheetListItem.header(headerTitle));
        lastDate = itemDate;
      }
      items.add(_SheetListItem.forecast(h));
    }
    return items;
  }
}

class _SheetListItem {
  final String? headerText;
  final HourlyForecast? forecast;

  _SheetListItem.header(this.headerText) : forecast = null;
  _SheetListItem.forecast(this.forecast) : headerText = null;

  bool get isHeader => headerText != null;
}
