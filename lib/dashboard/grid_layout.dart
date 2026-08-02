import 'dart:ui';

import 'package:flutter/foundation.dart';

/// Où un composant se pose dans la grille d'une page, fusions comprises.
///
/// Les coordonnées sont **à partir de zéro** et les étendues valent au moins 1 :
/// une cellule occupe toujours quelque chose, sans quoi elle ne serait pas dans
/// la liste.
@immutable
class GridSpan {
  const GridSpan({
    required this.row,
    required this.col,
    this.rowSpan = 1,
    this.colSpan = 1,
  });

  final int row;
  final int col;
  final int rowSpan;
  final int colSpan;

  int get lastRow => row + rowSpan - 1;
  int get lastCol => col + colSpan - 1;

  /// Deux cellules se recouvrent-elles ? Deux rectangles se croisent dès qu'ils
  /// se chevauchent sur les deux axes à la fois.
  bool overlaps(GridSpan other) =>
      row <= other.lastRow &&
      other.row <= lastRow &&
      col <= other.lastCol &&
      other.col <= lastCol;

  /// La même cellule ramenée dans une grille de [rows] × [cols], ou `null` si
  /// elle n'y a pas sa place du tout.
  ///
  /// Une étendue qui déborde est **rognée**, pas rejetée : un éditeur qui
  /// réduit une grille de 3 à 2 colonnes ne doit pas faire disparaître les
  /// composants qu'on y avait posés. Une origine hors grille, elle, n'a aucune
  /// interprétation raisonnable — on ne devine pas où le cycliste voulait la
  /// mettre.
  GridSpan? clampedTo({required int rows, required int cols}) {
    if (rows < 1 || cols < 1) return null;
    if (row < 0 || col < 0 || row >= rows || col >= cols) return null;

    return GridSpan(
      row: row,
      col: col,
      rowSpan: rowSpan.clamp(1, rows - row),
      colSpan: colSpan.clamp(1, cols - col),
    );
  }

  /// Décode une entrée du document. Tolérante : un champ absent vaut son défaut
  /// (une cellule simple en haut à gauche), jamais une exception.
  static GridSpan parse(Object? raw) {
    if (raw is! Map) return const GridSpan(row: 0, col: 0);
    return GridSpan(
      row: _int(raw['row'], 0),
      col: _int(raw['col'], 0),
      rowSpan: _int(raw['row_span'], 1),
      colSpan: _int(raw['col_span'], 1),
    );
  }

  static int _int(Object? raw, int fallback) =>
      raw is num ? raw.toInt() : fallback;

  @override
  bool operator ==(Object other) =>
      other is GridSpan &&
      other.row == row &&
      other.col == col &&
      other.rowSpan == rowSpan &&
      other.colSpan == colSpan;

  @override
  int get hashCode => Object.hash(row, col, rowSpan, colSpan);

  @override
  String toString() => 'GridSpan($row,$col $rowSpan×$colSpan)';
}

/// Le rectangle qu'occupe une cellule, gouttière comprise.
///
/// Géométrie pure, sans le moindre widget : les fusions et les débordements se
/// vérifient alors sur des nombres, assis, plutôt qu'en comparant des captures
/// d'écran de téléphone.
///
/// Les colonnes se partagent la largeur **à parts égales**, les lignes la
/// hauteur de même. Pas de pondération : une grille de tableau de bord se lit
/// d'un coup d'œil, et des colonnes de largeurs différentes obligeraient à
/// chercher où commence la suivante.
Rect gridRectFor(
  GridSpan span, {
  required int rows,
  required int cols,
  required Size size,
  double gap = 8,
}) {
  final cellWidth = (size.width - gap * (cols - 1)) / cols;
  final cellHeight = (size.height - gap * (rows - 1)) / rows;

  final left = span.col * (cellWidth + gap);
  final top = span.row * (cellHeight + gap);

  // La gouttière intérieure d'une cellule fusionnée lui revient : deux cellules
  // côte à côte et une cellule de deux colonnes doivent couvrir exactement la
  // même largeur, sinon les bords ne s'alignent plus d'une ligne à l'autre.
  return Rect.fromLTWH(
    left,
    top,
    cellWidth * span.colSpan + gap * (span.colSpan - 1),
    cellHeight * span.rowSpan + gap * (span.rowSpan - 1),
  );
}

/// Les rectangles de toutes les cellules, dans l'ordre où elles arrivent.
List<Rect> gridRectsFor(
  List<GridSpan> spans, {
  required int rows,
  required int cols,
  required Size size,
  double gap = 8,
}) =>
    [
      for (final span in spans)
        gridRectFor(span, rows: rows, cols: cols, size: size, gap: gap),
    ];

/// Ne garde que les cellules qui tiennent dans la grille et **ne se recouvrent
/// pas**.
///
/// La première posée gagne : c'est l'ordre du document qui tranche, donc l'ordre
/// que l'éditeur affichera. Le contraire — la dernière gagne — ferait
/// disparaître un composant qu'on vient de poser au profit d'un composant plus
/// bas dans la liste, ce qui n'a aucune explication visible à l'écran.
///
/// [T] est libre pour que la fonction reste géométrique : elle place des
/// cellules, elle ne sait pas ce qu'il y a dedans.
List<T> placedCells<T>(
  List<T> cells, {
  required GridSpan Function(T cell) spanOf,
  required T Function(T cell, GridSpan span) withSpan,
  required int rows,
  required int cols,
}) {
  final kept = <T>[];
  final taken = <GridSpan>[];

  for (final cell in cells) {
    final span = spanOf(cell).clampedTo(rows: rows, cols: cols);
    if (span == null) continue;
    if (taken.any(span.overlaps)) continue;
    taken.add(span);
    kept.add(withSpan(cell, span));
  }

  return kept;
}
