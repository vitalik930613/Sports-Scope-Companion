import 'dart:async';

import 'package:flutter/material.dart';

import '../../dashboard/dashboard_block.dart';
import '../../ui/formats.dart';
import '../../ui/zone_colors.dart';
import 'block_card.dart';

/// L'heure courante.
///
/// Seule case du tableau de bord avec son propre [Timer.periodic] : elle ne
/// dépend d'aucun `Listenable` (ni capteur, ni enregistreur — voir
/// [ClockBlock]), donc rien d'autre ne la ferait se reconstruire. Tique chaque
/// seconde même en mode [ClockMode.hm] : une seconde implémentation à deux
/// cadences pour économiser un `setState` par minute ne vaut pas la
/// complexité, sur une case qui n'affiche qu'un chiffre.
class ClockCard extends StatefulWidget {
  const ClockCard({
    super.key,
    this.mode = ClockMode.hm,
    this.color,
    this.textColor,
  });

  final ClockMode mode;

  /// Fond/texte réglés dans l'éditeur — voir [DashboardBlock.color]/
  /// [DashboardBlock.textColor].
  final Color? color;
  final Color? textColor;

  @override
  State<ClockCard> createState() => _ClockCardState();
}

class _ClockCardState extends State<ClockCard> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final text =
        widget.mode == ClockMode.hms ? formatClockHms(now) : formatClockHm(now);
    final ink = widget.textColor ??
        (widget.color == null ? Colors.white : foregroundOf(widget.color!));

    return BlockSurface(
      background: widget.color,
      child: Text(
        text,
        style: TextStyle(color: ink, fontSize: 48, fontWeight: FontWeight.bold),
      ),
    );
  }
}
