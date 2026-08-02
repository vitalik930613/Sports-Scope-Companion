import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:sports_scope_companion/dashboard/grid_layout.dart';

/// La géométrie des grilles de page : fusions, débordements, recouvrements.
///
/// Pure, donc vérifiable sur des nombres plutôt qu'en comparant des captures
/// d'écran de téléphone — c'est tout l'intérêt de l'avoir sortie des widgets.
void main() {
  group('gridRectFor', () {
    const size = Size(300, 200);

    test('les colonnes se partagent la largeur à parts égales', () {
      // 3 colonnes, 2 gouttières de 10 : (300 - 20) / 3.
      final rect = gridRectFor(
        const GridSpan(row: 0, col: 1),
        rows: 1,
        cols: 3,
        size: size,
        gap: 10,
      );

      expect(rect.width, closeTo(280 / 3, 0.001));
      expect(rect.left, closeTo(280 / 3 + 10, 0.001));
    });

    test('une fusion récupère la gouttière qu\'elle enjambe', () {
      // Sans quoi deux cellules côte à côte et une cellule de deux colonnes ne
      // couvriraient pas la même largeur, et les bords cesseraient de s'aligner
      // d'une ligne à l'autre.
      final single = gridRectFor(
        const GridSpan(row: 0, col: 0),
        rows: 1,
        cols: 3,
        size: size,
        gap: 10,
      );
      final merged = gridRectFor(
        const GridSpan(row: 0, col: 0, colSpan: 2),
        rows: 1,
        cols: 3,
        size: size,
        gap: 10,
      );

      expect(merged.width, closeTo(single.width * 2 + 10, 0.001));
    });

    test('une ligne fusionnée sur toute la largeur occupe tout', () {
      final rect = gridRectFor(
        const GridSpan(row: 1, col: 0, colSpan: 3),
        rows: 3,
        cols: 3,
        size: size,
        gap: 8,
      );

      expect(rect.left, 0);
      expect(rect.width, closeTo(size.width, 0.001));
    });

    test('la dernière cellule finit exactement au bord', () {
      final rect = gridRectFor(
        const GridSpan(row: 2, col: 2),
        rows: 3,
        cols: 3,
        size: size,
        gap: 8,
      );

      expect(rect.right, closeTo(size.width, 0.001));
      expect(rect.bottom, closeTo(size.height, 0.001));
    });
  });

  group('GridSpan.clampedTo', () {
    test('une étendue qui déborde est rognée, pas rejetée', () {
      // Réduire une grille de 3 à 2 colonnes dans l'éditeur ne doit pas faire
      // disparaître les composants qu'on y avait posés.
      final span = const GridSpan(row: 0, col: 1, colSpan: 3)
          .clampedTo(rows: 2, cols: 2);

      expect(span, isNotNull);
      expect(span!.colSpan, 1);
    });

    test('une origine hors grille est rejetée', () {
      // Contrairement à l'étendue, elle n'a aucune interprétation raisonnable :
      // on ne devine pas où le cycliste voulait mettre la cellule.
      expect(
        const GridSpan(row: 0, col: 5).clampedTo(rows: 2, cols: 2),
        isNull,
      );
      expect(
        const GridSpan(row: -1, col: 0).clampedTo(rows: 2, cols: 2),
        isNull,
      );
    });
  });

  group('placedCells', () {
    List<GridSpan> place(List<GridSpan> spans, {int rows = 3, int cols = 3}) =>
        placedCells<GridSpan>(
          spans,
          spanOf: (span) => span,
          withSpan: (_, span) => span,
          rows: rows,
          cols: cols,
        );

    test('la première posée gagne sur un recouvrement', () {
      // L'ordre du document tranche, donc l'ordre que l'éditeur affiche. Si la
      // dernière gagnait, poser un composant en ferait disparaître un autre sans
      // aucune explication visible à l'écran.
      final kept = place(const [
        GridSpan(row: 0, col: 0, colSpan: 2),
        GridSpan(row: 0, col: 1),
      ]);

      expect(kept, hasLength(1));
      expect(kept.single.colSpan, 2);
    });

    test('deux cellules qui se touchent sans se croiser tiennent toutes deux',
        () {
      final kept = place(const [
        GridSpan(row: 0, col: 0, colSpan: 2),
        GridSpan(row: 0, col: 2),
        GridSpan(row: 1, col: 0, colSpan: 3),
      ]);

      expect(kept, hasLength(3));
    });

    test('un recouvrement en diagonale compte comme un recouvrement', () {
      // Deux rectangles se croisent dès qu'ils se chevauchent sur les deux axes
      // à la fois : une comparaison ligne à ligne laisserait passer celui-ci.
      final kept = place(const [
        GridSpan(row: 0, col: 0, rowSpan: 2, colSpan: 2),
        GridSpan(row: 1, col: 1, rowSpan: 2, colSpan: 2),
      ]);

      expect(kept, hasLength(1));
    });

    test('une cellule hors grille est retirée, les autres restent', () {
      final kept = place(
        const [GridSpan(row: 0, col: 0), GridSpan(row: 9, col: 9)],
        rows: 2,
        cols: 2,
      );

      expect(kept, hasLength(1));
      expect(kept.single.row, 0);
    });
  });
}
