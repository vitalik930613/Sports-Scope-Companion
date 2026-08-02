import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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
        RadarMode.gauge => _gauge(view),
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

    return _shell(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (view.isAlerting)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.directions_car, size: 20, color: color),
                // Le compte n'est écrit que s'il y a de quoi compter : « ×1 »
                // sous une seule voiture ferait chercher la deuxième.
                if (view.count > 1)
                  Text(
                    ' ×${view.count}',
                    style: TextStyle(color: color, fontSize: 18),
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
  Widget _gauge(RadarView view) => _shell(
        child: Center(
          child: SizedBox(
            width: RadarSideGauge.width,
            child: RadarSideGauge(view: view, side: RadarGaugeSide.left),
          ),
        ),
      );

  Widget _shell({required Widget child}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: BlockCard.background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: child,
      );
}
