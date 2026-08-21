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
  const WorkoutRemainingCard({super.key, required this.recorder, this.upcoming = false, this.color, this.textColor});

  final RideRecorder recorder;

  /// Montre la durée du tronçon qui suivra celui en cours
  /// ([TrainingProgram.nextSegmentDurationAt]) plutôt qu'un compte à rebours
  /// vers son départ — ce tronçon n'a pas encore commencé, rien n'y décompte.
  final bool upcoming;

  /// Fond/texte réglés dans l'éditeur — voir [DashboardBlock.color]/
  /// [DashboardBlock.textColor]. À défaut, les couleurs du tronçon en cours
  /// ([WorkoutMilestone.color]/[textColor]) font foi — même précédence que
  /// [WorkoutSegmentCard], pour que les deux cases se lisent comme le même
  /// tronçon.
  final Color? color;
  final Color? textColor;

  static const _title = 'Restant';
  static const _upcomingTitle = 'Durée à venir';
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
          final milestone = program != null && elapsed != null
              ? (upcoming ? program.nextMilestoneAt(elapsed) : program.milestoneAt(elapsed))
              : null;
          final remaining = program != null && elapsed != null
              ? (upcoming ? program.nextSegmentDurationAt(elapsed) : program.remainingAt(elapsed))
              : null;

          final background = color ?? milestone?.color;
          final ink = textColor ??
              milestone?.textColor ??
              (background == null ? Colors.white : foregroundOf(background));
          const metrics = BlockMetrics.natural;

          // `upcoming` n'a pas de « Terminé » : ce tronçon n'a pas commencé,
          // il n'y a rien à annoncer de fini — juste un tiret quand sa durée
          // n'est pas connue (dernier de la timeline, programme absent).
          final String label;
          if (program == null) {
            label = '—';
          } else if (remaining == null) {
            label = upcoming ? '—' : _finished;
          } else {
            label = formatDuration(remaining);
          }

          return BlockSurface(
            background: background,
            child: SizedBox(
              width: _naturalWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    (upcoming ? _upcomingTitle : _title).toUpperCase(),
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
