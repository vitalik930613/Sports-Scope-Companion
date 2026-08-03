import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

/// Combien de place une cellule laisse à ce qu'on y a posé.
///
/// Un profil décrit sa grille en lignes et en colonnes, jamais en pixels : la
/// même page de 3 × 3 donne des cases de 104 × 194 sur un téléphone ordinaire et
/// bien moins sur un petit écran. Les composants, eux, étaient écrits à taille
/// fixe — 16 de rembourrage, un titre à 13, des lignes à 16 — et réclamaient donc
/// leur hauteur quelle que soit la case. Posés par `gridRectFor` dans un
/// rectangle imposé, ils débordaient sur la voisine.
///
/// D'où cette échelle : la case dit sa taille, la densité dit ce qu'on peut
/// encore dessiner dedans. **Le mode choisi sur le site devient un plafond et
/// non un ordre** — un composant peut toujours en montrer moins que ce qu'on lui
/// a demandé, jamais plus. Le format ne change pas d'un octet.
///
/// Deux façons de se dégrader, et le partage n'est pas arbitraire :
///
/// - ce qui se lit **en diagonale** (une légende de zones, une icône, une unité)
///   perd des éléments : réduit à 40 %, un tableau de sept lignes ne se lit plus,
///   alors que sa barre garde toute son information ;
/// - ce qui se lit **en entier** (une phrase d'état vide, qui dit *pourquoi* il
///   n'y a rien) rapetisse au lieu d'être tronqué — « Le temps par zone cardio
///   se rem… » ne vaut pas mieux que rien.
enum BlockDensity {
  /// Une case de page, ou une grille de 2 × 2 : tout tient.
  comfortable,

  /// Le cas courant d'une grille de 3 × 3.
  normal,

  /// Une case où il faut choisir : les tableaux passent en résumé.
  tight,

  /// Le chiffre et rien d'autre. Ni titre, ni unité, ni icône : à cette taille,
  /// chacun d'eux vole la moitié de ce qu'on est venu lire.
  minimal,
}

/// Les tailles à employer dans une cellule donnée.
///
/// Tout est ici et rien dans les widgets : les seuils se vérifient alors sur des
/// nombres, assis, plutôt qu'en comparant des captures d'écran de téléphone —
/// même raison que `gridRectFor`. C'est aussi ce que l'éditeur du site recopie
/// (`companionSettings.ts`), pour montrer la même dégradation avant le départ.
@immutable
class BlockMetrics {
  const BlockMetrics._({
    required this.density,
    required this.padding,
    required this.gap,
    required this.titleSize,
    required this.lineSize,
    required this.unitSize,
    required this.iconSize,
    required this.barHeight,
  });

  factory BlockMetrics.of(BoxConstraints constraints) => BlockMetrics.forCell(
        width: constraints.maxWidth,
        height: constraints.maxHeight,
      );

  /// La densité d'une case de [width] × [height], et les tailles qui vont avec.
  factory BlockMetrics.forCell({
    required double width,
    required double height,
  }) =>
      BlockMetrics.forDensity(densityFor(width: width, height: height));

  factory BlockMetrics.forDensity(BlockDensity density) => switch (density) {
        BlockDensity.comfortable => const BlockMetrics._(
            density: BlockDensity.comfortable,
            padding: 16,
            gap: 12,
            titleSize: 13,
            lineSize: 16,
            unitSize: 13,
            iconSize: 18,
            barHeight: 22,
          ),
        BlockDensity.normal => const BlockMetrics._(
            density: BlockDensity.normal,
            padding: 12,
            gap: 8,
            titleSize: 12,
            lineSize: 15,
            unitSize: 12,
            iconSize: 16,
            barHeight: 18,
          ),
        BlockDensity.tight => const BlockMetrics._(
            density: BlockDensity.tight,
            padding: 8,
            gap: 6,
            titleSize: 11,
            lineSize: 13,
            unitSize: 11,
            iconSize: 14,
            barHeight: 14,
          ),
        BlockDensity.minimal => const BlockMetrics._(
            density: BlockDensity.minimal,
            padding: 6,
            gap: 4,
            titleSize: 11,
            lineSize: 12,
            unitSize: 10,
            iconSize: 12,
            barHeight: 10,
          ),
      };

  final BlockDensity density;

  /// Le rembourrage de la carte, sur les quatre côtés.
  final double padding;

  /// Entre le titre et le contenu, et entre deux parties du contenu.
  final double gap;

  final double titleSize;
  final double lineSize;
  final double unitSize;
  final double iconSize;

  /// La barre des zones. Généreuse tant qu'on peut : c'est aussi la surface de
  /// lecture des couleurs, et un liseré de 6 pt ne se distingue plus sous la
  /// pluie.
  final double barHeight;

  /// Sous ces hauteurs, une cellule passe à la densité suivante. En pixels
  /// logiques, comme tout ce qui vient de [BoxConstraints].
  static const minimalHeight = 96.0;
  static const tightHeight = 148.0;
  static const normalHeight = 232.0;

  /// Une case plus étroite que ça ne tient plus qu'un chiffre, quelle que soit
  /// sa hauteur : c'est la largeur qui manque, et un titre y tiendrait sur trois
  /// lignes. Une grille de 4 colonnes sur un téléphone ordinaire y tombe.
  static const minimalWidth = 88.0;

  /// Ce qu'il faut de largeur à une ligne de légende : la pastille, la clé de
  /// zone, la durée et le pourcentage. En dessous, la ligne déborde **sur le
  /// côté** — l'autre façon de sortir de sa case, celle qu'on oublie parce
  /// qu'une grille se pense en hauteur.
  static const legendWidth = 150.0;

  /// Ce qu'il faut de largeur aux deux pastilles du budget de charge (la
  /// fraîcheur, le risque) posées côte à côte : une icône, un chiffre, et la
  /// gouttière entre elles. En dessous elles se marchent dessus — la case garde
  /// alors son chiffre et sa barre, qui portent l'essentiel.
  static const budgetChipsWidth = 120.0;

  /// L'interligne dont on tient compte pour décider. Majoré exprès : trop
  /// prudent, on retire une ligne de trop ; trop juste, on déborde — et déborder
  /// est précisément ce qu'on vient corriger.
  static const _leading = 1.35;

  /// L'espace sous chaque ligne d'une carte.
  static const _lineGap = 4.0;

  /// **Une hauteur infinie vaut `comfortable`** : c'est le cas d'une page qui
  /// défile, où le composant prend la hauteur qu'il lui faut et où rien ne peut
  /// déborder. Sans cette réponse, une page en liste se dessinerait comme la
  /// plus petite des cases.
  static BlockDensity densityFor({
    required double width,
    required double height,
  }) {
    if (!height.isFinite) return BlockDensity.comfortable;
    if (height < minimalHeight || width < minimalWidth) {
      return BlockDensity.minimal;
    }
    if (height < tightHeight) return BlockDensity.tight;
    if (height < normalHeight) return BlockDensity.normal;
    return BlockDensity.comfortable;
  }

  /// Le titre nomme la carte, et deux cartes de zones ne se distinguent que par
  /// lui — mais dans une case où il mangerait le quart de la hauteur, c'est le
  /// contenu qu'on vient lire.
  bool get showTitle => density != BlockDensity.minimal;

  /// L'unité est déjà dans la mesure qu'on a choisie sur le site ; le chiffre,
  /// non.
  bool get showUnit => density != BlockDensity.minimal;

  /// L'icône ne fait que redire ce que dit l'unité. Elle part avant elle.
  bool get showIcon =>
      density == BlockDensity.comfortable || density == BlockDensity.normal;

  double get titleHeight => (titleSize * _leading).roundToDouble();

  /// Une ligne de carte, son espacement compris.
  double get lineHeight => (lineSize * _leading).roundToDouble() + _lineGap;

  /// Une ligne de légende de zones : le texte, son rembourrage (4 en haut et en
  /// bas dans `_ZoneLine`) et l'espace qui la sépare de la suivante.
  double get legendRowHeight => (lineSize * _leading).roundToDouble() + 8 + 6;

  /// Combien des [wanted] lignes tiennent sous [height], titre compris.
  ///
  /// Zéro est une réponse : il reste alors le titre, qui dit au moins de quoi la
  /// case parle.
  int linesIn(double height, {required int wanted, bool withTitle = true}) {
    if (!height.isFinite) return wanted;

    var room = height - padding * 2;
    if (withTitle && showTitle) room -= titleHeight + gap;
    if (room <= 0) return 0;

    return (room ~/ lineHeight).clamp(0, wanted);
  }

  /// La hauteur du « 62 / 85 » du budget de charge : plus gros qu'une ligne
  /// ordinaire sans aller jusqu'au plein cadre — il se lit d'un coup d'œil, mais
  /// il en faut deux (le fait et la cible) et une barre en dessous.
  double get budgetFigureSize => (lineSize * 1.6).roundToDouble();

  double get budgetFigureHeight =>
      (budgetFigureSize * _leading).roundToDouble();

  /// La troisième ligne du budget de charge tient-elle : les pastilles fraîcheur
  /// et risque en mode « aujourd'hui », le reste à placer en mode « la semaine » ?
  ///
  /// Elle se lit **en diagonale** — c'est le contexte du chiffre, pas le chiffre —
  /// donc elle part la première quand la case se resserre, comme la légende des
  /// zones. Ce qui reste (« 62 / 85 » et sa barre) répond encore à la question
  /// qu'on se pose au guidon ; une pastille de couleur toute seule, non.
  ///
  /// **Recopié dans `companionSettings.ts`**, comme tous les seuils de ce
  /// fichier : sans ça, l'éditeur du site montrerait un contexte que le téléphone
  /// retirera. Les deux jeux de tests portent les mêmes attentes exprès.
  bool budgetContextFits(
    double height, {
    required double width,
    bool withTitle = true,
  }) {
    if (width - padding * 2 < budgetChipsWidth) return false;
    if (!height.isFinite) return true;

    var room = height - padding * 2;
    if (withTitle && showTitle) room -= titleHeight + gap;
    room -= budgetFigureHeight + gap;
    room -= barHeight + gap;

    return room >= lineHeight;
  }

  /// La légende de [zones] lignes tient-elle dans une case de [width] ×
  /// [height] ?
  ///
  /// **Tout ou rien.** Une légende amputée de ses deux dernières zones se lit
  /// comme une légende complète — on croirait n'avoir passé aucune seconde en
  /// Z5, ce qui est exactement l'inverse de la vérité. Une barre seule ne risque
  /// pas ça.
  bool legendFits(
    double height, {
    required double width,
    required int zones,
    required bool withBar,
    bool withTitle = true,
  }) {
    if (width - padding * 2 < legendWidth) return false;
    if (!height.isFinite) return true;

    var room = height - padding * 2;
    if (withTitle && showTitle) room -= titleHeight + gap;
    if (withBar) room -= barHeight + gap;

    return room >= zones * legendRowHeight;
  }
}
