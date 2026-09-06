import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_theme.dart';
import '../services/weather_service.dart';
import 'weather_detail_sheet.dart';

/// Aktuell temp + symbol för Hem-headern.
class WeatherHeaderBadge extends StatefulWidget {
  final double lat;
  final double lon;
  final String? placeName;
  final Color textColor;

  const WeatherHeaderBadge({
    super.key,
    required this.lat,
    required this.lon,
    this.placeName,
    required this.textColor,
  });

  @override
  State<WeatherHeaderBadge> createState() => _WeatherHeaderBadgeState();
}

class _WeatherHeaderBadgeState extends State<WeatherHeaderBadge> {
  WeatherSnapshot? _snap;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant WeatherHeaderBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lat != widget.lat || oldWidget.lon != widget.lon) {
      _load();
    }
  }

  Future<void> _load() async {
    final snap = await WeatherService.instance
        .forecastFor(widget.lat, widget.lon);
    if (mounted) setState(() => _snap = snap);
  }

  @override
  Widget build(BuildContext context) {
    final snap = _snap;
    if (snap == null) return const SizedBox.shrink();

    final temp = snap.currentTemp?.round() ??
        snap.daily.firstOrNull?.maxTemp?.round() ??
        snap.daily.firstOrNull?.minTemp?.round();
    if (temp == null) return const SizedBox.shrink();

    final emoji = snap.currentSymbol != null
        ? snap.currentEmoji
        : (snap.daily.firstOrNull?.emoji ?? '🌡️');
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => showWeatherDetailSheet(
          context,
          lat: widget.lat,
          lon: widget.lon,
          placeName: widget.placeName,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: widget.textColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 4),
              Text(
                '$temp°',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: widget.textColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 7-dagars prognosrad ovanför kalendern i Planering.
class WeatherForecastRow extends StatefulWidget {
  final double lat;
  final double lon;
  final Color dayColor;

  const WeatherForecastRow({
    super.key,
    required this.lat,
    required this.lon,
    required this.dayColor,
  });

  @override
  State<WeatherForecastRow> createState() => _WeatherForecastRowState();
}

class _WeatherForecastRowState extends State<WeatherForecastRow> {
  WeatherSnapshot? _snap;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant WeatherForecastRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lat != widget.lat || oldWidget.lon != widget.lon) {
      _load();
    }
  }

  Future<void> _load() async {
    final snap = await WeatherService.instance
        .forecastFor(widget.lat, widget.lon);
    if (mounted) setState(() => _snap = snap);
  }

  @override
  Widget build(BuildContext context) {
    final snap = _snap;
    if (snap == null || snap.daily.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: AppTheme.cardDecoration(radius: 14),
        child: Row(
          children: [
            for (var i = 0; i < snap.daily.length; i++) ...[
              if (i > 0) const SizedBox(width: 2),
              Expanded(child: _DayCell(day: snap.daily[i], color: widget.dayColor)),
            ],
          ],
        ),
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  final DailyForecast day;
  final Color color;

  const _DayCell({required this.day, required this.color});

  @override
  Widget build(BuildContext context) {
    String weekday;
    try {
      weekday = DateFormat('E', 'sv').format(day.date);
    } catch (_) {
      weekday = DateFormat('E').format(day.date);
    }
    weekday = weekday.replaceAll('.', '').toLowerCase();

    final max = day.maxTemp?.round();
    final min = day.minTemp?.round();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          weekday,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: color.withValues(alpha: 0.85),
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(day.emoji, style: const TextStyle(fontSize: 16)),
        const SizedBox(height: 2),
        if (max != null && min != null)
          Text(
            '$max°/$min°',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: AppTheme.getTextColor().withValues(alpha: 0.75),
            ),
            maxLines: 1,
          )
        else
          const SizedBox(height: 12),
      ],
    );
  }
}
