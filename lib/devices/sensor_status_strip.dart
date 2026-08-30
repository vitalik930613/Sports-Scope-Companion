import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../ble/sensor_connection.dart';
import '../ble/sensor_hub.dart';
import '../ride/battery_status.dart';
import '../ui/sensor_icons.dart';
import '../ui/zone_colors.dart';
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
///
/// Sous chaque capteur **connecté** qui expose son niveau, une pastille de
/// batterie ([SensorBatteryBadge]) : la rangée disait déjà qui répond, lui
/// coller le pourcentage dessous répond du même coup à « combien il leur
/// reste » — ce qui a permis de retirer la carte « Batteries » qui répétait la
/// liste des capteurs juste en dessous.
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
                            runSpacing: 12,
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

  /// La pastille d'un capteur, recolorée à chaque changement d'état, avec sous
  /// elle son niveau de batterie tant qu'il est connecté.
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
      builder: (context, status, _) {
        final dot = SensorLinkDot(
            icon: icon, name: name, status: status, autoConnect: autoConnect);
        // La batterie ne se montre que sous un capteur qui répond : la dernière
        // lecture d'un capteur qui a décroché se lirait sinon comme du direct,
        // exactement le contresens que l'orange de l'icône sert à éviter.
        if (status != SensorStatus.connected) return dot;
        return ValueListenableBuilder<int?>(
          valueListenable: connection.batteryLevel,
          builder: (context, percent, _) {
            if (percent == null) return dot;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                dot,
                const SizedBox(height: 4),
                SensorBatteryBadge(percent: percent),
              ],
            );
          },
        );
      },
    );
  }
}

/// Le niveau de batterie d'un capteur connecté, en pastille sous son icône.
///
/// Peinte de la même palette que les zones (`batteryLevelColor`) — rouge sous
/// l'alerte, vert plein — comme le faisait la carte « Batteries » qu'elle
/// remplace. Jamais rendue sans lecture (`percent` est non nul par
/// construction) : un `0 %` se lirait comme une batterie vide.
class SensorBatteryBadge extends StatelessWidget {
  const SensorBatteryBadge({super.key, required this.percent});

  final int percent;

  @override
  Widget build(BuildContext context) {
    final color = batteryLevelColor(percent);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$percent%',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: foregroundOf(color),
        ),
      ),
    );
  }
}

/// Une icône de capteur, colorée par son état — et **barrée** quand on a décidé
/// de ne plus s'y reconnecter.
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
    final color = sensorLinkColor(status, autoConnect: autoConnect);
    // Le nom et l'état ne sont pas peints : cinq capteurs tiendraient alors sur
    // trois lignes, et l'accueil doit se lire en un coup d'œil. Ils restent
    // atteignables par appui long, et en entier sur la page des capteurs.
    return Tooltip(
      message: '$name · ${sensorStatusLabel(status, autoConnect: autoConnect)}',
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(icon, size: size, color: color),
            if (!autoConnect) SensorLinkStrike(size: size, color: color),
          ],
        ),
      ),
    );
  }
}

/// La barre d'un capteur écarté.
///
/// Tracée à la main plutôt que d'utiliser les icônes `…_off` de Material : il
/// n'en existe pas pour chaque capacité (aucun « cœur barré », aucun
/// « éclair barré » assorti aux nôtres), et changer d'icône ferait en plus
/// perdre *ce qu'est* le capteur — or c'est justement ce qu'on doit continuer
/// de lire pour savoir lequel on a mis de côté.
class SensorLinkStrike extends StatelessWidget {
  const SensorLinkStrike({super.key, required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: math.pi / 4,
      child: Container(
        width: size * 1.15,
        height: math.max(1.5, size / 13),
        color: color,
      ),
    );
  }
}
