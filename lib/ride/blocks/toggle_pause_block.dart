import 'package:flutter/material.dart';

import '../../recording/ride_recorder.dart';
import 'action_button.dart';

/// Suspendre ou reprendre l'enregistrement, en case de bandeau ou d'encoche —
/// même geste combiné que [ToggleWorkoutControl] pour l'entraînement :
/// l'état de [recorder] décide seul lequel des deux gestes le bouton pose.
///
/// Pas de bouton d'arrêt ici, même raison que [RecordingControl]
/// (`recording_block.dart`) : une pause ne perd rien, un arrêt clôt la
/// sortie, et ce n'est pas un geste à portée du pouce en roulant.
///
/// Hors enregistrement (`RecorderState.idle`), grisé plutôt qu'absent :
/// démarrer se fait depuis l'écran des capteurs ou [RecordingControl], une
/// case de bandeau n'a pas la place pour l'attente GPS que celui-ci affiche
/// au départ — voir `RecordingControl._StartRecordingButton`.
class TogglePauseControl extends StatelessWidget {
  const TogglePauseControl({
    super.key,
    required this.recorder,
    this.compact = false,
    this.color,
    this.textColor,
  });

  final RideRecorder recorder;
  final bool compact;
  final Color? color;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: recorder,
      builder: (context, _) => recorder.state == RecorderState.paused
          ? DashboardActionButton(
              icon: Icons.play_arrow,
              label: 'Reprendre l\'enregistrement',
              compact: compact,
              onPressed: recorder.resume,
              color: color,
              textColor: textColor,
            )
          : DashboardActionButton(
              icon: Icons.pause,
              label: 'Mettre en pause',
              compact: compact,
              onPressed: recorder.state == RecorderState.recording
                  ? recorder.pause
                  : null,
              color: color,
              textColor: textColor,
            ),
    );
  }
}
