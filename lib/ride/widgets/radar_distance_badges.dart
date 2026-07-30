import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../radar_severity.dart';

/// Combien de véhicules, et à quelle distance est le plus proche — en haut de
/// l'écran, **de part et d'autre de l'encoche**.
///
/// Deux fois la même chose, et c'est voulu : on ne sait pas de quel côté les
/// yeux du cycliste reviendront de la route, et la bande du haut est la seule
/// surface de l'écran qui ne serve à rien d'autre — l'encoche l'a déjà rendue
/// inutilisable pour de la carte. Les deux côtés sont **identiques et pas en
/// miroir** : une forme qu'on reconnaît sans la lire vaut mieux qu'une symétrie
/// qui oblige à trouver par quel bout commencer.
///
/// C'est la seule partie du radar qui donne des chiffres. La jauge dit « quelque
/// chose approche » sans qu'on ait à lire ; ici on décide — se déporter ou
/// tenir, laisser passer un véhicule ou une file — et cette décision-là mérite
/// qu'on regarde.
///
/// Rien quand la route est dégagée : la bande du haut redevient noire.
class RadarDistanceBadges extends StatelessWidget {
  const RadarDistanceBadges({super.key, required this.view});

  final RadarView view;

  static const _close = Color(0xFFEF5350);
  static const _approaching = Color(0xFFFFA726);

  /// Hauteur minimale de la bande, pour les écrans sans encoche : sans plancher,
  /// le chiffre se collerait au bord.
  static const _minHeight = 30.0;

  @override
  Widget build(BuildContext context) {
    final nearest = view.nearestM;
    if (!view.isAlerting || nearest == null) return const SizedBox.shrink();

    final color =
        view.severity == RadarSeverity.close ? _close : _approaching;

    // `viewPadding` et non `padding` : en immersif les barres système sont
    // masquées, mais l'encoche, elle, est toujours là.
    final height = math.max(
      MediaQuery.viewPaddingOf(context).top,
      _minHeight,
    );

    // Aucun geste : la zone de tap du haut appartient à la page web, c'est elle
    // qui pilote le rétroéclairage.
    return IgnorePointer(
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < 2; i++)
                _Badge(
                  count: view.count,
                  distanceM: nearest,
                  color: color,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.count,
    required this.distanceM,
    required this.color,
  });

  final int count;
  final int distanceM;
  final Color color;

  /// La bande du haut peut tomber sur n'importe quoi — un ciel clair, un lac, un
  /// champ de neige. L'ombre porte le chiffre quelle que soit la carte dessous.
  static const _shadows = [
    Shadow(color: Colors.black, blurRadius: 4),
    Shadow(color: Colors.black, blurRadius: 8),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Le pictogramme dit de quoi on parle sans un mot : sans lui, deux
        // nombres côte à côte se liraient comme une seule mesure.
        Icon(
          Icons.directions_car,
          size: 18,
          color: color,
          shadows: _shadows,
        ),
        const SizedBox(width: 3),
        _number('$count', color),
        const SizedBox(width: 10),
        _number('$distanceM m', color),
      ],
    );
  }

  Widget _number(String value, Color color) => Text(
        value,
        maxLines: 1,
        style: TextStyle(
          color: color,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          height: 1,
          shadows: _shadows,
        ),
      );
}
