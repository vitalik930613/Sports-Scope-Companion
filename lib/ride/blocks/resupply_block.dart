import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../dashboard/dashboard_block.dart';
import '../../ui/formats.dart';
import '../route_resupply.dart';
import 'block_card.dart';

/// Les ravitaillements à venir sur le tracé — voir `ResupplyBlock`
/// (`dashboard_block.dart`).
///
/// La donnée est déjà projetée et triée côté site (`buildCompanionResupply`) :
/// ici on ne fait que mettre en forme. `null` (pas de carte) ou liste vide →
/// l'état vide, jamais des tirets.
class ResupplyCard extends StatelessWidget {
  const ResupplyCard({
    super.key,
    required this.resupply,
    this.mode = ResupplyMode.list,
    this.color,
    this.textColor,
  });

  final ValueListenable<RouteResupply>? resupply;
  final ResupplyMode mode;
  final Color? color;
  final Color? textColor;

  static const _title = 'Ravitos sur le tracé';

  /// Libellés recopiés à la main des serverTypes du site (`RESUPPLY_TYPES`) —
  /// un fac-similé, pas un rendu partagé.
  static String _label(String type) => switch (type) {
        'water' => 'Eau',
        'bakery' => 'Boulangerie',
        _ => 'Ravito',
      };

  @override
  Widget build(BuildContext context) {
    final listenable = resupply;
    if (listenable == null) {
      return BlockCard(
        title: _title,
        lines: const ['Aucun tracé suivi.'],
        color: color,
        textColor: textColor,
      );
    }

    return ValueListenableBuilder<RouteResupply>(
      valueListenable: listenable,
      builder: (context, value, _) {
        final stops = value.stops;
        if (stops.isEmpty) {
          return BlockCard(
            title: _title,
            lines: const ['Rien de repéré devant.'],
            color: color,
            textColor: textColor,
          );
        }

        if (mode == ResupplyMode.compact) {
          final next = stops.first;
          return BlockCard(
            title: 'Prochain ravito',
            lines: ['${_label(next.type)} · ${formatDistanceKm(next.remainingM)}'],
            color: color,
            textColor: textColor,
          );
        }

        return BlockCard(
          title: _title,
          lines: [
            for (final stop in stops.take(5))
              '${_label(stop.type)} · ${formatDistanceKm(stop.remainingM)}'
                  '${stop.detourM >= 30 ? ' (+${stop.detourM.round()} m)' : ''}',
          ],
          color: color,
          textColor: textColor,
        );
      },
    );
  }
}
