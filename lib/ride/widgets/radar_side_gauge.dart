import 'package:flutter/material.dart';

import '../radar_severity.dart';

/// La jauge radar, dans la gouttière droite de l'écran.
///
/// Un axe vertical, une pastille par véhicule, qui **monte du bas vers le
/// haut** à mesure qu'une voiture se rapproche : elle entre par le bas de
/// l'écran, comme elle entre dans le champ derrière soi, et arrive en haut
/// quand elle est à la roue. C'est une information qu'on lit **du coin de
/// l'œil** — d'où des pastilles franches et aucun chiffre ici, les mètres étant
/// affichés en haut de l'écran.
///
/// Elle est là sur toutes les pages du tableau de bord, pas seulement sur la
/// carte : une voiture qui remonte ne s'annonce pas moins quand on regarde ses
/// watts.
///
/// **Rien du tout quand il n'y a pas de radar** — pas de piste vide, pas de
/// place réservée. Sans Varia, l'écran est exactement celui d'avant.
class RadarSideGauge extends StatelessWidget {
  const RadarSideGauge({super.key, required this.view});

  final RadarView view;

  /// Même largeur que la bande de bord qu'elle recouvre : les deux partagent la
  /// gouttière, il ne doit pas y en avoir une qui déborde de l'autre.
  static const width = 22.0;

  static const _close = Color(0xFFEF5350);
  static const _approaching = Color(0xFFFFA726);
  static const _track = Color(0x22FFFFFF);

  @override
  Widget build(BuildContext context) {
    if (view.severity == RadarSeverity.absent) return const SizedBox.shrink();

    // Ne prend aucun geste : la gouttière sert aussi à changer de page, et la
    // jauge n'est là que pour être vue.
    return IgnorePointer(
      child: SizedBox(
        width: width,
        child: CustomPaint(
          painter: _GaugePainter(
            positions: view.positions,
            color: view.severity == RadarSeverity.close ? _close : _approaching,
            track: _track,
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
    required this.track,
  });

  final List<double> positions;
  final Color color;
  final Color track;

  /// Marge haute et basse, pour qu'une pastille à l'extrême ne soit pas coupée
  /// par le bord de l'écran. Suit le rayon : c'est exactement ce qu'il faut pour
  /// qu'une pastille en bout de course reste entière.
  static const _dotRadius = 8.0;
  static const _inset = _dotRadius + 3;

  /// Halo sombre sous la pastille. La jauge est posée sur une carte dont on ne
  /// maîtrise pas les couleurs — un orange sur un toit orange ne se verrait
  /// pas.
  static const _halo = Color(0x99000000);

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / 2;
    const top = _inset;
    final bottom = size.height - _inset;

    // La piste est dessinée dès qu'un radar répond, même route dégagée : c'est
    // ce qui distingue « rien derrière » de « pas de radar », et la seule façon
    // de s'assurer d'un coup d'œil que le capteur est toujours vivant.
    canvas.drawLine(
      Offset(x, top),
      Offset(x, bottom),
      Paint()
        ..color = track
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );

    final halo = Paint()..color = _halo;
    final paint = Paint()..color = color;
    for (final position in positions) {
      // `bottom - …` et non `top + …` : la proximité monte, donc la pastille
      // aussi. Un véhicule au bout de la portée entre par le bas, il est à la
      // roue quand il touche le haut.
      final center = Offset(x, bottom - position * (bottom - top));
      canvas.drawCircle(center, _dotRadius + 2, halo);
      canvas.drawCircle(center, _dotRadius, paint);
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.color != color || !_sameList(old.positions, positions);

  static bool _sameList(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
