/// Rallumer l'écran quand une voiture remonte, le rendre à la veille quand elle
/// est passée.
///
/// En veille, la page web est sous son voile noir et le rétroéclairage à 1 %.
/// Le cadre, les gouttières et les mètres du radar sont bien peints — mais à 1 %
/// ils ne se voient pas, et au soleil pas du tout. Or le radar est la seule
/// information de cet écran qui n'attende pas qu'on le regarde : c'est celle
/// qui a le droit de rallumer.
///
/// [hold] est ce qui empêche l'écran de battre. Un véhicule au bout de la portée
/// entre et sort du champ d'une trame à l'autre ; sans maintien, le
/// rétroéclairage suivrait chaque hésitation du capteur, ce qui prendrait plus
/// d'attention que l'alerte n'en mérite. Le délai sert aussi à autre chose : il
/// laisse le temps de voir *pourquoi* l'écran s'éteint — la voie est redevenue
/// libre — au lieu de renvoyer au noir sans un mot.
///
/// Classe pure et pilotée par une horloge passée en paramètre, comme
/// [AutoReturnPolicy] : c'est une décision qu'on ne peut pas essayer autrement
/// qu'avec une vraie voiture derrière soi.
class RadarWakePolicy {
  RadarWakePolicy({this.hold = const Duration(seconds: 5)});

  /// Combien de temps l'écran reste allumé après la dernière trame qui alerte.
  final Duration hold;

  bool _awake = false;
  DateTime? _clearedAt;

  /// L'écran doit-il être réveillé, veille demandée ou non ? L'arbitrage entre
  /// les deux appartient à [ScreenPolicy].
  bool get awake => _awake;

  /// Rend vrai quand l'état vient de changer — la coquille ne touche à la
  /// luminosité que sur les transitions.
  bool update({required DateTime now, required bool alerting}) {
    if (alerting) {
      // Le maintien repart de zéro : une deuxième voiture pendant le délai
      // rallonge le réveil, elle ne le laisse pas expirer.
      _clearedAt = null;
      if (_awake) return false;
      _awake = true;
      return true;
    }

    if (!_awake) return false;

    final clearedAt = _clearedAt ??= now;
    if (now.difference(clearedAt) < hold) return false;
    _awake = false;
    _clearedAt = null;
    return true;
  }

  void reset() {
    _awake = false;
    _clearedAt = null;
  }
}
