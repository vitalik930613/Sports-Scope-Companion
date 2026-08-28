import 'package:flutter/material.dart';

import '../account/rider_profile_store.dart';
import '../dashboard/dashboard_block.dart' show ZonesMode;
import '../ride/blocks/block_card.dart';
import '../ride/blocks/elevation_profile_surface.dart';
import '../ride/blocks/lap_summary_block.dart';
import '../ride/blocks/zones_block.dart';
import '../ride/climb_profile.dart' show climbLapSeries;
import '../ride/zone_time.dart';
import '../training/ride_load.dart';
import '../ui/formats.dart';
import '../ui/zone_colors.dart';
import 'elevation_profile_point.dart';
import 'ride_history.dart';
import 'ride_lap.dart';
import 'ride_session.dart';
import 'ride_stats.dart';
import 'ride_store.dart';
import 'ride_track_map.dart';
import 'track_point.dart';

/// Le détail d'une sortie déjà enregistrée : le bilan, le profil d'altitude,
/// la répartition par zones et les tours — tel qu'on l'aurait vu en roulant,
/// mais figé, relu depuis le JSONL plutôt que tenu à jour par un
/// `RideRecorder` vivant.
///
/// Les widgets de rendu (`LapSummaryCard`, `ElevationProfileSurface`,
/// `ZoneBreakdown`) sont ceux du tableau de bord en direct : aucun d'eux ne
/// dépend d'un `RideRecorder`, seulement des agrégats (`RideStats`,
/// `RideLap`) qu'on leur passe — cet écran les recalcule une fois plutôt
/// qu'à chaque tic.
class RideDetailPage extends StatefulWidget {
  const RideDetailPage({
    super.key,
    required this.session,
    required this.store,
    required this.riderProfile,
  });

  final RideSession session;
  final RideStore store;
  final RiderProfileStore riderProfile;

  @override
  State<RideDetailPage> createState() => _RideDetailPageState();
}

class _RideDetailPageState extends State<RideDetailPage> {
  RideStats? _stats;
  Map<String, List<RideLap>> _lapSeries = const {};
  List<ElevationProfilePoint> _elevationPoints = const [];
  List<double> _segmentGrades = const [];
  List<TrackPoint> _points = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final points = await widget.store.points(widget.session.id);
    final elevation = elevationTrackOf(points).points;

    if (!mounted) return;
    setState(() {
      _stats = RideStats.of(points);
      _lapSeries = lapSeriesHistoryOf(points);
      _elevationPoints = elevation;
      _segmentGrades = localGradesOf(elevation);
      _points = points;
    });
  }

  /// Au moins deux positions : en dessous, il n'y a rien à tracer — même
  /// convention que le profil d'altitude ([_elevationPoints]), qui s'efface
  /// aussi plutôt que de montrer un graphique vide sur une sortie déjà
  /// terminée.
  bool get _hasTrack =>
      _points.where((point) => point.hasPosition).length >= 2;

  @override
  Widget build(BuildContext context) {
    final stats = _stats;

    return Scaffold(
      appBar: AppBar(title: Text(formatDateTime(widget.session.startedAt))),
      body: stats == null
          ? const Center(child: CircularProgressIndicator())
          : ListenableBuilder(
              listenable: widget.riderProfile,
              builder: (context, _) => ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_hasTrack) ...[
                    SizedBox(height: 220, child: RideTrackMap(points: _points)),
                    const SizedBox(height: 16),
                  ],
                  _overview(stats),
                  if (_elevationPoints.length >= 2) ...[
                    const SizedBox(height: 16),
                    SizedBox(height: 220, child: _elevation(stats)),
                  ],
                  ..._zoneSections(stats),
                  ..._lapSections(),
                ],
              ),
            ),
    );
  }

  Widget _overview(RideStats stats) {
    final profile = widget.riderProfile.profile;
    final tss = rideTss(stats, profile)?.tss;

    Color? hrColor(int? bpm) =>
        bpm == null ? null : zoneColorOf(profile.hrZoneFor(bpm)?.key);
    Color? powerColor(int? watts) =>
        watts == null ? null : zoneColorOf(profile.powerZoneFor(watts)?.key);

    final rows = [
      StatRow('Durée', formatDurationHm(widget.session.moving)),
      StatRow('Distance', formatDistanceKm(stats.distanceM)),
      StatRow('D+', '${stats.ascentM.round()} m'),
      StatRow('D-', '${stats.descentM.round()} m'),
      StatRow('Vitesse moy.', _kmh(stats.avgSpeedMps)),
      StatRow('Vitesse max', _kmh(stats.maxSpeedMps)),
      StatRow('Cardio moy.', _bpm(stats.avgHeartRate),
          background: hrColor(stats.avgHeartRate)),
      StatRow('Cardio max', _bpm(stats.maxHeartRate),
          background: hrColor(stats.maxHeartRate)),
      StatRow('Puissance moy.', _watts(stats.avgPower),
          background: powerColor(stats.avgPower)),
      StatRow('Puissance norm.', _watts(stats.normalizedPowerW),
          background: powerColor(stats.normalizedPowerW)),
      StatRow('Puissance max', _watts(stats.maxPower),
          background: powerColor(stats.maxPower)),
      StatRow('Cadence moy.',
          stats.avgCadence == null ? '—' : '${stats.avgCadence} rpm'),
      StatRow('Calories', stats.calories?.toString() ?? '—'),
      StatRow('TSS', tss == null ? '—' : tss.round().toString()),
    ];

    return StatCard(title: 'Bilan de la sortie', rows: rows);
  }

  Widget _elevation(RideStats stats) => ElevationProfileSurface(
        title: "Profil d'altitude",
        headline: '+${stats.ascentM.round()} m',
        aside: formatDistance(stats.distanceM),
        grade: stats.gradePercent ?? 0,
        points: _elevationPoints,
        segmentGrades: _segmentGrades,
        // Rien de « restant » à distinguer sur une sortie déjà terminée —
        // même choix que `AltitudeProfileCard._rideCard` sur une sortie libre.
        ratio: null,
      );

  /// Une carte par mesure (cardio, puissance), seulement si le cycliste a des
  /// zones **et** que quelque chose a été mesuré dans cette sortie — pas
  /// d'état vide ici, contrairement au direct : sur une sortie déjà finie, une
  /// section vide n'a rien à annoncer qu'un « pas encore » qui ne viendra
  /// jamais.
  List<Widget> _zoneSections(RideStats stats) {
    final profile = widget.riderProfile.profile;
    final sections = <Widget>[];

    final hrShares = zoneSharesOf(
      stats.hrHistogram,
      bucket: RideStats.hrBucketBpm,
      zones: profile.hrZones,
      perPoint: const Duration(seconds: 1),
    );
    if (hrShares.isNotEmpty) {
      sections.addAll([
        const SizedBox(height: 16),
        ZoneBreakdown(
          title: 'Temps par zone cardio',
          shares: hrShares,
          currentIcon: Icons.favorite,
          mode: ZonesMode.bar,
        ),
      ]);
    }

    final powerShares = zoneSharesOf(
      stats.powerHistogram,
      bucket: RideStats.powerBucketW,
      zones: profile.powerZones,
      perPoint: const Duration(seconds: 1),
    );
    if (powerShares.isNotEmpty) {
      sections.addAll([
        const SizedBox(height: 16),
        ZoneBreakdown(
          title: 'Temps par zone de puissance',
          shares: powerShares,
          currentIcon: Icons.bolt,
          mode: ZonesMode.bar,
        ),
      ]);
    }

    return sections;
  }

  List<Widget> _lapSections() {
    if (_lapSeries.isEmpty) return const [];

    final nonClimbSeriesCount =
        _lapSeries.keys.where((key) => key != climbLapSeries).length;
    final sections = <Widget>[];

    for (final entry in _lapSeries.entries) {
      final isClimbs = entry.key == climbLapSeries;
      final title = isClimbs
          ? 'Cols'
          : nonClimbSeriesCount > 1
              ? 'Tours (${entry.key})'
              : 'Tours';

      sections.addAll([
        const SizedBox(height: 16),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        SizedBox(
          height: 200,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: entry.value.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Tour ${index + 1}',
                    style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 4),
                // Bornée en largeur et en hauteur : c'est ce qui fait
                // détecter à `ScaleToFit` (`BlockSurface`) qu'il doit
                // réduire la carte plutôt que de la laisser à sa taille
                // naturelle, qui pourrait déborder de la rangée.
                SizedBox(
                  width: 220,
                  height: 176,
                  child: LapSummaryCard(
                    lap: entry.value[index],
                    riderProfile: widget.riderProfile,
                  ),
                ),
              ],
            ),
          ),
        ),
      ]);
    }

    return sections;
  }

  static String _bpm(int? value) => value == null ? '—' : '$value bpm';
  static String _watts(int? value) => value == null ? '—' : '$value W';

  static String _kmh(double? metresPerSecond) => metresPerSecond == null
      ? '—'
      : '${(metresPerSecond * 3.6).toStringAsFixed(1).replaceAll('.', ',')} km/h';
}
