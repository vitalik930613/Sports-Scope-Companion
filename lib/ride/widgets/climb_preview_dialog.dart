import 'package:flutter/material.dart';

import '../../ui/formats.dart';
import '../../ui/grade_colors.dart';
import '../../ui/zone_colors.dart' show foregroundOf;
import '../route_climbs.dart';
import 'elevation_profile_graph.dart';

/// Le profil gradué d'un col **quel que soit son statut** — grimpé, en cours
/// ou pas encore atteint — ouvert depuis une ligne de [ClimbListCard].
///
/// Différent de [ClimbProfileOverlay] : celui-ci suit [NavClimb], donc une
/// position *dans* le col (`ratio`, D+ restant) qui n'existe pas pour un col
/// pas encore commencé. Ici `ratio: null` sur [ElevationProfileGraph] — le
/// graphique dessine alors le profil entier sans curseur ni aire « déjà
/// fait », exactement le même rendu que le profil d'une sortie libre. Les
/// chiffres d'en-tête sont donc ceux du col **entier** (gain, longueur, pente
/// moyenne), jamais un « restant » qui supposerait une position connue.
Future<void> showClimbPreview(
  BuildContext context, {
  required RouteClimb climb,
  required int index,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _ClimbPreviewDialog(climb: climb, index: index),
  );
}

class _ClimbPreviewDialog extends StatelessWidget {
  const _ClimbPreviewDialog({required this.climb, required this.index});

  final RouteClimb climb;
  final int index;

  @override
  Widget build(BuildContext context) {
    final profile = climb.profile;
    final gradeColor = gradeColorOf(climb.avgGrade);

    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.all(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(gradeColor),
            const SizedBox(height: 6),
            _figures(),
            const SizedBox(height: 10),
            SizedBox(
              height: 180,
              child: profile == null
                  ? const Center(child: Text('Profil non disponible pour ce col.'))
                  : ElevationProfileGraph(
                      points: profile.points,
                      segmentGrades: profile.segmentGrades,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(Color gradeColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            '${climb.name ?? 'Col $index'}'
            '${climb.category == null ? '' : ' · Cat. ${climb.category}'}',
            style: const TextStyle(
              color: Color(0xFF111827),
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: gradeColor,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '${climb.avgGrade.round()} % moy',
            style: TextStyle(
              color: foregroundOf(gradeColor),
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }

  Widget _figures() {
    return Text(
      '+${climb.gainM.round()} m D+ · ${formatDistanceKm(climb.lengthM)}',
      style: const TextStyle(color: Color(0xFF6C757D), fontWeight: FontWeight.w600, fontSize: 14),
    );
  }
}
