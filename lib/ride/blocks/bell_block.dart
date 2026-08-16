import 'package:flutter/material.dart';

import '../../dashboard/dashboard_block.dart';
import 'action_button.dart';
import 'bell_player.dart';

/// Fait sonner fort le téléphone — pour le retrouver dans un sac ou une
/// poche, ou attirer l'attention de quelqu'un qui roule devant.
///
/// Autonome comme [MarkLapControl] (`mark_lap_block.dart`) : rien à faire
/// remonter jusqu'à `RideShellPage`, un tap suffit à démarrer et à arrêter —
/// contrairement à [SleepControl], qui doit traverser la coquille pour
/// ramener le cycliste sur la carte.
///
/// Son au flux d'alarme (`AndroidUsageType.alarm`, focus exclusif) plutôt
/// qu'au volume média : c'est le seul flux qui traverse le mode
/// silencieux/Ne pas déranger comme le ferait un réveil, or un téléphone
/// qu'on cherche est justement celui qu'on a mis en silencieux avant de
/// rouler.
///
/// Boucle jusqu'au prochain tap, avec un arrêt de sécurité à 3 secondes — le
/// temps de repérer le bruit sans laisser sonner un téléphone qu'on ne
/// retrouve pas tout de suite.
class BellControl extends StatefulWidget {
  const BellControl({
    super.key,
    this.mode = BellMode.full,
    this.sound = BellSound.bell,
    this.color,
    this.textColor,
  });

  final BellMode mode;
  final BellSound sound;
  final Color? color;
  final Color? textColor;

  @override
  State<BellControl> createState() => _BellControlState();
}

class _BellControlState extends State<BellControl> {
  final _player = BellPlayer();

  @override
  void initState() {
    super.initState();
    _player.addListener(_onChanged);
  }

  @override
  void dispose() {
    _player.removeListener(_onChanged);
    _player.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => DashboardActionButton(
        icon: _player.ringing ? Icons.notifications_active : Icons.notifications,
        label: 'Faire sonner',
        compact: widget.mode == BellMode.compact,
        onPressed: () => _player.toggle(widget.sound),
        color: widget.color,
        textColor: widget.textColor,
      );
}
