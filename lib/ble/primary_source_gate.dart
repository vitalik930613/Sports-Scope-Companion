/// Qui a la parole quand deux appareils mesurent la même chose.
///
/// Le hub n'a qu'**une** valeur par mesure : une ceinture et une montre
/// connectées ensemble écrivaient à tour de rôle dans le même
/// `latestHeartRate`, et l'enregistrement tricotait les deux courbes. Le
/// cycliste désigne donc une source principale ; les autres ne servent que de
/// **relève**.
///
/// La relève n'est pas un luxe : une ceinture qui glisse ou dont la pile
/// flanche se tait en pleine sortie, et une trace sans cardio ne se rattrape
/// pas. Le principal garde la main tant qu'il a donné une mesure utile depuis
/// moins de [silence] ; au-delà, les autres reprennent, et il la retrouve à sa
/// première mesure utile.
///
/// « Utile » veut dire non nulle : une ceinture posée sur la table peut
/// continuer d'émettre des zéros, qui ne doivent ni tenir la place du
/// principal ni s'intercaler entre les mesures de la relève.
///
/// Pur, sans horloge à lui : l'horodatage vient de la trame.
class PrimarySourceGate {
  PrimarySourceGate({this.silence = const Duration(seconds: 5)});

  final Duration silence;

  String? _primary;
  DateTime? _primaryLiveAt;
  DateTime? _othersLiveAt;

  /// Faut-il retenir cette mesure venue de [source] ?
  ///
  /// [primary] est relu à chaque appel plutôt que figé : il se choisit sur la
  /// page des capteurs, pendant que les trames arrivent. Un changement de
  /// principal efface ce qu'on savait de l'ancien, sans quoi il garderait la
  /// main quelques secondes après avoir été détrôné.
  bool accept({
    required String source,
    required String? primary,
    required DateTime at,
    required bool live,
  }) {
    if (primary != _primary) {
      _primary = primary;
      _primaryLiveAt = null;
      _othersLiveAt = null;
    }
    if (primary == null) return true;

    if (source == primary) {
      if (live) {
        _primaryLiveAt = at;
        return true;
      }
      return !_isFresh(_othersLiveAt, at);
    }

    if (live) _othersLiveAt = at;
    return !_isFresh(_primaryLiveAt, at);
  }

  bool _isFresh(DateTime? lastAt, DateTime at) =>
      lastAt != null && at.difference(lastAt) < silence;
}
