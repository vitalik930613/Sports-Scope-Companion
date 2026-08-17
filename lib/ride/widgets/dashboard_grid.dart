import 'package:flutter/material.dart';

import '../../dashboard/dashboard_block.dart';
import '../../dashboard/grid_layout.dart';
import '../../dashboard/ride_preset.dart';

/// La grille `rows` × `cols` d'une page qui ne défile pas, chaque cellule à
/// son rectangle ([gridRectsFor]).
///
/// Partagée entre les pages de mesures ([GridPageSpec]) et les pages de
/// tours en grille ([LapGridLayout]) : la géométrie est la même, seul ce que
/// chaque cellule dessine diffère ([cellBuilder]) — un bloc ordinaire pour
/// l'une, le même bloc mais lu sur le tour choisi pour l'autre.
///
/// `LayoutBuilder` + `Positioned` plutôt qu'un `Table` — qui ne sait pas
/// fusionner sans imbriquer — et surtout **pas un `GridView`**, qui défile
/// alors que cette page ne doit justement pas défiler : elle se lit en
/// roulant, tout doit tenir à l'écran.
class DashboardGrid extends StatelessWidget {
  const DashboardGrid({
    super.key,
    required this.rows,
    required this.cols,
    required this.cells,
    required this.cellBuilder,
    this.dividers = const [],
    this.onMeasured,
  });

  final int rows;
  final int cols;
  final List<GridCell> cells;
  final Widget Function(DashboardBlock block) cellBuilder;

  /// Décoratifs, dessinés dans les gouttières — n'occupent jamais l'espace
  /// d'une cellule, aucune incidence sur [gridRectsFor].
  final List<GridDivider> dividers;

  /// La place que la grille vient d'avoir, une fois posée — voir
  /// `DashboardPage.onGridMeasured`, dont c'est le même contrat : le site
  /// s'en sert pour dimensionner les aperçus de son éditeur, qu'il s'agisse
  /// d'une page de mesures ou d'une page de tours.
  final ValueChanged<Size>? onMeasured;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          _report(size);

          final rects = gridRectsFor(
            [for (final cell in cells) cell.span],
            rows: rows,
            cols: cols,
            size: size,
          );

          return Stack(
            children: [
              // Peints avant les cellules : les deux ne se recouvrent jamais
              // (les séparateurs vivent dans les gouttières, les cellules
              // dedans), l'ordre n'a donc d'effet que sur des arrondis de
              // calcul à la frontière, où le trait doit rester visible.
              for (final divider in dividers)
                Positioned.fromRect(
                  rect: dividerRectFor(divider, rows: rows, cols: cols, size: size),
                  child: ColoredBox(color: divider.color),
                ),
              for (var i = 0; i < cells.length; i++)
                Positioned.fromRect(
                  rect: rects[i],
                  // Chaque cellule est coupée à son rectangle. Les composants se
                  // dégradent pour tenir (`BlockMetrics`), mais un `Stack` ne
                  // borne pas ses enfants : sans ceci, ce qui dépasserait malgré
                  // tout — une phrase plus longue qu'attendu, une police système
                  // plus grande — se peindrait sur la case voisine, en roulant,
                  // sans que rien ne le dise.
                  child: ClipRect(child: cellBuilder(cells[i].block)),
                ),
            ],
          );
        },
      ),
    );
  }

  /// Annonce la taille mesurée, **après la trame et pas pendant**.
  ///
  /// L'appelant écrit un fichier et pourrait vouloir se reconstruire ; le faire
  /// depuis un `LayoutBuilder` reviendrait à modifier l'arbre au milieu de sa
  /// propre mise en page. Le magasin, lui, ignore une taille qu'il connaît
  /// déjà : l'appel a beau revenir à chaque pose, il n'écrit qu'une fois.
  void _report(Size size) {
    final report = onMeasured;
    if (report == null || size.isEmpty) return;

    WidgetsBinding.instance.addPostFrameCallback((_) => report(size));
  }
}
