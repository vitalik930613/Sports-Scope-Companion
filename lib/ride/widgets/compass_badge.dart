import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Pastille de boussole, posée sur la carte tant qu'un profil l'active : elle
/// montre le cap mesuré (aiguille + degrés), **et son tap force la priorité à
/// la boussole sur la course GPS** — utile sous un couvert forestier, où la
/// vitesse GPS est trop bruitée pour distinguer un arrêt d'un mouvement, et
/// où c'est justement l'orientation du téléphone qu'on veut suivre. Pas la
/// flèche de navigation elle-même (qui vit côté site, dans le pont) : un
/// repère, et le bouton qui décide quelle source l'alimente.
class CompassBadge extends StatelessWidget {
  const CompassBadge({
    super.key,
    required this.headingDeg,
    required this.trusted,
    required this.forced,
    this.onTap,
  });

  final double headingDeg;
  final bool trusted;

  /// Le cycliste a-t-il forcé la boussole ? Un simple entourage blanc suffit
  /// à le distinguer — la couleur de l'aiguille est déjà prise par la
  /// confiance dans le calibrage, et « deux couleurs, pas trois » vaut ici
  /// aussi.
  final bool forced;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // Même code couleur que la rangée de capteurs de l'accueil
    // (`sensorLinkColor`) : vert exploitable, orange pas encore vérifié —
    // jamais un troisième état à distinguer d'un coup d'œil.
    final color = trusted ? Colors.teal : Colors.orange;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.black54,
          shape: BoxShape.circle,
          border: forced ? Border.all(color: Colors.white, width: 2) : null,
          boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 4)],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Transform.rotate(
              // Le nord de l'icône pointe vers le haut au repos : la faire
              // tourner de `headingDeg` la ramène sur le cap mesuré.
              angle: headingDeg * math.pi / 180,
              child: Icon(Icons.navigation, size: 18, color: color),
            ),
            Text(
              '${headingDeg.round()}°',
              style: TextStyle(
                color: color,
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
