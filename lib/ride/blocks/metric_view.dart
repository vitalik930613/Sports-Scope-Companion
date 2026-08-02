import 'package:flutter/material.dart';

import '../../dashboard/dashboard_block.dart';
import '../../dashboard/metric_id.dart';
import '../../ui/zone_colors.dart';
import 'block_card.dart';

/// Une mesure du catalogue, dessinée selon son mode.
///
/// Les quatre modes ne sont pas quatre styles : ce sont quatre réponses à
/// « combien de place ai-je, et qu'est-ce que je viens lire ? ». Le chiffre plein
/// cadre se lit à 30 km/h sans quitter la route des yeux ; la jauge répond à
/// « où j'en suis dans la plage » sans qu'on ait à comparer deux nombres ;
/// l'aplat de zone répond à la même question en couleur, ce qui est encore plus
/// rapide mais moins précis.
///
/// **Un tiret quand la mesure manque, jamais un zéro** — la règle du dépôt : un
/// zéro se lit comme une mesure, alors qu'un capteur muet ne mesure rien.
class MetricView extends StatelessWidget {
  const MetricView({
    super.key,
    required this.metric,
    required this.sources,
    this.mode = MetricMode.big,
    this.onTap,
  });

  final MetricId metric;
  final MetricSources sources;
  final MetricMode mode;

  /// Un tap sur la mesure. Sert aux watts, qui ouvrent la calibration du capteur
  /// de puissance : c'est là qu'on *constate* une puissance qui dérive, et non
  /// dans un menu deux pages plus loin.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = ListenableBuilder(
      listenable: Listenable.merge(metric.dependencies(sources)),
      builder: (context, _) => _paint(metric.read(sources)),
    );

    if (onTap == null) return content;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: content,
    );
  }

  Widget _paint(MetricReading reading) => switch (mode) {
        MetricMode.big => _big(reading),
        MetricMode.compact => _compact(reading),
        MetricMode.zone => _zone(reading),
        MetricMode.gauge => _gauge(reading),
      };

  /// Le chiffre aussi grand que la case le permet.
  ///
  /// `FittedBox` et pas une taille fixe : les valeurs sont de longueurs très
  /// inégales (« 8 » et « 1:12:34 ») et une cellule de grille ne s'élargit pas
  /// pour les accueillir.
  Widget _big(MetricReading reading) {
    final background = zoneColorOf(reading.zoneKey);
    final ink = background == null ? Colors.white : foregroundOf(background);

    return _shell(
      background: background,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                reading.value ?? '—',
                maxLines: 1,
                style: TextStyle(
                  color: ink,
                  fontSize: 64,
                  fontWeight: FontWeight.w500,
                  height: 1,
                ),
              ),
            ),
          ),
          Text(
            metric.unit,
            maxLines: 1,
            style: TextStyle(
              color: background == null
                  ? Colors.white54
                  : ink.withValues(alpha: 0.75),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  /// Icône, valeur, unité — la mise en forme de `MetricTile`, pour les cellules
  /// où l'on tient plusieurs mesures.
  Widget _compact(MetricReading reading) {
    final background = zoneColorOf(reading.zoneKey);
    final ink = background == null ? Colors.white : foregroundOf(background);

    return _shell(
      background: background,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(metric.icon, size: 18, color: ink.withValues(alpha: 0.7)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              reading.value ?? '—',
              maxLines: 1,
              style: TextStyle(color: ink, fontSize: 26, height: 1.1),
            ),
          ),
          Text(
            metric.unit,
            maxLines: 1,
            style: TextStyle(
              color: background == null
                  ? Colors.white54
                  : ink.withValues(alpha: 0.75),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  /// L'aplat de la zone du moment, la mesure dessus.
  ///
  /// Identique à [_big] quand la mesure porte une zone : c'est justement le
  /// point, la couleur *est* l'information. Sans zone connue, la case reste sur
  /// le fond du tableau de bord — une couleur inventée serait pire qu'une
  /// couleur absente.
  Widget _zone(MetricReading reading) => _big(reading);

  /// La position dans la plage, plutôt que le chiffre exact.
  ///
  /// La plage, ce sont les zones du cycliste : elles viennent du site, et il
  /// n'en existe pas d'autre qui veuille dire quelque chose (une puissance « sur
  /// 400 W » ne dit rien de commun entre deux cyclistes). **Sans zones, il n'y a
  /// pas de plage** : on retombe alors sur le chiffre plein cadre plutôt que de
  /// dessiner une jauge dont on aurait inventé le maximum.
  Widget _gauge(MetricReading reading) {
    final zones = metric.zonesOf(sources.riderProfile.profile);
    if (zones.isEmpty) return _big(reading);

    final index = zones.indexWhere((zone) => zone.key == reading.zoneKey);
    final color = zoneColorOf(reading.zoneKey) ?? Colors.white24;

    return _shell(
      background: null,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                reading.value ?? '—',
                maxLines: 1,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 48,
                  fontWeight: FontWeight.w500,
                  height: 1,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Une case par zone plutôt qu'un remplissage continu : les zones sont
          // des paliers, et un dégradé laisserait croire à une progression
          // linéaire qu'elles n'ont pas.
          Row(
            children: [
              for (var i = 0; i < zones.length; i++) ...[
                if (i > 0) const SizedBox(width: 2),
                Expanded(
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: i <= index && index >= 0
                          ? (zoneColorOf(zones[i].key) ?? color)
                          : Colors.white12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            metric.unit,
            maxLines: 1,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ],
      ),
    );
  }

  /// Le cadre commun : l'aplat de zone quand il y en a un, le fond des cartes
  /// sinon. Le rembourrage est le même dans tous les cas, pour qu'une mesure qui
  /// change de zone en roulant ne fasse pas sauter la mise en page.
  Widget _shell({required Color? background, required Widget child}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: background ?? BlockCard.background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: child,
      );
}
