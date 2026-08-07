import 'package:flutter/material.dart';

import '../../dashboard/block_density.dart';
import '../../dashboard/dashboard_block.dart';
import '../../recording/ride_recorder.dart';
import '../../recording/ride_stats.dart';
import 'block_card.dart';

/// Les moyennes de la sortie : cardio, puissance, cadence, vitesse.
///
/// Tout vient de [RideRecorder] — hors enregistrement il n'y a **rien** à
/// afficher, et le bloc le dit plutôt que d'exhiber des zéros.
///
/// Quatre cartes de même forme, deux par deux : chacune une mesure, et sous son
/// titre les trois chiffres qu'on lui demande — moyen, minimum, maximum —
/// alignés en deux colonnes. Une mesure se lit alors d'un coup d'œil au lieu de
/// se reconstituer de trois phrases dispersées entre deux cartes.
///
/// Le dénivelé et la dépense ont quitté ce bloc en même temps : ce ne sont pas
/// des moyennes, ils n'ont ni minimum ni maximum, et le catalogue les sert déjà
/// en cellule (`MetricId.ascent`, `MetricId.calories`) — comme la puissance
/// normalisée (`MetricId.powerNp`).
///
/// Le mode choisi (`cards`/`list`) est un **ordre**, plus un plafond : le
/// profil qui a demandé les quatre cartes les obtient toujours, quitte à ce
/// que [ScaleToFit] les réduise pour tenir dans une case étroite.
class AveragesCard extends StatelessWidget {
  const AveragesCard({
    super.key,
    required this.recorder,
    this.mode = AveragesMode.cards,
    this.statsOverride,
  });

  final RideRecorder recorder;
  final AveragesMode mode;

  /// Cible d'autres agrégats que ceux de la sortie entière — ceux d'un tour,
  /// par exemple (`RideLap.stats`). `recorder` reste nécessaire même alors :
  /// c'est encore lui qui dit si la sortie est active.
  final RideStats? statsOverride;

  /// La largeur à laquelle les quatre cartes se construisent avant mise à
  /// l'échelle. Fixe et non celle de la case — [ScaleToFit] la ramène à la
  /// case réelle.
  static const _naturalWidth = 280.0;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: recorder,
        builder: (context, _) => _paint(),
      );

  Widget _paint() {
    if (!recorder.isActive) {
      return const BlockCard(
        title: 'Sortie non lancée',
        lines: ['Les moyennes se remplissent dès le départ.'],
      );
    }

    final stats = statsOverride ?? recorder.stats;

    final cards = [
      _Stat('Cardio', 'bpm', _or(stats.avgHeartRate), _or(stats.minHeartRate),
          _or(stats.maxHeartRate)),
      _Stat('Puissance', 'W', _or(stats.avgPower), _or(stats.minPower),
          _or(stats.maxPower)),
      _Stat('Cadence', 'tr/min', _or(stats.avgCadence), _or(stats.minCadence),
          _or(stats.maxCadence)),
      _Stat('Vitesse', 'km/h', _kmh(stats.avgSpeedMps), _kmh(stats.minSpeedMps),
          _kmh(stats.maxSpeedMps)),
    ];

    if (mode == AveragesMode.list) {
      // En liste, les trois chiffres tiennent sur la ligne de leur mesure :
      // quatre lignes plutôt que douze.
      return BlockCard(
        title: 'Moyennes',
        lines: [for (final card in cards) card.line],
      );
    }

    // `ScaleToFit` et non `BlockSurface` : les quatre cartes ont déjà chacune
    // leur propre fond, la grille elle-même n'en a pas besoin d'un
    // supplémentaire — seulement de la mise à l'échelle qui la fait tenir.
    return ScaleToFit(
      child: SizedBox(
        width: _naturalWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _row(cards[0], cards[1]),
            SizedBox(height: BlockMetrics.natural.gap),
            _row(cards[2], cards[3]),
          ],
        ),
      ),
    );
  }

  /// Deux cartes côte à côte. Les deux ont désormais toujours la même forme —
  /// un titre, trois lignes — donc pas besoin de mesurer laquelle est la plus
  /// haute pour aligner l'autre dessus.
  static Widget _row(_Stat left, _Stat right) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: left.card()),
          SizedBox(width: BlockMetrics.natural.gap),
          Expanded(child: right.card()),
        ],
      );

  static String _or(num? value) => value?.toString() ?? '—';

  /// Les mêmes km/h que le catalogue (`MetricId`) : une décimale, la virgule
  /// française. Une sortie ne change pas de chiffres selon la case qui la
  /// montre.
  static String _kmh(double? metresPerSecond) => metresPerSecond == null
      ? '—'
      : (metresPerSecond * 3.6).toStringAsFixed(1).replaceAll('.', ',');
}

/// Une mesure et ses trois chiffres, dans les deux mises en page du bloc.
///
/// Le même objet sert la carte et la ligne : les deux modes ne peuvent donc pas
/// montrer des chiffres différents de la même sortie.
@immutable
class _Stat {
  const _Stat(this.name, this.unit, this.avg, this.min, this.max);

  final String name;
  final String unit;
  final String avg;
  final String min;
  final String max;

  Widget card() => StatCard(
        title: '$name ($unit)',
        rows: [
          StatRow('Moyen', avg),
          StatRow('Min', min),
          StatRow('Max', max),
        ],
      );

  String get line => '$name $avg $unit ($min – $max)';
}
