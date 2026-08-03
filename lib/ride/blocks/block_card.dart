import 'package:flutter/material.dart';

import '../../dashboard/block_density.dart';

/// La carte des pages de données : un titre discret, des lignes lisibles.
///
/// Extraite de `ride_summary_page.dart` telle quelle. Elle sert maintenant à
/// plusieurs blocs, qu'un profil peut poser dans n'importe quel ordre : sans
/// mise en forme commune, deux blocs voisins venus de deux endroits du code
/// n'auraient ni le même fond, ni le même arrondi, ni la même marge — et une
/// page composée à la main aurait l'air cassée.
///
/// Elle se mesure à la case qu'on lui donne ([BlockMetrics]) : dans une page qui
/// défile elle prend la place qu'il lui faut, dans une cellule de grille elle s'y
/// range. Ce qu'elle porte le plus souvent, ce sont des **états vides** — des
/// phrases qui disent *pourquoi* il n'y a rien — d'où le repli en taille plutôt
/// qu'en troncature : « Le temps par zone cardio se rem… » ne vaut pas mieux que
/// rien. Les lignes qui ne tiennent décidément plus sont retirées par le bas, la
/// première étant toujours la plus utile.
class BlockCard extends StatelessWidget {
  const BlockCard({
    super.key,
    required this.title,
    required this.lines,
    this.metrics,
  });

  final String title;
  final List<String> lines;

  /// Les tailles, quand l'appelant les a déjà calculées.
  ///
  /// Sert à qui pose plusieurs cartes dans une même case ([AveragesCard]) :
  /// elles se partagent alors une densité, celle de la case, plutôt que d'en
  /// déduire chacune une différente de son propre bout de place. Et surtout,
  /// cela évite un `LayoutBuilder` sous un `IntrinsicHeight`, qui ne sait pas
  /// mesurer ce qui n'existe qu'une fois les contraintes connues.
  final BlockMetrics? metrics;

  /// Le fond des cartes, partagé avec [ZoneBreakdown] : c'est ce qui les fait
  /// lire comme des éléments d'une même page.
  static const background = Color(0xFF1F2226);

  @override
  Widget build(BuildContext context) {
    final given = metrics;
    if (given != null) {
      return BlockSurface(metrics: given, child: _content(given, lines));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = BlockMetrics.of(constraints);
        final shown = lines
            .take(metrics.linesIn(constraints.maxHeight, wanted: lines.length))
            .toList();

        return BlockSurface(
          metrics: metrics,
          child: FittedProse(
            metrics: metrics,
            constraints: constraints,
            child: _content(metrics, shown),
          ),
        );
      },
    );
  }

  Widget _content(BlockMetrics metrics, List<String> shown) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (metrics.showTitle) ...[
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white70,
                fontSize: metrics.titleSize,
              ),
            ),
            SizedBox(height: metrics.gap),
          ],
          for (final line in shown)
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
      );
}

/// Le cadre commun de tous les composants : le fond des cartes, l'arrondi, le
/// rembourrage de la densité.
///
/// Un seul endroit, parce que le rembourrage entre dans le calcul de ce qui
/// tient : une carte qui se rembourrerait de son côté ferait mentir
/// [BlockMetrics.linesIn] du double de l'écart.
class BlockSurface extends StatelessWidget {
  const BlockSurface({
    super.key,
    required this.metrics,
    required this.child,
    this.background,
  });

  final BlockMetrics metrics;
  final Widget child;

  /// L'aplat de zone, quand la mesure en porte un. Le fond des cartes sinon.
  final Color? background;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: EdgeInsets.all(metrics.padding),
        decoration: BoxDecoration(
          color: background ?? BlockCard.background,
          borderRadius: BorderRadius.circular(12),
        ),
        // Une assurance, pas une politique : les composants se dégradent pour
        // tenir, et ce qui passerait quand même à travers est coupé au bord de
        // sa propre carte plutôt que peint sur la voisine.
        clipBehavior: Clip.hardEdge,
        child: child,
      );
}

/// Du texte qui rapetisse au lieu de déborder.
///
/// `FittedBox` mesure la colonne à sa taille naturelle, puis la met à l'échelle
/// si — et seulement si — elle ne tient pas : les phrases arrivent donc entières,
/// ce qui est tout l'intérêt d'un état vide. La largeur est imposée avant la mise
/// à l'échelle, sans quoi la colonne s'étirerait sur une seule ligne au lieu de
/// se replier.
///
/// **Sans hauteur bornée, on ne touche à rien** : dans une page qui défile, la
/// carte prend la hauteur qu'il lui faut, et un `Expanded` y étirerait la mise en
/// page vers l'infini.
class FittedProse extends StatelessWidget {
  const FittedProse({
    super.key,
    required this.metrics,
    required this.constraints,
    required this.child,
  });

  final BlockMetrics metrics;
  final BoxConstraints constraints;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!constraints.hasBoundedHeight) return child;

    // Une largeur infinie n'arrive pas dans une grille — chaque cellule reçoit
    // son rectangle — mais un `Row` sans `Expanded` en donnerait une, et un
    // `SizedBox` de largeur infinie lève. On rend alors la colonne telle quelle,
    // c'est-à-dire ce qu'on faisait avant la mise à l'échelle.
    final inner = constraints.maxWidth - metrics.padding * 2;
    if (!inner.isFinite || inner <= 0) return child;

    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.topLeft,
        child: SizedBox(width: inner, child: child),
      ),
    );
  }
}
