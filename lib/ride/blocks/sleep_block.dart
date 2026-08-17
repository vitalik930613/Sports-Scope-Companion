import 'package:flutter/material.dart';

import '../../dashboard/dashboard_block.dart';
import 'action_button.dart';

/// Demande la veille de la carte — voir [SleepBlock] pour l'arbitrage.
///
/// Nul sur un profil sans carte : il n'y a personne à endormir, et un bouton
/// sans effet vaudrait moins que pas de bouton (même règle que
/// `onChooseRoute` sur un profil sans carte).
class SleepControl extends StatelessWidget {
  const SleepControl({
    super.key,
    required this.onSleep,
    this.mode = SleepMode.full,
    this.color,
    this.textColor,
  });

  final VoidCallback? onSleep;
  final SleepMode mode;
  final Color? color;
  final Color? textColor;

  @override
  Widget build(BuildContext context) => DashboardActionButton(
        icon: Icons.bedtime,
        label: 'Mettre en veille',
        compact: mode == SleepMode.compact,
        onPressed: onSleep,
        color: color,
        textColor: textColor,
      );
}
