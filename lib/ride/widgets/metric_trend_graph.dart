import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../account/rider_profile.dart';
import '../../recording/ride_metric_track.dart';
import '../../ui/formats.dart';
import '../../ui/zone_colors.dart';

/// Le graphique de tendance d'une mesure de capteur (cardio, puissance) dans
/// le temps : abscisse en secondes écoulées, ordonnée la mesure — aire sous
/// la courbe peinte aux couleurs de zone, même dessin que
/// `ElevationProfileGraph` colore ses segments par pente, mais sur la valeur
/// du segment plutôt que sur sa dérivée : ici on colore *ce qu'on mesure*, pas
/// *sa variation*.
///
/// `points` doit être trié par [MetricTrackPoint.elapsedS] croissant et porter
/// au moins deux points — voir `RideMetricTrack`, qui garantit déjà cet
/// ordre. Ce widget ne filtre ni ne trie, il dessine ce qu'on lui donne.
class MetricTrendGraph extends StatelessWidget {
  const MetricTrendGraph({super.key, required this.points, required this.zones});

  final List<MetricTrackPoint> points;

  /// Les zones du cycliste pour cette mesure (`RiderProfile.hrZones`/
  /// `powerZones`) — vides quand le seuil correspondant est inconnu du site.
  /// Sans zones, l'aire garde une couleur neutre : le graphique reste utile
  /// (la forme de la courbe se lit toujours), seule la coloration par zone
  /// disparaît — même repli que [MetricId._zoned] pour une case sans seuil.
  final List<TrainingZone> zones;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => CustomPaint(
          size: Size(constraints.maxWidth, constraints.maxHeight),
          painter: _MetricTrendPainter(points: points, zones: zones),
        ),
      );
}

class _MetricTrendPainter extends CustomPainter {
  _MetricTrendPainter({required this.points, required this.zones});

  final List<MetricTrackPoint> points;
  final List<TrainingZone> zones;

  static const _bg = Color(0xFF14161A);
  static const _neutral = Color(0xFF546E7A);
  static const _label = Color(0x99FFFFFF);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8)),
      Paint()..color = _bg,
    );

    if (points.length < 2) return;

    const labelHeight = 14.0;
    final plotHeight = math.max(size.height - labelHeight, 1.0);

    final firstS = points.first.elapsedS;
    final lastS = points.last.elapsedS;
    final span = lastS == firstS ? 1 : lastS - firstS;

    final maxValue = points.map((p) => p.value).reduce(math.max);
    final minValue = points.map((p) => p.value).reduce(math.min);
    // Marge des deux côtés, contrairement à `PowerCurveGraph` (qui n'ouvre
    // que le bas) : une tendance oscille des deux côtés de sa moyenne, elle
    // n'a pas de sens à plafonner près de son sommet.
    final range = maxValue == minValue ? 1.0 : maxValue - minValue;
    final loValue = minValue - range * 0.1;
    final hiValue = maxValue + range * 0.1;
    final valueSpan = hiValue == loValue ? 1.0 : hiValue - loValue;

    double xOf(int elapsedS) => (elapsedS - firstS) / span * size.width;
    double yOf(double value) => plotHeight * (1 - (value - loValue) / valueSpan);

    // Aire colorée par zone, un trapèze par segment — aplat saturé et non
    // teinté, même règle que le bandeau (`zone_colors.dart`) : au soleil, un
    // aplat transparent sur un fond sombre ne donnerait que des gris à peine
    // différents.
    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];
      final x1 = xOf(a.elapsedS), x2 = xOf(b.elapsedS);
      final y1 = yOf(a.value), y2 = yOf(b.value);
      final mid = (a.value + b.value) / 2;
      final color = zoneColorOf(_zoneOf(zones, mid)?.key) ?? _neutral;

      final area = Path()
        ..moveTo(x1, plotHeight)
        ..lineTo(x1, y1)
        ..lineTo(x2, y2)
        ..lineTo(x2, plotHeight)
        ..close();
      canvas.drawPath(area, Paint()..color = color);
    }

    // La courbe elle-même, par-dessus les aplats : c'est elle qui porte la
    // valeur exacte, la couleur de zone ne fait que situer le contexte.
    // Tracée deux fois — un liseré noir sous un trait blanc — pour rester
    // lisible aussi bien sur un aplat sombre (z1 bleu) que clair (z3 jaune) :
    // une seule couleur de trait ne contrasterait pas avec les deux.
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final x = xOf(points[i].elapsedS);
      final y = yOf(points[i].value);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    // Deux repères de temps seulement — début et « maintenant » — assez pour
    // situer la fenêtre (toute la sortie ou les dernières minutes) sans
    // encombrer une case étroite d'une page liste à plusieurs colonnes.
    const labelStyle = TextStyle(color: _label, fontSize: 9);
    final leftPainter = TextPainter(
      text: TextSpan(text: '-${formatDurationHm(Duration(seconds: lastS - firstS))}', style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    leftPainter.paint(canvas, Offset(0, size.height - leftPainter.height));

    final rightPainter = TextPainter(
      text: const TextSpan(text: 'maintenant', style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    // Voir la même parade dans `PowerCurveGraph` : une case étroite peut
    // rendre le libellé plus large que le graphique lui-même.
    final rightX = math.max(0.0, size.width - rightPainter.width);
    rightPainter.paint(canvas, Offset(rightX, size.height - rightPainter.height));
  }

  /// La zone contenant cette valeur — même repli que `zoneSharesOf._zoneOf`
  /// (`ride/zone_time.dart`) : sous la première borne (repos, un capteur de
  /// puissance à l'arrêt), la première zone prend le relais plutôt que de
  /// laisser un patch de l'aire sans couleur.
  static TrainingZone? _zoneOf(List<TrainingZone> zones, num value) {
    for (final zone in zones) {
      if (zone.contains(value)) return zone;
    }
    return zones.isEmpty ? null : (value < zones.first.lo ? zones.first : null);
  }

  @override
  bool shouldRepaint(_MetricTrendPainter old) =>
      old.zones != zones || old.points != points;
}
