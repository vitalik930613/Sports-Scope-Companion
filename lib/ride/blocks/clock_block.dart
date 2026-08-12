import 'dart:async';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../dashboard/block_density.dart';
import '../../dashboard/dashboard_block.dart';
import '../../ui/formats.dart';
import '../../ui/zone_colors.dart';
import 'block_card.dart';

/// L'heure courante, disposée comme un bloc `metric` ([ClockBlock.layout]) —
/// mais réduite à ce qu'une horloge peut porter : icône, étiquette, chiffre.
/// **Jamais d'unité ni de jauge**, donc pas de moteur de rendu partagé avec
/// [MetricView] (`metric_view.dart`) : celui-ci est câblé de bout en bout sur
/// `MetricId`/`MetricSources` (étiquette = `metric.name`, jauge = zones/plage
/// du cycliste…), le généraliser aurait risqué un widget déjà éprouvé sur la
/// route pour un composant qui n'a besoin que d'un tiers de son moteur. Ce qui
/// suit reproduit donc son placement en grille 3 colonnes, en plus petit.
///
/// Seule case du tableau de bord avec son propre [Timer.periodic] : elle ne
/// dépend d'aucun `Listenable` (ni capteur, ni enregistreur — voir
/// [ClockBlock]), donc rien d'autre ne la ferait se reconstruire. Tique chaque
/// seconde même en mode [ClockMode.hm] : une seconde implémentation à deux
/// cadences pour économiser un `setState` par minute ne vaut pas la
/// complexité, sur une case qui n'affiche qu'un chiffre.
class ClockCard extends StatefulWidget {
  const ClockCard({
    super.key,
    this.mode = ClockMode.hm,
    this.layout = const MetricLayout(value: GridPosition(0, GridColumn.center)),
    this.icon,
    this.color,
    this.textColor,
  });

  final ClockMode mode;

  /// Où se posent l'icône, l'étiquette et le chiffre — voir [ClockBlock.layout].
  final MetricLayout layout;

  /// L'icône personnalisée réglée dans l'éditeur — voir [ClockBlock.icon].
  /// `null` : [_defaultIcon] fait foi.
  final FaIconData? icon;

  /// Fond/texte réglés dans l'éditeur — voir [DashboardBlock.color]/
  /// [DashboardBlock.textColor].
  final Color? color;
  final Color? textColor;

  @override
  State<ClockCard> createState() => _ClockCardState();
}

class _ClockCardState extends State<ClockCard> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Aucun `MetricId` pour porter un nom : une horloge n'a qu'un seul contenu
  /// possible, pas un catalogue à choisir dedans.
  static const _labelText = 'HORLOGE';

  /// Repli faute d'icône réglée — Material et non FontAwesome, même
  /// convention que [MetricId.icon] : l'icône *par défaut* d'un composant
  /// reste Material, FontAwesome est réservé au réglage de l'éditeur.
  static const _defaultIcon = Icons.access_time;

  static const _valueHeight = 72.0;
  static const _valueSize = 64.0;
  static const _rowGap = 0.0;
  static const _rowGapScrolling = 8.0;
  static const _naturalWidth = 220.0;

  /// Les rangées utilisées, dans l'ordre — une rangée sans aucun élément n'y
  /// figure pas. Jamais de rangée de jauge : structurellement absente d'ici,
  /// contrairement à [MetricView], donc jamais dessinée même si un document
  /// en portait une (voir [ClockBlock.parse], qui la retire déjà).
  List<int> get _usedRows {
    final rows = <int>{
      if (widget.layout.icon != null) widget.layout.icon!.row,
      if (widget.layout.label != null) widget.layout.label!.row,
      widget.layout.value.row,
    };
    return rows.toList()..sort();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final text = widget.mode == ClockMode.hms ? formatClockHms(now) : formatClockHm(now);
    final ink = widget.textColor ??
        (widget.color == null ? Colors.white : foregroundOf(widget.color!));
    final rows = _usedRows;

    return LayoutBuilder(
      builder: (context, outerConstraints) {
        final width = _measuredWidth(outerConstraints);
        final height = _measuredHeight(outerConstraints);

        final children = [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) SizedBox(height: height == null ? _rowGapScrolling : _rowGap),
            if (height != null)
              Expanded(
                flex: widget.layout.heightOf(rows[i]).weight,
                child: LayoutBuilder(
                  builder: (context, rowConstraints) => _gridRow(
                    rows[i],
                    text,
                    ink,
                    rowHeight: rowConstraints.maxHeight,
                  ),
                ),
              )
            else
              _gridRow(rows[i], text, ink),
          ],
        ];

        return BlockSurface(
          background: widget.color,
          child: SizedBox(
            width: width,
            height: height,
            child: Column(
              mainAxisSize: height == null ? MainAxisSize.min : MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        );
      },
    );
  }

  /// Une rangée normale : ses éléments répartis dans une barre à 3 tiers
  /// égaux (gauche/centre/droite) — même moteur que [MetricView._gridRow],
  /// réduit à icône/étiquette/chiffre.
  Widget _gridRow(int row, String text, Color ink, {double? rowHeight}) {
    final layout = widget.layout;
    final scale = layout.heightOf(row).scale;

    Widget? iconAt(GridColumn c) =>
        (layout.icon?.row == row && layout.icon?.column == c) ? _iconWidget(ink, scale) : null;
    Widget? labelAt(GridColumn c) =>
        (layout.label?.row == row && layout.label?.column == c) ? _labelWidget(ink, scale) : null;
    Widget? valueAt(GridColumn c) => (layout.value.row == row && layout.value.column == c)
        ? _valueWidget(text, ink, scale, rowHeight)
        : null;

    bool isEmpty(GridColumn c) => iconAt(c) == null && labelAt(c) == null && valueAt(c) == null;

    Widget columnContent(GridColumn c) {
      final parts = <Widget>[];
      void add(Widget? w) {
        if (w == null) return;
        if (parts.isNotEmpty) parts.add(SizedBox(width: BlockMetrics.natural.gap / 2));
        parts.add(w);
      }

      add(iconAt(c));
      add(labelAt(c));
      add(valueAt(c));

      return Row(mainAxisSize: MainAxisSize.min, children: parts);
    }

    Widget slot(GridColumn c, int flex) {
      if (isEmpty(c)) return const SizedBox.shrink();
      final content = columnContent(c);

      return Expanded(
        flex: flex,
        child: rowHeight == null
            ? Align(alignment: _columnAlignment(c), child: content)
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

  static Alignment _columnAlignment(GridColumn c) => switch (c) {
        GridColumn.left => Alignment.centerLeft,
        GridColumn.center => Alignment.center,
        GridColumn.right => Alignment.centerRight,
      };

  static Alignment _elementAlignment(GridColumn c) => switch (c) {
        GridColumn.left => Alignment.topLeft,
        GridColumn.center => Alignment.topCenter,
        GridColumn.right => Alignment.topRight,
      };

  Widget _iconWidget(Color ink, double scale) {
    final custom = widget.icon;
    final size = BlockMetrics.natural.iconSize * scale;
    final tint = ink.withValues(alpha: 0.7);
    final glyph = custom != null
        ? FaIcon(custom, size: size, color: tint)
        : Icon(_defaultIcon, size: size, color: tint);
    return FittedBox(fit: BoxFit.scaleDown, child: glyph);
  }

  Widget _labelWidget(Color ink, double scale) => Text(
        _labelText,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: ink.withValues(alpha: 0.85),
          fontSize: (BlockMetrics.natural.titleSize + 2) * scale,
          fontWeight: FontWeight.w700,
        ),
      );

  /// L'heure, à sa taille naturelle — jamais de tiret, contrairement à une
  /// mesure : une horloge a toujours une valeur.
  Widget _valueWidget(String text, Color ink, double scale, double? rowHeight) {
    final label = Text(
      text,
      maxLines: 1,
      style: TextStyle(color: ink, fontSize: _valueSize * scale, fontWeight: FontWeight.w500),
    );
    if (rowHeight != null) return label;
    return SizedBox(height: _valueHeight, child: FittedBox(fit: BoxFit.scaleDown, child: label));
  }

  double _measuredWidth(BoxConstraints constraints) => constraints.hasBoundedWidth
      ? constraints.maxWidth - BlockMetrics.natural.padding * 2
      : _naturalWidth;

  double? _measuredHeight(BoxConstraints constraints) =>
      constraints.hasBoundedHeight ? constraints.maxHeight - BlockMetrics.natural.padding * 2 : null;
}
