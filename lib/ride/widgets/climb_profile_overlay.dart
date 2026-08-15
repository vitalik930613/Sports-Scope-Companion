import 'package:flutter/material.dart';

import '../../ui/formats.dart';
import '../../ui/grade_colors.dart';
import '../../ui/zone_colors.dart' show foregroundOf;
import '../climb_profile.dart';
import '../nav_state.dart';
import 'elevation_profile_graph.dart';

/// La carte de col dépliée : le graphique gradué en entier, curseur compris.
/// Port de `NavClimbCard.vue` (site) — mêmes calculs (`buildClimbProfile`,
/// `profileYAt`), mais dessinés en [CustomPainter] plutôt qu'en SVG+clip-path.
///
/// [profile] peut être nul un court instant : le message `climb` (scalaire)
/// arrive par la trame `nav`, republiée chaque seconde, tandis que le profil
/// est un message à part, poussé une seule fois par col (voir
/// climb_profile.dart). L'ordre est garanti côté site
/// (`RouteNavigation.vue::climbProfileFor`), mais un aller-retour WebView plus
/// lent que prévu ne doit pas planter l'appli — d'où l'état « chargement »
/// plutôt qu'un profil supposé présent.
class ClimbProfileOverlay extends StatelessWidget {
  const ClimbProfileOverlay({
    super.key,
    required this.climb,
    required this.profile,
    required this.onTap,
  });

  final NavClimb climb;
  final ClimbProfile? profile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 8)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(),
            const SizedBox(height: 6),
            SizedBox(
              height: 180,
              child: profile == null
                  ? const Center(
                      child: Text('Profil du col en cours de réception…'),
                    )
                  : ElevationProfileGraph(
                      points: profile!.points,
                      segmentGrades: profile!.segmentGrades,
                      ratio: climb.ratio,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    final gradeColor = gradeColorOf(climb.grade);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '+${climb.remainingGainM.round()} m',
              style: const TextStyle(
                color: Color(0xFFC2410C),
                fontWeight: FontWeight.w800,
                fontSize: 22,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${(climb.ratio * 100).round()} %',
              style: const TextStyle(
                color: Color(0xFF6C757D),
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ],
        ),
        Row(
          children: [
            // Distance restante, comme formatDistancePrecise côté site — voir
            // lib/ui/formats.dart::formatDistance.
            Text(
              formatDistance(climb.lengthM * (1 - climb.ratio)),
              style: const TextStyle(
                color: Color(0xFF111827),
                fontWeight: FontWeight.w800,
                fontSize: 20,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: gradeColor,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${climb.grade.round()} %',
                style: TextStyle(
                  color: foregroundOf(gradeColor),
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
