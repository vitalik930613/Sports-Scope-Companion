import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../radar_severity.dart';

/// De quel bord de l'écran il s'agit — et donc de quel côté pointent les
/// triangles.
enum RadarGaugeSide {
  left,
  right;

  bool get pointsRight => this == RadarGaugeSide.right;
}

/// La jauge radar, dans une gouttière de l'écran.
///
/// Un axe vertical, un triangle par véhicule, qui **monte du bas vers le haut**
/// à mesure qu'une voiture se rapproche : elle entre par le bas de l'écran,
/// comme elle entre dans le champ derrière soi, et arrive en haut quand elle est
/// à la roue. C'est une information qu'on lit **du coin de l'œil** — d'où des
/// marques franches et aucun chiffre ici, les mètres étant affichés en haut de
/// l'écran.
///
/// Les triangles **pointent vers l'extérieur** : vers la droite au bord droit,
/// vers la gauche au bord gauche. Une pointe est directionnelle là où un rond ne
/// l'est pas, et elle emmène le regard hors de l'écran — du côté où il faudra
/// bien finir par regarder. La jauge est posée aux deux bords pour la même
/// raison que les mètres sont écrits deux fois : on ne sait pas d'où les yeux
/// reviendront de la route.
///
/// Elle est là sur toutes les pages du tableau de bord, pas seulement sur la
/// carte : une voiture qui remonte ne s'annonce pas moins quand on regarde ses
/// watts.
///
/// **Rien du tout quand il n'y a pas de radar** — pas de piste vide, pas de
/// place réservée. Sans Varia, l'écran est exactement celui d'avant.
class RadarSideGauge extends StatelessWidget {
  const RadarSideGauge({super.key, required this.view, required this.side});

  final RadarView view;
  final RadarGaugeSide side;

  /// Bien plus large que la bande de changement de page (22 pt) qu'elle
  /// recouvre : mesuré sur route, une réglette de la largeur de la bande ne se
  /// voyait pas du coin de l'œil, on la découvrait en cherchant les mètres en
  /// haut — c'est-à-dire trop tard. C'est un **dégradé** qui occupe cette
  /// largeur, pas un aplat : la carte reste lisible dessous, seul le bord de
  /// l'écran s'embrase.
  static const width = 72.0;

  static const _close = Color(0xFFEF5350);
  static const _approaching = Color(0xFFFFA726);

  @override
  Widget build(BuildContext context) {
    if (view.severity == RadarSeverity.absent) return const SizedBox.shrink();

    // Ne prend aucun geste : la gouttière sert aussi à changer de page, et la
    // jauge n'est là que pour être vue. Le dégradé déborde largement sur la
    // carte, il ne doit surtout pas lui prendre ses glissés.
    return IgnorePointer(
      child: SizedBox(
        width: width,
        // Même durée que [RadarFrame] : les deux signalent la même chose au
        // même instant, une seule montée les fait lire comme un seul geste.
        // Sans elle, une voiture qui entre en portée embrase l'écran d'un coup.
        child: TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          tween: Tween(end: view.isAlerting ? 1.0 : 0.0),
          builder: (context, glow, _) => CustomPaint(
            painter: _GaugePainter(
              positions: view.positions,
              color: view.severity == RadarSeverity.close
                  ? _close
                  : _approaching,
              pointsRight: side.pointsRight,
              glow: glow,
            ),
          ),
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  const _GaugePainter({
    required this.positions,
    required this.color,
    required this.pointsRight,
    required this.glow,
  });

  final List<double> positions;
  final Color color;
  final bool pointsRight;

  /// Où en est le dégradé de bord, de 0 (éteint) à 1. Animé par le widget.
  final double glow;

  /// Le triangle. Doublé par rapport à la première version : à 30 km/h, une
  /// marque de quinze points se confond avec un détail de la carte.
  static const _markWidth = 30.0;
  static const _markHeight = 36.0;

  /// L'axe des marques reste **collé au bord**, il ne se recentre pas sur la
  /// nouvelle largeur : c'est la vision périphérique qui lit cette jauge, et
  /// elle lit le bord de l'écran. La largeur sert au dégradé, pas à écarter les
  /// triangles du bord.
  static const _axisInset = 19.0;

  /// Marge haute et basse, pour qu'une marque à l'extrême ne soit pas coupée par
  /// le bord de l'écran.
  static const _inset = _markHeight / 2 + 3;

  /// Contour sombre autour de la marque. La jauge est posée sur une carte dont
  /// on ne maîtrise pas les couleurs — un orange sur un toit orange ne se
  /// verrait pas.
  static const _halo = Color(0x99000000);

  /// Opacité du dégradé au ras du bord, puis à mi-course. Assez pour teinter la
  /// carte, pas assez pour l'effacer : on doit continuer à suivre son itinéraire
  /// pendant qu'une voiture remonte.
  static const _glowEdge = 0.62;
  static const _glowMid = 0.20;

  @override
  void paint(Canvas canvas, Size size) {
    final x = pointsRight ? size.width - _axisInset : _axisInset;
    final outerX = pointsRight ? size.width : 0.0;
    final innerX = pointsRight ? 0.0 : size.width;
    const top = _inset;
    final bottom = size.height - _inset;

    // Le dégradé qui déborde sur la page du dessous — carte ou données, peu
    // importe : l'alerte appartient à la sortie. Il s'éteint tout seul route
    // dégagée, `glow` valant alors zéro.
    if (glow > 0) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(outerX, 0),
            Offset(innerX, 0),
            [
              color.withValues(alpha: _glowEdge * glow),
              color.withValues(alpha: _glowMid * glow),
              color.withValues(alpha: 0),
            ],
            // Décroissance rapide puis longue traîne : c'est ce qui distingue
            // un bord qui s'embrase d'un voile posé sur la moitié de l'écran.
            const [0.0, 0.35, 1.0],
          ),
      );
    }

    final halo = Paint()
      ..color = _halo
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = color;

    for (final position in positions) {
      // `bottom - …` et non `top + …` : la proximité monte, donc la marque
      // aussi. Un véhicule au bout de la portée entre par le bas, il est à la
      // roue quand il touche le haut.
      final path = _mark(Offset(x, bottom - position * (bottom - top)));
      canvas.drawPath(path, halo);
      canvas.drawPath(path, fill);
    }
  }

  Path _mark(Offset center) {
    final apexX = center.dx + (pointsRight ? _markWidth / 2 : -_markWidth / 2);
    final baseX = center.dx + (pointsRight ? -_markWidth / 2 : _markWidth / 2);

    return Path()
      ..moveTo(apexX, center.dy)
      ..lineTo(baseX, center.dy - _markHeight / 2)
      ..lineTo(baseX, center.dy + _markHeight / 2)
      ..close();
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.color != color ||
      old.pointsRight != pointsRight ||
      old.glow != glow ||
      !_sameList(old.positions, positions);

  static bool _sameList(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
