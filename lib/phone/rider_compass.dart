import 'dart:async';

import 'package:flutter/foundation.dart';

import '../recording/gps_fix.dart';
import 'compass_heading.dart';
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

  /// Le cap à afficher **quand la page ne peut pas le calculer** — c'est-à-dire
  /// à l'arrêt. `null` tant que la boussole n'a pas fait ses preuves contre le
  /// GPS, ou en roulant, où la course GPS est meilleure.
  double? get standstillHeadingDeg =>
      _heading.isFromCompass ? _heading.headingDeg : null;

  /// Décalage mesuré entre la boussole et la réalité, pour le diagnostic.
  double? get offsetDeg => _heading.offsetDeg;

  bool get isTrusted => _heading.isTrusted;

  void start() {
    if (_sub != null || phone == null) return;
    _sub = phone!.headingDeg().listen(_heading.addCompass, onError: (Object e) {
      debugPrint('[boussole] flux en erreur : $e');
    });
  }

  /// Range une position. C'est elle qui **valide** la boussole : sans course GPS
  /// à laquelle se comparer, on ne saurait pas qu'un support aimanté la fausse.
  void addFix(GpsFix? fix) {
    if (fix == null) return;
    final course = fix.headingDeg;
    final speed = fix.speedMps;
    if (course == null || speed == null) return;
    _heading.addCourse(courseDeg: course, speedMps: speed);
    // La déclinaison magnétique dépend de l'endroit : on la redonne au natif
    // quand on a bougé assez pour qu'elle ait changé de façon mesurable.
    _refreshDeclination(fix);
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
