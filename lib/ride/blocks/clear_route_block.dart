import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../dashboard/dashboard_block.dart';
import '../nav_state.dart';
import 'action_button.dart';

/// Retirer le tracé qu'on suit, sans quitter la sortie.
///
/// Même geste que « Retirer l'itinéraire » du menu ⋮
/// (`DashboardPage._clearRoute`, `ride_shell_page.dart`).
///
/// Désactivé — jamais masqué — hors d'un tracé : c'est un bouton qu'on a
/// délibérément posé sur sa page, et le faire disparaître ferait chercher une
/// case vide plutôt qu'un bouton grisé qui dit pourquoi il ne répond pas.
class ClearRouteControl extends StatelessWidget {
  const ClearRouteControl({
    super.key,
    required this.onClearRoute,
    this.nav,
    this.mode = ClearRouteMode.full,
    this.color,
    this.textColor,
  });

  /// Nul dans un profil sans carte.
  final VoidCallback? onClearRoute;

  /// Ce que la page web publie de la navigation. Nul dans un profil sans
  /// carte : il n'y a alors pas de page pour dire si un tracé est suivi.
  final ValueListenable<NavState?>? nav;

  final ClearRouteMode mode;

  /// Fond/texte réglés dans l'éditeur — voir [DashboardBlock.color]/
  /// [DashboardBlock.textColor].
  final Color? color;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    final compact = mode == ClearRouteMode.compact;

    final navListenable = nav;
    if (navListenable == null) {
      return DashboardActionButton(
        icon: Icons.route,
        barred: true,
        label: 'Retirer l\'itinéraire',
        compact: compact,
        onPressed: null,
        color: color,
        textColor: textColor,
      );
    }

    return ValueListenableBuilder<NavState?>(
      valueListenable: navListenable,
      builder: (context, state, _) => DashboardActionButton(
        icon: Icons.route,
        barred: true,
        label: 'Retirer l\'itinéraire',
        compact: compact,
        onPressed: state?.onRoute == true ? onClearRoute : null,
        color: color,
        textColor: textColor,
      ),
    );
  }
}
