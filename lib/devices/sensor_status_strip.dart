import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../ble/sensor_connection.dart';
import '../ble/sensor_hub.dart';
import '../ui/sensor_icons.dart';
import 'known_devices_store.dart';
import 'sensor_link_status.dart';

/// L'état des capteurs connus, en une rangée d'icônes.
///
/// C'est ce que l'accueil doit dire avant une sortie : est-ce que tout ce que
/// j'ai appairé répond. Une icône par capteur mémorisé, verte s'il est
/// connecté, orange sinon — la forme dit *quel* capteur, la couleur dit s'il
/// mesurera quelque chose. Les listes, le scan et l'appairage sont derrière,
/// sur la page des capteurs : on appaire une fois, on part rouler tous les
/// jours.
class SensorStatusStrip extends StatelessWidget {
  const SensorStatusStrip({
    super.key,
    required this.devices,
    required this.hub,
    required this.onTap,
  });

  final KnownDevicesStore devices;
  final SensorHub hub;

  /// Ouvre la page des capteurs. Toute la carte est tapable : une pastille
  /// orange est une question, et la réponse est toujours sur cette page-là.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Reconstruit sur le magasin : un capteur appairé sur la sous-page doit
    // apparaître ici au retour, sans que l'accueil ait à se rafraîchir.
    return ListenableBuilder(
      listenable: devices,
      builder: (context, _) {
        final known = devices.devices;

        return Card(
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Mes capteurs',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        if (known.isEmpty)
                          Text(
                            'Aucun capteur appairé',
                            style: Theme.of(context).textTheme.bodySmall,
                          )
                        else
                          Wrap(
                            spacing: 14,
                            runSpacing: 10,
                            children: [
                              for (final device in known)
                                _dotFor(device.remoteId,
                                    icon: iconForDevice(device.kinds),
                                    name: device.name.isEmpty
                                        ? '(sans nom)'
                                        : device.name,
                                    autoConnect: device.autoConnect),
                            ],
                          ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// La pastille d'un capteur, recolorée à chaque changement d'état.
  ///
  /// L'abonnement est pris sur la connexion elle-même : un capteur qui décroche
  /// en cours de route doit passer à l'orange sans que personne redessine
  /// l'accueil. Sans connexion ouverte, il n'y a rien à écouter — l'icône est
  /// orange et le restera jusqu'au prochain rattachement, qui, lui, passe par
  /// le magasin et reconstruit toute la rangée.
  Widget _dotFor(
    String remoteId, {
    required IconData icon,
    required String name,
    required bool autoConnect,
  }) {
    final connection = hub.connectionFor(DeviceIdentifier(remoteId));
    if (connection == null) {
      return SensorLinkDot(
          icon: icon, name: name, status: null, autoConnect: autoConnect);
    }
    return ValueListenableBuilder<SensorStatus>(
      valueListenable: connection.status,
      builder: (context, status, _) => SensorLinkDot(
          icon: icon, name: name, status: status, autoConnect: autoConnect),
    );
  }
}

/// Une icône de capteur, colorée par son état.
class SensorLinkDot extends StatelessWidget {
  const SensorLinkDot({
    super.key,
    required this.icon,
    required this.name,
    required this.status,
    this.autoConnect = true,
    this.size = 26,
  });

  final IconData icon;
  final String name;
  final SensorStatus? status;
  final bool autoConnect;
  final double size;

  @override
  Widget build(BuildContext context) {
    // Le nom et l'état ne sont pas peints : cinq capteurs tiendraient alors sur
    // trois lignes, et l'accueil doit se lire en un coup d'œil. Ils restent
    // atteignables par appui long, et en entier sur la page des capteurs.
    return Tooltip(
      message: '$name · ${sensorStatusLabel(status, autoConnect: autoConnect)}',
      child: Icon(icon, size: size, color: sensorLinkColor(status)),
    );
  }
}
