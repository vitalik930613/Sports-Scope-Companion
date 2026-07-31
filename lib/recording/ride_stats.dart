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
    this.baroAltitudeNoiseM = defaultBaroAltitudeNoiseM,
    this.normalizedWindow = defaultNormalizedWindow,
  });

  /// Seuil de bruit du dénivelé : l'altitude GPS oscille de quelques mètres à
  /// l'arrêt. Sans hystérésis, une pause de dix minutes « gravit » cent mètres.
  static const defaultAltitudeNoiseM = 1.0;

  /// Le même seuil, mais pour une altitude barométrique. Dix fois plus fin,
  /// parce que le bruit l'est : un baromètre MEMS oscille de quelques
  /// centimètres là où le GPS oscille de plusieurs mètres. C'est précisément ce
  /// qui fait qu'un faux plat montant finit enfin par être compté.
  static const defaultBaroAltitudeNoiseM = 0.3;

  /// Fenêtre de la moyenne glissante de la puissance normalisée, en points.
  /// Les points sont capturés une fois par seconde, donc 30 points ≈ 30 s —
  /// la fenêtre de la définition d'origine.
  static const defaultNormalizedWindow = 30;

  /// Largeur d'un palier des histogrammes, en bpm et en watts.
  ///
  /// Les mêmes que le site (`ZoneDistribution::HR_BUCKET`, `POWER_BUCKET`) : les
  /// deux répartitions se lisent l'une après l'autre, une sortie ne doit pas
  /// changer de forme selon l'écran qui la montre.
  static const hrBucketBpm = 5;
  static const powerBucketW = 25;

  final double altitudeNoiseM;
  final double baroAltitudeNoiseM;
  final int normalizedWindow;

  /// Temps passé par palier de mesure : borne basse du palier → nombre de points.
  ///
  /// Un histogramme et pas un cumul par zone, exactement comme le site : ce qu'on
  /// accumule est **intrinsèque à la sortie**, indépendant des seuils. Les zones
  /// s'en déduisent à l'affichage (`zoneSecondsOf`), donc un profil qui arrive en
  /// pleine sortie recolore tout le temps déjà écoulé au lieu de ne valoir que
  /// pour la suite.
  ///
  /// En points, pas en secondes : `RideStats` ne connaît pas la cadence de
  /// capture. Elle vaut une seconde par construction (cf. `RideRecorder`), et
  /// c'est l'appelant qui convertit.
  final Map<int, int> hrHistogram = {};
  final Map<int, int> powerHistogram = {};

  double distanceM = 0;
  double ascentM = 0;
  double descentM = 0;

  double? firstLat;
  double? firstLng;
  double? lastLat;
  double? lastLng;

  bool hasPosition = false;
  bool hasAltitude = false;

  /// La sortie porte-t-elle une altitude barométrique ? Une fois vrai, ça le
  /// reste : voir [add] pour ce qui se passe si le baromètre décroche en route.
  bool hasBaroAltitude = false;
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

    if (point.altitudeM != null || point.baroAltitudeM != null) {
      hasAltitude = true;
    }
    if (point.baroAltitudeM != null) hasBaroAltitude = true;

    // Dès qu'une sortie a du baromètre, le GPS ne reprend JAMAIS la main sur
    // l'altitude — pas même sur les points où le baromètre manque. Les deux
    // sources sont décalées l'une par rapport à l'autre de plusieurs mètres
    // (référence calée au départ d'un côté, géoïde de l'autre) : alterner ferait
    // compter cet écart comme une montée puis une descente, à chaque trou.
    // Un trou vaut mieux qu'une marche : la référence est conservée, et le
    // dénivelé reprend exactement où il s'était arrêté.
    final altitude = hasBaroAltitude ? point.baroAltitudeM : point.altitudeM;
    if (altitude != null) {
      // Le baromètre mesure au décimètre, le GPS à ±10 m : leur laisser le même
      // seuil de bruit reviendrait à jeter la précision qu'on est allé chercher.
      final noise = hasBaroAltitude ? baroAltitudeNoiseM : altitudeNoiseM;
      _altitudeReference ??= altitude;
      if (altitude - _altitudeReference! > noise) {
        ascentM += altitude - _altitudeReference!;
        _altitudeReference = altitude;
      } else if (_altitudeReference! - altitude > noise) {
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
      _bucket(hrHistogram, heartRate, hrBucketBpm);
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
      _bucket(powerHistogram, power, powerBucketW);
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

  /// Range une mesure dans son palier. Une mesure nulle ou négative est écartée :
  /// un capteur qui renvoie zéro n'a rien mesuré, et ce zéro-là ferait grossir la
  /// zone la plus basse d'un temps qui n'a pas été passé à pédaler doucement.
  static void _bucket(Map<int, int> histogram, num value, int width) {
    if (value <= 0) return;

    final low = (value ~/ width) * width;
    histogram[low] = (histogram[low] ?? 0) + 1;
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
    hasPosition = hasAltitude = hasBaroAltitude = hasHeartRate = false;
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
    hrHistogram.clear();
    powerHistogram.clear();
  }

  static int _max(int? current, int value) =>
      current == null || value > current ? value : current;
}
