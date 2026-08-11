import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../account/rider_profile.dart';
import '../../dashboard/block_density.dart';
import '../../dashboard/dashboard_block.dart';
import '../../dashboard/metric_id.dart';
import '../../ui/zone_colors.dart';
import 'block_card.dart';

/// Une mesure du catalogue, dessinée selon sa disposition ([MetricLayout]) :
/// une grille à 3 colonnes et jusqu'à [MetricLayout.maxRows] rangées, où
/// chaque élément (icône, étiquette, unité, chiffre, jauge) se pose dans une
/// case précise — voir `dashboard_block.dart`. Une rangée sans occupant ne
/// prend aucune place.
///
/// **Un tiret quand la mesure manque, jamais un zéro** — la règle du dépôt : un
/// zéro se lit comme une mesure, alors qu'un capteur muet ne mesure rien.
///
/// La disposition posée est un **ordre** : tout ce qu'elle décrit est toujours
/// dessiné, quelle que soit la case — c'est [ScaleToFit], posé par
/// [BlockSurface], qui réduit l'ensemble s'il ne tient pas, plutôt que de
/// retirer des éléments un à un. La *position* de chaque élément, elle, suit
/// la largeur réelle de la case ([_measuredWidth]) : une case posée « en haut
/// à droite » touche vraiment ce coin, quelle que soit la taille de la case,
/// plutôt qu'un repère qui ne vaudrait que pour une case de référence.
class MetricView extends StatelessWidget {
  const MetricView({
    super.key,
    required this.metric,
    required this.sources,
    this.layout = MetricLayout.fallback,
    this.format = DurationFormat.hm,
    this.icon,
    this.min,
    this.max,
    this.color,
    this.textColor,
    this.onTap,
  });

  final MetricId metric;
  final MetricSources sources;

  /// Où se pose chaque élément — voir [MetricLayout].
  final MetricLayout layout;

  /// N'a d'effet que sur une mesure de durée — voir [MetricBlock.format].
  final DurationFormat format;

  /// L'icône personnalisée réglée dans l'éditeur — voir [MetricBlock.icon].
  /// `null` : [MetricId.icon] fait foi.
  final FaIconData? icon;

  /// Bornes de la jauge à plage libre — voir [MetricBlock.min]/
  /// [MetricBlock.max]. N'ont d'effet que sur une mesure sans zones
  /// d'entraînement, sur la rangée de [layout] réglée en jauge.
  final double? min;
  final double? max;

  /// Fond réglé dans l'éditeur — voir [DashboardBlock.color]. Prioritaire sur
  /// [MetricReading.background]/la couleur de zone : c'est le seul moyen de
  /// choisir un fond différent de celui, sémantique, que la mesure porte
  /// déjà.
  final Color? color;

  /// Texte réglé dans l'éditeur — voir [DashboardBlock.textColor].
  /// Prioritaire sur le calcul habituel ([foregroundOf] du fond réel).
  final Color? textColor;

  /// Un tap sur la mesure. Sert aux watts, qui ouvrent la calibration du capteur
  /// de puissance : c'est là qu'on *constate* une puissance qui dérive, et non
  /// dans un menu deux pages plus loin.
  final VoidCallback? onTap;

  /// La hauteur naturelle du chiffre : celle à laquelle il est construit avant
  /// mise à l'échelle, dans une grille comme dans une page qui défile — une
  /// mesure posée dans une liste doit se lire comme une mesure posée dans une
  /// grille.
  static const _valueHeight = 72.0;

  /// La taille naturelle du chiffre — réduite quand la disposition porte une
  /// jauge, pour lui laisser de la place, même repli que la carte de jauge
  /// d'avant ce chantier.
  static const _bigValueSize = 64.0;
  static const _gaugeValueSize = 48.0;

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

  /// Les rangées utilisées, dans l'ordre — une rangée sans aucun élément n'y
  /// figure pas.
  List<int> get _usedRows {
    final rows = <int>{
      if (layout.icon != null) layout.icon!.row,
      if (layout.label != null) layout.label!.row,
      if (layout.unit != null) layout.unit!.row,
      layout.value.row,
      if (layout.gaugeRow != null) layout.gaugeRow!,
    };
    return rows.toList()..sort();
  }

  Widget _paint(MetricReading reading) {
    final background = color ?? reading.background ?? zoneColorOf(reading.zoneKey);
    final ink = textColor ?? (background == null ? Colors.white : foregroundOf(background));
    final valueSize = layout.gaugeRow != null ? _gaugeValueSize : _bigValueSize;
    final rows = _usedRows;

    return LayoutBuilder(
      builder: (context, outerConstraints) {
        final width = _measuredWidth(outerConstraints);
        final height = _measuredHeight(outerConstraints);

        // Une case en grille a une hauteur réelle à remplir (`height` non
        // nul) : la première rangée posée doit toucher le vrai haut de la
        // case, pas seulement le haut d'un bloc de contenu ensuite recentré
        // par [ScaleToFit] — et la dernière ne doit pas laisser de place
        // morte en dessous d'elle. Chaque rangée de texte/chiffre reçoit donc
        // une part de la hauteur réelle proportionnelle à son poids
        // (`Expanded.flex`, voir [RowHeight]), son contenu centré dedans à sa
        // taille naturelle ; une rangée de jauge, elle, garde toujours sa
        // hauteur naturelle (une barre plus haute n'apporte rien). Sans
        // hauteur réelle (une page qui défile) : repli sur la hauteur
        // naturelle du contenu, comme avant ce chantier.
        final children = [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) SizedBox(height: BlockMetrics.natural.gap),
            if (layout.gaugeRow == rows[i])
              _gaugeRow(reading)
            else if (height != null)
              Expanded(
                flex: layout.heightOf(rows[i]).weight,
                child: Center(child: _gridRow(rows[i], reading, ink, valueSize)),
              )
            else
              _gridRow(rows[i], reading, ink, valueSize),
          ],
        ];

        final column = Column(
          mainAxisSize: height == null ? MainAxisSize.min : MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        );

        return BlockSurface(
          background: background,
          child: SizedBox(
            width: width,
            height: height,
            child: column,
          ),
        );
      },
    );
  }

  /// Une rangée normale : ses éléments répartis dans une barre à 3 tiers
  /// égaux (gauche/centre/droite), le motif d'une barre d'outils — il gère
  /// nativement 1, 2 ou 3 tiers occupés, sans code spécifique par cas, et
  /// c'est lui qui fait qu'une case posée « à droite » touche vraiment le
  /// bord droit de la rangée, quelle que soit la largeur de ce qu'il y a (ou
  /// pas) à côté. Plusieurs éléments dans une même case s'y affichent dans un
  /// ordre fixe — icône, étiquette, unité, chiffre — qu'on les ait posés dans
  /// cet ordre ou non.
  Widget _gridRow(int row, MetricReading reading, Color ink, double valueSize) {
    Widget? iconAt(GridColumn c) =>
        (layout.icon?.row == row && layout.icon?.column == c) ? _iconWidget(ink) : null;
    Widget? labelAt(GridColumn c) =>
        (layout.label?.row == row && layout.label?.column == c) ? _labelWidget(ink) : null;
    // Un jeton `unit` sur une mesure dont l'unité est vide (durée, braquet…)
    // ne dessine simplement rien, comme la jauge sur une mesure non
    // éligible — pas une clé mal réglée à corriger, juste rien à y mettre.
    Widget? unitAt(GridColumn c) =>
        (metric.unit.isNotEmpty && layout.unit?.row == row && layout.unit?.column == c)
            ? _unitWidget(ink)
            : null;
    Widget? valueAt(GridColumn c) =>
        (layout.value.row == row && layout.value.column == c) ? _value(reading, ink, size: valueSize) : null;

    bool isEmpty(GridColumn c) =>
        iconAt(c) == null && labelAt(c) == null && unitAt(c) == null && valueAt(c) == null;

    // L'icône garde toujours sa taille — la rogner la rendrait illisible. Le
    // texte, lui, peut céder la place (`Flexible` + ellipse sur les `Text`
    // eux-mêmes) si sa case ne suffit pas, plutôt que de déborder.
    Widget columnContent(GridColumn c) {
      final parts = <Widget>[];
      void addFixed(Widget? w) {
        if (w == null) return;
        if (parts.isNotEmpty) parts.add(SizedBox(width: BlockMetrics.natural.gap / 2));
        parts.add(w);
      }

      void addFlexible(Widget? w) {
        if (w == null) return;
        if (parts.isNotEmpty) parts.add(SizedBox(width: BlockMetrics.natural.gap / 2));
        parts.add(Flexible(child: w));
      }

      addFixed(iconAt(c));
      addFlexible(labelAt(c));
      addFlexible(unitAt(c));
      addFlexible(valueAt(c));

      return Row(mainAxisSize: MainAxisSize.min, children: parts);
    }

    // Une colonne vide ne participe pas au partage de largeur — pas même une
    // part égale : c'est ce qui fait qu'une seule colonne occupée récupère
    // toute la largeur de la rangée plutôt qu'un tiers fixe. Occupée, elle
    // partage ce qui reste avec les autres colonnes occupées de cette même
    // rangée — jamais de débordement, même les trois chargées à la fois — le
    // centre gardant deux fois leur poids : c'est presque toujours lui qui
    // porte le chiffre, la colonne qui doit rester la plus grande quand
    // plusieurs se disputent la rangée.
    Widget slot(GridColumn c, AlignmentGeometry alignment, int flex) {
      if (isEmpty(c)) return const SizedBox.shrink();
      return Flexible(flex: flex, child: Align(alignment: alignment, child: columnContent(c)));
    }

    return Row(
      children: [
        slot(GridColumn.left, Alignment.centerLeft, 1),
        slot(GridColumn.center, Alignment.center, 2),
        slot(GridColumn.right, Alignment.centerRight, 1),
      ],
    );
  }

  Widget _iconWidget(Color ink) {
    final custom = icon;
    final size = BlockMetrics.natural.iconSize;
    final tint = ink.withValues(alpha: 0.7);
    // FontAwesome n'est pas dessinable par [Icon] — [FaIcon] seul évite le
    // rognage/désalignement des glyphes non carrés (voir la doc de
    // `FaIconData`). L'icône par défaut d'une mesure, elle, reste une icône
    // Material ([MetricId.icon]).
    return custom != null ? FaIcon(custom, size: size, color: tint) : Icon(metric.icon, size: size, color: tint);
  }

  Widget _labelWidget(Color ink) => Text(
        metric.name.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: ink.withValues(alpha: 0.85),
          fontSize: BlockMetrics.natural.titleSize + 2,
          fontWeight: FontWeight.w700,
        ),
      );

  Widget _unitWidget(Color ink) => Text(
        metric.unit.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: ink.withValues(alpha: 0.6),
          fontSize: BlockMetrics.natural.unitSize,
        ),
      );

  // ── La jauge ─────────────────────────────────────────────────────────────
  //
  // Trois natures, mutuellement exclusives, décidées ici plutôt que réglées
  // dans le document : une mesure à zones garde toujours la jauge du
  // cycliste (cardio, puissance) ; sinon un min/max réglé dans l'éditeur
  // dessine la jauge à plage libre ; sinon la plage observée en roulant
  // ([MetricId.liveRangeOf]) dessine la jauge dynamique. **Sans aucune des
  // trois, la rangée ne dessine rien** — contrairement à avant ce chantier,
  // où une jauge non éligible faisait retomber toute la carte sur le chiffre
  // plein cadre : ici seule la barre disparaît, le reste de la disposition
  // composée reste tel quel.

  static const _rangeGaugeSegments = 5;
  static const _rangeGaugeColor = Color(0xFF26A69A);
  static const _dynamicGaugeColor = Color(0xFF26A69A);

  Widget _gaugeRow(MetricReading reading) {
    final zones = metric.zonesOf(sources.riderProfile.profile);
    if (zones.isNotEmpty) return _zoneGaugeBar(reading, zones);
    if (min != null && max != null) return _rangeGaugeBar(reading);

    final range = metric.liveRangeOf(sources);
    final value = reading.numericValue;
    if (range != null && value != null) {
      final (rangeMin, rangeMax) = range;
      final fraction = ((value - rangeMin) / (rangeMax - rangeMin)).clamp(0.0, 1.0);
      return _dynamicGaugeBar(fraction);
    }

    return const SizedBox.shrink();
  }

  /// La jauge de zones : un palier par zone du cycliste, chacun de la couleur
  /// de sa zone, allumés jusqu'à celle du moment.
  Widget _zoneGaugeBar(MetricReading reading, List<TrainingZone> zones) {
    final index = zones.indexWhere((zone) => zone.key == reading.zoneKey);
    final fallback = zoneColorOf(reading.zoneKey) ?? Colors.white24;

    return _segments(
      count: zones.length,
      isLit: (i) => i <= index && index >= 0,
      litColorAt: (i) => zoneColorOf(zones[i].key) ?? fallback,
    );
  }

  /// La jauge à plage libre : le pendant de [_zoneGaugeBar] pour une mesure
  /// sans zones d'entraînement, sur les bornes [min]/[max] réglées dans
  /// l'éditeur. Mêmes paliers, également répartis entre les deux bornes
  /// plutôt que sur des seuils réels — d'où une seule couleur au lieu d'une
  /// par palier.
  ///
  /// Un chiffre absent ([MetricReading.numericValue] `null`) éteint tous les
  /// paliers plutôt que d'en deviner un : la mesure garde son tiret, la
  /// jauge doit dire la même chose que lui.
  Widget _rangeGaugeBar(MetricReading reading) {
    final value = reading.numericValue;
    final fraction = value == null ? null : ((value - min!) / (max! - min!)).clamp(0.0, 1.0);
    final lit = fraction == null ? -1 : (fraction * _rangeGaugeSegments).round();

    return _segments(
      count: _rangeGaugeSegments,
      isLit: (i) => i < lit,
      litColorAt: (_) => _rangeGaugeColor,
    );
  }

  /// Les paliers communs aux deux jauges à zones/plage libre — seuls leur
  /// nombre et leur couleur changent entre les deux.
  Widget _segments({
    required int count,
    required bool Function(int i) isLit,
    required Color Function(int i) litColorAt,
  }) =>
      Row(
        children: [
          for (var i = 0; i < count; i++) ...[
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
      );

  /// Le remplissage d'une jauge dynamique : une piste continue jusqu'à la
  /// position réelle, pas des paliers — la plage (min/max de la sortie, ou
  /// progression vers l'itinéraire) est une vraie progression, pas des
  /// seuils entre lesquels un dégradé mentirait comme pour les zones. Plus
  /// épaisse que [_segments] aussi ([BlockMetrics.natural.barHeight], la
  /// même que la barre de zones) — c'est elle qui porte l'information ici,
  /// pas des paliers à côté d'un chiffre déjà lisible seul.
  Widget _dynamicGaugeBar(double fraction) {
    final barHeight = BlockMetrics.natural.barHeight;

    return SizedBox(
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
    );
  }

  /// La largeur à laquelle la carte se construit avant mise à l'échelle,
  /// quand aucune contrainte réelle n'est disponible — cas resté théorique en
  /// pratique (cf. [_measuredWidth]).
  static const _naturalWidth = 220.0;

  /// La largeur réelle de la case, mesurée **avant** [BlockSurface] : son
  /// `FittedBox` (posé par `ScaleToFit`) mesure son enfant avec des
  /// contraintes non bornées — c'est ainsi qu'il calcule son facteur
  /// d'échelle — donc un `LayoutBuilder` posé plus bas, à l'intérieur de la
  /// carte, ne voit jamais la largeur réelle de la case en grille. Sans ce
  /// rattrapage, la carte se construirait toujours à [_naturalWidth], quelle
  /// que soit la largeur de la case, et une rangée posée « à droite »
  /// resterait au bord d'une largeur de référence plutôt qu'à celui de la
  /// case réelle — dans une case plus large, elle se lirait centrée avec du
  /// vide autour, pas au bord.
  double _measuredWidth(BoxConstraints constraints) => constraints.hasBoundedWidth
      ? constraints.maxWidth - BlockMetrics.natural.padding * 2
      : _naturalWidth;

  /// La hauteur réelle de la case, même rattrapage que [_measuredWidth] et
  /// pour la même raison : sans lui, le contenu (souvent plus bas qu'une case
  /// haute) se retrouverait recentré par [FittedBox] au lieu de remplir la
  /// case du haut vers le bas comme composé. `null` sans hauteur réelle (une
  /// page qui défile) — [_paint] retombe alors sur la hauteur naturelle du
  /// contenu, il n'y a rien à remplir.
  double? _measuredHeight(BoxConstraints constraints) =>
      constraints.hasBoundedHeight ? constraints.maxHeight - BlockMetrics.natural.padding * 2 : null;

  /// Le chiffre, à sa taille naturelle.
  ///
  /// `FittedBox` et pas une taille fixe : les valeurs sont de longueurs très
  /// inégales (« 8 » et « 1:12:34 ») et une largeur de case ne s'élargit pas
  /// pour les accueillir. La hauteur, elle, est fixe — c'est la carte entière
  /// que `ScaleToFit` met à l'échelle ensuite, pas ce chiffre pris seul.
  Widget _value(
    MetricReading reading,
    Color ink, {
    required double size,
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
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      );
}
