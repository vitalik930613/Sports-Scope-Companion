import 'package:flutter/material.dart';

import '../../recording/ride_metric_track.dart';

/// Le graphique de fond d'une case de mesure (`MetricView`) — une aire de
/// l'historique de la valeur, en aplat, plus le tracé de la courbe par-dessus.
/// Contrairement à `MetricTrendGraph` (`metric_trend_graph.dart`), pas de fond
/// opaque, pas de libellés d'échelle, pas de badge de valeur courante : rien
/// n'est peint en dehors de l'aire/du tracé, pour que le fond *plat* de la
/// case (posée dessous par `MetricView`/`BlockSurface`) reste visible partout
/// où la courbe ne passe pas.
///
/// `points` doit être trié par [MetricTrackPoint.elapsedS] croissant — même
/// contrat que `MetricTrendGraph`, garanti par `RideMetricTrack`.
class BackgroundChartGraph extends StatelessWidget {
  const BackgroundChartGraph({
    super.key,
    required this.points,
    required this.areaColor,
    this.lineColor = Colors.white,
  });

  final List<MetricTrackPoint> points;
  final Color areaColor;
  final Color lineColor;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => CustomPaint(
          size: Size(constraints.maxWidth, constraints.maxHeight),
          painter: _BackgroundChartPainter(points: points, areaColor: areaColor, lineColor: lineColor),
        ),
      );
}

class _BackgroundChartPainter extends CustomPainter {
  _BackgroundChartPainter({required this.points, required this.areaColor, required this.lineColor});

  final List<MetricTrackPoint> points;
  final Color areaColor;
  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    final firstS = points.first.elapsedS;
    final lastS = points.last.elapsedS;
    final span = lastS == firstS ? 1 : lastS - firstS;

    final maxValue = points.map((p) => p.value).reduce((a, b) => a > b ? a : b);
    final minValue = points.map((p) => p.value).reduce((a, b) => a < b ? a : b);
    // Marge des deux côtés, même parade que `MetricTrendGraph` : une valeur
    // qui oscille près d'une seule borne ne doit pas coller au bord de la
    // case.
    final range = maxValue == minValue ? 1.0 : maxValue - minValue;
    final loValue = minValue - range * 0.1;
    final hiValue = maxValue + range * 0.1;
    final valueSpan = hiValue == loValue ? 1.0 : hiValue - loValue;

    double xOf(int elapsedS) => (elapsedS - firstS) / span * size.width;
    double yOf(double value) => size.height * (1 - (value - loValue) / valueSpan);

    final line = Path();
    for (var i = 0; i < points.length; i++) {
      final x = xOf(points[i].elapsedS);
      final y = yOf(points[i].value);
      if (i == 0) {
        line.moveTo(x, y);
      } else {
        line.lineTo(x, y);
      }
    }

    final area = Path.from(line)
      ..lineTo(xOf(points.last.elapsedS), size.height)
      ..lineTo(xOf(points.first.elapsedS), size.height)
      ..close();
    canvas.drawPath(area, Paint()..color = areaColor);

    // Le tracé, par-dessus l'aire : un liseré noir sous le trait choisi, même
    // parade que `MetricTrendGraph` — reste lisible même quand `lineColor`
    // (blanc par défaut) se rapproche de la teinte de l'aire.
    canvas.drawPath(
      line,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_BackgroundChartPainter old) =>
      old.points != points || old.areaColor != areaColor || old.lineColor != lineColor;
}
