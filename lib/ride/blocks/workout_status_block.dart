import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../dashboard/block_density.dart';
import '../../dashboard/companion_icons.dart';
import '../../dashboard/dashboard_block.dart' show WorkoutStatusMode;
import '../../recording/ride_recorder.dart';
import '../../training_program/training_program.dart';
import '../../ui/formats.dart';
import '../../ui/zone_colors.dart';
import 'block_card.dart';

/// Le tronçon d'entraînement en cours et le temps restant avant le prochain
/// jalon, dans une seule carte — [WorkoutSegmentCard] et
/// [WorkoutRemainingCard] fondues, pour la page qui n'a la place que d'une
/// case mais veut les deux informations plutôt que choisir entre elles.
///
/// Deux mises en page ([WorkoutStatusMode]) : [WorkoutStatusMode.full] sur
/// deux lignes (le tronçon, puis le temps restant, chacun son titre), ou
/// [WorkoutStatusMode.line] fondues sur une seule — icône, nom, temps
/// restant, même contenu que [WorkoutBandTile] au langage visuel d'une
/// carte de page.
///
/// Même source ([RideRecorder.activeWorkout]/[RideRecorder.workoutElapsed],
/// `TrainingProgram.milestoneAt`/`remainingAt`) et même précédence de
/// couleur (réglage du bloc, puis [WorkoutMilestone.color]/[textColor], puis
/// repli) que les deux cartes d'origine — elles restent posables
/// séparément, celle-ci n'est qu'une troisième façon de lire le même état.
class WorkoutStatusCard extends StatelessWidget {
  const WorkoutStatusCard({
    super.key,
    required this.recorder,
    required this.mode,
    this.color,
    this.textColor,
  });

  final RideRecorder recorder;
  final WorkoutStatusMode mode;
  final Color? color;
  final Color? textColor;

  static const _naturalWidth = 220.0;
  static const _lineWidth = 260.0;
  static const _figureSize = 24.0;
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

          final name = milestone?.segmentName;
          final segmentLabel = (name == null || name.isEmpty) ? '—' : name;
          final remainingLabel =
              program == null ? '—' : (remaining == null ? _finished : formatDuration(remaining));
          final icon = workoutMilestoneIconFor(milestone?.icon);

          return BlockSurface(
            background: background,
            child: SizedBox(
              width: mode == WorkoutStatusMode.line ? _lineWidth : _naturalWidth,
              child: mode == WorkoutStatusMode.line
                  ? _line(icon, segmentLabel, remainingLabel, ink, metrics)
                  : _full(icon, segmentLabel, remainingLabel, ink, metrics),
            ),
          );
        },
      );

  /// [WorkoutStatusMode.full] : le tronçon, puis le temps restant, chacun sa
  /// ligne — mêmes rangées que [WorkoutSegmentCard]/[WorkoutRemainingCard].
  Widget _full(FaIconData icon, String segment, String remaining, Color ink, BlockMetrics metrics) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _row(icon, segment, ink, metrics),
          SizedBox(height: metrics.gap * 0.6),
          _row(FontAwesomeIcons.stopwatch, remaining, ink, metrics),
        ],
      );

  /// [WorkoutStatusMode.line] : icône, nom du tronçon et temps restant sur
  /// une seule ligne — le nom cède la place en premier (`Expanded` +
  /// ellipse), le temps ne tronque jamais.
  Widget _line(FaIconData icon, String segment, String remaining, Color ink, BlockMetrics metrics) => Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          FaIcon(icon, size: metrics.iconSize, color: ink.withValues(alpha: 0.85)),
          SizedBox(width: metrics.gap * 0.6),
          Expanded(
            child: Text(
              segment,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: ink, fontSize: _figureSize, fontWeight: FontWeight.w500),
            ),
          ),
          SizedBox(width: metrics.gap),
          Text(
            remaining,
            maxLines: 1,
            style: TextStyle(color: ink, fontSize: _figureSize, fontWeight: FontWeight.w500),
          ),
        ],
      );

  Widget _row(FaIconData icon, String label, Color ink, BlockMetrics metrics) => Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          FaIcon(icon, size: metrics.iconSize, color: ink.withValues(alpha: 0.85)),
          SizedBox(width: metrics.gap * 0.6),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: ink, fontSize: _figureSize, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      );
}
