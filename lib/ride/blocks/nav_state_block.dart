import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../dashboard/dashboard_block.dart';
import '../nav_state.dart';
import 'block_card.dart';

/// Ce que la page de navigation raconte d'elle-même.
///
/// C'est le seul moyen de vérifier sur la route que le pont livre bien un état
/// frais quand la carte est masquée — ce dont dépend le retour automatique à
/// l'approche d'un virage.
///
/// **Sans carte dans le profil, [nav] est nul** : il n'y a alors aucune page web
/// pour publier quoi que ce soit, et le bloc le dit en toutes lettres plutôt que
/// d'afficher « aucun état reçu », qui se lirait comme une panne du pont.
class NavStateCard extends StatelessWidget {
  const NavStateCard({
    super.key,
    required this.nav,
    this.mode = NavStateMode.full,
  });

  final ValueListenable<NavState?>? nav;
  final NavStateMode mode;

  @override
  Widget build(BuildContext context) {
    final nav = this.nav;
    if (nav == null) {
      return const BlockCard(
        title: 'Navigation',
        lines: ['Ce profil roule sans carte.'],
      );
    }

    return ValueListenableBuilder<NavState?>(
      valueListenable: nav,
      builder: (context, state, _) {
        if (state == null) {
          return const BlockCard(
            title: 'Navigation',
            lines: ['Aucun état reçu de la page.'],
          );
        }

        final turn = state.turn;
        final stale = state.isStale(DateTime.now());

        if (mode == NavStateMode.compact) {
          // Une seule ligne, celle qui compte le plus : ce qu'il reste à faire,
          // ou ce qui ne va pas. Une cellule de grille n'a pas la place d'un
          // diagnostic.
          return BlockCard(
            title: 'Navigation',
            lines: [
              if (stale)
                'État périmé'
              else if (state.offRoute)
                'Hors trace'
              else if (!state.onRoute)
                'Navigation libre'
              else
                '${(state.remainingM / 1000).toStringAsFixed(1)} km restants',
            ],
          );
        }

        return BlockCard(
          title: 'Navigation',
          lines: [
            if (!state.onRoute) 'Navigation libre',
            if (state.onRoute)
              'Restant : ${(state.remainingM / 1000).toStringAsFixed(1)} km '
                  '· ${state.remainingGainM.round()} m D+',
            if (turn == null) 'Pas de virage annoncé',
            if (turn != null)
              'Virage ${turn.phase.name} à ${turn.distM.round()} m'
                  '${turn.direction == null ? '' : ' (${turn.direction})'}',
            if (state.offRoute) 'Hors trace',
            if (state.arrived) 'Arrivé',
            if (stale) 'État périmé',
          ],
        );
      },
    );
  }
}
