import 'ride_elevation_track.dart';
import 'ride_lap.dart';
import 'track_point.dart';

/// Reconstruit les séries de tours d'une sortie déjà terminée, à partir de
/// `TrackPoint.laps` — même convention que `RideRecorder.tick`/`markLap` : un
/// point sans entrée pour une série est au tour 0 de cette série (voir la doc
/// de `TrackPoint.laps`). Rejoue d'un coup, sur les points relus du JSONL, la
/// même boucle que `RideRecorder.tick` en direct.
///
/// Une série jamais marquée au-delà de son tour 0 n'apparaît dans aucun
/// point, donc pas dans le résultat : rien à afficher n'est différent de
/// « rien enregistré ».
///
/// `RideLap.climbId` n'est jamais posé ici : il vient de `RideRecorder.
/// tagClimb`, appelé en direct au fil de la navigation, et n'est pas persisté
/// dans le JSONL.
Map<String, List<RideLap>> lapSeriesHistoryOf(List<TrackPoint> points) {
  final seriesKeys = <String>{};
  for (final point in points) {
    seriesKeys.addAll(point.laps.keys);
  }

  final result = <String, List<RideLap>>{};
  for (final series in seriesKeys) {
    final laps = <RideLap>[];
    RideLap? current;
    int? currentIndex;

    for (final point in points) {
      final index = point.laps[series] ?? 0;
      if (current == null || index != currentIndex) {
        current = RideLap(
          index: index,
          startedAt: point.at,
          startDistanceM: point.distanceM,
        );
        laps.add(current);
        currentIndex = index;
      }
      current.stats.add(point);
      current.pointCount++;
    }

    result[series] = laps;
  }
  return result;
}

/// Le profil (distance, altitude) d'une sortie déjà terminée, résolu entre GPS
/// et baromètre exactement comme `RideStats.add`/`RideRecorder.tick` : une
/// fois le baromètre vu sur un point, il ne rend jamais la main au GPS, même
/// sur un point où il manque — les deux sources sont décalées de plusieurs
/// mètres, et alterner ferait compter cet écart comme du relief. C'est cette
/// même règle qui garantit que le graphique tiré d'ici raconte la même sortie
/// que le D+ affiché à côté, calculé séparément par `RideStats`.
///
/// Réutilise la décimation de `RideElevationTrack` (déjà utilisée en direct)
/// plutôt que d'en écrire une nouvelle.
RideElevationTrack elevationTrackOf(List<TrackPoint> points) {
  final track = RideElevationTrack();
  var hasBaro = false;

  for (final point in points) {
    if (point.baroAltitudeM != null) hasBaro = true;
    final altitude = hasBaro ? point.baroAltitudeM : point.altitudeM;
    if (altitude != null) track.add(point.distanceM, altitude);
  }

  return track;
}
