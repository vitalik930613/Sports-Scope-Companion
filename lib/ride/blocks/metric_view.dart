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
/// Le mode demandé est un **plafond** : dans une case trop petite pour ce qu'il
/// suppose, on retire l'icône, puis l'unité, puis la jauge elle-même (cf.
/// [BlockMetrics]). Le chiffre, lui, ne part jamais — c'est ce qu'on est venu
/// lire.
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

  /// La hauteur que prend le chiffre dans une page qui défile, où il n'y a
  /// aucune case pour la lui donner. Celle d'une cellule de grille confortable :
  /// une mesure posée dans une liste doit se lire comme une mesure posée dans
  /// une grille.
  static const _unboundedValueHeight = 72.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = BlockMetrics.of(constraints);
        final content = ListenableBuilder(
          listenable: Listenable.merge(metric.dependencies(sources)),
          builder: (context, _) => _paint(
            metric.read(sources),
            metrics,
            bounded: constraints.hasBoundedHeight,
          ),
        );

        if (onTap == null) return content;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: content,
        );
      },
    );
  }

  Widget _paint(
    MetricReading reading,
    BlockMetrics metrics, {
    required bool bounded,
  }) =>
      switch (mode) {
        MetricMode.big => _big(reading, metrics, bounded: bounded),
        MetricMode.compact => _compact(reading, metrics, bounded: bounded),
        MetricMode.zone => _zone(reading, metrics, bounded: bounded),
        MetricMode.gauge => _gauge(reading, metrics, bounded: bounded),
      };

  /// Le chiffre aussi grand que la case le permet.
  ///
  /// `FittedBox` et pas une taille fixe : les valeurs sont de longueurs très
  /// inégales (« 8 » et « 1:12:34 ») et une cellule de grille ne s'élargit pas
  /// pour les accueillir.
  Widget _big(
    MetricReading reading,
    BlockMetrics metrics, {
    required bool bounded,
  }) {
    final background = zoneColorOf(reading.zoneKey);
    final ink = background == null ? Colors.white : foregroundOf(background);

    return BlockSurface(
      metrics: metrics,
      background: background,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _value(reading, ink, size: 64, bounded: bounded),
          if (metrics.showUnit)
            Text(
              metric.unit,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: background == null
                    ? Colors.white54
                    : ink.withValues(alpha: 0.75),
                fontSize: metrics.unitSize,
              ),
            ),
        ],
      ),
    );
  }

  /// Icône, valeur, unité — la mise en forme de `MetricTile`, pour les cellules
  /// où l'on tient plusieurs mesures.
  Widget _compact(
    MetricReading reading,
    BlockMetrics metrics, {
    required bool bounded,
  }) {
    final background = zoneColorOf(reading.zoneKey);
    final ink = background == null ? Colors.white : foregroundOf(background);

    return BlockSurface(
      metrics: metrics,
      background: background,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (metrics.showIcon) ...[
            Icon(
              metric.icon,
              size: metrics.iconSize,
              color: ink.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 4),
          ],
          _value(
            reading,
            ink,
            size: 26,
            weight: FontWeight.w400,
            leading: 1.1,
            bounded: bounded,
          ),
          if (metrics.showUnit)
            Text(
              metric.unit,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: background == null
                    ? Colors.white54
                    : ink.withValues(alpha: 0.75),
                fontSize: metrics.unitSize - 2,
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
  Widget _zone(
    MetricReading reading,
    BlockMetrics metrics, {
    required bool bounded,
  }) =>
      _big(reading, metrics, bounded: bounded);

  /// La position dans la plage, plutôt que le chiffre exact.
  ///
  /// La plage, ce sont les zones du cycliste : elles viennent du site, et il
  /// n'en existe pas d'autre qui veuille dire quelque chose (une puissance « sur
  /// 400 W » ne dit rien de commun entre deux cyclistes). **Sans zones, il n'y a
  /// pas de plage** : on retombe alors sur le chiffre plein cadre plutôt que de
  /// dessiner une jauge dont on aurait inventé le maximum.
  ///
  /// Même repli dans une case minuscule, et pour une raison voisine : sept
  /// paliers sur 48 pixels de large ne se distinguent plus les uns des autres,
  /// et une jauge qu'on ne sait pas lire vaut moins que le chiffre qu'elle
  /// remplaçait.
  Widget _gauge(
    MetricReading reading,
    BlockMetrics metrics, {
    required bool bounded,
  }) {
    final zones = metric.zonesOf(sources.riderProfile.profile);
    if (zones.isEmpty || metrics.density == BlockDensity.minimal) {
      return _big(reading, metrics, bounded: bounded);
    }

    final index = zones.indexWhere((zone) => zone.key == reading.zoneKey);
    final color = zoneColorOf(reading.zoneKey) ?? Colors.white24;

    return BlockSurface(
      metrics: metrics,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _value(reading, Colors.white, size: 48, bounded: bounded),
          SizedBox(height: metrics.gap),
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
          if (metrics.showUnit) ...[
            const SizedBox(height: 4),
            Text(
              metric.unit,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white54,
                fontSize: metrics.unitSize - 2,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Le chiffre, à la taille que la case lui laisse.
  ///
  /// `Expanded` dans une case — il prend tout ce que l'unité et l'icône n'ont
  /// pas pris — mais **jamais dans une page qui défile** : la hauteur y est
  /// infinie, et un enfant à flex non nul sous une contrainte infinie lève au
  /// premier rendu.
  Widget _value(
    MetricReading reading,
    Color ink, {
    required double size,
    required bool bounded,
    FontWeight weight = FontWeight.w500,
    double leading = 1,
  }) {
    final text = FittedBox(
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
    );

    if (!bounded) return SizedBox(height: _unboundedValueHeight, child: text);
    return Expanded(child: text);
  }
}
