import 'package:flutter/material.dart';

import '../ride_pages.dart';

/// Une surface qui ne retient du doigt qu'une chose : est-il parti à gauche ou
/// à droite ?
///
/// Trois endroits en ont besoin — le bandeau du bas et les deux bandes du bord
/// de la carte — avec exactement la même règle, d'où ce widget plutôt que trois
/// copies du même compteur.
///
/// Le déplacement est **cumulé** et pas seulement mesuré au relâchement : un
/// geste lent et appuyé doit compter autant qu'une chiquenaude, parce qu'à vélo
/// on fait rarement les deux fois le même geste. Et rien n'est annoncé avant que
/// le doigt ne se lève : un glissé qu'on ramène en arrière avant de lâcher n'a
/// jamais eu lieu.
class SwipeZone extends StatefulWidget {
  const SwipeZone({
    super.key,
    required this.onSwipe,
    required this.child,
    this.onTap,
    this.behavior = HitTestBehavior.opaque,
  });

  /// Appelé une fois le doigt levé, avec `1` (vers la suite) ou `-1` (vers le
  /// précédent). Un geste ambigu ne l'appelle pas du tout.
  final void Function(int direction) onSwipe;

  /// Facultatif : les bandes du bord servent aussi de bouton, parce qu'on y vise
  /// mal en roulant et qu'un appui raté vaut mieux qu'un appui perdu.
  final VoidCallback? onTap;

  final HitTestBehavior behavior;
  final Widget child;

  @override
  State<SwipeZone> createState() => _SwipeZoneState();
}

class _SwipeZoneState extends State<SwipeZone> {
  double _dragged = 0;

  void _onDragEnd(DragEndDetails details) {
    final direction = swipeDirection(
      dx: _dragged,
      velocity: details.velocity.pixelsPerSecond.dx,
    );
    _dragged = 0;
    if (direction != 0) widget.onSwipe(direction);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: widget.behavior,
      onTap: widget.onTap,
      onHorizontalDragStart: (_) => _dragged = 0,
      onHorizontalDragUpdate: (d) => _dragged += d.delta.dx,
      onHorizontalDragEnd: _onDragEnd,
      child: widget.child,
    );
  }
}
