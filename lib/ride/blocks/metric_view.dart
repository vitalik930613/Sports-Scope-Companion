import 'package:flutter/material.dart';

import '../../dashboard/block_density.dart';
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
///
/// Le mode demandé est un **ordre** : icône, unité et jauge sont toujours
/// dessinées, quelle que soit la case — c'est [ScaleToFit], posé par
/// [BlockSurface], qui réduit l'ensemble s'il ne tient pas, plutôt que de
/// retirer des éléments un à un.
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

  /// La hauteur naturelle du chiffre : celle à laquelle il est construit avant
  /// mise à l'échelle, dans une grille comme dans une page qui défile — une
  /// mesure posée dans une liste doit se lire comme une mesure posée dans une
  /// grille.
  static const _valueHeight = 72.0;

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

  /// Le chiffre, sa couleur de zone en fond.
  Widget _big(MetricReading reading) {
    final background = zoneColorOf(reading.zoneKey);
    final ink = background == null ? Colors.white : foregroundOf(background);

    return BlockSurface(
      background: background,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _value(reading, ink, size: 64),
          Text(
            metric.unit.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color:
                  background == null ? Colors.white54 : ink.withValues(alpha: 0.75),
              fontSize: BlockMetrics.natural.unitSize,
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

    return BlockSurface(
      background: background,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            metric.icon,
            size: BlockMetrics.natural.iconSize,
            color: ink.withValues(alpha: 0.7),
          ),
          const SizedBox(height: 4),
          _value(reading, ink, size: 26, weight: FontWeight.w400, leading: 1.1),
          Text(
            metric.unit.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color:
                  background == null ? Colors.white54 : ink.withValues(alpha: 0.75),
              fontSize: BlockMetrics.natural.unitSize - 2,
            ),
          ),
        ],
      ),
    );
  }

  /// L'aplat de la zone du moment, la mesure dessus.
  ///
  /// Comme [_big] — la couleur *est* l'information, sans zone connue la case
  /// reste sur le fond du tableau de bord. L'icône se pose devant le **titre**
  /// et non devant le chiffre : elle dit quelle mesure on regarde (cœur /
  /// éclair pour la case cardio et la case puissance, qui se peignent des
  /// mêmes couleurs de zone et affichent la même forme « Z3 ») au même endroit
  /// que le nom qui le confirme, avant qu'on descende lire le chiffre lui-même.
  Widget _zone(MetricReading reading) {
    final background = zoneColorOf(reading.zoneKey);
    final ink = background == null ? Colors.white : foregroundOf(background);
    final titleColor =
        background == null ? Colors.white70 : ink.withValues(alpha: 0.85);

    final title = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          metric.icon,
          size: BlockMetrics.natural.iconSize,
          color: titleColor,
        ),
        SizedBox(width: BlockMetrics.natural.gap / 2),
        Text(
          metric.unit.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: titleColor,
            fontSize: BlockMetrics.natural.unitSize + 6,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );

    return BlockSurface(
      background: background,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          title,
          const SizedBox(height: 2),
          // `height: 1` : sans lui, l'interligne par défaut de la police ajoute
          // un blanc au-dessus des chiffres, qui se voyait comme un écart bien
          // plus grand que le `SizedBox` entre le titre et eux.
          Text(
            reading.value ?? '—',
            maxLines: 1,
            style: TextStyle(
              color: ink,
              fontSize: 64,
              fontWeight: FontWeight.w500,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }

  /// La position dans la plage, plutôt que le chiffre exact.
  ///
  /// La plage, ce sont les zones du cycliste : elles viennent du site, et il
  /// n'en existe pas d'autre qui veuille dire quelque chose (une puissance « sur
  /// 400 W » ne dit rien de commun entre deux cyclistes). **Sans zones, il n'y a
  /// pas de plage** : on retombe alors sur le chiffre plein cadre plutôt que de
  /// dessiner une jauge dont on aurait inventé le maximum. C'est le seul repli
  /// de ce composant, et il tient à l'absence de donnée — pas à la taille de la
  /// case, que [ScaleToFit] absorbe désormais seul.
  Widget _gauge(MetricReading reading) {
    final zones = metric.zonesOf(sources.riderProfile.profile);
    if (zones.isEmpty) return _big(reading);

    final index = zones.indexWhere((zone) => zone.key == reading.zoneKey);
    final color = zoneColorOf(reading.zoneKey) ?? Colors.white24;

    // Largeur fixe et non `stretch` : la carte se construit désormais à sa
    // taille naturelle, indépendante de la case, et `stretch` sous une
    // largeur non bornée lèverait — c'est `ScaleToFit` qui ramène ensuite
    // cette largeur à celle de la case réelle.
    return BlockSurface(
      child: SizedBox(
        width: 220,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _value(reading, Colors.white, size: 48),
            SizedBox(height: BlockMetrics.natural.gap),
            // Une case par zone plutôt qu'un remplissage continu : les zones
            // sont des paliers, et un dégradé laisserait croire à une
            // progression linéaire qu'elles n'ont pas.
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
              metric.unit.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white54,
                fontSize: BlockMetrics.natural.unitSize - 2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Le chiffre, à sa taille naturelle.
  ///
  /// `FittedBox` et pas une taille fixe : les valeurs sont de longueurs très
  /// inégales (« 8 » et « 1:12:34 ») et une largeur de case ne s'élargit pas
  /// pour les accueillir. La hauteur, elle, est fixe — c'est la carte entière
  /// que [ScaleToFit] met à l'échelle ensuite, pas ce chiffre pris seul.
  Widget _value(
    MetricReading reading,
    Color ink, {
    required double size,
    FontWeight weight = FontWeight.w500,
    double leading = 1,
  }) =>
      SizedBox(
        height: _valueHeight,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            reading.value ?? '—',
            maxLines: 1,
            style: TextStyle(
              color: ink,
              fontSize: size,
              fontWeight: weight,
              height: leading,
            ),
          ),
        ),
      );
}
