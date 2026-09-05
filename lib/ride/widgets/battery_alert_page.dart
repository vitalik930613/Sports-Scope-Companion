import 'package:flutter/material.dart';

import '../battery_status.dart';

/// L'alerte plein écran quand une batterie franchit le seuil du profil à la
/// baisse — affichée jusqu'à ce que le cycliste l'écarte, pas un toast qui
/// s'efface tout seul après un délai : un franchissement mérite d'être vu,
/// pas manqué le temps de lever les yeux de la route.
///
/// Deux façons de l'écarter, toutes deux gérées par la coquille et pas ici :
/// un tap dessus ([onDismiss]), ou un changement de page — geste que
/// `RideShellPage._stepPage` détourne en premier pour fermer l'alerte plutôt
/// que de faire avancer le défilement en dessous, qu'il vienne d'un bouton
/// Di2 ou d'une gouttière.
///
/// Contrairement à `RadarWakePage`/`ReminderBanner`, elle capte le tap au
/// lieu de le laisser traverser jusqu'à la page dessous : ici, le tap *est*
/// le geste qui referme.
class BatteryAlertPage extends StatelessWidget {
  const BatteryAlertPage({
    super.key,
    required this.devices,
    required this.onDismiss,
  });

  /// Les appareils sous le seuil, jamais vide (la coquille efface la page en
  /// vidant la liste plutôt qu'en la montrant vide). S'accumulent d'un
  /// franchissement à l'autre tant que l'alerte n'a pas été écartée — un
  /// deuxième capteur qui passe sous le seuil pendant qu'on lit le premier ne
  /// doit pas le faire disparaître de l'écran.
  final List<BatteryStatus> devices;

  final VoidCallback onDismiss;

  static const _low = Color(0xFFEF5350);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onDismiss,
      child: ColoredBox(
        color: Colors.black,
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.battery_alert, color: _low, size: 72),
                  const SizedBox(height: 20),
                  for (final device in devices)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        '${device.label} · ${device.percent} %',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 30,
                          height: 1.2,
                        ),
                      ),
                    ),
                  const SizedBox(height: 28),
                  Text(
                    'Toucher l’écran ou changer de page pour continuer',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
