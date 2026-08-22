import 'package:flutter/material.dart';

import '../../dashboard/dashboard_block.dart';
import 'action_button.dart';

/// Quitte la sortie et retrouve l'accueil — voir [LeaveRideBlock] pour
/// l'arbitrage. Jamais désactivé, contrairement à [ClearRouteControl] :
/// rentrer a toujours un sens, avec ou sans carte.
class LeaveRideControl extends StatelessWidget {
  const LeaveRideControl({
    super.key,
    required this.onLeaveRide,
    this.mode = LeaveRideMode.full,
    this.color,
    this.textColor,
  });

  final VoidCallback? onLeaveRide;
  final LeaveRideMode mode;
  final Color? color;
  final Color? textColor;

  @override
  Widget build(BuildContext context) => DashboardActionButton(
        icon: Icons.home_outlined,
        label: 'Revenir à l\'accueil',
        compact: mode == LeaveRideMode.compact,
        onPressed: onLeaveRide,
        color: color,
        textColor: textColor,
      );
}
