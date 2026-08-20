import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../dashboard/block_density.dart';
import '../../recording/elevation_profile_point.dart';
import '../../ui/grade_colors.dart';
import '../../ui/zone_colors.dart' show foregroundOf;
import '../widgets/elevation_profile_graph.dart';
import 'block_card.dart';

/// La carte partagée par `ClimbProfileCard` et `AltitudeProfileCard` : un
/// titre, un en-tête chiffré (gain, distance, pente), le graphique.
///
/// **Ne passe volontairement pas par [BlockSurface]/[ScaleToFit]**,
/// contrairement à la plupart des autres blocs : ceux-là mettent à l'échelle
/// la carte entière d'un bloc, ce qui préserve son rapport largeur/hauteur
/// naturel — parfait pour un chiffre ou une icône, qui a une forme, mais faux
/// pour un graphique, qui n'en a pas et doit toujours remplir toute la
/// largeur de la case. Une case large et basse (une seule ligne de grille,
/// ~100 px de haut sur la grille 6×6 du téléphone) verrait sinon la carte
/// entière réduite à sa hauteur, laissant le graphique flotter au centre avec
/// du vide de chaque côté plutôt que de remplir la case.
///
/// Le graphique occupe donc toujours 100 % de la largeur et toute la hauteur
/// qui lui reste après l'en-tête ([Expanded]) ; c'est l'en-tête (titre +
/// chiffres) qui se réduit ([FittedBox], borné à une hauteur calculée) quand
/// la case est trop basse pour tenir à sa taille naturelle — jamais l'inverse.
class ElevationProfileSurface extends StatelessWidget {
  const ElevationProfileSurface({
    super.key,
    required this.title,
    required this.headline,
    required this.aside,
    required this.grade,
    required this.points,
    required this.segmentGrades,
    required this.ratio,
    this.color,
    this.textColor,
  });

  final String title;

  /// Le chiffre principal — le D+ restant (tracé) ou déjà grimpé (sortie
  /// libre) selon l'appelant.
  final String headline;

  /// À côté du chiffre principal, plus discret — la distance restante ou
  /// déjà parcourue, même paire que [headline].
  final String aside;

  final double grade;

  final List<ElevationProfilePoint> points;
  final List<double> segmentGrades;

  /// `null` : rien de « restant » à distinguer, tout le profil est déjà fait
  /// (sortie libre sans tracé) — voir [ElevationProfileGraph.ratio].
  final double? ratio;

  /// Fond/texte réglés dans l'éditeur — voir `DashboardBlock.color`/
  /// `DashboardBlock.textColor`. Ne remplacent jamais les couleurs de pente
  /// du graphique ([gradeColorOf]) : c'est une donnée.
  final Color? color;
  final Color? textColor;

  static const _naturalWidth = 220.0;

  /// La hauteur naturelle du titre + de la ligne de chiffres, gap compris —
  /// ce que l'en-tête occupe quand la case a assez de place. Mesurée sur
  /// `BlockMetrics.natural` (titre 13, ligne 16×1.3, interligne 1.35).
  static const _naturalHeaderHeight = 58.0;

  /// En dessous, l'en-tête n'est plus lisible — mieux vaut y laisser un peu
  /// de graphique en moins qu'un texte devenu un pixel.
  static const _minHeaderHeight = 16.0;

  /// Ce qu'il faut au minimum au graphique pour rester un graphique, pas un
  /// trait : en dessous, autant lui laisser toute la place et écraser
  /// l'en-tête à son plancher plutôt que l'inverse.
  static const _minChartHeight = 32.0;

  /// Hauteur du graphique hors contrainte de hauteur (page qui défile) : la
  /// case ne borne alors rien, il garde une hauteur raisonnable plutôt que de
  /// s'effondrer à zéro.
  static const _chartHeight = 140.0;

  @override
  Widget build(BuildContext context) {
    const metrics = BlockMetrics.natural;
    final ink = textColor ?? (color == null ? Colors.white : foregroundOf(color!));
    final gradeColor = gradeColorOf(grade);

    final header = SizedBox(
      width: _naturalWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: ink.withValues(alpha: 0.7), fontSize: metrics.titleSize),
          ),
          SizedBox(height: metrics.gap),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    headline,
                    style: TextStyle(color: ink, fontWeight: FontWeight.w800, fontSize: metrics.lineSize * 1.3),
                  ),
                  SizedBox(width: metrics.gap / 2),
                  Text(
                    aside,
                    style: TextStyle(
                      color: ink.withValues(alpha: 0.7),
                      fontWeight: FontWeight.w600,
                      fontSize: metrics.lineSize,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: gradeColor, borderRadius: BorderRadius.circular(6)),
                child: Text(
                  '${grade.round()} %',
                  style: TextStyle(color: foregroundOf(gradeColor), fontWeight: FontWeight.w700, fontSize: metrics.lineSize),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    final chart = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: ElevationProfileGraph(points: points, segmentGrades: segmentGrades, ratio: ratio),
    );

    return Container(
      width: double.infinity,
      // Jamais `height: double.infinity` : posée dans une page qui défile
      // (page Tours, `LapListBody`), la case ne borne pas la hauteur — un
      // `Container` qui la force quand même reçoit une contrainte tendue à
      // l'infini, invalide (`BoxConstraints forces an infinite height`), et
      // fait planter toute la mise en page de la liste. Sans hauteur forcée
      // ici, le `LayoutBuilder` ci-dessous voit les vraies contraintes
      // (bornées ou non) et choisit lui-même la bonne branche — c'est déjà
      // lui qui sait remplir une case bornée ou retomber sur [_chartHeight]
      // quand elle ne l'est pas.
      padding: EdgeInsets.all(metrics.padding),
      decoration: BoxDecoration(
        color: color ?? BlockCard.background,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.hardEdge,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (!constraints.hasBoundedHeight) {
            // Même parade que la branche bornée ci-dessous : une colonne de
            // page liste (`cols` à 3 ou 4) peut être bien plus étroite que
            // `_naturalWidth`, et rien dans `header` (chiffre, distance,
            // pastille de pente) n'a de plancher — sans le `FittedBox`, c'est
            // le `Row` de la ligne de chiffres qui déborde en `RenderFlex
            // overflowed`, la largeur y étant resserrée mais pas la hauteur.
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: _naturalHeaderHeight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: header,
                  ),
                ),
                SizedBox(height: metrics.gap),
                SizedBox(height: _chartHeight, child: chart),
              ],
            );
          }

          // L'en-tête prend sa taille naturelle s'il y a la place ; sinon il
          // cède jusqu'à son plancher, et c'est le graphique — jamais lui —
          // qui absorbe le reste de la case.
          final available = constraints.maxHeight - metrics.gap;
          final headerHeight = math.min(
            _naturalHeaderHeight,
            math.max(_minHeaderHeight, available - _minChartHeight),
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: headerHeight,
                // Le `FittedBox` mesure `header` à sa vraie taille naturelle
                // (contraintes non bornées) puis le réduit pour tenir dans
                // `headerHeight` — pas de hauteur forcée sur `header` lui-même,
                // qui romprait cette mesure et risquerait un débordement si
                // l'estimation de `_naturalHeaderHeight` ci-dessous s'écarte
                // ne serait-ce qu'un peu de la vraie hauteur du texte.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: header,
                ),
              ),
              SizedBox(height: metrics.gap),
              Expanded(child: chart),
            ],
          );
        },
      ),
    );
  }
}
