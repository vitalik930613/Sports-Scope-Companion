/// Convertit les compteurs cumulés d'événements BLE (tours de manivelle ou de
/// roue) en une fréquence instantanée.
///
/// Les profils Cycling Power et CSC ne publient pas une cadence, mais un
/// couple *(tours cumulés, horodatage du dernier tour)*. La fréquence se
/// calcule par différence entre deux notifications — d'où un décodeur avec
/// état, un par capteur connecté.
///
/// Les deux compteurs bouclent : sur 16 bits pour l'horodatage (donc toutes
/// les 64 s en 1/1024 s), et sur [revolutionsBits] pour les tours. Les deltas
/// sont donc calculés modulo, sans quoi une cadence part en négatif toutes les
/// minutes.
class RevCounter {
  RevCounter({
    required this.timeUnitHz,
    this.revolutionsBits = 16,
  });

  /// Résolution de l'horodatage : 1024 Hz partout, sauf la roue en Cycling
  /// Power qui est en 2048 Hz.
  final int timeUnitHz;

  /// Largeur du compteur de tours : 16 bits (manivelle) ou 32 (roue).
  final int revolutionsBits;

  int? _lastRevolutions;
  int? _lastEventTime;

  /// Tours par seconde depuis la notification précédente.
  ///
  /// Retourne `null` sur la toute première trame (pas de référence), et 0 si
  /// aucun tour n'a eu lieu — pédalage arrêté : le capteur continue d'émettre
  /// avec un horodatage figé, ce qui doit se lire comme une cadence nulle et
  /// non comme une absence de donnée.
  double? update(int revolutions, int eventTime) {
    final prevRevs = _lastRevolutions;
    final prevTime = _lastEventTime;
    _lastRevolutions = revolutions;
    _lastEventTime = eventTime;

    if (prevRevs == null || prevTime == null) return null;

    final revsMask = (1 << revolutionsBits) - 1;
    final deltaRevs = (revolutions - prevRevs) & revsMask;
    final deltaTicks = (eventTime - prevTime) & 0xFFFF;

    if (deltaRevs == 0) return 0;
    if (deltaTicks == 0) return null; // même événement republié

    return deltaRevs * timeUnitHz / deltaTicks;
  }

  void reset() {
    _lastRevolutions = null;
    _lastEventTime = null;
  }
}
