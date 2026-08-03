import 'package:flutter/material.dart';

import 'swipe_zone.dart';

/// Les bandes des deux bords de la carte : **l'appui** qui change de page, et
/// le seul signe visible qu'il y a des pages de part et d'autre.
///
/// Elles sont nées d'une contrainte qui n'existe plus — le glissé horizontal
/// appartenait alors au déplacement de la carte, et les deux bords étaient le
/// seul endroit où on pouvait le lui reprendre. Depuis que la carte se déplace à
/// deux doigts, tout le milieu se glisse aussi (`MapSwipeZone`). Ce qui les
/// garde, c'est l'autre moitié de leur rôle : on vise mal en roulant, un appui
/// est plus sûr qu'un glissé, et sans la barre claire rien ne dirait qu'il y a
/// quelque chose là.
///
/// Étroites à dessein : vingt-deux points, assez pour être touchées sans viser
/// et assez peu pour laisser la carte tranquille.
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
