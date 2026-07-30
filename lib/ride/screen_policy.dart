/// Qui a le dernier mot sur le rétroéclairage : la page demande, la coquille
/// arbitre.
///
/// La page de navigation sait se mettre en veille toute seule — carte figée,
/// voile noir — et demande alors 1 % de luminosité, ce qu'un navigateur ne peut
/// pas faire lui-même. Mais elle ignore tout du tableau de bord : une page de
/// données peut être affichée par-dessus, et éteindre l'écran d'un cycliste en
/// train de lire ses watts serait absurde.
///
/// D'où l'arbitrage ici : la demande de la page est **retenue** plutôt que
/// refusée. Revenir sur la carte rend la veille sans que la page ait à la
/// redemander — elle se croit déjà endormie et ne redira rien.
class ScreenPolicy {
  bool _requested = false;
  int _page = 0;
  bool _dimmed = false;

  /// L'écran doit-il être assombri, tout compte fait ?
  bool get dimmed => _dimmed;

  /// La page entre ou sort de sa veille.
  bool pageRequested(bool dim) {
    _requested = dim;
    return _settle();
  }

  /// Le cycliste a changé de page.
  bool movedTo(int page) {
    _page = page;
    return _settle();
  }

  /// La page a été rechargée : son voile est parti avec son état, et elle ne
  /// dira pas qu'elle s'est réveillée. Sans ça, un rechargement en pleine veille
  /// laisserait l'appareil à 1 % pour le reste de la sortie.
  bool pageReloaded() {
    _requested = false;
    return _settle();
  }

  /// Rend vrai quand l'état effectif vient de changer — la coquille n'appelle le
  /// réglage de luminosité que sur les transitions, pas à chaque message.
  bool _settle() {
    final next = _requested && _page == 0;
    if (next == _dimmed) return false;
    _dimmed = next;
    return true;
  }
}
