import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../account/rider_profile.dart';
import '../../account/rider_profile_store.dart';
import '../../dashboard/block_density.dart';
import '../../dashboard/dashboard_block.dart';
import '../../recording/ride_metric_track.dart';
import '../../recording/ride_recorder.dart';
import '../../ui/zone_colors.dart' show foregroundOf;
import '../widgets/metric_trend_graph.dart';
import 'block_card.dart';

/// La tendance d'une mesure de capteur (cardio, puissance) dans le temps —
/// toute la sortie, ou seulement les [windowS] dernières secondes, voir
/// `RideMetricTrack` pour les deux vues qu'elle garde en parallèle. L'aire
/// sous la courbe est peinte aux couleurs de zone du cycliste, même table que
/// [ZonesCard]/le bandeau (`zoneColorOf`) : on doit reconnaître un pic avant
/// de déchiffrer le chiffre.
///
/// Même composant pour les deux mesures ([source]), même raison que
/// [ZonesCard] : les deux graphiques sont le même code à deux jeux de
/// données près, l'icône de la ligne courante mise à part n'ayant même pas
/// lieu d'être ici (rien ne distingue une ligne « courante » sur une courbe
/// continue).
///
/// Se pose aussi bien sur une page de mesures ordinaire que sur une page
/// Tours (`LapListPage._block`) : sur la sortie entière par défaut, ou sur le
/// tour affiché quand [trackOverride] est réglé — voir `LapMetricTrendBlock`
/// et `RideLap.heartRateTrack`/`powerTrack` (`recording/ride_lap.dart`), même
/// principe que [ZonesCard.statsOverride]/[AveragesCard.statsOverride] pour
/// leurs variantes « Lap ».
class MetricTrendCard extends StatelessWidget {
  const MetricTrendCard({
    super.key,
    required this.source,
    required this.recorder,
    required this.riderProfile,
    this.windowS,
    this.trackOverride,
    this.color,
    this.textColor,
  });

  final ZonesSource source;
  final RideRecorder recorder;
  final RiderProfileStore riderProfile;

  /// `null` : toute la sortie ([RideMetricTrack.points], rééchantillonnée).
  /// Sinon, les `windowS` dernières secondes enregistrées
  /// ([RideMetricTrack.recent]), à pleine résolution. Sans effet quand
  /// [trackOverride] est réglé — le tour ouvert tient déjà lieu de fenêtre.
  final int? windowS;

  /// Cible une autre piste que celle de la sortie entière — celle d'un tour,
  /// par exemple (`RideLap.heartRateTrack`/`powerTrack`). `recorder` reste
  /// nécessaire même alors : c'est encore lui qui dit si la sortie est
  /// active, même raison que [ZonesCard.statsOverride].
  final RideMetricTrack? trackOverride;

  final Color? color;
  final Color? textColor;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([recorder, riderProfile]),
        builder: (context, _) => _paint(),
      );

  Widget _paint() {
    final hr = source == ZonesSource.hr;
    final title = hr ? 'Tendance cardio' : 'Tendance puissance';

    // Tout vient de l'enregistreur : hors enregistrement il n'y a rien à
    // afficher, même convention que [ZonesCard]/[PowerCurveCard].
    if (!recorder.isActive) {
      return BlockCard(
        title: title,
        lines: [
          hr
              ? 'La tendance cardio se remplit dès le départ.'
              : 'La tendance de puissance se remplit dès le départ.',
        ],
        color: color,
        textColor: textColor,
      );
    }

    final trackOverride = this.trackOverride;
    final track = trackOverride ?? (hr ? recorder.heartRateTrack : recorder.powerTrack);
    final windowS = this.windowS;
    final points = trackOverride != null || windowS == null ? track.points : track.recent(windowS);

    // Moins de deux points : trop tôt pour un tracé (sortie qui vient de
    // démarrer), fenêtre récente encore vide (capteur qui vient de
    // décrocher), ou capteur jamais mesuré — un seul message pour les trois,
    // même repli que `PowerCurveCard` en mode graphique : ce qui compte pour
    // le cycliste est « pas encore de courbe à voir », pas laquelle des trois
    // raisons s'applique.
    if (points.length < 2) {
      return BlockCard(
        title: title,
        lines: const ['Pas encore assez de recul pour un graphique.'],
        color: color,
        textColor: textColor,
      );
    }

    final profile = riderProfile.profile;
    return _MetricTrendChartCard(
      title: title,
      points: points,
      zones: hr ? profile.hrZones : profile.powerZones,
      color: color,
      textColor: textColor,
    );
  }
}

/// Le graphique seul, plein cadre — même patron que `_PowerCurveChartCard`
/// (`power_curve_block.dart`) et `ElevationProfileSurface` : un graphique n'a
/// pas de forme propre, il doit toujours remplir la largeur de sa case.
class _MetricTrendChartCard extends StatelessWidget {
  const _MetricTrendChartCard({
    required this.title,
    required this.points,
    required this.zones,
    this.color,
    this.textColor,
  });

  final String title;
  final List<MetricTrackPoint> points;
  final List<TrainingZone> zones;
  final Color? color;
  final Color? textColor;

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
      title.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: ink.withValues(alpha: 0.7), fontSize: metrics.titleSize),
    );

    final chart = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: MetricTrendGraph(points: points, zones: zones),
    );

    return Container(
      width: double.infinity,
      // Jamais `height: double.infinity` — même piège que dans
      // `elevation_profile_surface.dart` : posée dans une page qui défile,
      // cette case ne borne pas la hauteur.
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
