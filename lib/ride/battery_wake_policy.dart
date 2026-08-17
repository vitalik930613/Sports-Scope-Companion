/// Rallumer l'écran quand une batterie passe sous le seuil, le rendre à la
/// veille une fois le maintien passé.
///
/// Contrairement à [RadarWakePolicy], il n'y a pas d'état continu à observer
/// tic après tic — une batterie ne « redevient » pas basse d'une trame à
/// l'autre comme une voiture reste en portée. C'est un franchissement,
/// [trigger], suivi d'un maintien fixe : le temps de voir *quel* appareil est
/// concerné et à quel pourcentage, avant que l'écran ne se rendorme.
///
/// Classe pure, pilotée par une horloge passée en paramètre — même famille
/// que [RadarWakePolicy] et [AutoReturnPolicy].
class BatteryWakePolicy {
  BatteryWakePolicy({this.hold = const Duration(seconds: 6)});

  /// Combien de temps l'écran reste allumé après la dernière alerte.
  final Duration hold;

  bool _awake = false;
  DateTime? _triggeredAt;

  /// L'écran doit-il être réveillé, veille demandée ou non ? L'arbitrage
  /// appartient à [ScreenPolicy].
  bool get awake => _awake;

  /// Une alerte batterie vient d'arriver.
  ///
  /// Rend vrai seulement sur le front veille → réveil : une deuxième alerte
  /// pendant le maintien le prolonge (repart de zéro) sans redemander le
  /// réveil à [ScreenPolicy], qui l'a déjà accordé.
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

  void reset() {
    _awake = false;
    _triggeredAt = null;
  }
}
