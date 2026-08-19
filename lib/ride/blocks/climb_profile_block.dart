import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../ui/formats.dart';
import '../climb_profile.dart';
import '../nav_state.dart';
import '../route_climbs.dart';
import 'block_card.dart';
import 'elevation_profile_surface.dart';

/// Le profil gradué du col en cours, en graphique — voir `ClimbProfileBlock`
/// (`dashboard/dashboard_block.dart`). Même graphique que
/// `ClimbProfileOverlay` (posé sur la carte, sur tap du badge de col,
/// `ElevationProfileGraph` partagée entre les deux, et avec le profil de toute
/// la sortie — voir `AltitudeProfileCard`), mais composable comme n'importe
/// quel autre bloc de page plutôt que réservé à ce geste.
///
/// **Sans carte dans le profil, [climbProfile] et [climb] sont nuls** : aucune
/// page web pour publier quoi que ce soit, même sort que `ClimbListCard`.
/// Hors col en cours ([climb] à `null`), la carte le dit plutôt que de garder
/// affiché le graphique d'un col déjà terminé.
class ClimbProfileCard extends StatelessWidget {
  const ClimbProfileCard({
    super.key,
    required this.climbProfile,
    required this.climb,
    this.debugClimb,
    this.debugProfile,
    this.color,
    this.textColor,
  });

  final ValueListenable<ClimbProfile?>? climbProfile;

  /// Le col en cours, **stabilisé** — voir `MetricSources.climb`. Jamais
  /// `nav.value?.climb` en direct : brut, il flickerait `null` d'une trame à
  /// l'autre près de la frontière du col (position simulée surtout) et
  /// ferait retomber cette carte sur « Aucun col en cours » pendant que la
  /// pastille, elle, restait allumée.
  final ValueListenable<NavClimb?>? climb;

  /// Le col de démonstration (`RideShellPage._debugClimb`, bouton « Simuler
  /// un col » du menu), s'il est actif : prime sur le vrai col, même raison
  /// que sur la pastille et la carte dépliée (`ClimbBadge`,
  /// `ClimbProfileOverlay`) — c'est un banc d'essai, pas un second col qui
  /// s'ajouterait au premier. Suit son propre chemin plutôt que de passer par
  /// [nav]/[climbProfile] : le col simulé n'a pas de tracé, donc pas de
  /// `NavState` pour le porter.
  final NavClimb? debugClimb;
  final ClimbProfile? debugProfile;

  /// Fond/texte réglés dans l'éditeur — voir `DashboardBlock.color`/
  /// `DashboardBlock.textColor`. Ne remplacent jamais les couleurs de pente
  /// du graphique ([gradeColorOf]) : c'est une donnée.
  final Color? color;
  final Color? textColor;

  static const _title = 'Profil du col';

  @override
  Widget build(BuildContext context) {
    if (debugClimb case final climb?) {
      final profile = debugProfile;
      if (profile == null) {
        return BlockCard(
          title: _title,
          lines: const ['Profil du col en cours de réception…'],
          color: color,
          textColor: textColor,
        );
      }
      return _Card(climb: climb, profile: profile, color: color, textColor: textColor);
    }

    final climbProfile = this.climbProfile;
    final climb = this.climb;
    if (climbProfile == null || climb == null) {
      return BlockCard(
        title: _title,
        lines: const ['Ce profil roule sans carte.'],
        color: color,
        textColor: textColor,
      );
    }

    return ListenableBuilder(
      listenable: Listenable.merge([climbProfile, climb]),
      builder: (context, _) {
        final climb = this.climb!.value;
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

/// Le même graphique, mais pour un col déjà grimpé — posé sur la page Tours
/// (voir `LapListBody._block`, cas `ClimbProfileBlock`). [ClimbProfileCard]
/// se pilote par [NavClimb] : sur un tour qui n'est plus le tour courant, la
/// page web n'en parle plus (`nav.value?.climb == null`), donc son graphique
/// disparaîtrait alors que le tracé, lui, se souvient très bien de ce col.
///
/// La source est donc [RouteClimb] et son [RouteClimb.profile] — reçus une
/// fois pour tout le tracé au chargement (voir la doc de [ClimbProfile]),
/// donc toujours là après le sommet. `ratio: null` : rien à distinguer entre
/// « déjà grimpé » et « restant », c'est tout le col qu'on regarde ici, pas
/// la progression du moment (voir la doc de [ElevationProfileSurface.ratio]).
class LapClimbProfileCard extends StatelessWidget {
  const LapClimbProfileCard({
    super.key,
    required this.routeClimbs,
    required this.climbId,
    this.color,
    this.textColor,
  });

  final ValueListenable<RouteClimbs?>? routeClimbs;

  /// = `RideLap.climbId` du tour affiché. `null` sur un tour qui ne couvre
  /// aucun col (tracé entre deux cols, ou série autre que `climbLapSeries`).
  final int? climbId;

  final Color? color;
  final Color? textColor;

  static const _title = 'Profil du col';

  @override
  Widget build(BuildContext context) {
    final routeClimbs = this.routeClimbs;
    if (routeClimbs == null) {
      return BlockCard(
        title: _title,
        lines: const ['Ce profil roule sans carte.'],
        color: color,
        textColor: textColor,
      );
    }

    final climbId = this.climbId;
    if (climbId == null) {
      return BlockCard(
        title: _title,
        lines: const ['Ce tour ne couvre aucun col.'],
        color: color,
        textColor: textColor,
      );
    }

    return ListenableBuilder(
      listenable: routeClimbs,
      builder: (context, _) {
        final climb = _findClimb(routeClimbs.value, climbId);
        if (climb == null) {
          return BlockCard(
            title: _title,
            lines: const ['Col introuvable dans le tracé actuel.'],
            color: color,
            textColor: textColor,
          );
        }

        final profile = climb.profile;
        if (profile == null) {
          return BlockCard(
            title: _title,
            lines: const ['Profil de ce col non reçu.'],
            color: color,
            textColor: textColor,
          );
        }

        return ElevationProfileSurface(
          title: profile.category == null ? _title : '$_title · cat. ${profile.category}',
          headline: '+${climb.gainM.round()} m',
          aside: formatDistance(climb.lengthM),
          grade: climb.avgGrade,
          points: profile.points,
          segmentGrades: profile.segmentGrades,
          ratio: null,
          color: color,
          textColor: textColor,
        );
      },
    );
  }

  static RouteClimb? _findClimb(RouteClimbs? list, int id) {
    for (final climb in list?.climbs ?? const <RouteClimb>[]) {
      if (climb.id == id) return climb;
    }
    return null;
  }
}
