import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../recording/elevation_profile_point.dart';
import '../../ui/grade_colors.dart';
import '../../ui/zone_colors.dart' show foregroundOf;

/// Le graphique gradué d'un profil d'altitude, curseur compris — partagé entre
/// le col en cours ([ClimbProfileOverlay]/`ClimbProfileCard`) et le profil de
/// toute la sortie (`AltitudeProfileCard`, tracé ou sortie enregistrée) : les
/// trois n'ont besoin que de points + pentes par segment, jamais de la donnée
/// métier (gain, catégorie…) qui les entoure.
///
/// Port de `NavClimbCard.vue`/`buildClimbProfile` (site), dessiné en
/// [CustomPainter] plutôt qu'en SVG+clip-path. Dessine son propre fond
/// quelle que soit la carte qui l'entoure : les segments de pente colorés
/// ([gradeColorOf]) et l'aire « déjà fait » ont besoin de ce contraste pour
/// rester lisibles.
///
/// [ratio] est **nullable** : `null` dit qu'il n'y a rien de « restant » à
/// distinguer — tout le profil dessiné est déjà parcouru (sortie libre, sans
/// tracé). Dans ce cas ni l'aire « fait », ni le curseur, ni le pointillé de D+
/// restant ne sont dessinés : les couleurs de pente resteraient sinon
/// entièrement recouvertes par le voile « fait ».
///
/// [dark] est l'allure du **profil de toute la sortie** (`AltitudeProfileCard`
/// seulement) : fond noir, courbe d'altitude tracée en blanc par-dessus les
/// aplats de pente, et min/max/altitude courante en surimpression — le même
/// dessin que `MetricTrendGraph` pour le cardio et la puissance, pour qu'une
/// page de données garde un seul langage graphique. Le col en cours
/// ([ClimbProfileOverlay]/`ClimbProfileCard`), lui, garde le fond clair : posé
/// sur la carte, c'est ce contraste-là qui le détache.
class ElevationProfileGraph extends StatelessWidget {
  const ElevationProfileGraph({
    super.key,
    required this.points,
    required this.segmentGrades,
    this.ratio,
    this.dark = false,
  });

  final List<ElevationProfilePoint> points;
  final List<double> segmentGrades;
  final double? ratio;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => CustomPaint(
        size: Size(constraints.maxWidth, constraints.maxHeight),
        painter: _ElevationProfilePainter(
          points: points,
          segmentGrades: segmentGrades,
          ratio: ratio,
          dark: dark,
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
    required this.dark,
  });

  final List<ElevationProfilePoint> points;
  final List<double> segmentGrades;
  final double? ratio;
  final bool dark;

  static const _done = Color(0xFF9CA3AF);
  static const _bg = Color(0xFFF8F9FA);
  // Mêmes valeurs que `MetricTrendGraph` : fond, halo de libellé et voile
  // « déjà fait » d'une page de données doivent se ressembler d'un graphique à
  // l'autre.
  static const _darkBg = Color(0xFF14161A);
  static const _darkLabel = Color(0x99FFFFFF);
  static const _darkDoneScrim = Color(0x73000000);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = dark ? _darkBg : _bg);

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
    // typiquement). Trait clair sur fond noir, sombre sur fond clair.
    final gridPaint = Paint()
      ..color = dark ? const Color(0x1FFFFFFF) : const Color(0x24111827)
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

    if (dark) {
      _paintDark(canvas, size, xOf, yOf, minAlt, maxAlt);
      return;
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

  /// L'allure « page de données » : les aplats de pente sont déjà peints, on
  /// pose par-dessus la courbe d'altitude en blanc, le voile « déjà fait » et
  /// les libellés — même surimpression que `MetricTrendGraph`.
  void _paintDark(
    Canvas canvas,
    Size size,
    double Function(double) xOf,
    double Function(double) yOf,
    double minAlt,
    double maxAlt,
  ) {
    final pts = points;
    final ratio = this.ratio;

    final line = Path();
    for (var i = 0; i < pts.length; i++) {
      final x = xOf(pts[i].distM), y = yOf(pts[i].altM);
      if (i == 0) {
        line.moveTo(x, y);
      } else {
        line.lineTo(x, y);
      }
    }

    if (ratio != null) {
      // Voile sombre sur « ce qui est fait » plutôt que le gris plein du mode
      // clair : sur fond noir, assombrir les couleurs de pente déjà passées
      // se lit mieux que les recouvrir d'un aplat clair.
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, 0, size.width * ratio, size.height));
      final area = Path()..moveTo(xOf(pts.first.distM), size.height);
      for (final p in pts) {
        area.lineTo(xOf(p.distM), yOf(p.altM));
      }
      area
        ..lineTo(xOf(pts.last.distM), size.height)
        ..close();
      canvas.drawPath(area, Paint()..color = _darkDoneScrim);
      canvas.restore();
    }

    // La courbe elle-même : un liseré noir sous un trait blanc, même parade
    // que `MetricTrendGraph` — une seule couleur ne contrasterait pas à la
    // fois sur un aplat de descente (bleu sombre) et de raidard (jaune clair).
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
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    if (ratio != null) {
      final cursorX = size.width * ratio;
      final cursorY = _altYAt(cursorX, pts, xOf, yOf);
      canvas.drawLine(
        Offset(cursorX, 0),
        Offset(cursorX, size.height),
        Paint()
          ..color = const Color(0x8CFFFFFF)
          ..strokeWidth = 2,
      );
      final topY = pts.map((p) => yOf(p.altM)).reduce((a, b) => a < b ? a : b);
      _drawDashedLine(canvas, Offset(cursorX, cursorY), Offset(cursorX, topY));
      canvas.drawCircle(Offset(cursorX, cursorY), 5, Paint()..color = Colors.white);
      canvas.drawCircle(
        Offset(cursorX, cursorY),
        5,
        Paint()
          ..color = Colors.black
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    // Min / max d'altitude collés à gauche — assez pour l'amplitude sans la
    // grille d'un vrai graphique. Halo sombre plutôt qu'un fond opaque, comme
    // dans `MetricTrendGraph`.
    const scaleStyle = TextStyle(
      color: _darkLabel,
      fontSize: 9,
      shadows: [Shadow(color: Colors.black, blurRadius: 2)],
    );
    final maxPainter = TextPainter(
      text: TextSpan(text: '${maxAlt.round()} m', style: scaleStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    maxPainter.paint(canvas, const Offset(2, 1));
    final minPainter = TextPainter(
      text: TextSpan(text: '${minAlt.round()} m', style: scaleStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    minPainter.paint(canvas, Offset(2, size.height - minPainter.height - 1));

    // L'altitude courante, en bas à droite, sur un pavé de la couleur de la
    // pente du moment (même table que les aplats, `grade_colors.dart`) : lire
    // « où j'en suis » sans suivre la courbe jusqu'à son extrémité. Au curseur
    // s'il y en a un (tracé en cours), sinon au dernier point.
    final currentAlt = ratio == null ? pts.last.altM : _altAtRatio(ratio);
    final badgeColor = gradeColorOf(_gradeAtRatio(ratio));
    final badgePainter = TextPainter(
      text: TextSpan(
        text: '${currentAlt.round()} m',
        style: TextStyle(
          color: foregroundOf(badgeColor),
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    const padH = 5.0, padV = 2.0, margin = 4.0;
    final badgeRect = Rect.fromLTWH(
      math.max(0.0, size.width - margin - badgePainter.width - padH * 2),
      math.max(0.0, size.height - margin - badgePainter.height - padV * 2),
      badgePainter.width + padH * 2,
      badgePainter.height + padV * 2,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(badgeRect, const Radius.circular(4)),
      Paint()..color = badgeColor,
    );
    badgePainter.paint(canvas, badgeRect.topLeft + const Offset(padH, padV));
  }

  /// L'altitude interpolée à la fraction [r] de la distance totale — le point
  /// exact sous le curseur, pas l'échantillon le plus proche.
  double _altAtRatio(double r) {
    final target = r.clamp(0.0, 1.0) * points.last.distM;
    for (var i = 1; i < points.length; i++) {
      if (points[i].distM >= target) {
        final a = points[i - 1], b = points[i];
        final segSpan = b.distM - a.distM;
        final t = segSpan > 0 ? (target - a.distM) / segSpan : 0.0;
        return a.altM + t * (b.altM - a.altM);
      }
    }
    return points.last.altM;
  }

  /// La pente du segment sous le curseur (ou du dernier segment sans curseur) —
  /// repérée par distance et non par indice, les segments n'ayant pas tous la
  /// même longueur.
  double _gradeAtRatio(double? r) {
    if (segmentGrades.isEmpty) return 0;
    if (r == null) return segmentGrades.last;
    final target = r.clamp(0.0, 1.0) * points.last.distM;
    for (var i = 0; i < segmentGrades.length; i++) {
      if (points[i + 1].distM >= target) return segmentGrades[i];
    }
    return segmentGrades.last;
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
      old.dark != dark ||
      old.points != points ||
      old.segmentGrades != segmentGrades;
}
