import 'package:flutter/material.dart';

import '../climb_profile.dart';
import '../../ui/grade_colors.dart';

/// Le graphique gradué d'un col, curseur compris — extrait de
/// [ClimbProfileOverlay] pour être partagé avec `ClimbProfileCard`
/// (`lib/ride/blocks/climb_profile_block.dart`) : même dessin, posé soit sur
/// la carte (tap du badge de col), soit dans une case de page comme
/// n'importe quel autre bloc.
///
/// Port de `NavClimbCard.vue` (site) — mêmes calculs (`buildClimbProfile`,
/// `profileYAt`), mais dessinés en [CustomPainter] plutôt qu'en SVG+clip-path.
/// Dessine son propre fond clair ([_ClimbProfilePainter._bg]) quelle que soit
/// la carte qui l'entoure : les segments de pente colorés
/// ([gradeColorOf]) et l'aire « déjà grimpée » (gris) ont besoin de ce
/// contraste pour rester lisibles, sur la carte flottante blanche comme sur
/// une case sombre du tableau de bord.
class ClimbProfileGraph extends StatelessWidget {
  const ClimbProfileGraph({super.key, required this.ratio, required this.profile});

  final double ratio;
  final ClimbProfile profile;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => CustomPaint(
        size: Size(constraints.maxWidth, constraints.maxHeight),
        painter: _ClimbProfilePainter(ratio: ratio, profile: profile),
      ),
    );
  }
}

class _ClimbProfilePainter extends CustomPainter {
  _ClimbProfilePainter({required this.ratio, required this.profile});

  final double ratio;
  final ClimbProfile profile;

  static const _done = Color(0xFF9CA3AF);
  static const _bg = Color(0xFFF8F9FA);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = _bg);

    final pts = profile.points;
    final minAlt = pts.map((p) => p.altM).reduce((a, b) => a < b ? a : b);
    final maxAlt = pts.map((p) => p.altM).reduce((a, b) => a > b ? a : b);
    final range = (maxAlt - minAlt) == 0 ? 1 : (maxAlt - minAlt);
    final span = pts.last.distM == 0 ? 1 : pts.last.distM;

    double xOf(double distM) => distM / span * size.width;
    // 4-96 % de hauteur, sommet en haut — même inversion que
    // buildClimbProfile côté site (yOf = 96 - ... * 88).
    double yOf(double altM) =>
        size.height * (0.96 - (altM - minAlt) / range * 0.88);

    // Segments colorés — même polygone que le site (base à y=height).
    for (var i = 0; i < profile.segmentGrades.length; i++) {
      final x1 = xOf(pts[i].distM), x2 = xOf(pts[i + 1].distM);
      final y1 = yOf(pts[i].altM), y2 = yOf(pts[i + 1].altM);
      final path = Path()
        ..moveTo(x1, y1)
        ..lineTo(x2, y2)
        ..lineTo(x2, size.height)
        ..lineTo(x1, size.height)
        ..close();
      canvas.drawPath(
        path,
        Paint()..color = gradeColorOf(profile.segmentGrades[i]),
      );
    }

    // Portion déjà grimpée : l'aire entière redessinée en gris, clippée à
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
    List<ClimbProfilePoint> pts,
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
  bool shouldRepaint(_ClimbProfilePainter old) =>
      old.ratio != ratio || old.profile != profile;
}
