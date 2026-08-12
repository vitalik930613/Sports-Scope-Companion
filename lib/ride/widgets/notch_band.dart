import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../dashboard/metric_id.dart';
import '../../dashboard/ride_preset.dart';
import 'band_metric_tile.dart';

/// La bande de l'encoche : jusqu'à une mesure de chaque côté de la caméra
/// selfie, sur l'ancien emplacement de `RadarDistanceBadges` (retiré).
///
/// **Rien par défaut** : contrairement au bandeau du bas, un profil qui n'a
/// jamais touché ce réglage garde une bande invisible — exactement l'état
/// d'aujourd'hui. Branchée dans `RideShellPage` **avant** le cadre d'alerte
/// radar (`RadarFrame`) dans la pile, pour que celui-ci continue de se
/// dessiner par-dessus, comme il le faisait déjà par-dessus le reste de
/// l'écran.
///
/// Aucun geste : la zone de tap du haut appartient à la page web, c'est elle
/// qui pilote le rétroéclairage.
class NotchBand extends StatelessWidget {
  const NotchBand({super.key, required this.notch, required this.sources});

  final NotchSpec notch;
  final MetricSources sources;

  /// Plancher pour les écrans sans encoche : sans lui, la valeur se collerait
  /// au bord. Reprend la hauteur de l'ancienne bande `RadarDistanceBadges`.
  static const _minHeight = 46.0;

  @override
  Widget build(BuildContext context) {
    if (notch.left == null && notch.right == null) return const SizedBox.shrink();

    // `viewPadding` et non `padding` : en immersif les barres système sont
    // masquées, mais l'encoche, elle, est toujours là.
    final height = math.max(MediaQuery.viewPaddingOf(context).top, _minHeight);

    return IgnorePointer(
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _slot(notch.left, Alignment.centerLeft),
              _slot(notch.right, Alignment.centerRight),
            ],
          ),
        ),
      ),
    );
  }

  Widget _slot(MetricId? metric, Alignment alignment) {
    if (metric == null) return const SizedBox.shrink();

    return Flexible(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: alignment,
        child: ListenableBuilder(
          listenable: Listenable.merge(metric.dependencies(sources)),
          builder: (context, _) {
            final reading = metric.read(sources);
            return BandMetricTile(
              value: reading.value,
              label: metric.name,
              zoneKey: reading.zoneKey,
              background: reading.background,
            );
          },
        ),
      ),
    );
  }
}
