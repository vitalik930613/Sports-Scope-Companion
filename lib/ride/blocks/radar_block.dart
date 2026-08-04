import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../dashboard/block_density.dart';
import '../../dashboard/dashboard_block.dart';
import '../radar_severity.dart';
import '../widgets/radar_side_gauge.dart';
import 'block_card.dart';

/// Le radar arrière, posé dans une page de données.
///
/// La règle qui tient tout : **`absent` n'est pas `clear`.** Pas de radar ne
/// veut pas dire route dégagée. Écrire « voie libre » sans capteur serait la
/// pire information que cet écran puisse donner, et c'est précisément l'instant
/// où on la croirait — d'où « Pas de radar », qui ne se confond avec rien.
///
/// Le bloc est **facultatif dans un profil** et le restera : les gouttières et
/// le cadre de la coquille disent déjà le radar sur toutes les pages. Celui-ci
/// sert au profil qui veut le chiffre en grand, ou qui a coupé les gouttières.
class RadarBlockView extends StatelessWidget {
  const RadarBlockView({
    super.key,
    required this.radar,
    this.mode = RadarMode.distance,
  });

  /// Nul quand le profil a coupé le radar : le bloc le dit alors, plutôt que
  /// d'attendre indéfiniment une trame qui ne viendra pas.
  final ValueListenable<RadarView>? radar;

  final RadarMode mode;

  static const _close = Color(0xFFEF5350);
  static const _approaching = Color(0xFFFFA726);
  static const _clear = Color(0xFF81C784);

  @override
  Widget build(BuildContext context) {
    final radar = this.radar;
    if (radar == null) {
      return const BlockCard(
        title: 'Radar',
        lines: ['Coupé par ce profil.'],
      );
    }

    return ValueListenableBuilder<RadarView>(
      valueListenable: radar,
      builder: (context, view, _) => switch (mode) {
        RadarMode.gauge => _gauge(view, vertical: false),
        RadarMode.gaugeVertical => _gauge(view, vertical: true),
        RadarMode.distance => _distance(view),
      },
    );
  }

  Widget _distance(RadarView view) {
    final (label, color) = switch (view.severity) {
      RadarSeverity.close => ('${view.nearestM} m', _close),
      RadarSeverity.approaching => ('${view.nearestM} m', _approaching),
      RadarSeverity.clear => ('Voie libre', _clear),
      RadarSeverity.absent => ('Pas de radar', Colors.white38),
    };

    return BlockSurface(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // L'icône dit ce que la couleur dit déjà, quand il y a de quoi
          // alerter : sans voiture proche, il n'y a rien à redire au chiffre.
          if (view.isAlerting)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.directions_car,
                  size: BlockMetrics.natural.iconSize + 2,
                  color: color,
                ),
                // Le compte n'est écrit que s'il y a de quoi compter : « ×1 »
                // sous une seule voiture ferait chercher la deuxième.
                if (view.count > 1)
                  Text(
                    ' ×${view.count}',
                    style: TextStyle(
                      color: color,
                      fontSize: BlockMetrics.natural.iconSize,
                    ),
                  ),
              ],
            ),
          Text(
            label,
            maxLines: 1,
            style: TextStyle(
              color: color,
              fontSize: 44,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }

  /// La jauge de la gouttière, posée dans une cellule. Les mêmes positions et
  /// les mêmes couleurs que sur les bords de la carte : deux affichages du même
  /// capteur ne doivent pas raconter deux histoires.
  ///
  /// Debout ou couchée selon le mode, et **c'est la seule différence** : le
  /// dessin est le même, tourné d'un quart de tour. Une cellule large et une
  /// cellule haute ne veulent pas de la même jauge — mise à l'échelle dans la
  /// mauvaise, elle finit en réglette de la largeur d'un doigt au milieu d'une
  /// case vide.
  ///
  /// Couchée, un véhicule entre **par la gauche** et arrive à droite : c'est la
  /// jauge du bord gauche tournée dans le sens des aiguilles, donc le haut
  /// (la roue) qui devient la droite. Les pointes suivent la rotation et
  /// désignent alors le haut.
  ///
  /// Sa taille est celle de la gouttière, en dur : dans une case plus étroite,
  /// elle est mise à l'échelle par [ScaleToFit] (posé par [BlockSurface])
  /// plutôt que rognée — une jauge coupée dans sa longueur montrerait une
  /// voiture ailleurs qu'où elle est.
  Widget _gauge(RadarView view, {required bool vertical}) {
    final gauge = SizedBox(
      width: RadarSideGauge.width,
      height: RadarSideGauge.width * 2,
      child: RadarSideGauge(view: view, side: RadarGaugeSide.left),
    );

    return BlockSurface(
      // `RotatedBox` et non `Transform.rotate` : la rotation est prise en
      // compte à la mise en page, si bien que la mise à l'échelle mesure le
      // rectangle couché et non le rectangle debout — sinon la jauge
      // déborderait de sa case d'un côté et flotterait de l'autre.
      child: vertical ? gauge : RotatedBox(quarterTurns: 1, child: gauge),
    );
  }
}
