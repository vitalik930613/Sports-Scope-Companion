import 'dart:math' as math;

/// Une position datée, telle que la fournit le récepteur GNSS du téléphone.
///
/// Volontairement indépendante de `geolocator` : l'enregistreur ne doit
/// dépendre d'aucun greffon, sinon il ne serait testable qu'avec un moteur
/// Flutter et un vrai GPS. La traduction depuis le greffon vit dans
/// [GeolocatorGpsSource] (`gps_source.dart`), seule pièce non testable hors
/// appareil.
class GpsFix {
  const GpsFix({
    required this.at,
    required this.lat,
    required this.lng,
    this.altitudeM,
    this.speedMps,
    this.accuracyM,
  });

  final DateTime at;
  final double lat;
  final double lng;

  /// Altitude ellipsoïdale ou MSL selon l'appareil — bruitée de quelques
  /// mètres en vélo. On l'enregistre telle quelle : lisser ici reviendrait à
  /// jeter de l'information que le site sait déjà retraiter (`computeElevGain`).
  final double? altitudeM;

  /// Vitesse instantanée rendue par le GPS (effet Doppler), en m/s. Bien plus
  /// stable que la dérivée des positions, d'où sa conservation à part.
  final double? speedMps;

  /// Rayon d'incertitude horizontale en mètres, à 68 %. C'est lui qui décide si
  /// un déplacement compte dans la distance parcourue ou si c'est du bruit.
  final double? accuracyM;

  /// Rayon terrestre moyen (IUGG), en mètres.
  static const _earthRadiusM = 6371008.8;

  /// Distance orthodromique jusqu'à [other], en mètres.
  double distanceTo(GpsFix other) =>
      haversineM(lat, lng, other.lat, other.lng);

  /// Distance orthodromique entre deux couples de coordonnées, en mètres.
  ///
  /// Haversine sur une sphère : à l'échelle d'une seconde de vélo, l'écart avec
  /// un calcul ellipsoïdal se compte en millimètres — sans commune mesure avec
  /// le bruit du GPS lui-même.
  ///
  /// Statique parce que tout ne vient pas d'un [GpsFix] : le virage annoncé par
  /// la page de navigation n'est qu'un couple de coordonnées, et lui fabriquer
  /// une date et une précision pour pouvoir le mesurer serait un mensonge.
  static double haversineM(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    final dLat = _radians(lat2 - lat1);
    final dLng = _radians(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_radians(lat1)) *
            math.cos(_radians(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return 2 * _earthRadiusM * math.asin(math.min(1, math.sqrt(a)));
  }

  static double _radians(double degrees) => degrees * math.pi / 180;

  @override
  String toString() =>
      'GpsFix($lat, $lng, alt=$altitudeM, v=$speedMps, ±$accuracyM)';
}
