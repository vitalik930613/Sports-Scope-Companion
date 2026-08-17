import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../ride/battery_status.dart';

/// L'état des batteries des capteurs connus, en une carte sur l'accueil.
///
/// Complète [SensorStatusStrip] : la rangée d'icônes dit qui répond, cette
/// carte dit combien il leur reste — la question qu'on se pose avant de
/// partir pour la journée, pas seulement avant une sortie. Une ligne par
/// appareil connu, `—` sans lecture (jamais `0 %`, qui se lirait comme une
/// batterie vide) : un Varia qui n'expose pas le service batterie standard
/// en BLE le dit ainsi plutôt que de disparaître de la liste.
///
/// N'existe pas du tout tant qu'aucun capteur n'est connu : rien à dire avant
/// le premier appairage, et l'accueil n'a pas à réserver une place vide pour
/// une carte qui ne sert à personne le premier jour.
class BatteryStatusCard extends StatelessWidget {
  const BatteryStatusCard({
    super.key,
    required this.battery,
    required this.onTap,
  });

  final ValueListenable<List<BatteryStatus>> battery;

  /// Ouvre la page des capteurs — même geste que [SensorStatusStrip] : c'est
  /// là qu'on renomme, recharge ou oublie un appareil.
  final VoidCallback onTap;

  static const _low = Color(0xFFD32F2F);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<BatteryStatus>>(
      valueListenable: battery,
      builder: (context, devices, _) {
        if (devices.isEmpty) return const SizedBox.shrink();

        return Card(
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Batteries', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  for (final device in devices) _row(context, device),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _row(BuildContext context, BatteryStatus device) {
    final color = device.low ? _low : null;
    // Grisée plutôt qu'effacée : la dernière lecture reste affichée (un
    // capteur débranché n'efface pas ce qu'il a mesuré), mais ce n'est plus
    // du direct — sans ce grisé, un capteur éteint depuis hier se lirait
    // comme un capteur qui répond là, maintenant.
    return Opacity(
      opacity: device.connected ? 1 : 0.45,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(device.icon, size: 20, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(device.label, overflow: TextOverflow.ellipsis),
            ),
            Text(
              device.percent == null ? '—' : '${device.percent} %',
              style: TextStyle(fontWeight: FontWeight.w600, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
