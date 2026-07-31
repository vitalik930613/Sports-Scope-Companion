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
  /// le chiffre se collerait au bord. Relevée avec la pastille — un fond plein
  /// a besoin d'un peu d'air, sinon il touche le haut de l'écran.
  static const _minHeight = 46.0;

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
                // Les deux pastilles ont grossi jusqu'à occuper presque toute
                // la largeur : sur un écran étroit, on préfère les réduire un
                // peu que déborder. Elles restent entières, jamais rognées.
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: i == 0
                        ? Alignment.centerLeft
                        : Alignment.centerRight,
                    child: _Badge(
                      count: view.count,
                      distanceM: nearest,
                      color: color,
                    ),
                  ),
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

  /// **Un aplat de la couleur de l'alerte, pas du texte coloré.** La bande du
  /// haut peut tomber sur n'importe quoi — un ciel clair, un lac, un champ de
  /// neige, une route grise — et un chiffre orange posé dessus était illisible
  /// à vélo, ombres portées comprises. La pastille, elle, apporte son propre
  /// fond : le contraste ne dépend plus de la carte. Elle porte du même coup la
  /// gravité **sans qu'on lise le chiffre**, comme le cadre et les gouttières.
  ///
  /// Encre noire sur les deux couleurs : le rouge et l'orange du radar sont
  /// clairs (contraste ~7 avec le noir, ~3 avec le blanc). Même raison que le
  /// jaune de la zone 4 dans le bandeau du bas.
  static const _ink = Colors.black;

  /// Un liseré sombre autour de la pastille : sur une carte sombre, un aplat
  /// saturé bave et perd son bord.
  static const _outline = Color(0x66000000);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _outline, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Le pictogramme dit de quoi on parle sans un mot : sans lui, deux
          // nombres côte à côte se liraient comme une seule mesure.
          const Icon(Icons.directions_car, size: 22, color: _ink),
          const SizedBox(width: 4),
          _number('$count'),
          const SizedBox(width: 12),
          _number('$distanceM m'),
        ],
      ),
    );
  }

  Widget _number(String value) => Text(
        value,
        maxLines: 1,
        style: const TextStyle(
          color: _ink,
          fontSize: 24,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      );
}
