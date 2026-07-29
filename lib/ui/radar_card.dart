import 'package:flutter/material.dart';

import '../ble/samples.dart';
import '../ble/sensor_hub.dart';

/// Le radar arrière sur l'écran de diagnostic.
///
/// Il mérite son propre bloc : la donnée est une liste, et l'affichage doit
/// distinguer « route dégagée » de « pas de radar ».
///
/// C'est le rendu détaillé, pour vérifier ce qu'on décode. Pendant une sortie,
/// c'est la jauge latérale de la coquille qui prend le relais — plus discrète,
/// et lisible sans quitter la route des yeux.
class RadarCard extends StatelessWidget {
  const RadarCard({super.key, required this.hub});

  final SensorHub hub;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<RadarSample?>(
      valueListenable: hub.latestRadar,
      builder: (context, radar, _) {
        if (radar == null) {
          return const SizedBox.shrink();
        }

        final nearest = radar.nearest;
        final color = radar.isClear
            ? Colors.teal
            : (nearest!.distanceM < 40 ? Colors.red : Colors.orange);

        return Card(
          color: color.withValues(alpha: 0.12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(radar.isClear ? Icons.check_circle : Icons.warning,
                    color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: radar.isClear
                      ? const Text('Route dégagée')
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${radar.targets.length} véhicule(s)',
                                style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 4),
                            for (final t in radar.targets)
                              Text('$t',
                                  style: const TextStyle(
                                      fontFamily: 'monospace', fontSize: 12)),
                          ],
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
