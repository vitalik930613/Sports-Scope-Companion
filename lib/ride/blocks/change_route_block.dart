import 'package:flutter/material.dart';

import '../../dashboard/dashboard_block.dart';
import 'action_button.dart';

/// Choisir un autre itinéraire sans quitter la sortie.
///
/// Même geste que « Choisir un autre itinéraire » du menu ⋮
/// (`DashboardPage._chooseRoute`, `ride_shell_page.dart`), posé là où le
/// pouce le trouve plutôt que rangé dans un menu qu'on n'ouvre presque
/// jamais.
class ChangeRouteControl extends StatelessWidget {
  const ChangeRouteControl({
    super.key,
    required this.onChooseRoute,
    this.mode = ChangeRouteMode.full,
  });

  /// Nul dans un profil sans carte : il n'y a alors aucune page à qui
  /// adresser la demande.
  final VoidCallback? onChooseRoute;
  final ChangeRouteMode mode;

  @override
  Widget build(BuildContext context) => DashboardActionButton(
        icon: Icons.route,
        label: 'Changer d\'itinéraire',
        compact: mode == ChangeRouteMode.compact,
        onPressed: onChooseRoute,
      );
}
