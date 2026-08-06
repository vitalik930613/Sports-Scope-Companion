import 'package:flutter/material.dart';

import '../../dashboard/block_density.dart';

/// La largeur à laquelle une carte de texte (phrases ou lignes à deux
/// colonnes) se construit avant mise à l'échelle — ce qu'il faut pour que les
/// phrases se replient sur plusieurs lignes plutôt que de filer sur une
/// seule, très longue, qu'on aurait ensuite à réduire jusqu'à l'illisible.
/// Fixe et non celle de la case : c'est [ScaleToFit] qui la ramène à la case
/// réelle.
const _naturalCardWidth = 220.0;

/// La carte des pages de données : un titre discret, des lignes lisibles.
///
/// Extraite de `ride_summary_page.dart` telle quelle. Elle sert maintenant à
/// plusieurs blocs, qu'un profil peut poser dans n'importe quel ordre : sans
/// mise en forme commune, deux blocs voisins venus de deux endroits du code
/// n'auraient ni le même fond, ni le même arrondi, ni la même marge — et une
/// page composée à la main aurait l'air cassée.
///
/// Toutes les lignes sont toujours écrites : c'est le mode du profil qui
/// décide de ce qu'il y a à dire, pas la case qui décide de ce qu'elle
/// garde. [BlockSurface] réduit l'ensemble s'il ne tient pas.
class BlockCard extends StatelessWidget {
  const BlockCard({super.key, required this.title, required this.lines});

  final String title;
  final List<String> lines;

  /// Le fond des cartes, partagé avec [ZoneBreakdown] : c'est ce qui les fait
  /// lire comme des éléments d'une même page.
  static const background = Color(0xFF1F2226);

  @override
  Widget build(BuildContext context) => BlockSurface(child: _content());

  Widget _content() {
    const metrics = BlockMetrics.natural;
    return SizedBox(
      width: _naturalCardWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white70,
              fontSize: metrics.titleSize,
            ),
          ),
          SizedBox(height: metrics.gap),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                line,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: metrics.lineSize,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Une ligne de [StatCard] : ce qu'on mesure à gauche, ce que ça vaut à droite.
@immutable
class StatRow {
  const StatRow(this.label, this.value);

  final String label;
  final String value;
}

/// La carte des moyennes : un titre, puis des lignes en **deux colonnes**.
///
/// Une [BlockCard] écrit des phrases (« Max 178 bpm »), qu'on relit chacune en
/// entier pour retrouver le chiffre. Ici les trois chiffres d'une même mesure
/// sont l'un sous l'autre, alignés à droite : on les compare d'un coup d'œil,
/// et c'est tout ce qu'on demande à un bilan de moyennes.
///
/// L'unité est dans le titre et pas sur chaque ligne : elle vaut pour les
/// trois, et la colonne des valeurs tient alors dans une demi-case.
class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.title, required this.rows});

  final String title;
  final List<StatRow> rows;

  @override
  Widget build(BuildContext context) => BlockSurface(child: _content());

  Widget _content() {
    const metrics = BlockMetrics.natural;
    return SizedBox(
      width: _naturalCardWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white70,
              fontSize: metrics.titleSize,
            ),
          ),
          SizedBox(height: metrics.gap),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Text(
                      row.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: metrics.lineSize,
                      ),
                    ),
                  ),
                  SizedBox(width: metrics.gap),
                  Text(
                    row.value,
                    maxLines: 1,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: metrics.lineSize,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Le cadre commun de tous les composants : le fond des cartes, l'arrondi, le
/// rembourrage, et la mise à l'échelle qui les fait tenir dans leur case.
///
/// Un seul endroit pour le rembourrage, parce qu'il entre dans la taille
/// naturelle que [ScaleToFit] compare à la case réelle : une carte qui se
/// rembourrerait de son côté fausserait ce que voit la mise à l'échelle.
class BlockSurface extends StatelessWidget {
  const BlockSurface({
    super.key,
    required this.child,
    this.background,
  });

  final Widget child;

  /// L'aplat de zone, quand la mesure en porte un. Le fond des cartes sinon.
  final Color? background;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: EdgeInsets.all(BlockMetrics.natural.padding),
        decoration: BoxDecoration(
          color: background ?? BlockCard.background,
          borderRadius: BorderRadius.circular(12),
        ),
        // Une assurance, pas une politique : une case pathologiquement petite
        // peut rester plus petite que ce que `ScaleToFit` sait encore réduire
        // (l'échelle a un plancher pratique), et ce qui déborderait malgré
        // tout est coupé au bord de sa propre carte plutôt que peint sur la
        // voisine.
        clipBehavior: Clip.hardEdge,
        child: ScaleToFit(child: child),
      );
}

/// Réduit son enfant pour qu'il tienne dans la case donnée, sans jamais
/// l'agrandir au-delà de sa taille naturelle ni en retirer un morceau.
///
/// `FittedBox(fit: BoxFit.scaleDown)` mesure l'enfant à sa taille naturelle
/// puis le met à l'échelle si — et seulement si — il ne tient pas : tout ce
/// qu'on a posé dedans arrive donc en entier, en plus ou moins grand. C'est
/// le mode choisi sur le site qui décide du contenu ; la taille de la case ne
/// fait plus ce choix à sa place.
///
/// Volontairement **shrink-only** : une case généreuse ne grossit pas au-delà
/// de la taille naturelle du contenu, pour ne pas afficher un chiffre
/// disproportionné à côté de cases voisines restées à leur taille normale.
///
/// **Sans hauteur ou largeur bornée, on ne touche à rien** : dans une page
/// qui défile, la carte prend la place qu'il lui faut, et un enfant mis à
/// l'échelle dans un `SizedBox.expand` sous une contrainte infinie lèverait.
class ScaleToFit extends StatelessWidget {
  const ScaleToFit({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          if (!constraints.hasBoundedHeight || !constraints.hasBoundedWidth) {
            return child;
          }
          return SizedBox.expand(
            child: FittedBox(fit: BoxFit.scaleDown, child: child),
          );
        },
      );
}
