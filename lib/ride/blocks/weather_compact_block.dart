import 'package:flutter/material.dart';

import '../../dashboard/block_density.dart';
import '../../recording/ride_recorder.dart';
import '../../ui/zone_colors.dart';
import '../../weather/weather_forecast_client.dart';
import 'block_card.dart';

/// Les valeurs météo actuelles (Open-Meteo), pour la position GPS courante —
/// voir `WeatherCompactBlock` (`dashboard_block.dart`).
///
/// Trois chiffres — température, vent, pluie — tels que maintenant, chacun
/// avec une flèche qui dit où ça va dans les six prochaines heures. Pour la
/// case qui n'a pas la place du graphique de [WeatherForecastBlockView] :
/// même source et mêmes couleurs de série que lui ([WeatherForecastClient]),
/// pour que les deux composants se lisent comme une seule famille.
///
/// Taille naturelle, réduite à la case réelle par [ScaleToFit] (comme
/// [BlockCard]/[StatCard]) — contrairement à [WeatherForecastBlockView], qui
/// remplit toute la case : trois lignes de texte n'ont rien à gagner à
/// s'étirer, là où un graphique profite d'une case généreuse.
///
/// Relève une nouvelle prévision à chaque changement de position GPS
/// significatif — [WeatherForecastClient] throttle lui-même l'appel réseau.
class WeatherCompactBlockView extends StatefulWidget {
  WeatherCompactBlockView({
    super.key,
    required this.recorder,
    this.color,
    this.textColor,
    WeatherForecastClient? client,
  }) : client = client ?? WeatherForecastClient();

  final RideRecorder recorder;
  final Color? color;
  final Color? textColor;

  /// Injectable pour les tests ; par défaut un client qui parle au vrai proxy
  /// du site.
  final WeatherForecastClient client;

  @override
  State<WeatherCompactBlockView> createState() => _WeatherCompactBlockViewState();
}

class _WeatherCompactBlockViewState extends State<WeatherCompactBlockView> {
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
        final fix = widget.recorder.lastFix;
        if (fix == null) {
          return BlockCard(
            title: 'Météo',
            lines: const ['Pas de GPS.'],
            color: widget.color,
            textColor: widget.textColor,
          );
        }

        final forecast = _forecast;
        if (forecast == null || forecast.steps.isEmpty) {
          return BlockCard(
            title: 'Météo',
            lines: const ['Prévision indisponible.'],
            color: widget.color,
            textColor: widget.textColor,
          );
        }

        return _WeatherCompactCard(
          forecast: forecast,
          color: widget.color,
          textColor: widget.textColor,
        );
      },
    );
  }
}

/// Où va une mesure entre maintenant et le pas visé (~6h) : un écart sous le
/// seuil ne compte pas — même raison que l'hystérésis d'altitude
/// (`RideStats`), sans elle un bruit de mesure ferait clignoter la flèche
/// d'un relevé à l'autre plutôt que de rester stable.
enum _Trend { up, flat, down }

/// La carte composée : un titre, trois lignes (pastille de couleur, libellé,
/// valeur actuelle, flèche de tendance).
class _WeatherCompactCard extends StatelessWidget {
  const _WeatherCompactCard({required this.forecast, this.color, this.textColor});

  final WeatherForecast forecast;
  final Color? color;
  final Color? textColor;

  /// Largeur de construction avant mise à l'échelle — même convention que
  /// `_naturalCardWidth` de [BlockCard] : trois lignes courtes n'ont pas
  /// besoin de sa largeur (pensée pour des phrases), une case plus étroite
  /// suffit à les garder lisibles sans réduction inutile.
  static const _naturalWidth = 180.0;

  static const _tempColor = Color(0xFFFF8A3D);
  static const _windColor = Color(0xFF8FD3FF);
  static const _precipColor = Color(0xFF2E6FD6);

  // Seuils en dessous desquels la tendance reste « stable » : température et
  // vent horaires bruitent de quelques dixièmes/unités sans que ça vaille une
  // flèche, la pluie de quelques dixièmes de mm.
  static const _tempThreshold = 1.0; // °C
  static const _windThreshold = 3.0; // km/h
  static const _precipThreshold = 0.2; // mm/h

  @override
  Widget build(BuildContext context) {
    const metrics = BlockMetrics.natural;
    final ink = textColor ?? (color == null ? Colors.white : foregroundOf(color!));

    final now = forecast.steps.first;
    final later = _sixHourStepOf(forecast);

    return BlockSurface(
      background: color,
      child: SizedBox(
        width: _naturalWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'MÉTÉO',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: ink.withValues(alpha: 0.7), fontSize: metrics.titleSize),
            ),
            SizedBox(height: metrics.gap),
            _row(
              'Température',
              '${now.temperature.round()}°C',
              _tempColor,
              ink,
              metrics,
              later == null ? null : _trendOf(now.temperature, later.temperature, _tempThreshold),
            ),
            _row(
              'Vent',
              '${now.windSpeed.round()} km/h',
              _windColor,
              ink,
              metrics,
              later == null ? null : _trendOf(now.windSpeed, later.windSpeed, _windThreshold),
            ),
            _row(
              'Pluie',
              '${now.precipitation.toStringAsFixed(1)} mm/h',
              _precipColor,
              ink,
              metrics,
              later == null ? null : _trendOf(now.precipitation, later.precipitation, _precipThreshold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, Color dot, Color ink, BlockMetrics metrics, _Trend? trend) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: ink.withValues(alpha: 0.75), fontSize: metrics.lineSize * 0.85),
              ),
            ),
            SizedBox(width: metrics.gap / 2),
            Text(value, style: TextStyle(color: ink, fontSize: metrics.lineSize, fontWeight: FontWeight.w600)),
            const SizedBox(width: 4),
            Icon(_iconFor(trend), size: metrics.lineSize, color: ink.withValues(alpha: 0.75)),
          ],
        ),
      );

  IconData _iconFor(_Trend? trend) => switch (trend) {
        _Trend.up => Icons.trending_up,
        _Trend.down => Icons.trending_down,
        _Trend.flat || null => Icons.trending_flat,
      };

  _Trend _trendOf(double now, double later, double threshold) {
    final delta = later - now;
    if (delta > threshold) return _Trend.up;
    if (delta < -threshold) return _Trend.down;
    return _Trend.flat;
  }

  /// Le pas le plus proche de +6h, replié sur le dernier pas connu si l'API
  /// en renvoie moins — l'horizon annoncé au cycliste, pas une hypothèse sur
  /// combien de pas le proxy garantit. `null` seulement si un seul pas est
  /// disponible : rien à comparer, pas de flèche plutôt qu'une tendance
  /// devinée sur zéro donnée.
  WeatherForecastStep? _sixHourStepOf(WeatherForecast forecast) {
    final steps = forecast.steps;
    if (steps.length < 2) return null;
    final idx = steps.length > 6 ? 6 : steps.length - 1;
    return steps[idx];
  }
}
