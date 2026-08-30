import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../recording/ride_recorder.dart';
import '../../weather/weather_forecast_client.dart';
import 'block_card.dart';

/// Le vent tel qu'on le prend en roulant — voir `WindBlock`
/// (`dashboard_block.dart`).
///
/// Croise deux sources : la prévision horaire Open-Meteo (via le proxy du
/// site, comme les autres blocs météo) pour la vitesse et la direction du
/// vent, et le cap GPS de l'enregistreur pour savoir dans quel sens on va. De
/// leur produit sort la **composante de face** (vitesse du vent projetée sur
/// le cap, positive quand il freine, négative quand il pousse) et un repère
/// de direction relative au déplacement.
///
/// Sans cap frais — à l'arrêt, GPS perdu, home-trainer — il ne peut rien
/// projeter : il se rabat sur le vent absolu (vitesse et secteur). Sans
/// direction du vent (prévision servie par un site antérieur au champ), même
/// repli.
class WindBlockView extends StatefulWidget {
  WindBlockView({
    super.key,
    required this.recorder,
    this.color,
    this.textColor,
    WeatherForecastClient? client,
  }) : client = client ?? WeatherForecastClient();

  final RideRecorder recorder;
  final Color? color;
  final Color? textColor;

  /// Injectable pour les tests ; par défaut un client qui parle au proxy du
  /// site.
  final WeatherForecastClient client;

  @override
  State<WindBlockView> createState() => _WindBlockViewState();
}

class _WindBlockViewState extends State<WindBlockView> {
  WeatherForecast? _forecast;
  bool _fetching = false;

  @override
  void initState() {
    super.initState();
    widget.recorder.addListener(_onRecorderChanged);
    _maybeRefresh();
  }

  @override
  void dispose() {
    widget.recorder.removeListener(_onRecorderChanged);
    super.dispose();
  }

  void _onRecorderChanged() => _maybeRefresh();

  Future<void> _maybeRefresh() async {
    if (_fetching) return;
    final fix = widget.recorder.lastFix;
    if (fix == null) return;

    _fetching = true;
    final forecast = await widget.client.forecastFor(fix.lat, fix.lng);
    _fetching = false;
    if (mounted && forecast != null) setState(() => _forecast = forecast);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.recorder,
      builder: (context, _) {
        final step = _forecast?.steps.isNotEmpty ?? false
            ? _forecast!.steps.first
            : null;
        if (step == null) {
          return BlockCard(
            title: 'Vent',
            lines: const ['Prévision indisponible.'],
            color: widget.color,
            textColor: widget.textColor,
          );
        }

        final now = DateTime.now();
        final fix = widget.recorder.lastFix;
        final heading = fix != null &&
                now.difference(fix.at) <= RideRecorder.fixTtl
            ? fix.headingDeg
            : null;
        final direction = step.windDirection;

        return BlockCard(
          title: 'Vent',
          lines: _lines(step.windSpeed, direction, heading),
          color: widget.color,
          textColor: widget.textColor,
        );
      },
    );
  }

  static List<String> _lines(
    double windSpeedKmh,
    double? windFromDeg,
    double? headingDeg,
  ) {
    final absolute = '${windSpeedKmh.round()} km/h';
    if (windFromDeg == null || headingDeg == null) {
      final sector = windFromDeg == null ? null : _cardinal(windFromDeg);
      return [
        'Vent $absolute',
        sector == null ? 'Direction inconnue' : 'Secteur $sector',
      ];
    }

    // Angle du vent (d'où il vient) par rapport au cap, ramené à [-180, 180].
    final theta = _wrap180(windFromDeg - headingDeg);
    final headwind = windSpeedKmh * math.cos(theta * math.pi / 180);
    final qualifier = theta.abs() <= 45
        ? 'De face'
        : theta.abs() >= 135
            ? 'De dos'
            : 'De travers';
    // Flèche 8 directions : sens dans lequel le vent te pousse, « haut » =
    // vent arrière. `theta + 180` fait passer « d'où il vient » à « où il
    // va », relatif au cap.
    final arrow = _arrow(theta + 180);

    return [
      '$arrow $qualifier · ${headwind.abs().round()} km/h',
      'Vent $absolute',
    ];
  }

  static double _wrap180(double deg) {
    final r = (deg + 180) % 360;
    return (r < 0 ? r + 360 : r) - 180;
  }

  static String _arrow(double deg) {
    const arrows = ['↑', '↗', '→', '↘', '↓', '↙', '←', '↖'];
    final r = ((deg % 360) + 360) % 360;
    return arrows[(r / 45).round() % 8];
  }

  static String _cardinal(double deg) {
    const points = ['N', 'NE', 'E', 'SE', 'S', 'SO', 'O', 'NO'];
    final r = ((deg % 360) + 360) % 360;
    return points[(r / 45).round() % 8];
  }
}
