import 'package:flutter/material.dart';

import '../ble/sensor_profile.dart';

/// L'icône d'une capacité capteur.
///
/// Volontairement hors de `sensor_profile.dart` : le registre des profils
/// décrit du GATT et ne doit rien savoir de Material. C'est aussi la seule
/// table de correspondance de l'appli — les valeurs en direct et les listes
/// d'appareils tirent leurs icônes d'ici, donc un cœur veut dire « cardio »
/// partout.
IconData iconFor(SensorKind kind) => switch (kind) {
      SensorKind.heartRate => Icons.favorite,
      SensorKind.power => Icons.bolt,
      SensorKind.speedCadence => Icons.autorenew,
      SensorKind.gears => Icons.settings,
      SensorKind.radar => Icons.radar,
      SensorKind.battery => Icons.battery_full,
    };

/// Icône d'un appareil dont on ne sait pas encore ce qu'il mesure : jamais
/// connecté, ou connecté sans qu'aucun profil connu n'ait été reconnu.
const unknownSensorIcon = Icons.bluetooth;

/// L'icône qui représente le mieux un appareil multi-profils.
///
/// Un boîtier qui publie puissance *et* cadence est d'abord un capteur de
/// puissance : on prend le premier profil dans l'ordre du registre, qui est
/// aussi l'ordre d'importance.
IconData iconForDevice(Set<SensorKind> kinds) {
  for (final profile in sensorProfiles) {
    if (kinds.contains(profile.kind)) return iconFor(profile.kind);
  }
  return unknownSensorIcon;
}

/// La rangée d'icônes d'un appareil, une par capacité détectée.
class SensorKindIcons extends StatelessWidget {
  const SensorKindIcons(this.kinds, {super.key, this.size = 15});

  final Set<SensorKind> kinds;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).textTheme.bodySmall?.color;
    if (kinds.isEmpty) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.help_outline, size: size, color: color),
          const SizedBox(width: 6),
          Text('capacités inconnues',
              style: Theme.of(context).textTheme.bodySmall),
        ],
      );
    }

    // Icône *et* libellé : un cœur se lit d'un coup d'œil, mais rien ne dit
    // qu'une roue crantée veut dire « Di2 » avant de l'avoir appris.
    return Wrap(
      spacing: 10,
      runSpacing: 2,
      children: [
        for (final profile in sensorProfiles)
          if (kinds.contains(profile.kind))
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(iconFor(profile.kind), size: size, color: color),
                const SizedBox(width: 4),
                Text(profile.label,
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
      ],
    );
  }
}
