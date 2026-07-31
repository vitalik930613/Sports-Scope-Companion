import '../account/rider_profile.dart';

/// Le temps passé dans une zone, prêt à dessiner.
class ZoneShare {
  const ZoneShare({required this.key, required this.time, required this.share});

  /// `z1`…`z5` pour le cardio, `z1`…`z7` pour la puissance.
  final String key;

  final Duration time;

  /// Part du temps mesuré, entre 0 et 1. Le total fait 1 — c'est une répartition
  /// du temps **avec capteur**, pas du temps de sortie : sous un maillot mal
  /// humidifié, la ceinture décroche, et compter ces minutes-là quelque part
  /// serait inventer une intensité.
  final double share;
}

/// Répartit un histogramme de mesures dans les zones du cycliste.
///
/// Chaque palier est classé par son **point milieu**, comme le fait le site
/// (`ZoneDistribution.bucketize`) : un palier de 5 bpm chevauche forcément une
/// borne de zone de temps en temps, et le milieu est le seul arbitrage qui ne
/// favorise systématiquement ni la zone du dessous ni celle du dessus.
///
/// [perPoint] est la durée que vaut un point de l'histogramme — une seconde avec
/// le cadencement de `RideRecorder`. Elle est demandée plutôt que supposée : le
/// jour où l'on capturera à 4 Hz, un oubli ici donnerait des temps quadruplés
/// sans que rien ne le signale.
///
/// Liste vide si le cycliste n'a pas de zones (seuil inconnu du site) ou si rien
/// n'a été mesuré : dans les deux cas il n'y a **rien** à dessiner, et surtout
/// pas cinq zones à zéro qui se liraient comme une sortie sans effort.
List<ZoneShare> zoneSharesOf(
  Map<int, int> histogram, {
  required int bucket,
  required List<TrainingZone> zones,
  required Duration perPoint,
}) {
  if (zones.isEmpty || histogram.isEmpty) return const [];

  final points = <String, int>{};
  var total = 0;
  histogram.forEach((low, count) {
    final middle = low + bucket / 2;
    final zone = _zoneOf(zones, middle);
    if (zone == null) return;

    points[zone.key] = (points[zone.key] ?? 0) + count;
    total += count;
  });
  if (total == 0) return const [];

  return [
    for (final zone in zones)
      ZoneShare(
        key: zone.key,
        time: perPoint * (points[zone.key] ?? 0),
        share: (points[zone.key] ?? 0) / total,
      ),
  ];
}

/// La zone contenant cette valeur. Sous la première borne — un cardio de repos
/// quand `z1` ne part pas de zéro — la première zone prend le relais plutôt que
/// de perdre le temps mesuré : il a été passé quelque part.
TrainingZone? _zoneOf(List<TrainingZone> zones, num value) {
  for (final zone in zones) {
    if (zone.contains(value)) return zone;
  }
  return value < zones.first.lo ? zones.first : null;
}
