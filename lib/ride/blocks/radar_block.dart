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

    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = BlockMetrics.of(constraints);
        return ValueListenableBuilder<RadarView>(
          valueListenable: radar,
          builder: (context, view, _) => switch (mode) {
            RadarMode.gauge => _gauge(view, metrics),
            RadarMode.distance => _distance(view, metrics),
          },
        );
      },
    );
  }

  Widget _distance(RadarView view, BlockMetrics metrics) {
    final (label, color) = switch (view.severity) {
      RadarSeverity.close => ('${view.nearestM} m', _close),
      RadarSeverity.approaching => ('${view.nearestM} m', _approaching),
      RadarSeverity.clear => ('Voie libre', _clear),
      RadarSeverity.absent => ('Pas de radar', Colors.white38),
    };

    return BlockSurface(
      metrics: metrics,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // L'icône part la première dans une petite case : elle redit ce que la
          // couleur dit déjà, alors que le nombre de mètres ne se déduit de rien.
          if (view.isAlerting && metrics.showIcon)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.directions_car,
                  size: metrics.iconSize + 2,
                  color: color,
                ),
                // Le compte n'est écrit que s'il y a de quoi compter : « ×1 »
                // sous une seule voiture ferait chercher la deuxième.
                if (view.count > 1)
                  Text(
                    ' ×${view.count}',
                    style: TextStyle(color: color, fontSize: metrics.iconSize),
                  ),
              ],
            ),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  color: color,
                  fontSize: 44,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// La jauge de la gouttière, à l'horizontale d'une cellule. Les mêmes
  /// positions et les mêmes couleurs que sur les bords de la carte : deux
  /// affichages du même capteur ne doivent pas raconter deux histoires.
  /// Sa largeur est celle de la gouttière, en dur : dans une case plus étroite,
  /// elle est mise à l'échelle plutôt que rognée — une jauge coupée dans sa
  /// largeur montrerait une voiture ailleurs qu'où elle est. `contain` et non
  /// `scaleDown` : elle remplissait la hauteur de sa case avant, et doit
  /// continuer.
  Widget _gauge(RadarView view, BlockMetrics metrics) => BlockSurface(
        metrics: metrics,
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: RadarSideGauge.width,
            height: RadarSideGauge.width * 2,
            child: RadarSideGauge(view: view, side: RadarGaugeSide.left),
          ),
        ),
      );
}
