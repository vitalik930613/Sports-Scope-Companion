import 'package:flutter/material.dart';

import '../radar_severity.dart';

/// Le cadre coloré : ce qui se voit sans regarder.
///
/// La jauge dit *où*, le cadre dit *qu'il y a quelque chose*. Une bordure au
/// bord de l'écran est perçue par la vision périphérique, celle qui reste
/// disponible quand les yeux sont sur la route — c'est tout l'intérêt d'en faire
/// une deuxième signalisation plutôt qu'un simple accent sur la jauge.
///
/// Il entoure **tout** l'écran, bandeau et pages de données compris : l'alerte
/// n'appartient pas à la carte, elle appartient à la sortie.
///
/// Rien quand la route est dégagée, et rien du tout sans radar : la bordure est
/// alors de largeur nulle et transparente, donc l'écran est celui d'avant. La
/// transition est animée pour qu'une voiture qui entre en portée ne fasse pas
/// clignoter l'écran d'un coup sec.
class RadarFrame extends StatelessWidget {
  const RadarFrame({super.key, required this.severity});

  final RadarSeverity severity;

  static const _close = Color(0xFFEF5350);
  static const _approaching = Color(0xFFFFA726);

  /// Assez épais pour être vu du coin de l'œil, assez fin pour ne pas rogner la
  /// carte — il est posé par-dessus, il ne pousse rien.
  static const _approachingWidth = 6.0;
  static const _closeWidth = 10.0;

  @override
  Widget build(BuildContext context) {
    final (color, width) = switch (severity) {
      RadarSeverity.close => (_close, _closeWidth),
      RadarSeverity.approaching => (_approaching, _approachingWidth),
      _ => (Colors.transparent, 0.0),
    };

    return IgnorePointer(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          border: Border.all(color: color, width: width),
        ),
      ),
    );
  }
}
