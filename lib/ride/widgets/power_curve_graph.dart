import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Un point de la courbe de puissance : une durée tenue, la meilleure moyenne
/// vue pour elle.
@immutable
class PowerCurvePoint {
  const PowerCurvePoint(this.durationS, this.watts);

  final int durationS;
  final int watts;
}

/// Le graphique de la courbe de puissance : durée en abscisse, **échelle
/// logarithmique** (5 s et 90 min ne se lisent pas sur la même règle
/// linéaire — la première moitié du graphique serait vide), puissance en
/// ordonnée, linéaire.
///
/// `points` doit déjà être trié par durée croissante et n'avoir que des
/// durées atteintes (voir `RideStats.powerCurveW`, qui n'écrit une entrée que
/// lorsque sa fenêtre s'est remplie) : ce widget ne filtre ni ne trie, il
/// dessine ce qu'on lui donne.
class PowerCurveGraph extends StatelessWidget {
  const PowerCurveGraph({super.key, required this.points});

  final List<PowerCurvePoint> points;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => CustomPaint(
          size: Size(constraints.maxWidth, constraints.maxHeight),
          painter: _PowerCurvePainter(points: points),
        ),
      );
}

class _PowerCurvePainter extends CustomPainter {
  _PowerCurvePainter({required this.points});

  final List<PowerCurvePoint> points;

  static const _bg = Color(0xFF14161A);
  static const _line = Color(0xFFFFA726);
  static const _grid = Color(0x1FFFFFFF);
  static const _label = Color(0x99FFFFFF);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8)),
      Paint()..color = _bg,
    );

    if (points.length < 2) return;

    // Marge basse pour les libellés de durée, sous le tracé.
    const labelHeight = 16.0;
    final plotHeight = math.max(size.height - labelHeight, 1.0);

    final logFirst = math.log(points.first.durationS.toDouble());
    final logLast = math.log(points.last.durationS.toDouble());
    final logSpan = logLast == logFirst ? 1.0 : logLast - logFirst;

    final maxWatts = points.map((p) => p.watts).reduce(math.max);
    final minWatts = points.map((p) => p.watts).reduce(math.min);
    // La courbe descend presque toujours (moyenne sur une fenêtre plus
    // longue = plus basse) : ancrer le bas de l'échelle à 0 l'écraserait
    // dans le tiers supérieur du graphique. 10 % de marge en haut pour que
    // le sommet ne touche jamais le bord.
    final loWatts = math.min(minWatts.toDouble(), maxWatts * 0.9);
    final hiWatts = maxWatts * 1.1;
    final wattsSpan = hiWatts == loWatts ? 1.0 : hiWatts - loWatts;

    double xOf(int durationS) =>
        (math.log(durationS.toDouble()) - logFirst) / logSpan * size.width;
    double yOf(int watts) => plotHeight * (1 - (watts - loWatts) / wattsSpan);

    final gridPaint = Paint()
      ..color = _grid
      ..strokeWidth = 1;
    const labelStyle = TextStyle(color: _label, fontSize: 9);
    for (final point in points) {
      final x = xOf(point.durationS);
      canvas.drawLine(Offset(x, 0), Offset(x, plotHeight), gridPaint);

      final painter = TextPainter(
        text: TextSpan(text: _durationLabel(point.durationS), style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      // `size.width - painter.width` peut être négatif — une case étroite
      // (colonne d'une page Tours à plusieurs colonnes) où le libellé
      // dépasse la largeur du graphique — et `clamp` exige `lowerLimit <=
      // upperLimit`, sous peine de lever. `math.max(0, …)` absorbe ce cas :
      // le libellé part alors du bord gauche, tronqué par le clip du
      // graphique plutôt que de faire planter tout le tracé.
      final maxX = math.max(0.0, size.width - painter.width);
      painter.paint(
        canvas,
        Offset((x - painter.width / 2).clamp(0, maxX), size.height - painter.height),
      );
    }

    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final x = xOf(points[i].durationS);
      final y = yOf(points[i].watts);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = _line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );

    for (final point in points) {
      canvas.drawCircle(
        Offset(xOf(point.durationS), yOf(point.watts)),
        3,
        Paint()..color = _line,
      );
    }
  }

  static String _durationLabel(int seconds) =>
      seconds < 60 ? '${seconds}s' : '${seconds ~/ 60}m';

  @override
  bool shouldRepaint(_PowerCurvePainter old) => !_sameData(old.points);

  bool _sameData(List<PowerCurvePoint> other) {
    if (other.length != points.length) return false;
    for (var i = 0; i < points.length; i++) {
      if (other[i].durationS != points[i].durationS || other[i].watts != points[i].watts) {
        return false;
      }
    }
    return true;
  }
}
