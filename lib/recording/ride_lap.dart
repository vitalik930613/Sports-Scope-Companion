import 'ride_stats.dart';

/// Un tour, du geste qui l'ouvre au suivant (ou à la fin de la sortie).
///
/// Porte sa propre [RideStats], alimentée exactement comme celle de la sortie
/// entière — mêmes histogrammes, mêmes moyennes, même D+ — mais remise à zéro
/// à l'ouverture du tour : aucune divergence de calcul entre « la sortie » et
/// « un tour de la sortie ».
///
/// Seule la distance ne peut pas se lire directement sur [stats] : `add()`
/// pose `distanceM` à la valeur du point, cumulée depuis le *départ de la
/// sortie* (c'est ce qu'attend un [RideStats] nourri de la sortie entière).
/// Sur un tour, ce serait donc la distance totale à la fin du tour, pas la
/// distance parcourue *pendant* le tour. [distanceM] retranche le repère posé
/// à l'ouverture pour rendre le vrai delta.
class RideLap {
  RideLap({
    required this.index,
    required this.startedAt,
    required this.startDistanceM,
  }) : stats = RideStats();

  final int index;
  final DateTime startedAt;
  final RideStats stats;

  /// Distance cumulée depuis le départ de la sortie, au moment où ce tour
  /// s'ouvre — le repère que [distanceM] retranche.
  final double startDistanceM;

  /// Nombre de points capturés depuis l'ouverture du tour — une seconde par
  /// point, même convention que `RideRecorder.recorded`.
  int pointCount = 0;

  /// Sur la série `cols` (`climbLapSeries`) seulement : l'identifiant du col
  /// que ce tour couvre — même convention que `RouteClimb.id`/`ClimbProfile.id`
  /// (l'index de départ du col côté site). Posé après coup par
  /// `RideRecorder.tagClimb`, une fois le profil du col reçu, jamais à
  /// l'ouverture du tour : c'est ce qui permet à la page Tours d'afficher son
  /// nom plutôt que « Tour N » (voir `LapListBody._lapLabel`). `null` sur
  /// toute autre série, et sur un tour de `cols` qui n'est pas une montée (le
  /// tracé entre deux cols).
  int? climbId;

  /// Distance parcourue pendant ce tour, jamais la distance cumulée de la
  /// sortie. Bornée à 0 : avant le premier point du tour, `stats.distanceM`
  /// vaut encore 0 et pourrait passer sous le repère.
  double get distanceM =>
      (stats.distanceM - startDistanceM).clamp(0, double.infinity);
}
