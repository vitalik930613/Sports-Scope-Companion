import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../ble/sensor_hub.dart';
import '../ble/sensor_profile.dart';
import '../drivetrain.dart';
import 'sensor_icons.dart';

/// Une mesure instantanée : icône, valeur, unité.
///
/// Le briquet d'affichage commun à l'écran des capteurs et au tableau de bord de
/// sortie — un tiret quand la valeur manque, jamais un zéro qui ferait croire à
/// une mesure. Extrait de l'écran des capteurs pour que les deux ne puissent pas
/// diverger de mise en forme.
class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.listenable,
    required this.unit,
    required this.icon,
    this.format,
  });

  final ValueListenable<Object?> listenable;
  final String unit;
  final IconData icon;

  /// Mise en forme de la valeur brute. Par défaut `toString()`, ce qui convient
  /// aux entiers (bpm, watts) mais pas aux doubles (cadence).
  final String Function(Object)? format;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Object?>(
      valueListenable: listenable,
      builder: (context, value, _) => Column(
        children: [
          Icon(icon, size: 20),
          const SizedBox(height: 4),
          Text(
            value == null ? '—' : (format?.call(value) ?? value.toString()),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          Text(unit, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// Les trois mesures continues (cardio, puissance, cadence) et le braquet.
///
/// La transmission sert à traduire une position Di2 en dents et en
/// développement : le Di2 ne publie que des positions, et rien d'autre ne sait
/// ce qu'il y a sur le vélo.
class LiveValuesCard extends StatelessWidget {
  const LiveValuesCard({
    super.key,
    required this.hub,
    this.drivetrain = Drivetrain.road,
  });

  final SensorHub hub;
  final Drivetrain drivetrain;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                MetricTile(
                  listenable: hub.latestHeartRate,
                  unit: 'bpm',
                  icon: iconFor(SensorKind.heartRate),
                ),
                MetricTile(
                  listenable: hub.latestPower,
                  unit: 'W',
                  icon: iconFor(SensorKind.power),
                ),
                MetricTile(
                  listenable: hub.latestCadence,
                  unit: 'tr/min',
                  icon: iconFor(SensorKind.speedCadence),
                  format: (v) => (v as double).round().toString(),
                ),
              ],
            ),
            const Divider(height: 32),
            ValueListenableBuilder(
              valueListenable: hub.latestGears,
              builder: (context, gears, _) {
                if (gears == null) {
                  return const Text('Vitesses : —');
                }
                final front = drivetrain.chainringTeeth(gears);
                final rear = drivetrain.sprocketTeeth(gears);
                final ratio = drivetrain.ratio(gears);
                final dev = drivetrain.development(gears);
                return Column(
                  children: [
                    Text('$gears',
                        style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 4),
                    Text(
                      front != null &&
                              rear != null &&
                              ratio != null &&
                              dev != null
                          // Le ratio se compare d'un vélo à l'autre, le
                          // développement dépend des pneus : les deux servent,
                          // et pas aux mêmes questions.
                          ? '$front × $rear dents · ratio ${ratio.toStringAsFixed(2)} · ${dev.toStringAsFixed(2)} m/tour'
                          : 'dents inconnues pour cette position',
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
