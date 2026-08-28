import 'dart:async';

import '../recording/gps_fix.dart';
import 'compass_heading.dart';
import 'debug_log.dart';
import 'phone_sensors.dart';

/// La boussole du cycliste : le magnétomètre du téléphone, arbitré contre les
/// positions GPS.
///
/// Une seule instance, au niveau de l'application — mais **allumée seulement
/// pendant la navigation** ([start] / [stop]). Un magnétomètre laissé branché
/// réveille le processeur en continu, et hors navigation personne ne regarde de
/// flèche.
///
/// La décision elle-même est dans [CompassHeading], pure et testée. Ici il n'y a
/// que de la plomberie : brancher le flux, dater, republier.
class RiderCompass {
  RiderCompass({this.phone, CompassHeading? heading})
      : _heading = heading ?? CompassHeading();

  /// Nul sur un appareil sans magnétomètre — et tout ce dossier se comporte
  /// alors comme avant : [headingDeg] reste nul, la page garde sa flèche GPS.
  final PhoneSensors? phone;

  final CompassHeading _heading;

  StreamSubscription<double>? _sub;

  /// Force la priorité à la boussole, même en roulant — activé par le
  /// cycliste (tap sur la pastille de la carte), pour s'orienter sous un
  /// couvert (forêt) où la vitesse GPS est trop bruitée pour distinguer un
  /// arrêt d'un mouvement, et où c'est justement l'orientation du téléphone
  /// qu'on veut suivre. `false` par défaut, et **remis à `false` à chaque
  /// [start]** : un forçage oublié activé ne doit pas survivre à la sortie où
  /// il a été demandé.
  bool forced = false;

  /// Le cap à pousser vers la page, ou `null` si rien n'est exploitable.
  ///
  /// À l'arrêt, ou si [forced] : la boussole. En roulant sans [forced] :
  /// `null`, la page garde sa propre course GPS — meilleure que n'importe
  /// quelle boussole tant que rien ne dit le contraire, pas la peine de la
  /// concurrencer.
  double? get pushHeadingDeg {
    if (forced) return _heading.correctedDeg;
    return _heading.isFromCompass ? _heading.headingDeg : null;
  }

  /// Décalage mesuré entre la boussole et la réalité, pour le diagnostic.
  double? get offsetDeg => _heading.offsetDeg;

  bool get isTrusted => _heading.isTrusted;

  /// Le cap de la boussole à tout moment, pour la pastille de diagnostic —
  /// jamais pour la page, qui utilise [pushHeadingDeg]. Voir
  /// [CompassHeading.correctedDeg].
  double? get correctedHeadingDeg => _heading.correctedDeg;

  void start() {
    if (_sub != null || phone == null) return;
    forced = false;
    _sub = phone!.headingDeg().listen(_heading.addCompass, onError: (Object e) {
      DebugLog.instance.add('[boussole] flux en erreur : $e');
    });
  }

  /// Range une position. C'est elle qui **valide** la boussole : sans course GPS
  /// à laquelle se comparer, on ne saurait pas qu'un support aimanté la fausse.
  void addFix(GpsFix? fix) {
    if (fix == null) return;
    // La déclinaison magnétique ne dépend que de la position : on la redonne au
    // natif dès qu'on a bougé assez pour qu'elle ait changé de façon mesurable,
    // **avant** le garde sur la course. À pied (le cas du cap forcé) la course
    // GPS manque presque toujours ; la laisser conditionner ce rafraîchissement
    // ferait rester le cap en nord magnétique, faux d'un offset constant.
    _refreshDeclination(fix);
    final course = fix.headingDeg;
    final speed = fix.speedMps;
    if (course == null || speed == null) return;
    _heading.addCourse(courseDeg: course, speedMps: speed);
  }

  GpsFix? _declinationAt;

  /// Distance au-delà de laquelle on recalcule la déclinaison. Elle varie de
  /// l'ordre du degré par centaine de kilomètres : la rafraîchir à chaque point
  /// ne ferait que traverser le canal pour rien.
  static const _declinationStepM = 50000.0;

  void _refreshDeclination(GpsFix fix) {
    final previous = _declinationAt;
    if (previous != null && previous.distanceTo(fix) < _declinationStepM) return;
    _declinationAt = fix;
    unawaited(phone?.setLocation(
      lat: fix.lat,
      lng: fix.lng,
      altitudeM: fix.altitudeM ?? 0,
    ));
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }

  /// Nouveau vélo, nouveau support : ce qu'on avait appris du décalage ne vaut
  /// plus rien.
  void reset() {
    _heading.reset();
    _declinationAt = null;
  }
}
