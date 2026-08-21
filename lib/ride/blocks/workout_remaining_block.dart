import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../dashboard/block_density.dart';
import '../../recording/ride_recorder.dart';
import '../../training_program/training_program.dart';
import '../../ui/formats.dart';
import '../../ui/zone_colors.dart';
import 'block_card.dart';

/// Le temps restant avant le prochain jalon du programme d'entraînement actif.
///
/// Même source que [WorkoutSegmentCard] — [RideRecorder.activeWorkout]/
/// [RideRecorder.workoutElapsed], recalculé à chaque rebuild
/// ([TrainingProgram.remainingAt]) plutôt que lu depuis un curseur. Trois
/// états : un tiret sans programme actif, « Terminé » une fois le dernier
/// jalon dépassé, le compte à rebours sinon ([formatDuration] : `mm:ss`,
/// `h:mm:ss` au-delà d'une heure).
class WorkoutRemainingCard extends StatelessWidget {
  const WorkoutRemainingCard({super.key, required this.recorder, this.color, this.textColor});

  final RideRecorder recorder;

  /// Fond/texte réglés dans l'éditeur — voir [DashboardBlock.color]/
  /// [DashboardBlock.textColor]. À défaut, les couleurs du tronçon en cours
  /// ([WorkoutMilestone.color]/[textColor]) font foi — même précédence que
  /// [WorkoutSegmentCard], pour que les deux cases se lisent comme le même
  /// tronçon.
  final Color? color;
  final Color? textColor;

  static const _title = 'Restant';
  static const _naturalWidth = 180.0;
  static const _figureSize = 34.0;

  static const _icon = FontAwesomeIcons.stopwatch;
  static const _finished = 'Terminé';

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: recorder,
        builder: (context, _) {
          final program = recorder.activeWorkout;
          final elapsed = recorder.workoutElapsed;
          final milestone = program != null && elapsed != null ? program.milestoneAt(elapsed) : null;
          final remaining = program != null && elapsed != null ? program.remainingAt(elapsed) : null;

          final background = color ?? milestone?.color;
          final ink = textColor ??
              milestone?.textColor ??
              (background == null ? Colors.white : foregroundOf(background));
          const metrics = BlockMetrics.natural;

          final label = program == null ? '—' : (remaining == null ? _finished : formatDuration(remaining));

          return BlockSurface(
            background: background,
            child: SizedBox(
              width: _naturalWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _title.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: ink.withValues(alpha: 0.7), fontSize: metrics.titleSize),
                  ),
                  SizedBox(height: metrics.gap * 0.6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      FaIcon(_icon, size: metrics.iconSize, color: ink.withValues(alpha: 0.85)),
                      SizedBox(width: metrics.gap * 0.6),
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: ink, fontSize: _figureSize, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
}
