import 'package:flutter/material.dart';

import '../../recording/elevation_profile_point.dart';
import '../../ui/grade_colors.dart';

/// Le graphique gradué d'un profil d'altitude, curseur compris — partagé entre
/// le col en cours ([ClimbProfileOverlay]/`ClimbProfileCard`) et le profil de
/// toute la sortie (`AltitudeProfileCard`, tracé ou sortie enregistrée) : les
/// trois n'ont besoin que de points + pentes par segment, jamais de la donnée
/// métier (gain, catégorie…) qui les entoure.
///
/// Port de `NavClimbCard.vue`/`buildClimbProfile` (site), dessiné en
/// [CustomPainter] plutôt qu'en SVG+clip-path. Dessine son propre fond clair
/// ([_ElevationProfilePainter._bg]) quelle que soit la carte qui l'entoure :
/// les segments de pente colorés ([gradeColorOf]) et l'aire « déjà fait »
/// (grise) ont besoin de ce contraste pour rester lisibles.
///
/// [ratio] est **nullable** : `null` dit qu'il n'y a rien de « restant » à
/// distinguer — tout le profil dessiné est déjà parcouru (sortie libre, sans
/// tracé). Dans ce cas ni l'aire grise, ni le curseur, ni le pointillé de D+
/// restant ne sont dessinés : les couleurs de pente resteraient sinon
/// entièrement recouvertes par le gris « fait ».
class ElevationProfileGraph extends StatelessWidget {
  const ElevationProfileGraph({
    super.key,
    required this.points,
    required this.segmentGrades,
    this.ratio,
  });

  final List<ElevationProfilePoint> points;
  final List<double> segmentGrades;
  final double? ratio;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => CustomPaint(
        size: Size(constraints.maxWidth, constraints.maxHeight),
        painter: _ElevationProfilePainter(
          points: points,
          segmentGrades: segmentGrades,
          ratio: ratio,
        ),
      ),
    );
  }
}

class _ElevationProfilePainter extends CustomPainter {
  _ElevationProfilePainter({
    required this.points,
    required this.segmentGrades,
    required this.ratio,
  });

  final List<ElevationProfilePoint> points;
  final List<double> segmentGrades;
  final double? ratio;

  static const _done = Color(0xFF9CA3AF);
  static const _bg = Color(0xFFF8F9FA);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = _bg);

    final pts = points;
    final minAlt = pts.map((p) => p.altM).reduce((a, b) => a < b ? a : b);
    final maxAlt = pts.map((p) => p.altM).reduce((a, b) => a > b ? a : b);
    final range = (maxAlt - minAlt) == 0 ? 1 : (maxAlt - minAlt);
    final span = pts.last.distM == 0 ? 1 : pts.last.distM;

    double xOf(double distM) => distM / span * size.width;
    // 4-96 % de hauteur, sommet en haut — même inversion que
    // buildClimbProfile côté site (yOf = 96 - ... * 88).
    double yOf(double altM) =>
        size.height * (0.96 - (altM - minAlt) / range * 0.88);

    // Repères tous les 10 km — avant les segments, donc recouverts par l'aire
    // colorée : ils ne restent visibles que dans le ciel, au-dessus du
    // profil, comme sur un altimètre papier. Une échelle de lecture, pas une
    // donnée : aucune graduation sur un profil de moins de 10 km (un col,
    // typiquement).
    final gridPaint = Paint()
      ..color = const Color(0x24111827)
      ..strokeWidth = 1;
    for (var gridDistM = 10000.0; gridDistM < pts.last.distM; gridDistM += 10000.0) {
      final x = xOf(gridDistM);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    // Segments colorés — même polygone que le site (base à y=height).
    for (var i = 0; i < segmentGrades.length; i++) {
      final x1 = xOf(pts[i].distM), x2 = xOf(pts[i + 1].distM);
      final y1 = yOf(pts[i].altM), y2 = yOf(pts[i + 1].altM);
      final path = Path()
        ..moveTo(x1, y1)
        ..lineTo(x2, y2)
        ..lineTo(x2, size.height)
        ..lineTo(x1, size.height)
        ..close();
      canvas.drawPath(path, Paint()..color = gradeColorOf(segmentGrades[i]));
    }

    final ratio = this.ratio;
    if (ratio == null) return;

    // Portion déjà faite : l'aire entière redessinée en gris, clippée à
    // gauche du curseur — équivalent du clip-path SVG du site.
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width * ratio, size.height));
    final area = Path()..moveTo(xOf(pts.first.distM), size.height);
    for (final p in pts) {
      area.lineTo(xOf(p.distM), yOf(p.altM));
    }
    area
      ..lineTo(xOf(pts.last.distM), size.height)
      ..close();
    canvas.drawPath(area, Paint()..color = _done);
    canvas.restore();

    // Curseur : ligne verticale + point sur la ligne d'altitude, interpolée
    // linéairement entre les deux points encadrants (port de profileYAt).
    final cursorX = size.width * ratio;
    final cursorY = _altYAt(cursorX, pts, xOf, yOf);
    canvas.drawLine(
      Offset(cursorX, 0),
      Offset(cursorX, size.height),
      Paint()
        ..color = const Color(0x8C111827)
        ..strokeWidth = 2,
    );

    // Ligne pointillée de D+ restant, du curseur au sommet.
    final topY = pts.map((p) => yOf(p.altM)).reduce((a, b) => a < b ? a : b);
    _drawDashedLine(canvas, Offset(cursorX, cursorY), Offset(cursorX, topY));

    canvas.drawCircle(
      Offset(cursorX, cursorY),
      6,
      Paint()..color = const Color(0xFF111827),
    );
    canvas.drawCircle(
      Offset(cursorX, cursorY),
      6,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  double _altYAt(
    double x,
    List<ElevationProfilePoint> pts,
    double Function(double) xOf,
    double Function(double) yOf,
  ) {
    for (var i = 1; i < pts.length; i++) {
      final xi = xOf(pts[i].distM);
      if (xi >= x) {
        final xPrev = xOf(pts[i - 1].distM);
        final t = xi > xPrev ? (x - xPrev) / (xi - xPrev) : 0.0;
        return yOf(pts[i - 1].altM) + t * (yOf(pts[i].altM) - yOf(pts[i - 1].altM));
      }
    }
    return yOf(pts.last.altM);
  }

  void _drawDashedLine(Canvas canvas, Offset top, Offset bottom) {
    const dash = 4.0, gap = 3.0;
    final paint = Paint()
      ..color = const Color(0xFFF97316)
      ..strokeWidth = 2;
    var y = top.dy;
    while (y < bottom.dy) {
      final next = (y + dash).clamp(y, bottom.dy);
      canvas.drawLine(Offset(top.dx, y), Offset(top.dx, next), paint);
      y = next + gap;
    }
  }

  @override
  bool shouldRepaint(_ElevationProfilePainter old) =>
      old.ratio != ratio ||
      old.points != points ||
      old.segmentGrades != segmentGrades;
}
