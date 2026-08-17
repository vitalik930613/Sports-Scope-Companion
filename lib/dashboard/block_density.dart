import 'package:flutter/foundation.dart';

/// Les tailles naturelles d'une carte de bloc.
///
/// Il n'y a plus qu'un seul jeu de tailles : le mode choisi sur le site est un
/// **ordre**, pas un plafond — titre, unité, icône, légende, contexte du
/// budget de charge sont toujours construits, quelle que soit la case. C'est
/// [BlockSurface] qui fait tenir cette taille naturelle dans la case réelle,
/// en la réduisant d'un bloc (`FittedBox`) plutôt qu'en retirant des
/// éléments — exactement ce qui se passait déjà pour le grand chiffre, la
/// jauge radar et le texte des états vides, généralisé à toute la carte.
///
/// C'est aussi ce que l'éditeur du site recopie (`companionSettings.ts`),
/// pour montrer le même contenu avant le départ — mais plus aucun seuil à
/// garder synchronisé entre les deux dépôts : une seule taille, pas quatre
/// paliers.
@immutable
class BlockMetrics {
  const BlockMetrics._({
    required this.padding,
    required this.gap,
    required this.titleSize,
    required this.lineSize,
    required this.unitSize,
    required this.iconSize,
    required this.barHeight,
  });

  /// Les tailles naturelles, indépendantes de la case : il n'y a plus qu'un
  /// seul jeu de valeurs.
  static const natural = BlockMetrics._(
    padding: 10,
    gap: 12,
    titleSize: 13,
    lineSize: 16,
    unitSize: 13,
    iconSize: 26,
    barHeight: 22,
  );

  /// Le rembourrage de la carte, sur les quatre côtés.
  final double padding;

  /// Entre le titre et le contenu, et entre deux parties du contenu.
  final double gap;

  final double titleSize;
  final double lineSize;
  final double unitSize;
  final double iconSize;

  /// La barre des zones. Généreuse : c'est aussi la surface de lecture des
  /// couleurs, et un liseré trop fin ne se distingue plus sous la pluie.
  final double barHeight;

  /// L'interligne dont on tient compte pour dimensionner une colonne. Majoré
  /// exprès : la hauteur naturelle sert ensuite de référence à un
  /// `FittedBox`, et une hauteur sous-estimée ferait chevaucher deux lignes
  /// avant même la mise à l'échelle.
  static const _leading = 1.35;

  /// L'espace sous chaque ligne d'une carte.
  static const _lineGap = 4.0;

  double get titleHeight => (titleSize * _leading).roundToDouble();

  /// Une ligne de carte, son espacement compris.
  double get lineHeight => (lineSize * _leading).roundToDouble() + _lineGap;

  /// Une ligne de légende de zones : le texte, son rembourrage (4 en haut et
  /// en bas dans `_ZoneLine`) et l'espace qui la sépare de la suivante.
  double get legendRowHeight => (lineSize * _leading).roundToDouble() + 8 + 6;

  /// La hauteur du « 62 / 85 » du budget de charge : plus gros qu'une ligne
  /// ordinaire sans aller jusqu'au plein cadre — il se lit d'un coup d'œil,
  /// mais il en faut deux (le fait et la cible) et une barre en dessous.
  double get budgetFigureSize => (lineSize * 1.6).roundToDouble();
}
