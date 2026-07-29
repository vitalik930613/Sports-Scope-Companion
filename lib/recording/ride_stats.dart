import 'dart:collection';
import 'dart:math' as math;

import 'track_point.dart';

/// Ce qu'on peut dire d'une sortie, point par point.
///
/// Une seule définition de « puissance moyenne », de « dénivelé positif » et de
/// leurs voisines, partagée entre l'écran et le `.fit`. Avant, ces calculs ne
/// vivaient qu'au moment de l'export : le tableau de bord aurait dû les refaire,
/// et les deux auraient fini par diverger sur un détail (un point sans capteur
/// compté ou non, une hystérésis différente) — exactement le genre d'écart
/// qu'un cycliste remarque et qui fait douter des deux chiffres.
///
/// Alimenter en direct avec [add] (un appel par point capturé), ou d'un coup
/// avec [of]. Les deux chemins passent par le même code : ce que l'écran affiche
/// pendant la sortie est ce que le fichier contiendra à l'arrivée.
class RideStats {
  RideStats({
    this.altitudeNoiseM = defaultAltitudeNoiseM,
    this.normalizedWindow = defaultNormalizedWindow,
  });

  /// Seuil de bruit du dénivelé : l'altitude GPS oscille de quelques mètres à
  /// l'arrêt. Sans hystérésis, une pause de dix minutes « gravit » cent mètres.
  static const defaultAltitudeNoiseM = 1.0;

  /// Fenêtre de la moyenne glissante de la puissance normalisée, en points.
  /// Les points sont capturés une fois par seconde, donc 30 points ≈ 30 s —
  /// la fenêtre de la définition d'origine.
  static const defaultNormalizedWindow = 30;

  final double altitudeNoiseM;
  final int normalizedWindow;

  double distanceM = 0;
  double ascentM = 0;
  double descentM = 0;

  double? firstLat;
  double? firstLng;
  double? lastLat;
  double? lastLng;

  bool hasPosition = false;
  bool hasAltitude = false;
  bool hasHeartRate = false;
  bool hasCadence = false;
  bool hasPower = false;
  bool hasSpeed = false;

  int? maxHeartRate;
  int? maxCadence;
  int? maxPower;
  double? maxSpeedMps;

  // Sommes courantes : les moyennes sont des accesseurs, pour qu'une valeur lue
  // en cours de sortie soit toujours celle des points déjà vus — pas celle d'un
  // total figé au dernier calcul.
  int _hrSum = 0;
  int _hrCount = 0;
  double _cadenceSum = 0;
  int _cadenceCount = 0;
  int _powerSum = 0;
  int _powerCount = 0;
  double _speedSum = 0;
  int _speedCount = 0;
  double? _altitudeReference;

  // Puissance normalisée : moyenne glissante sur la fenêtre, puis racine
  // quatrième de la moyenne des puissances quatrièmes de cette moyenne.
  final Queue<int> _npWindow = Queue<int>();
  int _npWindowSum = 0;
  double _npFourthSum = 0;
  int _npCount = 0;

  int? get avgHeartRate => _hrCount > 0 ? (_hrSum / _hrCount).round() : null;

  int? get avgCadence =>
      _cadenceCount > 0 ? (_cadenceSum / _cadenceCount).round() : null;

  int? get avgPower => _powerCount > 0 ? (_powerSum / _powerCount).round() : null;

  double? get avgSpeedMps => _speedCount > 0 ? _speedSum / _speedCount : null;

  /// Puissance normalisée, `null` tant que la fenêtre n'est pas pleine : sur
  /// moins de 30 s la valeur n'aurait aucun sens, et un chiffre faux vaut moins
  /// qu'un tiret.
  int? get normalizedPowerW =>
      _npCount > 0 ? math.pow(_npFourthSum / _npCount, 0.25).round() : null;

  /// La vitesse d'un point : celle du GPS, ou à défaut celle du capteur de roue.
  ///
  /// Le GPS d'abord parce qu'il ne dépend d'aucun réglage ; le capteur de roue
  /// en secours parce qu'il continue de mesurer là où le GPS ne voit plus rien
  /// (tunnel, forêt dense).
  static double? speedOf(TrackPoint point) =>
      point.speedMps ?? point.wheelSpeedMps;

  /// Replie une sortie entière. Passe par [add] point par point, donc donne
  /// exactement le même résultat qu'un cumul en direct.
  static RideStats of(Iterable<TrackPoint> points) {
    final stats = RideStats();
    for (final point in points) {
      stats.add(point);
    }
    return stats;
  }

  void add(TrackPoint point) {
    distanceM = point.distanceM;

    if (point.hasPosition) {
      hasPosition = true;
      firstLat ??= point.lat;
      firstLng ??= point.lng;
      lastLat = point.lat;
      lastLng = point.lng;
    }

    final altitude = point.altitudeM;
    if (altitude != null) {
      hasAltitude = true;
      _altitudeReference ??= altitude;
      if (altitude - _altitudeReference! > altitudeNoiseM) {
        ascentM += altitude - _altitudeReference!;
        _altitudeReference = altitude;
      } else if (_altitudeReference! - altitude > altitudeNoiseM) {
        descentM += _altitudeReference! - altitude;
        _altitudeReference = altitude;
      }
    }

    final heartRate = point.heartRate;
    if (heartRate != null) {
      hasHeartRate = true;
      _hrSum += heartRate;
      _hrCount++;
      maxHeartRate = _max(maxHeartRate, heartRate);
    }

    final cadence = point.cadence;
    if (cadence != null) {
      hasCadence = true;
      _cadenceSum += cadence;
      _cadenceCount++;
      maxCadence = _max(maxCadence, cadence.round());
    }

    final power = point.power;
    if (power != null) {
      hasPower = true;
      _powerSum += power;
      _powerCount++;
      maxPower = _max(maxPower, power);
      _addNormalized(power);
    }

    final speed = speedOf(point);
    if (speed != null) {
      hasSpeed = true;
      _speedSum += speed;
      _speedCount++;
      maxSpeedMps =
          maxSpeedMps == null || speed > maxSpeedMps! ? speed : maxSpeedMps;
    }
  }

  /// Les trous sans puissance sont sautés, pas comblés par des zéros : un
  /// capteur qui décroche trente secondes ne doit pas se lire comme trente
  /// secondes de roue libre.
  void _addNormalized(int power) {
    _npWindow.addLast(power);
    _npWindowSum += power;
    if (_npWindow.length > normalizedWindow) {
      _npWindowSum -= _npWindow.removeFirst();
    }
    if (_npWindow.length < normalizedWindow) return;

    final rolling = _npWindowSum / normalizedWindow;
    _npFourthSum += rolling * rolling * rolling * rolling;
    _npCount++;
  }

  /// Remet tout à zéro pour une nouvelle sortie, sans réallouer.
  void reset() {
    distanceM = 0;
    ascentM = 0;
    descentM = 0;
    firstLat = firstLng = lastLat = lastLng = null;
    hasPosition = hasAltitude = hasHeartRate = false;
    hasCadence = hasPower = hasSpeed = false;
    maxHeartRate = maxCadence = maxPower = null;
    maxSpeedMps = null;
    _hrSum = _hrCount = 0;
    _cadenceSum = 0;
    _cadenceCount = 0;
    _powerSum = _powerCount = 0;
    _speedSum = 0;
    _speedCount = 0;
    _altitudeReference = null;
    _npWindow.clear();
    _npWindowSum = 0;
    _npFourthSum = 0;
    _npCount = 0;
  }

  static int _max(int? current, int value) =>
      current == null || value > current ? value : current;
}
