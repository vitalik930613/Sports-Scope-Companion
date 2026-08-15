import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../ui/formats.dart';
import '../climb_profile.dart';
import '../nav_state.dart';
import 'block_card.dart';
import 'elevation_profile_surface.dart';

/// Le profil gradué du col en cours, en graphique — voir `ClimbProfileBlock`
/// (`dashboard/dashboard_block.dart`). Même graphique que
/// `ClimbProfileOverlay` (posé sur la carte, sur tap du badge de col,
/// `ElevationProfileGraph` partagée entre les deux, et avec le profil de toute
/// la sortie — voir `AltitudeProfileCard`), mais composable comme n'importe
/// quel autre bloc de page plutôt que réservé à ce geste.
///
/// **Sans carte dans le profil, [climbProfile] et [nav] sont nuls** : aucune
/// page web pour publier quoi que ce soit, même sort que `ClimbListCard`.
/// Hors col en cours (`nav.value?.climb == null`), la carte le dit plutôt que
/// de garder affiché le graphique d'un col déjà terminé.
class ClimbProfileCard extends StatelessWidget {
  const ClimbProfileCard({
    super.key,
    required this.climbProfile,
    required this.nav,
    this.color,
    this.textColor,
  });

  final ValueListenable<ClimbProfile?>? climbProfile;
  final ValueListenable<NavState?>? nav;

  /// Fond/texte réglés dans l'éditeur — voir `DashboardBlock.color`/
  /// `DashboardBlock.textColor`. Ne remplacent jamais les couleurs de pente
  /// du graphique ([gradeColorOf]) : c'est une donnée.
  final Color? color;
  final Color? textColor;

  static const _title = 'Profil du col';

  @override
  Widget build(BuildContext context) {
    final climbProfile = this.climbProfile;
    final nav = this.nav;
    if (climbProfile == null || nav == null) {
      return BlockCard(
        title: _title,
        lines: const ['Ce profil roule sans carte.'],
        color: color,
        textColor: textColor,
      );
    }

    return ListenableBuilder(
      listenable: Listenable.merge([climbProfile, nav]),
      builder: (context, _) {
        final climb = nav.value?.climb;
        if (climb == null) {
          return BlockCard(
            title: _title,
            lines: const ['Aucun col en cours.'],
            color: color,
            textColor: textColor,
          );
        }

        final profile = climbProfile.value;
        if (profile == null) {
          return BlockCard(
            title: _title,
            lines: const ['Profil du col en cours de réception…'],
            color: color,
            textColor: textColor,
          );
        }

        return _Card(climb: climb, profile: profile, color: color, textColor: textColor);
      },
    );
  }
}

/// La carte composée : un titre, l'en-tête chiffré, le graphique — voir
/// `ElevationProfileSurface`, partagée avec `AltitudeProfileCard`.
class _Card extends StatelessWidget {
  const _Card({required this.climb, required this.profile, this.color, this.textColor});

  final NavClimb climb;
  final ClimbProfile profile;
  final Color? color;
  final Color? textColor;

  @override
  Widget build(BuildContext context) => ElevationProfileSurface(
        title: _title(),
        headline: '+${climb.remainingGainM.round()} m',
        aside: formatDistance(climb.lengthM * (1 - climb.ratio)),
        grade: climb.grade,
        points: profile.points,
        segmentGrades: profile.segmentGrades,
        ratio: climb.ratio,
        color: color,
        textColor: textColor,
      );

  String _title() => profile.category == null ? 'Profil du col' : 'Profil du col · cat. ${profile.category}';
}
