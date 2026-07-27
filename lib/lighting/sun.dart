import 'dart:math' as math;

/// Position du soleil, pour décider du mode d'éclairage.
///
/// On raisonne en **hauteur du soleil** plutôt qu'en heures de lever/coucher :
/// c'est une grandeur continue, elle se compare à un seuil sans cas particulier,
/// et elle ne s'effondre pas aux latitudes où le soleil ne se couche pas. Un
/// couple (lever, coucher) obligerait à gérer « pas de lever aujourd'hui »,
/// les passages de minuit et les changements d'heure — trois sources de bugs
/// pour aucun gain.
///
/// Algorithme solaire de faible précision (~1 minute d'arc sur le siècle en
/// cours). Largement au-delà du nécessaire : on cherche à savoir s'il fait jour,
/// pas à pointer un télescope.
class Sun {
  const Sun._();

  /// Hauteur du soleil en degrés au-dessus de l'horizon.
  ///
  /// Négatif = sous l'horizon. Repères utiles :
  ///   +6° et plus  → plein jour
  ///    0°          → lever / coucher
  ///   -6°          → fin du crépuscule civil, il fait nuit pour un cycliste
  static double elevationDeg({
    required DateTime utc,
    required double latitude,
    required double longitude,
  }) {
    assert(utc.isUtc, 'passer un DateTime en UTC');

    final n = _julianDay(utc) - 2451545.0;

    // Longitude et anomalie moyennes du soleil.
    final meanLongitude = _norm360(280.460 + 0.9856474 * n);
    final meanAnomaly = _rad(_norm360(357.528 + 0.9856003 * n));

    // Longitude écliptique (équation du centre au premier ordre).
    final eclipticLongitude = _rad(_norm360(meanLongitude +
        1.915 * math.sin(meanAnomaly) +
        0.020 * math.sin(2 * meanAnomaly)));

    final obliquity = _rad(23.439 - 0.0000004 * n);

    final rightAscension = math.atan2(
      math.cos(obliquity) * math.sin(eclipticLongitude),
      math.cos(eclipticLongitude),
    );
    final declination =
        math.asin(math.sin(obliquity) * math.sin(eclipticLongitude));

    // Temps sidéral local, puis angle horaire.
    final gmstHours = _norm24(18.697374558 + 24.06570982441908 * n);
    final lmstHours = _norm24(gmstHours + longitude / 15.0);
    final hourAngle = _rad(_norm360(lmstHours * 15.0 - _deg(rightAscension)));

    final lat = _rad(latitude);
    final sinElevation = math.sin(lat) * math.sin(declination) +
        math.cos(lat) * math.cos(declination) * math.cos(hourAngle);

    return _deg(math.asin(sinElevation.clamp(-1.0, 1.0)));
  }

  static double _julianDay(DateTime utc) =>
      utc.millisecondsSinceEpoch / 86400000.0 + 2440587.5;

  static double _norm360(double d) {
    final r = d % 360.0;
    return r < 0 ? r + 360.0 : r;
  }

  static double _norm24(double h) {
    final r = h % 24.0;
    return r < 0 ? r + 24.0 : r;
  }

  static double _rad(double deg) => deg * math.pi / 180.0;
  static double _deg(double rad) => rad * 180.0 / math.pi;
}
