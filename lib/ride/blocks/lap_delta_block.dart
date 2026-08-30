import 'package:flutter/material.dart';

import '../../recording/ride_recorder.dart';
import 'block_card.dart';

/// Le tour en cours comparé au tour précédent — voir `LapDeltaBlock`
/// (`dashboard_block.dart`).
///
/// Toujours les deux derniers tours de la série manuelle (`'default'`, celle
/// qu'ouvre un bouton « Marquer un tour » sans série précisée) : le tour
/// encore ouvert et celui d'avant. Les écarts portent sur des moyennes
/// (vitesse, puissance, cardio), qui ont un sens même à mi-tour —
/// contrairement à la durée ou la distance cumulées, qui ne feraient que
/// rattraper le tour précédent.
class LapDeltaCard extends StatelessWidget {
  const LapDeltaCard({
    super.key,
    required this.recorder,
    this.color,
    this.textColor,
  });

  final RideRecorder recorder;
  final Color? color;
  final Color? textColor;

  static const _series = 'default';
  static const _title = 'Tour vs précédent';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: recorder,
      builder: (context, _) {
        final laps = recorder.lapsOf(_series);
        if (laps.length < 2) {
          return BlockCard(
            title: _title,
            lines: const ['Pas de tour précédent.'],
            color: color,
            textColor: textColor,
          );
        }

        final current = laps.last;
        final previous = laps[laps.length - 2];
        final rows = <StatRow>[
          if (_row('Vitesse', current.stats.avgSpeedMps, previous.stats.avgSpeedMps,
              scale: 3.6, decimals: 1) case final row?)
            row,
          if (_row('Puissance', current.stats.avgPower?.toDouble(),
              previous.stats.avgPower?.toDouble()) case final row?)
            row,
          if (_row('Cardio', current.stats.avgHeartRate?.toDouble(),
              previous.stats.avgHeartRate?.toDouble()) case final row?)
            row,
        ];

        if (rows.isEmpty) {
          return BlockCard(
            title: _title,
            lines: const ['Pas de capteur.'],
            color: color,
            textColor: textColor,
          );
        }

        return StatCard(
          title: _title,
          rows: rows,
          color: color,
          textColor: textColor,
        );
      },
    );
  }

  /// Une ligne « valeur du tour · écart signé au précédent », ou `null` si
  /// l'un des deux tours n'a pas cette mesure (capteur absent, tour trop
  /// court).
  static StatRow? _row(
    String label,
    double? current,
    double? previous, {
    double scale = 1,
    int decimals = 0,
  }) {
    if (current == null || previous == null) return null;
    final cur = current * scale;
    final delta = cur - previous * scale;
    final sign = delta >= 0 ? '+' : '−';
    final magnitude = delta.abs().toStringAsFixed(decimals).replaceAll('.', ',');
    final value = cur.toStringAsFixed(decimals).replaceAll('.', ',');
    return StatRow(label, '$value  ($sign$magnitude)');
  }
}
