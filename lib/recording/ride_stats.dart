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
    this.stationarySpeedMps = defaultStationarySpeedMps,
    this.maxVerticalSpeedMps = defaultMaxVerticalSpeedMps,
  });

  /// Seuil de bruit du dénivelé : l'altitude GPS oscille de quelques mètres à
  /// l'arrêt. Sans hystérésis, une pause de dix minutes « gravit » cent mètres.
  static const defaultAltitudeNoiseM = 1.0;

  /// Le même seuil, mais pour une altitude barométrique. Dix fois plus fin,
  /// parce que le bruit l'est : un baromètre MEMS oscille de quelques
  /// centimètres là où le GPS oscille de plusieurs mètres. C'est précisément ce
  /// qui fait qu'un faux plat montant finit enfin par être compté.
  static const defaultBaroAltitudeNoiseM = 0.3;

  /// En dessous de 1,8 km/h on ne roule pas : l'appareil est posé.
  ///
  /// L'hystérésis n'a jamais suffi à l'arrêt, et le baromètre l'a rendu pire au
  /// lieu de le régler : son seuil est dix fois plus fin, donc la dérive de
  /// pression d'une pause (vent, soleil sur le téléphone, dépression qui
  /// s'installe) le franchit d'autant plus facilement. Mesuré sur une sortie de
  /// 146 km enregistrée en parallèle par un compteur : 58 minutes immobiles
  /// réparties sur 754 arrêts valaient 253 m de D+ gagnés sans avancer.
  ///
  /// À l'arrêt on suit donc l'altitude sans l'accumuler — la référence continue
  /// d'avancer, sans quoi la dérive de la pause serait comptée d'un bloc à la
  /// reprise.
  static const defaultStationarySpeedMps = 0.5;

  /// Vitesse verticale au-delà de laquelle une variation n'est plus du relief
  /// mais une discontinuité : 5 m/s, soit 18 km/h à la verticale. Une descente
  /// de col à 60 km/h dans du -20 % plafonne à 3,3 m/s.
  ///
  /// Deux marches nous guettent, et elles sont dans notre propre chaîne :
  ///
  ///  • le passage de l'altitude GPS à l'altitude barométrique, quand la
  ///    première pression arrive (les deux sources sont décalées de plusieurs
  ///    mètres) ;
  ///  • le calage de la référence par [BarometricAltimeter.calibrateWith], qui
  ///    déplace tout le profil d'un coup — l'altimètre ne le fait qu'une fois
  ///    par sortie *précisément* pour cette raison, mais cette fois-là compte.
  ///
  /// Sur la sortie de comparaison, les deux réunies valaient 115 m : l'altitude
  /// est passée de 923,8 m à 1039,2 m **en une seconde**. Franchir ce plafond
  /// recale la référence sans rien compter.
  static const defaultMaxVerticalSpeedMps = 5.0;

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
  final double stationarySpeedMps;
  final double maxVerticalSpeedMps;

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

  // Le dénivelé se lit entre la référence et le point courant, pas entre deux
  // points consécutifs : sous le seuil de bruit la référence ne bouge pas, et
  // c'est ce qui laisse une pente douce finir par être comptée. D'où la date de
  // la référence à côté d'elle — c'est sur *cet* intervalle-là que se juge une
  // vitesse verticale, pas sur la seconde écoulée.
  double? _altitudeReference;
  DateTime? _referenceAt;
  bool _referenceFromBaro = false;

  DateTime? _lastAt;
  double? _lastDistanceM;
  double _movingMs = 0;

  // Puissance normalisée : moyenne glissante sur la fenêtre, puis racine
  // quatrième de la moyenne des puissances quatrièmes de cette moyenne.
  final Queue<int> _npWindow = Queue<int>();
  int _npWindowSum = 0;
  double _npFourthSum = 0;
  int _npCount = 0;

  /// Temps passé à avancer, arrêts exclus — le `total_moving_time` du `.fit`.
  ///
  /// À distinguer du temps *chronométré*, qui est le nombre de points capturés :
  /// tant qu'une sortie n'est pas mise en pause à la main, l'appli enregistre un
  /// point par seconde y compris au feu rouge. Sans ce champ, un lecteur retombe
  /// sur `total_timer_time` et lit les arrêts comme du roulage — 7 h 38 au lieu
  /// de 6 h 29 sur la sortie de comparaison, et une vitesse moyenne fausse dans
  /// la même proportion.
  Duration get movingTime => Duration(milliseconds: _movingMs.round());

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
    // Avance-t-on ? `null` sur le premier point : il n'y a pas d'intervalle à
    // juger, et rien à accumuler de toute façon.
    final previousAt = _lastAt;
    final previousDistanceM = _lastDistanceM;
    _lastAt = point.at;
    _lastDistanceM = point.distanceM;

    final seconds = previousAt == null
        ? null
        : point.at.difference(previousAt).inMilliseconds / 1000;
    bool? moving;
    if (seconds != null && seconds > 0 && previousDistanceM != null) {
      moving = point.distanceM - previousDistanceM >= stationarySpeedMps * seconds;
      if (moving) _movingMs += seconds * 1000;
    }

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
    if (altitude != null) _addAltitude(altitude, point.at, moving);

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

  /// Le dénivelé d'un point, à partir de la référence courante.
  ///
  /// Trois situations recalent la référence **sans rien compter** : l'écart
  /// qu'on lirait alors n'est pas du relief.
  void _addAltitude(double altitude, DateTime at, bool? moving) {
    final reference = _altitudeReference;
    final referenceAt = _referenceAt;

    // 1. La source a changé (GPS → baromètre) : les deux échelles ne se
    //    comparent pas. 2. La variation dépasse le plafond de vitesse verticale
    //    (calage de l'altimètre). 3. On est à l'arrêt : c'est de la dérive.
    final sinceReference = referenceAt == null
        ? null
        : at.difference(referenceAt).inMilliseconds / 1000;
    final jumped = reference != null &&
        sinceReference != null &&
        sinceReference > 0 &&
        (altitude - reference).abs() > maxVerticalSpeedMps * sinceReference;

    if (reference == null ||
        _referenceFromBaro != hasBaroAltitude ||
        jumped ||
        moving == false) {
      _altitudeReference = altitude;
      _referenceAt = at;
      _referenceFromBaro = hasBaroAltitude;
      return;
    }

    // Le baromètre mesure au décimètre, le GPS à ±10 m : leur laisser le même
    // seuil de bruit reviendrait à jeter la précision qu'on est allé chercher.
    final noise = hasBaroAltitude ? baroAltitudeNoiseM : altitudeNoiseM;
    if (altitude - reference > noise) {
      ascentM += altitude - reference;
    } else if (reference - altitude > noise) {
      descentM += reference - altitude;
    } else {
      // Sous le seuil : la référence NE bouge pas, sinon une pente douce ne
      // franchirait jamais le seuil et ne serait jamais comptée.
      return;
    }
    _altitudeReference = altitude;
    _referenceAt = at;
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
    _referenceAt = null;
    _referenceFromBaro = false;
    _lastAt = null;
    _lastDistanceM = null;
    _movingMs = 0;
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
