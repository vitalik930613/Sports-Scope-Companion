import 'package:flutter/material.dart';

/// La poignée du bord droit : la seconde façon de quitter la carte.
///
/// Sur la carte, le glissé horizontal appartient à MapLibre — on ne peut pas le
/// lui reprendre sans casser le déplacement. Restent le bandeau du bas, les
/// pastilles… et cette bande, qui a l'avantage d'être là où le pouce droit tombe
/// naturellement sur un guidon.
///
/// Étroite à dessein : quatorze points, c'est assez pour être touché sans viser
/// et trop peu pour gêner un déplacement de carte. La barre claire au milieu
/// n'est pas décorative — sans elle, rien ne dirait qu'il y a quelque chose là.
class MapEdgeHandle extends StatelessWidget {
  const MapEdgeHandle({super.key, required this.onOpen});

  /// Le cycliste demande la page suivante.
  final VoidCallback onOpen;

  static const width = 14.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onOpen,
        // Un glissé vers la gauche ouvre aussi : c'est le geste que le bandeau a
        // appris au cycliste, il doit marcher partout où il a un sens.
        onHorizontalDragEnd: (d) {
          if (d.velocity.pixelsPerSecond.dx < 0) onOpen();
        },
        child: Center(
          child: Container(
            width: 4,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white38,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }
}
