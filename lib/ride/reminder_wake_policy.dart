/// Rallumer l'écran pour un rappel, et le rendre à la veille une fois le
/// maintien passé.
///
/// Même mécanique que `BatteryWakePolicy` — un franchissement ([trigger])
/// suivi d'un maintien fixe, pas d'état continu à observer tic après tic —
/// mais un canal séparé dans `ScreenPolicy` : un rappel ne pilote pas
/// `radarWake` (réservé à `RadarWakePage`), il n'a d'ailleurs pas de page
/// dédiée, seulement le toast (`ReminderBanner`) qui se pose par-dessus
/// tout. Le maintien tient aussi le bandeau visible — voir
/// `RideShellPage._updateReminders`, qui vide `_reminderAlert` sur le même
/// front que celui-ci referme la veille.
///
/// Classe pure, pilotée par une horloge passée en paramètre — même famille
/// que `RadarWakePolicy`, `BatteryWakePolicy` et `AutoReturnPolicy`.
class ReminderWakePolicy {
  ReminderWakePolicy({this.hold = const Duration(seconds: 10)});

  /// Combien de temps l'écran (et le toast) restent visibles après le
  /// dernier rappel. Plus long que la batterie (6 s) : un pourcentage se lit
  /// d'un chiffre, un rappel est une phrase qu'on doit avoir le temps de
  /// finir sans s'arrêter de rouler.
  final Duration hold;

  bool _awake = false;
  DateTime? _triggeredAt;

  bool get awake => _awake;

  /// Un rappel vient de tomber.
  ///
  /// Rend vrai seulement sur le front veille → réveil : un second rappel
  /// pendant le maintien le prolonge (repart de zéro) sans redemander le
  /// réveil à `ScreenPolicy`, qui l'a déjà accordé.
  bool trigger(DateTime now) {
    _triggeredAt = now;
    if (_awake) return false;
    _awake = true;
    return true;
  }

  /// À appeler à chaque tic : referme le réveil une fois le maintien passé.
  /// Rend vrai seulement sur ce front-là.
  bool update(DateTime now) {
    if (!_awake) return false;
    final triggeredAt = _triggeredAt;
    if (triggeredAt != null && now.difference(triggeredAt) < hold) {
      return false;
    }
    _awake = false;
    _triggeredAt = null;
    return true;
  }
}
