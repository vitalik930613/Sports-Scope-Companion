import 'dart:math' as math;

/// Le cap du cycliste, arbitré entre la boussole et la course GPS.
///
/// Le besoin est étroit et précis : **à l'arrêt, la course GPS n'existe pas**.
/// Elle se déduit du déplacement, donc au feu rouge ou au carrefour la flèche se
/// fige sur la dernière direction connue — au moment exact où l'on cherche par
/// où repartir. La boussole, elle, mesure une orientation immobile.
///
/// En roulant c'est l'inverse : la course GPS est la référence. Elle est déjà
/// dans le nord géographique, elle ignore le cadre en acier, la dynamo et
/// l'aimant du support — et cet aimant est le vrai danger. Un support magnétique
/// (Quad Lock MAG et consorts) sature purement et simplement le magnétomètre :
/// la boussole y indique le nord du support, pas celui de la Terre.
///
/// D'où le mécanisme central de ce fichier : tant qu'on roule, on **compare** la
/// boussole à la course GPS. L'écart moyen sert deux fois — il dit si la
/// boussole est crédible, et il corrige un décalage constant (téléphone monté de
/// travers dans son étui, ce qui est courant et sinon indétectable). Une
/// boussole qui ne se recoupe pas avec le GPS n'est jamais utilisée : mieux vaut
/// une flèche figée qu'une flèche qui pointe l'aimant.
class CompassHeading {
  CompassHeading({
    this.movingMps = 2.5,
    this.minSamples = 20,
    this.minAgreement = 0.8,
    this.memory = 0.02,
  });

  /// Vitesse au-dessus de laquelle la course GPS est jugée exploitable.
  ///
  /// 2,5 m/s ≈ 9 km/h : en dessous, la course d'un GPS est bruitée au point
  /// d'être inutilisable — c'est d'ailleurs pour ça qu'on a besoin d'une
  /// boussole.
  final double movingMps;

  /// Nombre de comparaisons avant de se prononcer sur la boussole. Une poignée
  /// de trames prises dans un virage suffirait à conclure n'importe quoi.
  final int minSamples;

  /// Concentration minimale des écarts (longueur du vecteur résultant, de 0 à 1)
  /// pour tenir la boussole pour crédible. 0,8 correspond à une dispersion de
  /// l'ordre de ±35° : large, parce qu'on ne cherche pas la précision d'un
  /// compas de marine mais à distinguer « ça se recoupe » de « c'est du bruit ».
  final double minAgreement;

  /// Poids d'une comparaison neuve dans la moyenne des écarts.
  ///
  /// Très faible (2 %) : le décalage qu'on estime est une constante mécanique —
  /// la façon dont le téléphone est posé. Le faire suivre vite reviendrait à
  /// recopier le bruit d'un virage dans la correction.
  final double memory;

  // Moyenne circulaire des écarts (boussole − course), en composantes : une
  // moyenne arithmétique passerait de 359° à 1° par 180°, à l'opposé du vrai.
  double _sin = 0;
  double _cos = 0;
  int _samples = 0;

  double? _lastCompassDeg;
  double? _lastCourseDeg;

  /// Nombre de comparaisons prises en compte.
  int get sampleCount => _samples;

  /// Décalage estimé entre la boussole et la réalité, en degrés, ou `null` tant
  /// qu'on n'a pas assez comparé. Nul sur un téléphone posé droit ; proche de
  /// 90° sur un téléphone monté en travers.
  double? get offsetDeg {
    if (_samples < minSamples) return null;
    return _degrees(math.atan2(_sin, _cos));
  }

  /// À quel point les écarts se recoupent, de 0 (aléatoire) à 1 (constant).
  double get agreement =>
      _samples == 0 ? 0 : math.sqrt(_sin * _sin + _cos * _cos);

  /// La boussole est-elle exploitable sur ce vélo ?
  bool get isTrusted => _samples >= minSamples && agreement >= minAgreement;

  /// Range une mesure de boussole.
  void addCompass(double deg) {
    if (!deg.isFinite) return;
    _lastCompassDeg = _normalize(deg);
  }

  /// Range une course GPS et sa vitesse.
  ///
  /// C'est ici que se fait la comparaison : uniquement en roulant, seul moment
  /// où la course veut dire quelque chose.
  void addCourse({required double courseDeg, required double speedMps}) {
    if (!courseDeg.isFinite || speedMps < movingMps) {
      // À l'arrêt la course est du bruit : on l'oublie plutôt que de la garder
      // comme « dernière connue », sinon la flèche repartirait sur elle.
      if (speedMps < movingMps) _lastCourseDeg = null;
      return;
    }
    _lastCourseDeg = _normalize(courseDeg);

    final compass = _lastCompassDeg;
    if (compass == null) return;
    _observeOffset(compass - courseDeg);
  }

  /// Le cap à afficher, ou `null` si rien n'est exploitable.
  ///
  /// Priorité à la course GPS quand elle existe : c'est la direction réellement
  /// suivie, pas celle vers laquelle le guidon est tourné. La boussole ne prend
  /// la main qu'à l'arrêt, et seulement si elle s'est montrée crédible en
  /// roulant.
  double? get headingDeg {
    final course = _lastCourseDeg;
    if (course != null) return course;

    final compass = _lastCompassDeg;
    final offset = offsetDeg;
    if (compass == null || offset == null || !isTrusted) return null;
    return _normalize(compass - offset);
  }

  /// Le cap vient-il de la boussole (et non du GPS) ? La page l'affiche
  /// autrement : une flèche « à l'arrêt » ne promet pas la même chose.
  bool get isFromCompass => _lastCourseDeg == null && headingDeg != null;

  /// Nouveau vélo, nouveau support : le décalage appris ne vaut plus.
  void reset() {
    _sin = 0;
    _cos = 0;
    _samples = 0;
    _lastCompassDeg = null;
    _lastCourseDeg = null;
  }

  void _observeOffset(double deltaDeg) {
    final radians = _radians(deltaDeg);
    final sin = math.sin(radians);
    final cos = math.cos(radians);
    if (_samples == 0) {
      // Amorce sur la première comparaison : partir de zéro ferait converger la
      // correction en plusieurs minutes, donc bien après le premier arrêt.
      _sin = sin;
      _cos = cos;
    } else {
      _sin += (sin - _sin) * memory;
      _cos += (cos - _cos) * memory;
    }
    _samples++;
  }

  static double _normalize(double deg) => (deg % 360 + 360) % 360;
  static double _degrees(double radians) => _normalize(radians * 180 / math.pi);
  static double _radians(double deg) => deg * math.pi / 180;
}
