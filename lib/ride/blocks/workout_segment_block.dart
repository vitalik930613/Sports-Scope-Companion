import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../dashboard/block_density.dart';
import '../../dashboard/companion_icons.dart';
import '../../recording/ride_recorder.dart';
import '../../training_program/training_program.dart';
import '../../ui/zone_colors.dart';
import 'block_card.dart';

/// Le nom du tronçon d'entraînement en cours, avec son icône.
///
/// Dérivé de [RideRecorder.activeWorkout]/[RideRecorder.workoutElapsed] à
/// chaque rebuild ([TrainingProgram.milestoneAt]) — pas de curseur propre,
/// contrairement à `WorkoutPolicy` (qui ne sert qu'à `RideShellPage`, pour
/// marquer les tours). Sans programme actif, un tiret plutôt qu'une carte qui
/// disparaît : même convention qu'une mesure indisponible.
class WorkoutSegmentCard extends StatelessWidget {
  const WorkoutSegmentCard({super.key, required this.recorder, this.upcoming = false, this.color, this.textColor});

  final RideRecorder recorder;

  /// Montre le tronçon qui suivra celui en cours ([TrainingProgram.
  /// nextMilestoneAt]) plutôt que le tronçon en cours — un aperçu de ce qui
  /// arrive, posable à côté d'une carte qui montre déjà le tronçon en cours.
  final bool upcoming;

  /// Fond/texte réglés dans l'éditeur — voir [DashboardBlock.color]/
  /// [DashboardBlock.textColor]. À défaut, [WorkoutMilestone.color]/
  /// [WorkoutMilestone.textColor] du tronçon affiché (en cours ou suivant)
  /// font foi : le réglage du bloc l'emporte toujours, le jalon n'est qu'un
  /// repli.
  final Color? color;
  final Color? textColor;

  static const _title = 'Tronçon';
  static const _upcomingTitle = 'Suivant';
  static const _naturalWidth = 220.0;
  static const _figureSize = 30.0;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: recorder,
        builder: (context, _) {
          final program = recorder.activeWorkout;
          final elapsed = recorder.workoutElapsed;
          final milestone = program != null && elapsed != null
              ? (upcoming ? program.nextMilestoneAt(elapsed) : program.milestoneAt(elapsed))
              : null;

          final background = color ?? milestone?.color;
          final ink = textColor ??
              milestone?.textColor ??
              (background == null ? Colors.white : foregroundOf(background));
          const metrics = BlockMetrics.natural;

          final name = milestone?.segmentName;
          final label = (name == null || name.isEmpty) ? '—' : name;

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
                      FaIcon(
                        workoutMilestoneIconFor(milestone?.icon),
                        size: metrics.iconSize,
                        color: ink.withValues(alpha: 0.85),
                      ),
                      SizedBox(width: metrics.gap * 0.6),
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 2,
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
