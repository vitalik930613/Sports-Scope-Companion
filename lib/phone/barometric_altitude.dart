import 'dart:math' as math;

/// L'altitude tirée de la pression atmosphérique.
///
/// Pourquoi doubler le GPS : un récepteur donne l'altitude à ±10 m près, et
/// cette erreur **bouge** d'une seconde à l'autre. C'est elle qui oblige
/// `RideStats` à ignorer les variations de moins d'un mètre (`altitudeNoiseM`),
/// hystérésis qui mange en retour du vrai dénivelé en pente douce. Un baromètre
/// mesure la différence d'altitude au décimètre : le D+ cesse d'être une
/// estimation. C'est la raison d'être de ce fichier, et la seule.
///
/// Pur et sans plateforme : on lui donne des hectopascals, il rend des mètres.
class BarometricAltimeter {
  BarometricAltimeter({
    this.smoothing = 0.3,
    this.calibrationAccuracyM = 15,
  });

  /// Pression au niveau de la mer de l'atmosphère standard (ISA).
  static const standardSeaLevelHpa = 1013.25;

  /// Poids de la mesure neuve dans le lissage exponentiel de la pression.
  ///
  /// Le bruit d'un baromètre MEMS vaut quelques centièmes d'hPa, soit ±25 cm.
  /// Assez peu pour ne pas lisser fort — et surtout, lisser fort retarderait le
  /// haut d'un col, là où on regarde justement l'altitude.
  final double smoothing;

  /// Précision GPS au-delà de laquelle on refuse de caler l'altitude absolue.
  /// Un point à ±40 m décalerait tout le profil de la sortie.
  final double calibrationAccuracyM;

  double? _hpa;
  double _seaLevelHpa = standardSeaLevelHpa;
  bool _calibrated = false;

  /// A-t-on déjà calé l'altitude absolue sur le GPS ?
  bool get isCalibrated => _calibrated;

  /// Dernière pression lissée, en hPa. `null` avant la première mesure.
  double? get pressureHpa => _hpa;

  /// Altitude courante, en mètres. `null` tant qu'aucune pression n'est arrivée.
  ///
  /// Disponible **avant** tout calage : sans référence, l'altitude absolue peut
  /// être fausse de plusieurs centaines de mètres (la pression au niveau de la
  /// mer varie de 950 à 1050 hPa selon la météo), mais ses *variations* sont
  /// justes — et le dénivelé ne demande rien d'autre. Attendre le GPS pour
  /// commencer à mesurer perdrait les premières minutes de sortie.
  double? get altitudeM {
    final hpa = _hpa;
    return hpa == null ? null : altitudeFor(hpa, _seaLevelHpa);
  }

  /// Range une mesure de pression.
  void addPressure(double hpa) {
    if (!hpa.isFinite || hpa <= 0) return;
    final previous = _hpa;
    _hpa = previous == null ? hpa : previous + (hpa - previous) * smoothing;
  }

  /// Cale l'altitude absolue sur une position GPS. Renvoie vrai si le calage a
  /// été retenu.
  ///
  /// **Une seule fois par sortie**, et c'est le point à ne pas défaire : chaque
  /// recalage déplace tout le profil d'un coup, et `RideStats` compte cette
  /// marche comme du dénivelé. Recaler toutes les dix minutes fabriquerait des
  /// centaines de mètres de D+ imaginaire — exactement le défaut qu'on est venu
  /// corriger.
  ///
  /// Conséquence assumée : la pression de référence est figée au départ. Une
  /// dépression qui s'installe pendant la sortie fait dériver l'altitude
  /// absolue de ~8 m par hPa. Sur cinq heures de gros temps, quelques dizaines
  /// de mètres — sans commune mesure avec le bruit du GPS, mais ce n'est pas
  /// zéro.
  bool calibrateWith({required double gpsAltitudeM, double? accuracyM}) {
    if (_calibrated) return false;
    final hpa = _hpa;
    if (hpa == null) return false;
    if (accuracyM != null && accuracyM > calibrationAccuracyM) return false;
    if (!gpsAltitudeM.isFinite) return false;

    _seaLevelHpa = seaLevelFor(hpa, gpsAltitudeM);
    _calibrated = true;
    return true;
  }

  /// Nouvelle sortie : la référence du jour n'a rien à voir avec celle d'hier.
  void reset() {
    _hpa = null;
    _seaLevelHpa = standardSeaLevelHpa;
    _calibrated = false;
  }

  /// Formule hypsométrique de l'atmosphère standard. Exacte à quelques mètres
  /// près en absolu ; c'est sa dérivée qui nous intéresse, et elle est juste.
  static double altitudeFor(double hpa, [double seaLevelHpa = standardSeaLevelHpa]) =>
      44330.0 * (1 - math.pow(hpa / seaLevelHpa, 1 / 5.255));

  /// L'inverse : quelle pression au niveau de la mer place [hpa] à [altitudeM].
  static double seaLevelFor(double hpa, double altitudeM) =>
      hpa / math.pow(1 - altitudeM / 44330.0, 5.255);
}
