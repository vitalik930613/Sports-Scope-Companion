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
