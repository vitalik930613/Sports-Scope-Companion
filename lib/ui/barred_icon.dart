import 'dart:math' as math;

import 'package:flutter/material.dart';

/// La même icône que le geste « choisir », barrée en diagonale — pour le
/// geste qui le défait.
///
/// Ni `route_off` ni `fitness_center_off` n'existent dans Material : sans ce
/// widget, « choisir un itinéraire »/« retirer l'itinéraire » (ou
/// l'entraînement) tombaient sur deux glyphes sans rapport, difficiles à
/// distinguer d'un coup d'œil en roulant. La barre rattache visuellement les
/// deux gestes d'une même paire l'un à l'autre, plutôt qu'à un symbole
/// générique partagé par plusieurs paires différentes.
class BarredIcon extends StatelessWidget {
  const BarredIcon(this.icon, {super.key, this.size, this.color});

  final IconData icon;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final resolvedSize = size ?? iconTheme.size ?? 24;
    final resolvedColor = color ?? iconTheme.color;

    return SizedBox.square(
      dimension: resolvedSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(icon, size: resolvedSize, color: resolvedColor),
          Transform.rotate(
            angle: -math.pi / 4,
            child: Container(
              width: resolvedSize * 1.2,
              height: math.max(2, resolvedSize * 0.1),
              color: resolvedColor ?? Colors.black,
            ),
          ),
        ],
      ),
    );
  }
}
