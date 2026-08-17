import 'elevation_profile_point.dart';

/// Accumule le profil (distance, altitude) de la sortie en cours, pour le
/// composant de tableau de bord « Profil d'altitude » quand aucun tracé n'est
/// chargé (voir `AltitudeProfileCard`, `lib/ride/blocks/altitude_profile_block.dart`).
///
/// Pur et local au téléphone : rien n'est transmis nulle part, contrairement à
/// [TraveledPathTracker] (`navigation/traveled_path_tracker.dart`) qui pousse sa
/// trace vers la page web. `RideRecorder` lui pousse `(point.distanceM,
/// altitude)` à chaque tic ([RideRecorder.tick]), altitude déjà résolue entre
/// GPS et baromètre par l'appelant (même préférence que `RideStats`).
///
/// Rééchantillonné en continu plutôt que gardé en entier : une sortie de
/// plusieurs heures produirait sinon des dizaines de milliers de points pour un
/// graphique qui n'en affiche jamais plus de quelques centaines de pixels de
/// large. Le pas minimal double et la moitié des points est jetée dès que le
/// plafond est atteint — un compactage amorti, comme `decimateClimbProfile`
/// côté site mais recalculé au fil de l'eau plutôt qu'une fois à la fin.
class RideElevationTrack {
  RideElevationTrack({this.maxPoints = 300});

  final int maxPoints;

  final List<ElevationProfilePoint> _points = [];
  double _minStepM = 5.0;

  List<ElevationProfilePoint> get points => List.unmodifiable(_points);

  void add(double distanceM, double altitudeM) {
    if (_points.isNotEmpty && distanceM - _points.last.distM < _minStepM) return;

    _points.add(ElevationProfilePoint(distM: distanceM, altM: altitudeM));

    if (_points.length > maxPoints * 2) _compact();
  }

  /// Jette un point sur deux et double le pas minimal — les deux extrémités
  /// sont gardées, comme `decimateClimbProfile` côté site.
  void _compact() {
    final kept = <ElevationProfilePoint>[];
    for (var i = 0; i < _points.length; i += 2) {
      kept.add(_points[i]);
    }
    if (kept.last != _points.last) kept.add(_points.last);
    _points
      ..clear()
      ..addAll(kept);
    _minStepM *= 2;
  }

  void reset() {
    _points.clear();
    _minStepM = 5.0;
  }
}
