import 'package:flutter/foundation.dart';

import 'dashboard_block.dart';
import 'ride_preset.dart';

/// Un tronçon d'une page qui défile ([ListPageSpec], ou [LapBlocksLayout] une
/// fois le tour choisi), dans l'ordre du document : soit un groupe de
/// colonnes classique, soit un bloc `full_width` seul sur toute la largeur.
///
/// Même traversée que `CompanionSettings.place_list_blocks` côté Rails — le
/// document ne stocke jamais un index de colonne, seulement les ruptures
/// [ListBlockPlacement.newColumn]/[ListBlockPlacement.fullWidth] — les deux
/// doivent s'accorder sur où elles tombent.
@immutable
sealed class ListSegment {
  const ListSegment();
}

/// Un groupe de colonnes côte à côte, chacune sa pile de blocs dans l'ordre
/// du document.
class ColumnsSegment extends ListSegment {
  const ColumnsSegment(this.columns);

  final List<List<DashboardBlock>> columns;
}

/// Un bloc `full_width`, seul sur sa propre ligne.
class FullWidthSegment extends ListSegment {
  const FullWidthSegment(this.block);

  final DashboardBlock block;
}

/// Regroupe les blocs d'une page qui défile en tronçons affichables.
///
/// Un bloc reste par défaut dans la colonne de celui qui le précède
/// (première colonne au départ, et après chaque tronçon `full_width`) ;
/// [ListBlockPlacement.newColumn] avance d'une colonne, avec retour à la
/// première après la dernière (sans effet si [cols] vaut 1, il n'y a rien
/// d'autre où aller) ; [ListBlockPlacement.fullWidth] clôt le groupe de
/// colonnes en cours — s'il n'est pas vide — pour poser son propre tronçon,
/// puis la suite repart en première colonne.
List<ListSegment> listSegmentsOf(List<ListBlockPlacement> blocks, int cols) {
  final segments = <ListSegment>[];
  var columns = List.generate(cols, (_) => <DashboardBlock>[]);
  var col = 0;
  var hasContent = false;

  void flushColumns() {
    if (hasContent) segments.add(ColumnsSegment(columns));
    columns = List.generate(cols, (_) => <DashboardBlock>[]);
    col = 0;
    hasContent = false;
  }

  for (final placement in blocks) {
    if (placement.fullWidth) {
      flushColumns();
      segments.add(FullWidthSegment(placement.block));
      continue;
    }
    if (placement.newColumn && cols > 1) col = (col + 1) % cols;
    columns[col].add(placement.block);
    hasContent = true;
  }
  flushColumns();

  return segments;
}
