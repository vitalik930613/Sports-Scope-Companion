import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../dashboard/block_density.dart';
import '../../ui/formats.dart';
import '../../ui/grade_colors.dart';
import '../../ui/zone_colors.dart' show foregroundOf;
import '../climb_profile.dart';
import '../nav_state.dart';
import '../widgets/climb_profile_graph.dart';
import 'block_card.dart';

/// Le profil gradué du col en cours, en graphique — voir `ClimbProfileBlock`
/// (`dashboard/dashboard_block.dart`). Même graphique que
/// `ClimbProfileOverlay` (posé sur la carte, sur tap du badge de col,
/// [ClimbProfileGraph] partagée entre les deux), mais composable comme
/// n'importe quel autre bloc de page plutôt que réservé à ce geste.
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

/// La carte composée : un titre, l'en-tête chiffré, le graphique — même
/// convention de mise en page que `WeatherForecastBlockView` : le graphique
/// remplit toute la case ([Expanded]/[LayoutBuilder]), seul le texte garde
/// une taille fixe.
class _Card extends StatelessWidget {
  const _Card({required this.climb, required this.profile, this.color, this.textColor});

  final NavClimb climb;
  final ClimbProfile profile;
  final Color? color;
  final Color? textColor;

  /// Repli hors contrainte de hauteur (page qui défile), même raison que
  /// `WeatherForecastBlockView` : la case ne borne alors rien, le graphique
  /// garde une hauteur raisonnable plutôt que de s'effondrer à zéro.
  static const _chartAreaHeight = 140.0;

  @override
  Widget build(BuildContext context) {
    const metrics = BlockMetrics.natural;
    final ink = textColor ?? (color == null ? Colors.white : foregroundOf(color!));
    final gradeColor = gradeColorOf(climb.grade);

    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: EdgeInsets.all(metrics.padding),
      decoration: BoxDecoration(
        color: color ?? BlockCard.background,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.hardEdge,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final chart = ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: ClimbProfileGraph(ratio: climb.ratio, profile: profile),
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: constraints.hasBoundedHeight ? MainAxisSize.max : MainAxisSize.min,
            children: [
              Text(
                _title(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: ink.withValues(alpha: 0.7), fontSize: metrics.titleSize),
              ),
              SizedBox(height: metrics.gap),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '+${climb.remainingGainM.round()} m',
                        style: TextStyle(
                          color: ink,
                          fontWeight: FontWeight.w800,
                          fontSize: metrics.lineSize * 1.3,
                        ),
                      ),
                      SizedBox(width: metrics.gap / 2),
                      Text(
                        formatDistance(climb.lengthM * (1 - climb.ratio)),
                        style: TextStyle(
                          color: ink.withValues(alpha: 0.7),
                          fontWeight: FontWeight.w600,
                          fontSize: metrics.lineSize,
                        ),
                      ),
                    ],
                  ),
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
                        fontSize: metrics.lineSize,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: metrics.gap),
              constraints.hasBoundedHeight
                  ? Expanded(child: chart)
                  : SizedBox(height: _chartAreaHeight, child: chart),
            ],
          );
        },
      ),
    );
  }

  String _title() => profile.category == null ? 'PROFIL DU COL' : 'PROFIL DU COL · CAT. ${profile.category}';
}
