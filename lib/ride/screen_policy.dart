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
///
/// Le radar suspend la veille de la même façon, et pour la même raison : la page
/// web ignore qu'une voiture remonte, et une alerte à 1 % de rétroéclairage est
/// une alerte que personne ne voit. La demande de veille survit au passage de la
/// voiture, donc l'écran se rendort tout seul.
class ScreenPolicy {
  bool _requested = false;

  /// La veille demandée par **l'appui long de l'appli**, hors de la carte.
  ///
  /// Séparée de celle de la page web parce qu'elle ne se retient pas de la même
  /// façon : celle de la page ne vaut que sur la carte, la nôtre vaut là où le
  /// doigt s'est posé — une page de données, le bandeau, un bilan ouvert depuis
  /// le menu. Les fondre en un seul drapeau ferait éteindre l'écran d'un
  /// cycliste qui lit ses watts, ce que [_onMap] existe précisément pour
  /// empêcher.
  bool _held = false;

  /// Le cycliste est-il sur la carte ? Un booléen et non un index : la carte se
  /// place où l'on veut dans le profil, et certains profils n'en ont pas du tout
  /// (home-trainer). Comparer à zéro revenait à supposer les deux.
  bool _onMap = true;

  bool _radarAwake = false;
  bool _dimmed = false;

  /// L'écran doit-il être assombri, tout compte fait ?
  bool get dimmed => _dimmed;

  /// L'écran est endormi, d'où que vienne la demande.
  bool get _asleep => _held || (_requested && _onMap);

  /// La veille est-elle interrompue par le radar, et par lui seul ? C'est ce qui
  /// met la page radar à l'écran : sous un voile noir — celui de la page web ou
  /// le nôtre — il n'y a rien d'autre à regarder. Hors veille, la carte et ses
  /// gouttières disent déjà tout, et il n'y a rien à recouvrir.
  bool get radarWake => _asleep && _radarAwake;

  /// Le voile de l'appli est-il posé ? Celui de la page web, lui, est peint par
  /// la page : quand elle s'endort, l'appli n'a rien à recouvrir.
  bool get veiled => _held && !_radarAwake;

  /// La page entre ou sort de sa veille.
  bool pageRequested(bool dim) {
    _requested = dim;
    return _settle();
  }

  /// L'appui long de l'appli endort, un tap sur le voile réveille.
  bool holdRequested(bool dim) {
    _held = dim;
    return _settle();
  }

  /// Le radar réveille l'écran, ou rend la veille (voir [RadarWakePolicy], qui
  /// tient le délai).
  bool radarAwake(bool awake) {
    _radarAwake = awake;
    return _settle();
  }

  /// Le cycliste a changé de page.
  bool movedTo({required bool onMap}) {
    _onMap = onMap;
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
    final next = _asleep && !_radarAwake;
    if (next == _dimmed) return false;
    _dimmed = next;
    return true;
  }
}
