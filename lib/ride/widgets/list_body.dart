import 'package:flutter/material.dart';

import '../../dashboard/dashboard_block.dart';
import '../../dashboard/list_layout.dart';
import '../../dashboard/ride_preset.dart';

/// Le corps d'une page qui défile ([ListPageSpec], ou [LapBlocksLayout] une
/// fois le tour choisi) : une colonne le cas courant, plusieurs côte à côte
/// quand le profil le demande ([listSegmentsOf]), un bloc `full_width` sur
/// toute la largeur entre deux groupes de colonnes.
///
/// Toute la page défile d'un bloc, colonnes comprises : les faire défiler
/// chacune pour son compte ferait perdre le repère commun (« où en est
/// l'autre colonne ? ») à chaque glissé, et une liste n'a de toute façon pas
/// à tenir dans l'écran comme une grille.
///
/// Partagé entre [DashboardPage] et [LapListPage] : les deux composaient la
/// même disposition, dupliquée, avant ce réglage — seul ce que chaque bloc
/// dessine diffère ([blockBuilder]), même principe que [DashboardGrid].
class DashboardListBody extends StatelessWidget {
  const DashboardListBody({
    super.key,
    required this.blocks,
    required this.cols,
    required this.blockBuilder,
    this.controller,
  });

  final List<ListBlockPlacement> blocks;
  final int cols;
  final Widget Function(DashboardBlock block) blockBuilder;

  /// Propre à la page de tours (barre de défilement désactivée par-dessus,
  /// voir `LapListPage`) — absent pour une page de mesures.
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final segments = listSegmentsOf(blocks, cols);

    return SingleChildScrollView(
      controller: controller,
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final segment in segments) _segment(segment)],
      ),
    );
  }

  Widget _padded(Widget child) =>
      Padding(padding: const EdgeInsets.only(bottom: 12), child: child);

  Widget _segment(ListSegment segment) => switch (segment) {
        final FullWidthSegment full => _padded(blockBuilder(full.block)),
        final ColumnsSegment group when group.columns.length <= 1 => Column(
            children: [for (final block in group.columns.first) _padded(blockBuilder(block))],
          ),
        final ColumnsSegment group => Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var col = 0; col < group.columns.length; col++) ...[
                if (col > 0) const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    children: [for (final block in group.columns[col]) _padded(blockBuilder(block))],
                  ),
                ),
              ],
            ],
          ),
      };
}
