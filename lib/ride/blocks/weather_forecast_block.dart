import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../dashboard/block_density.dart';
import '../../recording/ride_recorder.dart';
import '../../ui/zone_colors.dart';
import '../../weather/weather_forecast_client.dart';
import 'block_card.dart';

/// Les prévisions météo horaires (Open-Meteo), pour la position GPS
/// courante — voir `WeatherForecastBlock` (`dashboard_block.dart`).
///
/// Distinct de [PrecipForecastBlockView] (une phrase et une frise sur 3h, qui
/// répond à « une averse arrive-t-elle bientôt ? ») : ce bloc dessine un
/// graphique — température et vent en courbes, précipitations en barres —
/// pour lire la tendance de toute la sortie qui vient (12h).
///
/// Même convention de mise en page que [PrecipForecastBlockView] : le
/// graphique remplit toute la case ([Expanded]/[LayoutBuilder]), seul le
/// texte (titre, phrase de tête, légende) garde une taille fixe.
///
/// Relève une nouvelle prévision à chaque changement de position GPS
/// significatif — [WeatherForecastClient] throttle lui-même l'appel réseau.
class WeatherForecastBlockView extends StatefulWidget {
  WeatherForecastBlockView({
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
  State<WeatherForecastBlockView> createState() => _WeatherForecastBlockViewState();
}

class _WeatherForecastBlockViewState extends State<WeatherForecastBlockView> {
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
            title: 'Prévisions météo',
            lines: const ['Pas de GPS.'],
            color: widget.color,
            textColor: widget.textColor,
          );
        }

        final forecast = _forecast;
        if (forecast == null || forecast.steps.isEmpty) {
          return BlockCard(
            title: 'Prévisions météo',
            lines: const ['Prévision indisponible.'],
            color: widget.color,
            textColor: widget.textColor,
          );
        }

        return _WeatherForecastCard(
          forecast: forecast,
          color: widget.color,
          textColor: widget.textColor,
        );
      },
    );
  }
}

/// La carte composée : un titre, la phrase de tête, le graphique, sa légende.
class _WeatherForecastCard extends StatelessWidget {
  const _WeatherForecastCard({required this.forecast, this.color, this.textColor});

  final WeatherForecast forecast;
  final Color? color;
  final Color? textColor;

  /// Repli hors contrainte de hauteur (page qui défile), même raison que
  /// [PrecipForecastBlockView] : la case ne borne alors rien, le graphique
  /// garde une hauteur raisonnable plutôt que de s'effondrer à zéro.
  static const _chartAreaHeight = 64.0;

  static const _tempColor = Color(0xFFFF8A3D);
  static const _windColor = Color(0xFF8FD3FF);
  static const _precipColor = Color(0xFF2E6FD6);

  @override
  Widget build(BuildContext context) {
    const metrics = BlockMetrics.natural;
    final ink = textColor ?? (color == null ? Colors.white : foregroundOf(color!));

    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: EdgeInsets.all(BlockMetrics.natural.padding),
      decoration: BoxDecoration(
        color: color ?? BlockCard.background,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.hardEdge,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final chart = CustomPaint(
            painter: _WeatherChartPainter(steps: forecast.steps),
            size: Size.infinite,
          );

          // Le budget vertical du contenu fixe hors légende : rembourrage,
          // titre, phrase de tête, labels « Maintenant »/« +Nh ». Le
          // graphique n'y entre pas, il absorbe le reste via `Expanded` et
          // peut se réduire jusqu'à zéro sans déborder. `titleHeight`/
          // `lineHeight` incluent déjà leur propre interligne
          // (`BlockMetrics`, même valeurs recopiées côté éditeur).
          final chromeHeight = metrics.padding * 2 +
              metrics.titleHeight +
              metrics.gap +
              metrics.lineHeight +
              metrics.gap +
              2 +
              metrics.lineHeight;
          // La légende ajoute une ligne de plus : sous ce budget, une case
          // aussi basse qu'une seule ligne de grille n'a plus la place de
          // l'afficher en plus du graphique sans déborder de la carte
          // (`RenderFlex overflowed`). Elle disparaît alors plutôt que de
          // pousser la carte hors de sa case — le titre et les couleurs du
          // graphique restent lisibles sans elle.
          final showLegend =
              !constraints.hasBoundedHeight || constraints.maxHeight >= chromeHeight + metrics.gap / 2 + metrics.lineHeight;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: constraints.hasBoundedHeight ? MainAxisSize.max : MainAxisSize.min,
            children: [
              Text(
                'PRÉVISIONS MÉTÉO',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: ink.withValues(alpha: 0.7), fontSize: metrics.titleSize),
              ),
              SizedBox(height: metrics.gap),
              Text(
                _headline(),
                style: TextStyle(color: ink, fontSize: metrics.lineSize, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: metrics.gap),
              constraints.hasBoundedHeight
                  ? Expanded(child: chart)
                  : SizedBox(height: _chartAreaHeight, child: chart),
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Maintenant',
                      style: TextStyle(color: ink.withValues(alpha: 0.6), fontSize: metrics.lineSize * 0.75)),
                  Text(_lastLabel(),
                      style: TextStyle(color: ink.withValues(alpha: 0.6), fontSize: metrics.lineSize * 0.75)),
                ],
              ),
              if (showLegend) ...[
                SizedBox(height: metrics.gap / 2),
                // Un `Row` à trois tiers égaux et non un `Wrap` : une case
                // étroite (une colonne d'une grille à plusieurs colonnes) ne
                // doit jamais faire passer la légende sur une deuxième
                // ligne — ce serait une hauteur de plus, non comptée dans
                // `showLegend`, et donc un débordement. Chaque libellé se
                // tronque plutôt (`_legendChip`), la légende reste toujours
                // exactement une ligne.
                Row(
                  children: [
                    Expanded(child: _legendChip('Température', _tempColor, ink, metrics)),
                    Expanded(child: _legendChip('Vent', _windColor, ink, metrics)),
                    Expanded(child: _legendChip('Précipitations', _precipColor, ink, metrics)),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _legendChip(String label, Color dot, Color ink, BlockMetrics metrics) => Row(
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: ink.withValues(alpha: 0.75), fontSize: metrics.lineSize * 0.7),
            ),
          ),
        ],
      );

  String _headline() {
    final first = forecast.steps.first;
    return '${first.temperature.round()}°C · vent ${first.windSpeed.round()} km/h';
  }

  String _lastLabel() => '+${forecast.steps.length}h';
}

/// Le graphique lui-même : température et vent en courbes (chacune sur sa
/// propre échelle — un min/max ne dit rien de l'autre, les unités diffèrent),
/// précipitations en barres sur le tiers bas.
class _WeatherChartPainter extends CustomPainter {
  _WeatherChartPainter({required this.steps});

  final List<WeatherForecastStep> steps;

  /// La hauteur pleine d'une barre, en mm sur l'heure — au-delà, l'intensité
  /// ne change plus la lecture. Un cumul horaire est d'ordinaire plus faible
  /// qu'un pic à 15 min (voir `PrecipForecastBlockView._maxMmPerStep`), d'où
  /// un plafond plus bas.
  static const _maxMmPerHour = 2.0;

  /// Les barres n'occupent que le tiers bas du graphique : le reste est
  /// réservé aux courbes, qui ont besoin de toute la hauteur pour rester
  /// lisibles.
  static const _barAreaFraction = 0.35;

  static const _tempColor = Color(0xFFFF8A3D);
  static const _windColor = Color(0xFF8FD3FF);
  static const _precipColor = Color(0xFF2E6FD6);

  @override
  void paint(Canvas canvas, Size size) {
    if (steps.isEmpty || size.width <= 0 || size.height <= 0) return;

    _paintGrid(canvas, size);
    _paintBars(canvas, size);
    _paintLine(
      canvas,
      size,
      steps.map((s) => s.windSpeed).toList(growable: false),
      _windColor,
      dashed: true,
      labelsOnRight: true,
    );
    _paintLine(
      canvas,
      size,
      steps.map((s) => s.temperature).toList(growable: false),
      _tempColor,
      dashed: false,
      labelsOnRight: false,
      labelSuffix: '°',
    );
  }

  /// Cadrillage de fond : horizontal fixe (haut/milieu/bas), vertical calé
  /// sur l'intervalle réel entre deux pas plutôt que sur un index — l'API
  /// n'est pas garantie strictement horaire. Purement un repère visuel, pas
  /// lié à l'échelle d'une courbe en particulier (température et vent ont
  /// chacune la sienne, voir `_paintLine`).
  void _paintGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..strokeWidth = 1;

    for (final fraction in const [0.0, 0.5, 1.0]) {
      final y = fraction * size.height;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    if (steps.length < 2) return;
    final stepMinutes = steps[1].time.difference(steps[0].time).inMinutes;
    if (stepMinutes <= 0) return;

    final stepsPerLine = math.max(1, (180 / stepMinutes).round());
    final stepX = size.width / (steps.length - 1);
    for (var i = stepsPerLine; i < steps.length - 1; i += stepsPerLine) {
      final x = i * stepX;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  void _paintBars(Canvas canvas, Size size) {
    final paint = Paint()..color = _precipColor.withValues(alpha: 0.55);
    final stepX = size.width / steps.length;
    final barWidth = stepX * 0.6;
    final barAreaHeight = size.height * _barAreaFraction;

    for (var i = 0; i < steps.length; i++) {
      final height = _barHeight(steps[i].precipitation, barAreaHeight);
      if (height <= 0) continue;

      final x = i * stepX + (stepX - barWidth) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, size.height - height, barWidth, height),
          const Radius.circular(1.5),
        ),
        paint,
      );
    }

    _paintPrecipScaleLabels(canvas, size, barAreaHeight);
  }

  double _barHeight(double mmPerHour, double barAreaHeight) =>
      (mmPerHour / _maxMmPerHour).clamp(0.0, 1.0) * barAreaHeight;

  /// Min/max du cumul horaire affiché, même convention que les courbes
  /// (`_paintScaleLabels`) mais centrées : gauche et droite sont déjà pris
  /// par température et vent. Rien à montrer si la fenêtre reste sèche —
  /// « 0mm » ne ferait que confirmer ce que l'absence de barre dit déjà. Le
  /// label se cale sur la même hauteur que la barre correspondante
  /// (`_barHeight`), donc juste au-dessus d'elle même quand le cumul dépasse
  /// le plafond d'affichage (`_maxMmPerHour`).
  void _paintPrecipScaleLabels(Canvas canvas, Size size, double barAreaHeight) {
    final values = steps.map((s) => s.precipitation).toList(growable: false);
    final max = values.reduce(math.max);
    if (max <= 0) return;
    final min = values.reduce(math.min);

    void paintAt(double value) {
      final painter = TextPainter(
        text: TextSpan(
          text: '${value.toStringAsFixed(1)}mm',
          style: const TextStyle(color: _precipColor, fontSize: 8, fontWeight: FontWeight.w600),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final dx = (size.width - painter.width) / 2;
      final y = size.height - _barHeight(value, barAreaHeight);
      final dy = (y - painter.height / 2).clamp(0.0, math.max(0.0, size.height - painter.height)).toDouble();
      painter.paint(canvas, Offset(dx, dy));
    }

    paintAt(max);
    if (min > 0) paintAt(min);
  }

  void _paintLine(
    Canvas canvas,
    Size size,
    List<double> values,
    Color color, {
    required bool dashed,
    required bool labelsOnRight,
    String labelSuffix = '',
  }) {
    if (values.length < 2) return;

    final min = values.reduce(math.min);
    final max = values.reduce(math.max);
    final span = (max - min) == 0 ? 1.0 : (max - min);
    // Un peu de marge verticale : une courbe qui touche les bords se lit mal.
    const paddingV = 4.0;
    final usableHeight = size.height - paddingV * 2;
    final stepX = size.width / (values.length - 1);

    final points = <Offset>[
      for (var i = 0; i < values.length; i++)
        Offset(i * stepX, paddingV + (1 - (values[i] - min) / span) * usableHeight),
    ];

    final paint = Paint()
      ..color = color
      ..strokeWidth = dashed ? 1.5 : 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (!dashed) {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, paint);
    } else {
      // Une ligne pointillée à la main : contrairement à SVG côté éditeur
      // (`CompanionBlockPreview.vue`, `stroke-dasharray`), `Paint`/`Path` de
      // Flutter n'a pas de motif de trait natif.
      for (var i = 0; i < points.length - 1; i++) {
        _drawDashedSegment(canvas, points[i], points[i + 1], paint);
      }
    }

    _paintScaleLabels(canvas, size, min, max, color, labelsOnRight, labelSuffix);
  }

  /// Les bornes de la plage affichée, dans la couleur de la courbe : pas
  /// d'axe numéroté commun possible, température et vent sont normalisés
  /// chacun sur son propre min/max (voir le commentaire de classe). Gauche
  /// pour la température, droite pour le vent — les deux se retrouveraient
  /// sinon superposées, chaque courbe utilisant toute la hauteur disponible.
  void _paintScaleLabels(
    Canvas canvas,
    Size size,
    double min,
    double max,
    Color color,
    bool alignRight,
    String suffix,
  ) {
    void paintAt(double value, double y) {
      final painter = TextPainter(
        text: TextSpan(
          text: '${value.round()}$suffix',
          style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.w600),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final x = alignRight ? size.width - painter.width : 0.0;
      final dy = (y - painter.height / 2).clamp(0.0, math.max(0.0, size.height - painter.height)).toDouble();
      painter.paint(canvas, Offset(x, dy));
    }

    paintAt(max, 0);
    paintAt(min, size.height);
  }

  void _drawDashedSegment(Canvas canvas, Offset start, Offset end, Paint paint) {
    const dashLength = 4.0;
    const gapLength = 3.0;

    final total = (end - start).distance;
    if (total == 0) return;

    final direction = (end - start) / total;
    var covered = 0.0;
    while (covered < total) {
      final segmentEnd = math.min(covered + dashLength, total);
      canvas.drawLine(start + direction * covered, start + direction * segmentEnd, paint);
      covered += dashLength + gapLength;
    }
  }

  @override
  bool shouldRepaint(covariant _WeatherChartPainter oldDelegate) => !identical(oldDelegate.steps, steps);
}
