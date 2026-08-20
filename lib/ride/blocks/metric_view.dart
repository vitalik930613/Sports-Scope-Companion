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
    this.label,
    this.min,
    this.max,
    this.gaugeFill,
    this.gaugeSegments,
    this.gaugeColorMode,
    this.gaugeColor,
    this.gaugeThickness = GaugeThickness.normal,
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

  /// Le libellé personnalisé réglé dans l'éditeur — voir [MetricBlock.label].
  /// `null` : [MetricId.name] fait foi, comme avant ce réglage.
  final String? label;

  /// Bornes de la jauge à plage libre — voir [MetricBlock.min]/
  /// [MetricBlock.max]. N'ont d'effet que sur une mesure sans zones
  /// d'entraînement, sur la rangée de [layout] réglée en jauge.
  final double? min;
  final double? max;

  /// Forme, nombre de tronçons et couleur du remplissage de la jauge — voir
  /// [MetricBlock.gaugeFill]/[MetricBlock.gaugeSegments]/
  /// [MetricBlock.gaugeColorMode]/[MetricBlock.gaugeColor]. `null` partout :
  /// la jauge garde le rendu d'avant ce réglage, propre à sa nature (zones,
  /// plage libre, plage dynamique).
  final GaugeFill? gaugeFill;
  final int? gaugeSegments;
  final GaugeColorMode? gaugeColorMode;
  final Color? gaugeColor;

  /// Épaisseur de la jauge — voir [MetricBlock.gaugeThickness].
  final GaugeThickness gaugeThickness;

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

  /// L'espace entre deux rangées (icône/étiquette/unité/chiffre/jauge) — nul
  /// en grille : sur une case déjà courte, ces quelques pixels valent mieux
  /// rendus au chiffre (via `grow()`) qu'à un vide entre les rangées. Une page
  /// qui défile garde un espace, sinon les rangées s'y liraient collées.
  static const _rowGap = 0.0;
  static const _rowGapScrolling = 8.0;

  @override
  Widget build(BuildContext context) {
    final content = ListenableBuilder(
      // Les dépendances des mesures secondaires aussi : sans ça, une carte
      // dont seule la moyenne bouge (la vitesse instantanée restant stable)
      // ne se rafraîchirait jamais.
      listenable: Listenable.merge([
        ...metric.dependencies(sources),
        for (final slot in layout.secondary) ...slot.metric.dependencies(sources),
      ]),
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
      for (final slot in layout.secondary) slot.position.row,
    };
    return rows.toList()..sort();
  }

  Widget _paint(MetricReading reading) {
    final background = color ?? reading.background ?? zoneColorOf(reading.zoneKey);
    final ink = textColor ?? (background == null ? Colors.white : foregroundOf(background));
    final valueSize = layout.gaugeRow != null ? _gaugeValueSize : _bigValueSize;
    final rows = _usedRows;
    // Lues une fois pour toute la carte plutôt qu'à chaque case : plusieurs
    // slots peuvent porter la même mesure (rare mais pas interdit), et
    // `MetricId.read` n'est pas gratuit (zones, formatage).
    final secondaryReadings = {
      for (final slot in layout.secondary) slot: slot.metric.read(sources, format: format),
    };

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
        // (`Expanded.flex`, voir [RowHeight]), et son contenu grandit pour la
        // remplir plutôt que de rester centré à sa taille naturelle avec du
        // vide autour — un centrage y aurait fait le même effet qu'un padding
        // interne, en double emploi avec [_rowGap] ; une rangée de jauge, elle,
        // garde toujours sa hauteur naturelle (une barre plus haute n'apporte
        // rien). Sans hauteur réelle (une page qui défile) : repli sur la
        // hauteur naturelle du contenu, comme avant ce chantier.
        final children = [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) SizedBox(height: height == null ? _rowGapScrolling : _rowGap),
            if (layout.gaugeRow == rows[i])
              _gaugeRow(reading)
            else if (height != null)
              Expanded(
                flex: layout.heightOf(rows[i]).weight,
                child: LayoutBuilder(
                  builder: (context, rowConstraints) => _gridRow(
                    rows[i],
                    reading,
                    ink,
                    valueSize,
                    secondaryReadings,
                    rowHeight: rowConstraints.maxHeight,
                  ),
                ),
              )
            else
              _gridRow(rows[i], reading, ink, valueSize, secondaryReadings),
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
  Widget _gridRow(
    int row,
    MetricReading reading,
    Color ink,
    double valueSize,
    Map<SecondaryMetricSlot, MetricReading> secondaryReadings, {
    double? rowHeight,
  }) {
    // Le facteur d'échelle de cette rangée ([RowHeight.scale]) : une rangée
    // ne reçoit plus de place ([slot], plus bas) que si son contenu grandit
    // d'autant, sinon elle déborderait sur sa voisine plutôt que de s'y
    // ajuster — voir la doc de [RowHeight].
    final scale = layout.heightOf(row).scale;

    Widget? iconAt(GridColumn c) {
      if (layout.icon?.row != row || layout.icon?.column != c) return null;
      // Sur la même case qu'une étiquette ou le chiffre, l'icône reprend leur
      // taille : posés côte à côte, ils se lisent comme un seul mot (« ❤ FC »
      // ou « ❤ 158 »), et une icône bien plus grande que ce qui la suit casse
      // cette lecture d'un coup d'œil. Le libellé gagne si les deux partagent
      // la case avec l'icône : c'est lui, pas le chiffre, qu'on veut lire
      // comme sa légende. Seule, l'icône garde sa taille habituelle, plus
      // lisible dans une case qui n'a qu'elle à montrer.
      final pairedWithLabel = layout.label?.row == row && layout.label?.column == c;
      final pairedWithValue = layout.value.row == row && layout.value.column == c;
      final matchSize = pairedWithLabel
          ? (BlockMetrics.natural.titleSize + 2) * scale
          : pairedWithValue
              ? valueSize * scale
              : null;
      return _iconWidget(ink, scale, matchSize: matchSize);
    }
    Widget? labelAt(GridColumn c) =>
        (layout.label?.row == row && layout.label?.column == c) ? _labelWidget(ink, scale) : null;
    // Un jeton `unit` sur une mesure dont l'unité est vide (durée, braquet…)
    // ne dessine simplement rien, comme la jauge sur une mesure non
    // éligible — pas une clé mal réglée à corriger, juste rien à y mettre.
    Widget? unitAt(GridColumn c) =>
        (metric.unit.isNotEmpty && layout.unit?.row == row && layout.unit?.column == c)
            ? _unitWidget(ink, scale)
            : null;
    Widget? valueAt(GridColumn c) => (layout.value.row == row && layout.value.column == c)
        ? _value(
            reading,
            ink,
            size: valueSize * scale,
            naturalHeight: rowHeight == null ? _valueHeight : null,
          )
        : null;
    // Au plus un slot par case — la collision est déjà tranchée en amont
    // (`MetricLayout.parse`, « premier posé gagne »), donc `firstWhere`
    // trouve toujours zéro ou une entrée.
    Widget? secondaryAt(GridColumn c) {
      for (final entry in secondaryReadings.entries) {
        if (entry.key.position.row == row && entry.key.position.column == c) {
          return _secondaryWidget(entry.key, entry.value, ink, scale * entry.key.size.factor);
        }
      }
      return null;
    }

    bool isEmpty(GridColumn c) =>
        iconAt(c) == null &&
        labelAt(c) == null &&
        unitAt(c) == null &&
        valueAt(c) == null &&
        secondaryAt(c) == null;

    // Les éléments d'une même case, à leur taille *naturelle* et dans un
    // ordre fixe (icône, étiquette, unité, chiffre, annotation secondaire) —
    // qu'on les ait posés dans cet ordre ou non. C'est le groupe entier que
    // [slot] met ensuite à l'échelle et pousse vers le bord de sa colonne,
    // jamais chaque élément séparément : deux éléments posés « en haut à
    // gauche » doivent rester collés l'un à l'autre, pas dispersés chacun sur
    // son propre partage de la largeur de la rangée.
    Widget columnContent(GridColumn c) {
      final parts = <Widget>[];
      void add(Widget? w) {
        if (w == null) return;
        if (parts.isNotEmpty) parts.add(SizedBox(width: BlockMetrics.natural.gap / 2));
        parts.add(w);
      }

      add(iconAt(c));
      add(labelAt(c));
      add(unitAt(c));
      add(valueAt(c));
      add(secondaryAt(c));

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
    Widget slot(GridColumn c, int flex) {
      if (isEmpty(c)) return const SizedBox.shrink();
      final content = columnContent(c);

      // `Expanded` (ajustement *tight*), toujours : c'est ce qui donne à la
      // case, en grille, une largeur *fixée* plutôt qu'un plafond — sans ça
      // `FittedBox` (plus bas) mesurerait sa boîte sur la taille naturelle du
      // groupe et ne grandirait jamais, quelle que soit la hauteur de rangée
      // disponible (le chiffre resterait à sa taille naturelle, centré dans
      // du vide). Sur une page qui défile, `Align` seul décide de tout et
      // prend de toute façon toute la largeur qu'on lui offre — `Expanded`
      // au lieu de `Flexible` n'y change donc rien.
      return Expanded(
        flex: flex,
        child: rowHeight == null
            ? Align(alignment: _columnAlignment(c), child: content)
            // La boîte entière (icône **et** étiquette, pas chacune la
            // sienne) grandit d'un seul tenant sur la hauteur réelle de la
            // rangée : leurs tailles relatives — celle voulue par [scale] —
            // restent donc celles composées plus haut, quel que soit le
            // facteur qui les agrandit ensuite. Aligner sur le même coin que
            // [_columnAlignment] (`top…` et non `center…`) évite qu'un
            // groupe qui ne remplit pas toute la hauteur de sa boîte flotte
            // au milieu plutôt que de tenir le bord réel de la rangée — et
            // qu'un groupe voisin, plus gourmand, vienne y mordre : chacun
            // grandit dans **sa** part de la largeur, jamais dans celle du
            // suivant.
            : SizedBox(
                height: rowHeight,
                child: FittedBox(fit: BoxFit.contain, alignment: _elementAlignment(c), child: content),
              ),
      );
    }

    return Row(
      children: [
        slot(GridColumn.left, 1),
        slot(GridColumn.center, 2),
        slot(GridColumn.right, 1),
      ],
    );
  }

  /// Le bord vers lequel une colonne pousse son contenu — sur une page qui
  /// défile, où rien ne dispute la hauteur d'une rangée à une autre.
  static Alignment _columnAlignment(GridColumn c) => switch (c) {
        GridColumn.left => Alignment.centerLeft,
        GridColumn.center => Alignment.center,
        GridColumn.right => Alignment.centerRight,
      };

  /// Le coin vers lequel un groupe pousse son contenu en grille — même
  /// colonne que [_columnAlignment], mais calé en haut plutôt qu'au centre :
  /// voir la doc de [_gridRow.slot] pour pourquoi le vertical n'y suit pas la
  /// même règle.
  static Alignment _elementAlignment(GridColumn c) => switch (c) {
        GridColumn.left => Alignment.topLeft,
        GridColumn.center => Alignment.topCenter,
        GridColumn.right => Alignment.topRight,
      };

  Widget _iconWidget(Color ink, double scale, {double? matchSize}) {
    final custom = icon;
    final size = matchSize ?? BlockMetrics.natural.iconSize * scale;
    final tint = ink.withValues(alpha: 0.7);
    // FontAwesome n'est pas dessinable par [Icon] — [FaIcon] seul évite le
    // rognage/désalignement des glyphes non carrés (voir la doc de
    // `FaIconData`). L'icône par défaut d'une mesure, elle, reste une icône
    // Material ([MetricId.icon]).
    final glyph = custom != null ? FaIcon(custom, size: size, color: tint) : Icon(metric.icon, size: size, color: tint);
    // `FittedBox` en dernier recours seulement — une case généreuse laisse
    // l'icône à sa taille naturelle (rien à réduire), mais une colonne plus
    // étroite que [size] (une case d'une seule colonne dans une grille de
    // six et plus, l'icône y dépasse déjà la largeur disponible avant même
    // toute mise à l'échelle de rangée) la réduit plutôt que de déborder de
    // la rangée.
    return FittedBox(fit: BoxFit.scaleDown, child: glyph);
  }

  Widget _labelWidget(Color ink, double scale) => Text(
        (label?.trim().isNotEmpty == true ? label!.trim() : metric.name).toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: ink.withValues(alpha: 0.85),
          fontSize: (BlockMetrics.natural.titleSize + 2) * scale,
          fontWeight: FontWeight.w700,
        ),
      );

  Widget _unitWidget(Color ink, double scale) => Text(
        metric.unit.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: ink.withValues(alpha: 0.6),
          fontSize: BlockMetrics.natural.unitSize * scale,
        ),
      );

  /// Le repère par défaut d'un slot secondaire sans [SecondaryMetricSlot.label] —
  /// déduit du suffixe de la clé (`_avg`/`_max`/`_min`), jamais du nom complet
  /// de la mesure ([MetricId.name], « Vitesse moyenne »), bien trop long pour
  /// un coin de carte. `null` sur une mesure sans suffixe reconnu : mieux vaut
  /// un chiffre sans repère qu'un mot deviné.
  static String? _defaultSecondaryCaption(MetricId metric) {
    if (metric.key.endsWith('_avg')) return 'MOY';
    if (metric.key.endsWith('_max')) return 'MAX';
    if (metric.key.endsWith('_min')) return 'MIN';
    return null;
  }

  /// Une annotation de coin : un petit repère (« MOY », « MAX »…) collé au
  /// chiffre — jamais d'icône ni d'unité, qui la feraient répéter toute la
  /// mise en forme d'une carte dans un espace prévu pour rester minuscule.
  /// [scale] porte déjà le facteur de la rangée (voir [RowHeight]) composé
  /// avec celui propre au slot (voir [SecondaryMetricSize]) — l'appelant
  /// ([_gridRow.secondaryAt]) les multiplie avant d'arriver ici.
  Widget _secondaryWidget(SecondaryMetricSlot slot, MetricReading reading, Color ink, double scale) {
    final caption = slot.label ?? _defaultSecondaryCaption(slot.metric);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        if (caption != null) ...[
          Text(
            caption.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: ink.withValues(alpha: 0.6),
              fontSize: BlockMetrics.natural.unitSize * scale,
            ),
          ),
          SizedBox(width: BlockMetrics.natural.gap / 4),
        ],
        Text(
          reading.value ?? '—',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: ink,
            fontSize: BlockMetrics.natural.titleSize * scale,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

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
  //
  // La nature choisie, [gaugeFill]/[gaugeSegments]/[gaugeColorMode]/
  // [gaugeColor] (réglés dans l'éditeur, voir [MetricBlock]) décident
  // ensuite seulement de LA FORME de la barre obtenue, jamais de sa nature.
  // `null` partout retombe exactement sur le rendu d'avant ce réglage : des
  // tronçons dont chacun porte la couleur de sa propre zone pour la jauge de
  // zones, 5 tronçons d'une seule couleur fixe pour la plage libre, une
  // barre continue de cette même couleur fixe pour la dynamique. Poser l'une
  // de ces clés explicitement sur une jauge de zones — un nombre de tronçons qui ne
  // correspond plus au nombre de zones, une barre pleine, ou une couleur
  // fixe — casse la correspondance tronçon↔zone réelle : la barre retombe
  // alors sur une seule couleur (fixe, ou celle de la zone du moment), un
  // dégradé par tronçon n'ayant plus de seuils réels à représenter.

  static const _defaultSegments = 5;
  static const _defaultColor = Color(0xFF26A69A);

  Widget _gaugeRow(MetricReading reading) {
    final zones = metric.zonesOf(sources.riderProfile.profile);
    if (zones.isNotEmpty) return _zoneGaugeBar(reading, zones);
    if (min != null && max != null) return _rangeGaugeBar(reading);

    final range = metric.liveRangeOf(sources);
    final value = reading.numericValue;
    if (range != null && value != null) {
      final (rangeMin, rangeMax) = range;
      final fraction = ((value - rangeMin) / (rangeMax - rangeMin)).clamp(0.0, 1.0);
      return _dynamicGaugeBar(reading, fraction);
    }

    return const SizedBox.shrink();
  }

  /// La jauge de zones : un palier par zone du cycliste, chacun de la couleur
  /// de sa zone, allumés jusqu'à celle du moment — le rendu d'avant ce
  /// chantier, gardé tel quel tant que rien ne casse la correspondance
  /// tronçon↔zone ([gaugeFill]/[gaugeSegments] absents, [gaugeColorMode] pas
  /// [GaugeColorMode.fixed]).
  Widget _zoneGaugeBar(MetricReading reading, List<TrainingZone> zones) {
    final index = zones.indexWhere((zone) => zone.key == reading.zoneKey);
    final fill = gaugeFill ?? GaugeFill.segments;
    final colorMode = gaugeColorMode ?? GaugeColorMode.auto;

    if (fill == GaugeFill.segments && gaugeSegments == null && colorMode == GaugeColorMode.auto) {
      final fallback = zoneColorOf(reading.zoneKey) ?? Colors.white24;
      return _segments(
        count: zones.length,
        isLit: (i) => i <= index && index >= 0,
        litColorAt: (i) => zoneColorOf(zones[i].key) ?? fallback,
      );
    }

    final fraction = index < 0 ? null : (index + 1) / zones.length;
    return _resolvedFillBar(
      reading,
      fraction,
      fill: fill,
      colorMode: colorMode,
      naturalSegments: zones.length,
      hasZone: true,
    );
  }

  /// La jauge à plage libre : le pendant de [_zoneGaugeBar] pour une mesure
  /// sans zones d'entraînement, sur les bornes [min]/[max] réglées dans
  /// l'éditeur. Un chiffre absent ([MetricReading.numericValue] `null`)
  /// éteint tous les paliers (ou vide la barre continue) plutôt que d'en
  /// deviner un : la mesure garde son tiret, la jauge doit dire la même
  /// chose que lui. Tronçons d'une seule couleur fixe par défaut, comme
  /// avant ce chantier.
  Widget _rangeGaugeBar(MetricReading reading) {
    final value = reading.numericValue;
    final fraction = value == null ? null : ((value - min!) / (max! - min!)).clamp(0.0, 1.0);
    return _resolvedFillBar(
      reading,
      fraction,
      fill: gaugeFill ?? GaugeFill.segments,
      colorMode: gaugeColorMode ?? GaugeColorMode.fixed,
      naturalSegments: _defaultSegments,
    );
  }

  /// Le remplissage d'une jauge dynamique — barre continue d'une seule
  /// couleur fixe par défaut, comme avant ce chantier ; [gaugeFill] peut la
  /// repasser en tronçons.
  Widget _dynamicGaugeBar(MetricReading reading, double fraction) => _resolvedFillBar(
        reading,
        fraction,
        fill: gaugeFill ?? GaugeFill.full,
        colorMode: gaugeColorMode ?? GaugeColorMode.fixed,
        naturalSegments: _defaultSegments,
      );

  /// Le point commun aux trois natures de jauge une fois qu'elles ne
  /// dessinent plus leur rendu spécifique (le ladder de zones de
  /// [_zoneGaugeBar]) : des tronçons ([_segments]) ou une barre continue
  /// ([_fullBar]) — fixe ([gaugeColor], repli [_defaultColor]) partout,
  /// automatique différemment selon [hasZone] : la couleur de la zone du
  /// moment (`zoneColorOf(reading.zoneKey)`, même repli fixe si la mesure
  /// n'en a pas de courante) pour une jauge de zones, un dégradé bleu →
  /// violet sur [fraction] sinon — une mesure sans zone (vitesse…) n'a pas de
  /// teinte propre à s'y raccrocher. En tronçons, le dégradé porte sur
  /// chaque palier selon sa position plutôt que sur une seule couleur
  /// commune : un ladder, comme la jauge de zones en est déjà un.
  Widget _resolvedFillBar(
    MetricReading reading,
    double? fraction, {
    required GaugeFill fill,
    required GaugeColorMode colorMode,
    required int naturalSegments,
    bool hasZone = false,
  }) {
    final fallback = gaugeColor ?? _defaultColor;
    final auto = colorMode == GaugeColorMode.auto;
    final gradient = auto && !hasZone;
    final color = !auto
        ? fallback
        : hasZone
            ? zoneColorOf(reading.zoneKey) ?? fallback
            : _gaugeGradientColor(fraction ?? 0);

    if (fill == GaugeFill.full) return _fullBar(fraction ?? 0, color);

    final count = gaugeSegments ?? naturalSegments;
    final lit = fraction == null ? -1 : (fraction * count).round();
    return _segments(
      count: count,
      isLit: (i) => i < lit,
      litColorAt: (i) => gradient ? _gaugeGradientColor((i + 1) / count) : color,
    );
  }

  /// Les deux bornes du dégradé — mêmes couleurs que
  /// `GAUGE_AUTO_GRADIENT_FROM`/`GAUGE_AUTO_GRADIENT_TO` (`companionSettings.ts`).
  static const _gaugeGradientFrom = Color(0xFF2196F3);
  static const _gaugeGradientTo = Color(0xFF673AB7);

  /// Interpolation linéaire entre les deux bornes du dégradé — [fraction]
  /// bornée à 0–1 : au-delà, on sortirait du dégradé plutôt que de rester à
  /// sa couleur terminale.
  Color _gaugeGradientColor(double fraction) =>
      Color.lerp(_gaugeGradientFrom, _gaugeGradientTo, fraction.clamp(0, 1))!;

  /// Les paliers communs aux trois natures de jauge — seuls leur nombre, leur
  /// éclairage et leur couleur changent d'un appelant à l'autre. La hauteur
  /// naturelle (8) est multipliée par [GaugeThickness.factor] — voir
  /// [MetricBlock.gaugeThickness].
  Widget _segments({
    required int count,
    required bool Function(int i) isLit,
    required Color Function(int i) litColorAt,
  }) {
    final height = 8 * gaugeThickness.factor;
    return Row(
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(width: 2),
          Expanded(
            child: Container(
              height: height,
              decoration: BoxDecoration(
                color: isLit(i) ? litColorAt(i) : Colors.white12,
                borderRadius: BorderRadius.circular(height / 4),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Le remplissage continu d'une jauge en mode [GaugeFill.full] : une piste
  /// jusqu'à la position réelle, pas des paliers — la plage (échelle de
  /// zones, min/max de la sortie, ou progression vers l'itinéraire) est une
  /// vraie progression, pas des seuils entre lesquels un dégradé mentirait
  /// comme pour les zones, d'où une seule couleur ([color]). Plus épaisse
  /// que [_segments] à épaisseur égale aussi ([BlockMetrics.natural.barHeight],
  /// la même hauteur naturelle que la barre de zones) — c'est elle qui porte
  /// l'information ici, pas des paliers à côté d'un chiffre déjà lisible
  /// seul. Hauteur naturelle multipliée par [GaugeThickness.factor], comme
  /// [_segments].
  Widget _fullBar(double fraction, Color color) {
    final barHeight = BlockMetrics.natural.barHeight * gaugeThickness.factor;

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
                        child: ColoredBox(color: color),
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
  ///
  /// [naturalHeight] pose une hauteur de référence fixe pour la mesure de
  /// taille naturelle — utile en page qui défile, où rien d'autre ne fixe une
  /// échelle commune aux chiffres de longueurs très inégales. `null` en
  /// grille : `grow()` (dans [_gridRow]) pose déjà sa propre boîte sur la
  /// hauteur *réelle* de la rangée, donc cette référence fixe n'y servirait
  /// qu'à imposer une deuxième échelle inutile, redondante avec celle de
  /// `grow()` — la seule que suivent déjà l'icône, l'étiquette et l'unité.
  Widget _value(
    MetricReading reading,
    Color ink, {
    required double size,
    double? naturalHeight = _valueHeight,
  }) {
    final text = Text(
      reading.value ?? '—',
      maxLines: 1,
      style: TextStyle(
        color: ink,
        fontSize: size,
        fontWeight: FontWeight.w500,
      ),
    );
    if (naturalHeight == null) return text;
    return SizedBox(height: naturalHeight, child: FittedBox(fit: BoxFit.scaleDown, child: text));
  }
}
