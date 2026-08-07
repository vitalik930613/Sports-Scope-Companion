import 'package:flutter/material.dart';

import '../../ui/grade_colors.dart';
import '../../ui/zone_colors.dart' show foregroundOf;
import '../nav_state.dart';

/// La pastille repliée d'un col en cours : pente instantanée et D+ restant,
/// épinglée près d'un bord d'écran tant que [NavState.climb] n'est pas nul —
/// voir la doc de `RideShellPage._climbExpanded` pour le pourquoi d'un état
/// replié/déplié plutôt qu'un recouvrement forcé comme `RadarWakePage`.
class ClimbBadge extends StatelessWidget {
  const ClimbBadge({super.key, required this.climb, required this.onTap});

  final NavClimb climb;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = gradeColorOf(climb.grade);
    final fg = foregroundOf(bg);

    return GestureDetector(
      onTap: onTap,
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
            Icon(Icons.landscape, size: 18, color: fg),
            const SizedBox(width: 6),
            Text(
              '${climb.grade.round()} %',
              style:
                  TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 15),
            ),
            const SizedBox(width: 8),
            Text(
              '+${climb.remainingGainM.round()} m',
              style:
                  TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
