import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../dashboard/companion_icons.dart';
import '../../training_program/training_program.dart';
import '../../ui/zone_colors.dart';

/// Le changement de tronçon d'un programme d'entraînement, annoncé au centre
/// de l'écran — voir `RideShellPage._showWorkoutChangePopup`, qui l'affiche
/// 2-3 s puis l'efface. Complète la pastille (`WorkoutBadge`, repère
/// permanent) d'un front bien plus visible, le temps de lever les yeux.
///
/// Pure information, comme `ReminderBanner`/`BatteryAlertBanner` : aucun
/// geste à voler, rien à traverser pour continuer de rouler.
class WorkoutChangePopup extends StatelessWidget {
  const WorkoutChangePopup({super.key, required this.milestone});

  final WorkoutMilestone milestone;

  /// Même repli que `WorkoutBadge` — un jalon sans couleur propre garde le
  /// même bleu neutre dans les deux, la pastille et le popup doivent se lire
  /// comme le même tronçon.
  static const _defaultBackground = Color(0xFF1976D2);

  @override
  Widget build(BuildContext context) {
    final bg = milestone.color ?? _defaultBackground;
    final fg = milestone.textColor ?? foregroundOf(bg);
    final name = milestone.segmentName;
    final label = name.isEmpty ? '—' : name;

    return IgnorePointer(
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 12)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FaIcon(workoutMilestoneIconFor(milestone.icon), size: 40, color: fg),
              const SizedBox(height: 12),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 28),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
