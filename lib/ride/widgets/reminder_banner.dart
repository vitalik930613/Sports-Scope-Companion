import 'package:flutter/material.dart';

import '../../dashboard/ride_preset.dart';

/// Le rappel périodique du profil — boire, manger, entamer une intervalle —
/// montré en grand pendant que `ReminderWakePolicy` tient l'écran réveillé.
///
/// Un rappel est une phrase qu'on doit pouvoir lire d'un coup d'œil en
/// roulant, sans s'arrêter dessus — c'est la « grosse alerte » demandée, pas
/// une pastille de plus.
///
/// Pure information : aucun geste à voler, rien à traverser pour continuer de
/// rouler. Contrairement à l'alerte batterie (`BatteryAlertPage`), qui est
/// plein écran et bloquante — un rappel n'a pas besoin d'être acquitté.
class ReminderBanner extends StatelessWidget {
  const ReminderBanner({super.key, required this.reminders});

  /// Les rappels tombés au même tic — jamais vide (la coquille efface le
  /// bandeau en vidant la liste plutôt qu'en le montrant vide). Rejoints par
  /// une puce quand deux intervalles coïncident, comme `BatteryAlertBanner`
  /// le fait pour deux appareils : un seul toast plutôt que deux qui
  /// s'empileraient.
  final List<ReminderSpec> reminders;

  static const _accent = Color(0xFF5C6BC0);

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _accent, width: 2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.notifications_active,
                  color: _accent,
                  size: 32,
                ),
                const SizedBox(width: 14),
                Flexible(
                  child: Text(
                    reminders.map((r) => r.message).join(' · '),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 26,
                      height: 1.2,
                    ),
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
