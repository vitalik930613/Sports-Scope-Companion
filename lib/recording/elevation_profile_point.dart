import 'package:flutter/foundation.dart';

/// Un point d'un profil d'altitude : distance depuis un départ, altitude.
///
/// Type partagé entre [RideElevationTrack] (accumulé localement), `ClimbProfile`
/// et `RouteProfile` (reçus du site) et `ElevationProfileGraph` (le dessin) —
/// aucun des trois ne porte plus de champ que ça, inutile d'en avoir trois
/// classes identiques. Vit dans `recording/` (couche basse, sans dépendance sur
/// `ride/`) pour que [RideElevationTrack] puisse le produire sans remonter la
/// hiérarchie des imports.
@immutable
class ElevationProfilePoint {
  const ElevationProfilePoint({required this.distM, required this.altM});

  final double distM;
  final double altM;

  @override
  bool operator ==(Object other) =>
      other is ElevationProfilePoint && other.distM == distM && other.altM == altM;

  @override
  int get hashCode => Object.hash(distM, altM);
}

/// Pente de chaque segment consécutif d'un profil (distance, altitude) —
/// personne ne la transmet ici (contrairement à un tracé du site, où elle est
/// déjà lissée) : c'est le calcul local, partagé par `AltitudeProfileCard`
/// (sortie en cours) et l'écran de détail d'une sortie passée.
List<double> localGradesOf(List<ElevationProfilePoint> points) {
  final grades = <double>[];
  for (var i = 0; i < points.length - 1; i++) {
    final dd = points[i + 1].distM - points[i].distM;
    grades.add(dd > 0 ? (points[i + 1].altM - points[i].altM) / dd * 100 : 0);
  }
  return grades;
}
