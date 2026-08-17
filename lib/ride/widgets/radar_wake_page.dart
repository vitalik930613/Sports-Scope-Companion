import 'package:flutter/material.dart';

import '../radar_severity.dart';
import 'radar_side_gauge.dart';

/// La page qui s'invite pendant la veille : le radar, en gros, sur du noir.
///
/// Elle **ne fait pas partie du catalogue** ([RidePage]) et ne se fait pas
/// défiler : l'y ajouter changerait le nombre de pages, donc le numéro annoncé,
/// les gestes et la boucle, pour un écran qu'on ne choisit jamais d'ouvrir. Elle
/// apparaît quand une voiture remonte alors que l'écran dormait, et repart
/// quand c'est passé — voir [RadarWakePolicy] et [ScreenPolicy].
///
/// Ce qu'elle recouvre est le voile noir de la page web, pas la carte : en
/// veille, il n'y a rien dessous. D'où le fond opaque, qui garantit une surface
/// connue plutôt qu'un voile dont on ne maîtrise ni l'opacité ni la couleur.
/// Elle s'arrête **au-dessus du bandeau du bas**, qui garde ses mesures : on
/// vient de rallumer l'écran, autant que la vitesse et le cardio en profitent.
///
/// Les chiffres sont ceux d'un écran qu'on regarde une demi-seconde, casque
/// tourné : un seul nombre, énorme, à la couleur de la gravité. Les gouttières
/// et les pastilles de mètres de la coquille se peignent par-dessus — c'est
/// voulu, elles disent la même chose au même instant et par les mêmes couleurs.
class RadarWakePage extends StatelessWidget {
  const RadarWakePage({super.key, required this.view});

  final RadarView view;

  static const _close = Color(0xFFEF5350);
  static const _approaching = Color(0xFFFFA726);

  /// Le vert de la voie libre. Il ne s'affiche que **pendant le maintien**,
  /// après le passage d'un véhicule : c'est la réponse à la question qu'on
  /// venait de poser, et la raison pour laquelle l'écran va se rendormir.
  static const _clear = Color(0xFF81C784);

  /// Aucun geste : la page web est dessous, et c'est elle qui possède le tap de
  /// réveil. Un cycliste qui touche l'écran pendant l'alerte doit réveiller la
  /// navigation, pas taper dans le vide.
  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ColoredBox(
        color: Colors.black,
        child: Center(
          child: Padding(
            // Les gouttières sont peintes par-dessus, aux deux bords : le
            // chiffre ne doit pas passer dessous.
            padding: const EdgeInsets.symmetric(
              horizontal: RadarSideGauge.width + 8,
            ),
            child: FittedBox(fit: BoxFit.scaleDown, child: _readout()),
          ),
        ),
      ),
    );
  }

  Widget _readout() {
    final nearest = view.nearestM;
    if (!view.isAlerting || nearest == null) return _resolution();

    final color = view.severity == RadarSeverity.close ? _close : _approaching;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.directions_car, size: 44, color: color),
            // Le compte n'est écrit que s'il y a de quoi compter : « ×1 » sous
            // une seule voiture ferait chercher la deuxième. Même taille que
            // l'icône juste avant — même règle que `RadarBlockView._count`.
            if (view.count > 1) ...[
              const SizedBox(width: 8),
              Text(
                '×${view.count}',
                style: TextStyle(
                  color: color,
                  fontSize: 44,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '$nearest m',
          style: TextStyle(
            color: color,
            fontSize: 112,
            fontWeight: FontWeight.w800,
            height: 1,
          ),
        ),
      ],
    );
  }

  /// Ce qui s'affiche pendant le maintien, une fois l'alerte éteinte.
  ///
  /// **« Voie libre » n'est écrit que si un radar l'a dit.** Un capteur qui se
  /// tait pendant l'alerte — batterie, ceinture décrochée — annonce sa perte,
  /// jamais une route dégagée : ce serait la pire information que cet écran
  /// puisse donner, et c'est exactement l'instant où on la croirait.
  Widget _resolution() {
    final (label, color) = view.severity == RadarSeverity.clear
        ? ('Voie libre', _clear)
        : ('Radar perdu', Colors.white54);

    return Text(
      label,
      style: TextStyle(
        color: color,
        fontSize: 48,
        fontWeight: FontWeight.w700,
        height: 1,
      ),
    );
  }
}
