import 'package:flutter/material.dart';

import '../battery_status.dart';

/// Le bandeau qui nomme l'appareil et son pourcentage quand une batterie
/// passe sous le seuil du profil.
///
/// Un bandeau, pas une boîte à fermer : sur la route, une confirmation à
/// traverser coûterait plus cher que l'information qu'elle protège — même
/// principe qu'ailleurs dans la coquille (sortir d'une sortie ne demande
/// aucune confirmation non plus). Il disparaît tout seul, avec le réveil
/// d'écran qui l'accompagne (voir `BatteryWakePolicy`).
///
/// Contrairement à `RadarWakePage`, qui n'a de sens que sous le voile de la
/// carte, une batterie faible est pertinente sur n'importe quelle page du
/// tableau de bord — la coquille le pose donc au sommet de sa pile, visible
/// quelle que soit la page affichée.
class BatteryAlertBanner extends StatelessWidget {
  const BatteryAlertBanner({super.key, required this.devices});

  /// Les appareils qui viennent de franchir le seuil — jamais vide (la
  /// coquille efface le bandeau en vidant la liste plutôt qu'en le montrant
  /// vide).
  final List<BatteryStatus> devices;

  static const _low = Color(0xFFEF5350);

  @override
  Widget build(BuildContext context) {
    // Pure information : le tap de réveil de la carte, le glissé de page et
    // les gestes du bandeau appartiennent tous à ce qui est dessous.
    return IgnorePointer(
      child: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.battery_alert, color: _low, size: 22),
                const SizedBox(width: 8),
                Text(
                  devices
                      .map((d) => '${d.label} ${d.percent} %')
                      .join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
