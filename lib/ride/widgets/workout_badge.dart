import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../dashboard/companion_icons.dart';
import '../../training_program/training_program.dart';
import '../../ui/formats.dart';
import '../../ui/zone_colors.dart';

/// La pastille du tronçon en cours d'un programme d'entraînement — nom,
/// icône et temps restant avant le prochain jalon, épinglée en haut d'écran
/// quelle que soit la page (voir `RideShellPage`).
///
/// Même famille que `ClimbBadge`, mais sans état déplié/replié : rien à
/// développer, le nom et le compte à rebours tiennent déjà dans la pastille
/// — c'est le popup de changement (`WorkoutChangePopup`) qui porte l'annonce
/// plus visible, celle-ci reste un repère permanent du coin de l'œil.
class WorkoutBadge extends StatelessWidget {
  const WorkoutBadge({
    super.key,
    required this.milestone,
    this.remaining,
    this.upcoming = false,
  });

  final WorkoutMilestone milestone;

  /// `null` une fois le dernier jalon dépassé (programme terminé), ou quand
  /// [upcoming] est vrai — voir `TrainingProgram.remainingAt`.
  final Duration? remaining;

  /// Aperçu du jalon suivant plutôt que le tronçon en cours — voir
  /// `RideShellPage`, qui la montre sous la pastille courante dans les
  /// [upcomingLead] dernières secondes du tronçon. Pas de compte à rebours
  /// (rien n'a encore commencé) et une opacité réduite, pour ne jamais se
  /// lire comme un second tronçon déjà actif.
  final bool upcoming;

  /// Combien de temps avant la fin du tronçon en cours l'aperçu du suivant
  /// doit paraître.
  static const upcomingLead = Duration(seconds: 5);

  /// Repli quand le jalon n'a pas de couleur propre — un bleu neutre plutôt
  /// que le gris de `ClimbBadge` (dérivé de la pente), rien d'équivalent
  /// n'existe ici à en déduire.
  static const _defaultBackground = Color(0xFF1976D2);
  static const _finished = 'Terminé';

  @override
  Widget build(BuildContext context) {
    final bg = milestone.color ?? _defaultBackground;
    final fg = milestone.textColor ?? foregroundOf(bg);
    final name = milestone.segmentName;
    final label = name.isEmpty ? '—' : name;

    return Opacity(
      opacity: upcoming ? 0.6 : 1,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 4)],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (upcoming) ...[
              Icon(Icons.arrow_downward, size: 13, color: fg),
              const SizedBox(width: 4),
            ],
            FaIcon(workoutMilestoneIconFor(milestone.icon), size: 15, color: fg),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 110),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 15),
              ),
            ),
            if (!upcoming) ...[
              const SizedBox(width: 8),
              Text(
                remaining == null ? _finished : formatDuration(remaining!),
                style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
