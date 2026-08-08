import 'package:flutter/material.dart';

import '../../account/rider_profile.dart';
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
    this.format = DurationFormat.hm,
    this.min,
    this.max,
    this.onTap,
  });

  final MetricId metric;
  final MetricSources sources;
  final MetricMode mode;

  /// N'a d'effet que sur une mesure de durée — voir [MetricBlock.format].
  final DurationFormat format;

  /// Bornes de la jauge à plage libre — voir [MetricBlock.min]/[MetricBlock.max].
  /// N'ont d'effet qu'en [MetricMode.gauge], sur une mesure sans zones
  /// d'entraînement.
  final double? min;
  final double? max;

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
      builder: (context, _) => _paint(metric.read(sources, format: format)),
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
        MetricMode.dynamicGauge => _dynamicGauge(reading),
      };

  /// Le chiffre, sa couleur de zone en fond.
  Widget _big(MetricReading reading) {
    final background = reading.background ?? zoneColorOf(reading.zoneKey);
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
    final background = reading.background ?? zoneColorOf(reading.zoneKey);
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
    final background = reading.background ?? zoneColorOf(reading.zoneKey);
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

  /// Le nombre de paliers de la jauge à plage libre — même dessin que la
  /// jauge de zones, mais répartis également entre [min] et [max] plutôt que
  /// sur des seuils réels. Cinq, comme les zones cardio : c'est la jauge la
  /// plus familière de l'appli. **Même valeur que `RANGE_GAUGE_SEGMENTS`
  /// côté site** (`companionSettings.ts`) — c'est elle qui dessine la
  /// vignette qu'on a composée.
  static const _rangeGaugeSegments = 5;

  /// Une seule couleur pour tous les paliers allumés : contrairement aux
  /// zones, une plage libre n'a pas de teinte propre à chaque tranche — juste
  /// « on y est ». **Même valeur que `RANGE_GAUGE_COLOR` côté site.**
  static const _rangeGaugeColor = Color(0xFF26A69A);

  /// La position dans la plage, plutôt que le chiffre exact.
  ///
  /// Deux sources de plage, mutuellement exclusives : les zones du cycliste
  /// quand la mesure en porte ([_zoneGauge]) — cardio, puissance, les seules
  /// qui veulent dire quelque chose d'un cycliste à l'autre — ou un min/max
  /// réglé dans l'éditeur ([_rangeGauge]) pour les autres. **Sans l'une ni
  /// l'autre, on retombe sur le chiffre plein cadre** plutôt que de dessiner
  /// une jauge dont on aurait inventé la plage.
  Widget _gauge(MetricReading reading) {
    final zones = metric.zonesOf(sources.riderProfile.profile);
    if (zones.isNotEmpty) return _zoneGauge(reading, zones);
    if (min != null && max != null) return _rangeGauge(reading);
    return _big(reading);
  }

  /// La jauge de zones : un palier par zone du cycliste, chacun de la couleur
  /// de sa zone, allumés jusqu'à celle du moment.
  Widget _zoneGauge(MetricReading reading, List<TrainingZone> zones) {
    final index = zones.indexWhere((zone) => zone.key == reading.zoneKey);
    final color = zoneColorOf(reading.zoneKey) ?? Colors.white24;

    return _gaugeCard(
      reading,
      segments: zones.length,
      isLit: (i) => i <= index && index >= 0,
      litColorAt: (i) => zoneColorOf(zones[i].key) ?? color,
    );
  }

  /// La jauge à plage libre : le pendant de [_zoneGauge] pour une mesure sans
  /// zones d'entraînement, sur les bornes [min]/[max] réglées dans l'éditeur.
  /// Mêmes paliers, également répartis entre les deux bornes plutôt que sur
  /// des seuils réels — d'où une seule couleur au lieu d'une par palier.
  ///
  /// Un chiffre absent ([MetricReading.numericValue] `null`) éteint tous les
  /// paliers plutôt que d'en deviner un : la mesure garde son tiret, la
  /// jauge doit dire la même chose que lui.
  Widget _rangeGauge(MetricReading reading) {
    final value = reading.numericValue;
    final fraction = value == null
        ? null
        : ((value - min!) / (max! - min!)).clamp(0.0, 1.0);
    final lit = fraction == null ? -1 : (fraction * _rangeGaugeSegments).round();

    return _gaugeCard(
      reading,
      segments: _rangeGaugeSegments,
      isLit: (i) => i < lit,
      litColorAt: (_) => _rangeGaugeColor,
    );
  }

  /// La carte commune aux deux jauges : le chiffre, une rangée de paliers,
  /// l'unité — seuls le nombre de paliers et leur couleur changent entre
  /// [_zoneGauge] et [_rangeGauge].
  Widget _gaugeCard(
    MetricReading reading, {
    required int segments,
    required bool Function(int i) isLit,
    required Color Function(int i) litColorAt,
  }) {
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
            // Une case par palier plutôt qu'un remplissage continu : un
            // dégradé laisserait croire à une progression linéaire que les
            // zones n'ont pas — et la plage libre garde le même dessin.
            Row(
              children: [
                for (var i = 0; i < segments; i++) ...[
                  if (i > 0) const SizedBox(width: 2),
                  Expanded(
                    child: Container(
                      height: 8,
                      decoration: BoxDecoration(
                        color: isLit(i) ? litColorAt(i) : Colors.white12,
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

  /// Le remplissage d'une jauge dynamique : même couleur que la jauge à
  /// plage libre, pour rester le même langage visuel — « on y est » sans
  /// teinte propre à une tranche.
  static const _dynamicGaugeColor = Color(0xFF26A69A);

  /// La jauge dynamique : le pendant de [_gauge] pour une plage qui ne se
  /// règle pas dans l'éditeur mais se lit dans la sortie en cours — voir
  /// [MetricId.liveRangeOf]. Sans plage exploitable, ou sans chiffre à y
  /// placer, on retombe sur le chiffre plein cadre plutôt que de dessiner un
  /// curseur dont on aurait inventé la position.
  Widget _dynamicGauge(MetricReading reading) {
    final range = metric.liveRangeOf(sources);
    final value = reading.numericValue;
    if (range == null || value == null) return _big(reading);

    final (min, max) = range;
    final fraction = ((value - min) / (max - min)).clamp(0.0, 1.0);
    return _dynamicGaugeCard(reading, fraction: fraction);
  }

  /// La largeur à laquelle la carte se construit avant mise à l'échelle,
  /// quand aucune contrainte réelle n'est disponible — cas resté théorique en
  /// pratique (cf. [_measuredWidth]).
  static const _dynamicGaugeNaturalWidth = 220.0;

  /// La largeur réelle de la case, mesurée **avant** [BlockSurface] : son
  /// `FittedBox` (posé par [ScaleToFit]) mesure son enfant avec des
  /// contraintes non bornées — c'est ainsi qu'il calcule son facteur
  /// d'échelle — donc un `LayoutBuilder` posé plus bas, à l'intérieur de la
  /// carte, ne voit jamais la largeur réelle de la case en grille. Sans ce
  /// rattrapage, la carte se construirait toujours à
  /// [_dynamicGaugeNaturalWidth], quelle que soit la largeur de la case, et
  /// la piste resterait plus étroite que la case chaque fois que celle-ci est
  /// plus large — exactement le rattrapage déjà fait pour le budget de charge
  /// ([TrainingBudgetBlock]), ici parce qu'une piste bénéficie de toute la
  /// largeur disponible, contrairement au chiffre plein cadre.
  double _measuredWidth(BoxConstraints constraints) => constraints.hasBoundedWidth
      ? constraints.maxWidth - BlockMetrics.natural.padding * 2
      : _dynamicGaugeNaturalWidth;

  /// Le chiffre, une piste continue, l'unité — même carte que [_gaugeCard]
  /// mais un remplissage jusqu'à la position réelle plutôt que des paliers :
  /// la plage d'une jauge dynamique est une vraie progression (une position
  /// dans la sortie, ou vers l'arrivée), pas des seuils entre lesquels un
  /// dégradé mentirait comme pour les zones. Plus épaisse que [_gaugeCard]
  /// aussi ([BlockMetrics.natural.barHeight], la même que la barre de zones)
  /// — c'est elle qui porte l'information ici, pas des paliers à côté d'un
  /// chiffre déjà lisible seul.
  Widget _dynamicGaugeCard(MetricReading reading, {required double fraction}) {
    return LayoutBuilder(
      builder: (context, outerConstraints) {
        final width = _measuredWidth(outerConstraints);
        final barHeight = BlockMetrics.natural.barHeight;

        return BlockSurface(
          child: SizedBox(
            width: width,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _value(reading, Colors.white, size: 48),
                SizedBox(height: BlockMetrics.natural.gap),
                SizedBox(
                  height: barHeight,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final trackWidth = constraints.maxWidth;
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(barHeight / 2),
                        child: Stack(
                          children: [
                            const Positioned.fill(child: ColoredBox(color: Colors.white12)),
                            Positioned.fill(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  SizedBox(
                                    width: trackWidth * fraction,
                                    child: const ColoredBox(color: _dynamicGaugeColor),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
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
      },
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
