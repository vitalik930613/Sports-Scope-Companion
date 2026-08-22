import 'package:flutter/material.dart';

import '../../dashboard/dashboard_block.dart';
import '../../recording/ride_recorder.dart';
import 'action_button.dart';

/// Démarrer un programme d'entraînement, ou détacher celui qui tourne —
/// combinés en un seul bouton, même principe que [RouteControl] pour la
/// navigation : [recorder] dit ce qui est déjà en cours, le bouton pose donc
/// toujours le geste qui reste à faire plutôt que de laisser choisir entre
/// les deux.
///
/// Écoute [recorder] directement plutôt qu'un booléen figé au rendu — même
/// patron que [WorkoutSegmentCard] (`workout_segment_block.dart`) — pour
/// suivre un programme démarré ou arrêté ailleurs (menu ⋮, FAB de l'accueil)
/// sans attendre de reconstruire toute la page.
class ToggleWorkoutControl extends StatelessWidget {
  const ToggleWorkoutControl({
    super.key,
    required this.recorder,
    required this.onChooseWorkout,
    this.mode = ToggleWorkoutMode.full,
    this.color,
    this.textColor,
  });

  final RideRecorder recorder;

  /// Ouvre le choix de programme (`WorkoutPickerSheet`) — voir
  /// `RideShellPage._chooseWorkout`. Toujours utilisable, contrairement à
  /// [RouteControl.onChooseRoute] : un programme se démarre aussi bien sur
  /// home-trainer, sans carte.
  final VoidCallback? onChooseWorkout;

  final ToggleWorkoutMode mode;

  /// Fond/texte réglés dans l'éditeur — voir [DashboardBlock.color]/
  /// [DashboardBlock.textColor].
  final Color? color;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    final compact = mode == ToggleWorkoutMode.compact;

    return ListenableBuilder(
      listenable: recorder,
      builder: (context, _) => recorder.activeWorkout != null
          ? DashboardActionButton(
              icon: Icons.fitness_center,
              barred: true,
              label: 'Retirer l\'entraînement',
              compact: compact,
              onPressed: recorder.stopWorkout,
              color: color,
              textColor: textColor,
            )
          : DashboardActionButton(
              icon: Icons.fitness_center,
              label: 'Choisir un entraînement',
              compact: compact,
              onPressed: onChooseWorkout,
              color: color,
              textColor: textColor,
            ),
    );
  }
}
