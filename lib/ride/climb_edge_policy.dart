/// Stabilise `NavState.climb` avant d'en tirer un tour, un reset de profil ou
/// l'ouverture automatique de la page col.
///
/// La page web pousse `climb` brut, ~1×/s : non-`null` dès que la position
/// estimée est jugée dans un col. En simulation (et parfois avec un GPS
/// bruité) cette position oscille facilement de part et d'autre de la
/// frontière — `climb` repasse alors `null` puis non-`null` d'une trame à
/// l'autre. Sans filtre, chaque flicker faisait battre la page col
/// (`_nearCol`), ouvrait un tour parasite (`RideRecorder.markLap`) et vidait
/// le profil affiché (`_climbProfile.reset()`) le temps qu'il se remplisse à
/// nouveau — trois symptômes d'une seule cause.
///
/// Même patron que [RadarWakePolicy] : l'entrée est immédiate (rater le
/// début d'un col serait pire), la sortie est retenue [hold] — une vraie fin
/// de col la dépasse largement, un flicker jamais.
class ClimbEdgePolicy {
  ClimbEdgePolicy({this.hold = const Duration(seconds: 5)});

  /// Combien de temps le col reste « en cours » après la dernière trame qui
  /// le signale.
  final Duration hold;

  bool _climbing = false;
  DateTime? _clearedAt;

  /// L'état stabilisé — celui que doivent lire [_nearCol] et l'affichage.
  bool get climbing => _climbing;

  /// Rend vrai quand l'état vient de changer : c'est ce front-là, et lui
  /// seul, qui doit ouvrir/fermer un tour ou (re)mettre à zéro le profil
  /// affiché.
  bool update({required DateTime now, required bool climbing}) {
    if (climbing) {
      // Le maintien repart de zéro : un flicker vers `null` pendant le délai
      // ne doit pas laisser la sortie s'installer.
      _clearedAt = null;
      if (_climbing) return false;
      _climbing = true;
      return true;
    }

    if (!_climbing) return false;

    final clearedAt = _clearedAt ??= now;
    if (now.difference(clearedAt) < hold) return false;
    _climbing = false;
    _clearedAt = null;
    return true;
  }

  void reset() {
    _climbing = false;
    _clearedAt = null;
  }
}
