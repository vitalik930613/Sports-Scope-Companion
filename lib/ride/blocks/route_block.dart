import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../dashboard/dashboard_block.dart';
import '../nav_state.dart';
import 'action_button.dart';

/// [ChangeRouteControl] et [ClearRouteControl], combinés en un seul bouton.
///
/// Retire le tracé suivi quand il y en a un, en propose un sinon — même icône
/// et même libellé que le bouton qu'il remplace pour le geste du moment, mais
/// un seul bouton à poser plutôt que deux.
///
/// Contrairement à [ClearRouteControl] seul, jamais désactivé : hors tracé,
/// il propose déjà le geste qui en pose un, il n'y a donc rien à griser.
class RouteControl extends StatelessWidget {
  const RouteControl({
    super.key,
    required this.onChooseRoute,
    required this.onClearRoute,
    this.nav,
    this.mode = RouteMode.full,
    this.color,
    this.textColor,
  });

  /// Nul dans un profil sans carte : il n'y a alors aucune page à qui
  /// adresser la demande.
  final VoidCallback? onChooseRoute;
  final VoidCallback? onClearRoute;

  /// Ce que la page web publie de la navigation. Nul dans un profil sans
  /// carte : il n'y a alors pas de page pour dire si un tracé est suivi, et
  /// le bouton retombe sur le geste qui en choisit un.
  final ValueListenable<NavState?>? nav;

  final RouteMode mode;

  /// Fond/texte réglés dans l'éditeur — voir [DashboardBlock.color]/
  /// [DashboardBlock.textColor].
  final Color? color;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    final compact = mode == RouteMode.compact;
    final navListenable = nav;

    if (navListenable == null) {
      return DashboardActionButton(
        icon: Icons.route,
        label: 'Choisir un itinéraire',
        compact: compact,
        onPressed: onChooseRoute,
        color: color,
        textColor: textColor,
      );
    }

    return ValueListenableBuilder<NavState?>(
      valueListenable: navListenable,
      builder: (context, state, _) => state?.onRoute == true
          ? DashboardActionButton(
              icon: Icons.layers_clear,
              label: 'Retirer l\'itinéraire',
              compact: compact,
              onPressed: onClearRoute,
              color: color,
              textColor: textColor,
            )
          : DashboardActionButton(
              icon: Icons.route,
              label: 'Choisir un itinéraire',
              compact: compact,
              onPressed: onChooseRoute,
              color: color,
              textColor: textColor,
            ),
    );
  }
}
