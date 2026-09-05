import 'package:flutter/material.dart';

import '../../dashboard/block_density.dart';
import '../../ui/zone_colors.dart';

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
  const BlockCard({
    super.key,
    required this.title,
    required this.lines,
    this.color,
    this.textColor,
  });

  final String title;
  final List<String> lines;

  /// Fond de la carte, réglé dans l'éditeur — voir [DashboardBlock.color].
  /// `null` : le fond habituel ([background]).
  final Color? color;

  /// Texte de la carte, réglé dans l'éditeur — voir [DashboardBlock.textColor].
  /// `null` : blanc sur le fond habituel, ou calculé pour rester lisible sur
  /// [color] quand il est réglé sans texte choisi.
  final Color? textColor;

  /// Le fond des cartes, partagé avec [ZoneBreakdown] : c'est ce qui les fait
  /// lire comme des éléments d'une même page.
  static const background = Color(0xFF1F2226);

  @override
  Widget build(BuildContext context) =>
      BlockSurface(background: color, child: _content());

  Widget _content() {
    const metrics = BlockMetrics.natural;
    final ink = textColor ?? (color == null ? Colors.white : foregroundOf(color!));

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
              color: ink.withValues(alpha: 0.7),
              fontSize: metrics.titleSize,
            ),
          ),
          SizedBox(height: metrics.gap),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                line,
                style: TextStyle(
                  color: ink,
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
  const StatRow(
    this.label,
    this.value, {
    this.background,
    this.icon,
    this.dimmed = false,
  });

  final String label;
  final String value;

  /// La couleur de la zone dans laquelle tombe cette valeur (`zoneColorOf`),
  /// `null` sans seuil connu ou pour une mesure qui n'a pas de zone (cadence,
  /// vitesse) — la ligne garde alors le texte blanc uni.
  final Color? background;

  /// La valeur vient d'un appareil qui n'est plus connecté : elle reste
  /// affichée (une batterie ne se remet pas à zéro toute seule en se
  /// débranchant, contrairement à un capteur en direct — même règle que
  /// `SensorHub.latest*`), mais grisée pour dire *ce n'est plus mesuré en
  /// direct*, plutôt qu'un chiffre à jour qu'on croirait actuel.
  final bool dimmed;

  /// Devant le libellé, `null` la plupart du temps : la mesure d'une carte
  /// (moyennes, bilan de tour) est déjà dite par l'icône du titre, une par
  /// ligne serait redondante. Sert quand chaque ligne est un *appareil*
  /// différent plutôt qu'un chiffre différent de la même mesure — voir le
  /// composant `battery`, où chaque ligne a son propre capteur donc sa
  /// propre icône.
  final IconData? icon;
}

/// La carte des moyennes : un titre, puis des lignes en **deux colonnes**.
///
/// Une [BlockCard] écrit des phrases (« Max 178 bpm »), qu'on relit chacune en
/// entier pour retrouver le chiffre. Ici les trois chiffres d'une même mesure
/// sont l'un sous l'autre, alignés à droite : on les compare d'un coup d'œil,
/// et c'est tout ce qu'on demande à un bilan de moyennes.
///
/// L'unité est dans le titre et pas sur chaque ligne : elle vaut pour les
/// trois, et la colonne des valeurs tient alors dans une demi-case. Rendue
/// plus petite que le titre ([StatCard.unit]) : sur la même ligne qu'un
/// libellé ou une icône, elle ne doit jamais rivaliser avec eux.
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.title,
    required this.rows,
    this.unit,
    this.icon,
    this.color,
    this.textColor,
  });

  final String title;

  /// Affichée après le titre, plus petite — jamais concaténée dedans : sur
  /// la même ligne qu'un libellé, l'unité doit toujours se lire plus
  /// discrète que lui.
  final String? unit;

  final List<StatRow> rows;

  /// Devant le titre : dit quelle mesure on regarde avant même de lire le nom
  /// — le même cœur, le même éclair que partout ailleurs dans l'appli
  /// (`ui/sensor_icons.dart`, `MetricId`).
  final IconData? icon;

  /// Fond de la carte, réglé dans l'éditeur — voir [DashboardBlock.color].
  final Color? color;

  /// Texte de la carte, réglé dans l'éditeur — voir [DashboardBlock.textColor].
  /// N'affecte jamais [StatRow.background] : la pastille de zone reste une
  /// donnée, pas la surface du texte.
  final Color? textColor;

  @override
  Widget build(BuildContext context) =>
      BlockSurface(background: color, child: _content());

  Widget _content() {
    const metrics = BlockMetrics.natural;
    final ink = textColor ?? (color == null ? Colors.white : foregroundOf(color!));
    final dimInk = ink.withValues(alpha: 0.7);

    return SizedBox(
      width: _naturalCardWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: metrics.titleSize + 2, color: dimInk),
                SizedBox(width: metrics.gap / 2),
              ],
              Expanded(
                child: RichText(
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  text: TextSpan(
                    text: title.toUpperCase(),
                    style: TextStyle(
                      color: dimInk,
                      fontSize: metrics.titleSize,
                    ),
                    children: unit == null
                        ? null
                        : [
                            TextSpan(
                              text: ' (${unit!.toUpperCase()})',
                              style: TextStyle(fontSize: metrics.titleSize * 0.8),
                            ),
                          ],
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: metrics.gap),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              // Pas de `baseline` ici : le fond de zone met la valeur dans un
              // `Container` (pour son rembourrage et son coin arrondi), qui
              // n'a pas de ligne de base à offrir — un Row en `baseline` la
              // recalerait sur son bord haut plutôt que sur le texte du
              // libellé.
              child: Opacity(
                opacity: row.dimmed ? 0.45 : 1,
                child: Row(
                  children: [
                    if (row.icon != null) ...[
                      Icon(row.icon, size: metrics.lineSize, color: dimInk),
                      SizedBox(width: metrics.gap / 2),
                    ],
                    Expanded(
                      child: Text(
                        row.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: dimInk,
                          fontSize: metrics.lineSize,
                        ),
                      ),
                    ),
                    SizedBox(width: metrics.gap),
                    _value(row, metrics, ink),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// La valeur d'une ligne, en pastille de la couleur de zone quand elle en a
  /// une — le même traitement que le bandeau et le mode `zone` de
  /// [MetricView] : la couleur se lit avant le chiffre. [ink] est le texte de
  /// la carte (réglé ou calculé), utilisé seulement hors pastille — la
  /// pastille garde son propre contraste ([foregroundOf]), sémantique et non
  /// personnalisable.
  static Widget _value(StatRow row, BlockMetrics metrics, Color ink) {
    final background = row.background;
    if (background == null) {
      return Text(
        row.value,
        maxLines: 1,
        style: TextStyle(color: ink, fontSize: metrics.lineSize),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        row.value,
        maxLines: 1,
        style: TextStyle(
          color: foregroundOf(background),
          fontWeight: FontWeight.w600,
          fontSize: metrics.lineSize,
        ),
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
    this.backgroundChart,
  });

  final Widget child;

  /// L'aplat de zone, quand la mesure en porte un. Le fond des cartes sinon.
  final Color? background;

  /// Le graphique de fond d'une mesure (`MetricView`, `background_chart_window`)
  /// — une couche entre le fond plat et [child], jamais un remplacement de
  /// [background] : c'est justement lui qui doit rester visible partout où le
  /// graphique laisse transparent. `null` pour tous les autres genres de
  /// composants, et pour une mesure sans ce réglage — comportement inchangé.
  final Widget? backgroundChart;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: background ?? BlockCard.background,
          borderRadius: BorderRadius.circular(12),
        ),
        // Une assurance, pas une politique : une case pathologiquement petite
        // peut rester plus petite que ce que `ScaleToFit` sait encore réduire
        // (l'échelle a un plancher pratique), et ce qui déborderait malgré
        // tout est coupé au bord de sa propre carte plutôt que peint sur la
        // voisine. Sert aussi à `backgroundChart` : le contour arrondi défini
        // ici s'applique aussi à l'aire du graphique, posée bord à bord.
        clipBehavior: Clip.hardEdge,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final content = Padding(
              padding: EdgeInsets.all(BlockMetrics.natural.padding),
              child: ScaleToFit(child: child),
            );
            final chart = backgroundChart;
            // `Stack(fit: expand)` réclame des contraintes bornées, comme
            // `SizedBox.expand` dans [ScaleToFit] : sans hauteur/largeur
            // réelle (une page qui défile), le graphique de fond n'a de
            // toute façon pas de « case » entière à remplir — on retombe
            // silencieusement sur le rendu d'avant ce réglage plutôt que de
            // lever.
            if (chart == null || !constraints.hasBoundedHeight || !constraints.hasBoundedWidth) {
              return content;
            }
            return Stack(
              fit: StackFit.expand,
              children: [Positioned.fill(child: chart), content],
            );
          },
        ),
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
