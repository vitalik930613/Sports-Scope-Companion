import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_scope_companion/dashboard/block_density.dart';

/// Ce qu'une case laisse dessiner. Pure, donc vérifiable sur des nombres plutôt
/// qu'en comparant des captures d'écran de téléphone — même raison que
/// `grid_layout_test.dart`.
///
/// Les tailles de référence sont celles d'un téléphone ordinaire (360 × 800),
/// une fois retirés la barre système, le bandeau du bas, l'en-tête et les
/// marges : il reste **328 × 598** pour la grille. C'est de là que sortent les
/// cases citées ici, et c'est ce que l'éditeur du site suppose de son côté.
void main() {
  /// La case d'une grille de [rows] × [cols] sur ce téléphone-là.
  ({double width, double height}) cell(int rows, int cols) {
    const gap = 8.0;
    return (
      width: (328 - gap * (cols - 1)) / cols,
      height: (598 - gap * (rows - 1)) / rows,
    );
  }

  BlockDensity densityOf(int rows, int cols) {
    final size = cell(rows, cols);
    return BlockMetrics.densityFor(width: size.width, height: size.height);
  }

  group('densityFor', () {
    test('une grille de 2 × 2 laisse tout dessiner', () {
      expect(densityOf(2, 2), BlockDensity.comfortable);
    });

    test('une grille de 3 × 3 est le cas courant', () {
      expect(densityOf(3, 3), BlockDensity.normal);
    });

    test('quatre lignes serrent, six ne laissent que le chiffre', () {
      expect(densityOf(4, 3), BlockDensity.tight);
      expect(densityOf(6, 6), BlockDensity.minimal);
    });

    test('la largeur a son mot à dire, même dans une case haute', () {
      // Quatre colonnes sur deux lignes : 79 de large pour 295 de haut. C'est
      // large comme un pouce — un titre y tiendrait sur trois lignes.
      expect(densityOf(2, 4), BlockDensity.minimal);
    });

    test('une hauteur infinie est confortable, pas minuscule', () {
      // Le cas d'une page qui défile : le composant prend la hauteur qu'il lui
      // faut, rien ne peut déborder. Sans cette réponse, une page en liste se
      // dessinerait comme la plus petite des cases.
      expect(
        BlockMetrics.densityFor(width: 328, height: double.infinity),
        BlockDensity.comfortable,
      );
    });

    test('elle vient des contraintes que le rendu donne à la case', () {
      final metrics = BlockMetrics.of(
        const BoxConstraints.tightFor(width: 48, height: 93),
      );
      expect(metrics.density, BlockDensity.minimal);
      expect(metrics.showTitle, isFalse);
      expect(metrics.showUnit, isFalse);
      expect(metrics.showIcon, isFalse);
    });
  });

  group('linesIn', () {
    test('ne rend jamais plus de lignes qu\'on en a', () {
      final metrics = BlockMetrics.forDensity(BlockDensity.comfortable);
      expect(metrics.linesIn(600, wanted: 3), 3);
    });

    test('en retire quand la case raccourcit', () {
      final metrics = BlockMetrics.forDensity(BlockDensity.tight);
      final size = cell(4, 3);

      final fitting = metrics.linesIn(size.height, wanted: 8);
      expect(fitting, lessThan(8));
      expect(fitting, greaterThan(0));

      // Ce qu'on garde tient vraiment : rembourrage et titre compris.
      expect(
        metrics.padding * 2 +
            metrics.titleHeight +
            metrics.gap +
            fitting * metrics.lineHeight,
        lessThanOrEqualTo(size.height),
      );
    });

    test('zéro est une réponse : il reste le titre', () {
      final metrics = BlockMetrics.forDensity(BlockDensity.minimal);
      expect(metrics.linesIn(20, wanted: 4), 0);
    });

    test('une hauteur infinie garde tout', () {
      final metrics = BlockMetrics.forDensity(BlockDensity.comfortable);
      expect(metrics.linesIn(double.infinity, wanted: 8), 8);
    });
  });

  group('legendFits', () {
    test('cinq zones et leur barre demandent une pleine hauteur', () {
      final metrics = BlockMetrics.forDensity(BlockDensity.comfortable);

      // Une page qui défile : oui. Une case de grille de 3 × 3 : non — c'est
      // exactement la légende qui débordait sur la voisine.
      expect(
        metrics.legendFits(
          double.infinity,
          width: 328,
          zones: 5,
          withBar: true,
        ),
        isTrue,
      );
      expect(
        BlockMetrics.forDensity(BlockDensity.normal).legendFits(
          cell(3, 3).height,
          width: cell(3, 3).width,
          zones: 5,
          withBar: true,
        ),
        isFalse,
      );
    });

    test('sept zones de puissance tiennent moins bien que cinq de cardio', () {
      final metrics = BlockMetrics.forDensity(BlockDensity.comfortable);
      final height = cell(2, 1).height;

      // La même case, la même barre, le même titre : c'est le nombre de zones
      // qui tranche. Elles viennent du site et ne sont pas les mêmes des deux
      // côtés — cinq en cardio, sept en puissance.
      expect(
        metrics.legendFits(height, width: 328, zones: 5, withBar: true),
        isTrue,
      );
      expect(
        metrics.legendFits(height, width: 328, zones: 7, withBar: true),
        isFalse,
      );
    });

    test('sans barre, la légende a la place de deux lignes de plus', () {
      final metrics = BlockMetrics.forDensity(BlockDensity.comfortable);
      final height =
          metrics.padding * 2 +
          metrics.titleHeight +
          metrics.gap +
          5 * metrics.legendRowHeight;

      expect(
        metrics.legendFits(height, width: 328, zones: 5, withBar: false),
        isTrue,
      );
      expect(
        metrics.legendFits(height, width: 328, zones: 5, withBar: true),
        isFalse,
      );
    });

    test('une case haute mais étroite ne la porte pas non plus', () {
      // Deux colonnes sur une pleine hauteur : 160 de large, 598 de haut. La
      // place ne manque pas en hauteur — mais une ligne de légende porte une
      // pastille, une clé, une durée et un pourcentage, et c'est en largeur
      // qu'elle sortait de sa case.
      final metrics = BlockMetrics.forDensity(BlockDensity.comfortable);
      final size = cell(1, 2);

      expect(
        metrics.legendFits(
          size.height,
          width: size.width,
          zones: 5,
          withBar: true,
        ),
        isFalse,
      );
    });
  });
}
