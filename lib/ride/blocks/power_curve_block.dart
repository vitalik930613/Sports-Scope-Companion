import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../account/rider_profile.dart';
import '../../account/rider_profile_store.dart';
import '../../dashboard/block_density.dart';
import '../../dashboard/dashboard_block.dart';
import '../../recording/ride_recorder.dart';
import '../../recording/ride_stats.dart';
import '../../ui/zone_colors.dart';
import '../widgets/power_curve_graph.dart';
import 'block_card.dart';

/// La courbe de puissance : la meilleure moyenne tenue depuis le départ, pour
/// chacune des durées de [RideStats.powerCurveDurationsS] (5 s à 90 min).
///
/// Tout vient de [RideRecorder] — hors enregistrement il n'y a **rien** à
/// afficher, même convention que [AveragesCard]/[ZonesCard]. Deux mises en
/// forme du même contenu ([PowerCurveMode]) : un tableau qui se lit chiffre
/// par chiffre, ou le même chiffres en graphique — l'un plus lisible à
/// l'arrêt, l'autre plus parlant pour voir la forme du profil (sprinteur vs.
/// rouleur) d'un coup d'œil.
class PowerCurveCard extends StatelessWidget {
  const PowerCurveCard({
    super.key,
    required this.recorder,
    required this.riderProfile,
    this.mode = PowerCurveMode.table,
    this.statsOverride,
    this.color,
    this.textColor,
  });

  final RideRecorder recorder;

  /// Les seuils du cycliste : c'est d'eux que sort la zone qui colore chaque
  /// meilleure moyenne, en mode tableau — même source que [AveragesCard].
  final RiderProfileStore riderProfile;

  final PowerCurveMode mode;

  /// Cible d'autres agrégats que ceux de la sortie entière — voir
  /// [AveragesCard.statsOverride]. `recorder` reste nécessaire même alors :
  /// c'est encore lui qui dit si la sortie est active.
  final RideStats? statsOverride;

  final Color? color;
  final Color? textColor;

  static const _title = 'Courbe de puissance';

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([recorder, riderProfile]),
        builder: (context, _) => _paint(),
      );

  Widget _paint() {
    if (!recorder.isActive) {
      return BlockCard(
        title: 'Sortie non lancée',
        lines: const ['La courbe de puissance se remplit dès le départ.'],
        color: color,
        textColor: textColor,
      );
    }

    final stats = statsOverride ?? recorder.stats;
    if (!stats.hasPower) {
      return BlockCard(
        title: _title,
        lines: const ['Nécessite un capteur de puissance.'],
        color: color,
        textColor: textColor,
      );
    }

    if (mode == PowerCurveMode.chart) {
      final points = [
        for (final duration in RideStats.powerCurveDurationsS)
          if (stats.powerCurveW[duration] case final watts?)
            PowerCurvePoint(duration, watts),
      ];
      if (points.length < 2) {
        return BlockCard(
          title: _title,
          lines: const ['Pas encore assez de recul pour un graphique.'],
          color: color,
          textColor: textColor,
        );
      }
      return _PowerCurveChartCard(points: points, color: color, textColor: textColor);
    }

    final profile = riderProfile.profile;
    return StatCard(
      title: _title,
      unit: 'W',
      icon: Icons.bolt,
      rows: [
        for (final duration in RideStats.powerCurveDurationsS)
          StatRow(
            _durationLabel(duration),
            _or(stats.powerCurveW[duration]),
            background: _zoneBg(profile.powerZoneFor, stats.powerCurveW[duration]),
          ),
      ],
      color: color,
      textColor: textColor,
    );
  }

  static Color? _zoneBg(TrainingZone? Function(num) zoneFor, num? value) =>
      value == null ? null : zoneColorOf(zoneFor(value)?.key);

  static String _or(int? value) => value?.toString() ?? '—';

  /// « 5 s »… « 90 min » : toutes nos durées tombent rond sur la minute au-delà
  /// de 60 s, pas besoin d'un format plus général.
  static String _durationLabel(int seconds) =>
      seconds < 60 ? '$seconds s' : '${seconds ~/ 60} min';
}

/// Le graphique seul, plein cadre — même raison que `ElevationProfileSurface`
/// (`ride/blocks/elevation_profile_surface.dart`) : un graphique n'a pas de
/// forme propre, il doit toujours remplir la largeur de sa case, ce que
/// [ScaleToFit]/[BlockSurface] ne garantit pas (ils préservent le rapport
/// largeur/hauteur naturel, pensé pour un chiffre). Pas d'abstraction commune
/// avec elle : son en-tête porte un gain, une distance, une pente — rien de
/// tout ça ici.
class _PowerCurveChartCard extends StatelessWidget {
  const _PowerCurveChartCard({required this.points, this.color, this.textColor});

  final List<PowerCurvePoint> points;
  final Color? color;
  final Color? textColor;

  static const _title = 'Courbe de puissance';

  /// Hauteur naturelle du titre seul (une ligne, `metrics.titleSize`).
  static const _naturalHeaderHeight = 20.0;
  static const _minHeaderHeight = 12.0;
  static const _minChartHeight = 32.0;

  /// Hauteur du graphique hors contrainte de hauteur (page qui défile).
  static const _chartHeight = 140.0;

  @override
  Widget build(BuildContext context) {
    const metrics = BlockMetrics.natural;
    final ink = textColor ?? (color == null ? Colors.white : foregroundOf(color!));

    final header = Text(
      _title.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: ink.withValues(alpha: 0.7), fontSize: metrics.titleSize),
    );

    final chart = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: PowerCurveGraph(points: points),
    );

    return Container(
      width: double.infinity,
      // Jamais `height: double.infinity` — voir la même note dans
      // `elevation_profile_surface.dart` : posée dans une page qui défile,
      // cette case ne borne pas la hauteur, et un `Container` qui la force
      // quand même reçoit une contrainte tendue à l'infini, invalide.
      padding: EdgeInsets.all(metrics.padding),
      decoration: BoxDecoration(
        color: color ?? BlockCard.background,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.hardEdge,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (!constraints.hasBoundedHeight) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                header,
                SizedBox(height: metrics.gap),
                SizedBox(height: _chartHeight, child: chart),
              ],
            );
          }

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
