import 'package:flutter/material.dart';

import 'swipe_zone.dart';

/// Les bandes des deux bords de la carte : la façon de changer de page sans
/// prendre à MapLibre le geste dont il a besoin.
///
/// Sur la carte, le glissé horizontal appartient au déplacement de la carte —
/// on ne peut pas le lui reprendre en plein milieu sans casser la consultation
/// de l'itinéraire. Ces bandes découpent donc les deux bords, où l'on ne
/// déplace pas la carte de toute façon : c'est là que tombent les pouces sur un
/// guidon, et un glissé qui y démarre ne peut vouloir dire qu'une chose.
///
/// Étroites à dessein : vingt-deux points, assez pour être touchées sans viser
/// et assez peu pour laisser la carte tranquille. La barre claire au milieu
/// n'est pas décorative — sans elle, rien ne dirait qu'il y a quelque chose là.
class MapEdgeHandle extends StatelessWidget {
  const MapEdgeHandle({
    super.key,
    required this.direction,
    required this.onStep,
    this.showBar = true,
  });

  /// Ce que vaut un *appui* sur cette bande : `1` pour celle de droite (la page
  /// suivante), `-1` pour celle de gauche. Un *glissé*, lui, garde toujours sa
  /// propre direction — même sur la bande de gauche, partir vers la gauche
  /// avance.
  final int direction;

  /// Le cycliste demande la page d'à côté, dans le sens donné.
  final void Function(int direction) onStep;

  /// La barre est effacée quand la jauge radar occupe la même gouttière : deux
  /// signes dans vingt-deux points se liraient mal, et entre « il y a une
  /// poignée ici » et « une voiture arrive », le choix est vite fait. La bande
  /// continue de prendre les gestes — seul son repère s'éclipse.
  final bool showBar;

  static const width = 22.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: SwipeZone(
        onTap: () => onStep(direction),
        onSwipe: onStep,
        child: showBar
            ? Center(
                child: Container(
                  width: 4,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white38,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              )
            : const SizedBox.expand(),
      ),
    );
  }
}
