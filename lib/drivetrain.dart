import 'ble/decoders/di2.dart';

/// Configuration de transmission, pour traduire une position Di2 en donnée
/// exploitable.
///
/// Les positions brutes ne servent à rien pour l'analyse : ce qui compte c'est
/// le développement, et son croisement avec la cadence.
class Drivetrain {
  const Drivetrain({
    required this.chainrings,
    required this.sprockets,
    required this.wheelCircumference,
  });

  /// La transmission réelle, lue dans un `.fit` du Geoid CC600 : 50/34 et
  /// cassette Shimano 12v 11-36. Les dents viennent du Di2 lui-même — il les
  /// publie en ANT+, le compteur les recopie dans chaque `gear_change`.
  ///
  /// Circonférence : hypothèse 700×28. À corriger si les pneus diffèrent, c'est
  /// le seul paramètre que le Di2 ne fournit pas.
  static const road = Drivetrain(
    chainrings: [34, 50],
    sprockets: [36, 32, 28, 24, 21, 19, 17, 15, 14, 13, 12, 11],
    wheelCircumference: 2.136,
  );

  /// Dents des plateaux, dans l'ordre des positions : **le petit plateau
  /// d'abord**, la position 1 étant le braquet le plus facile.
  final List<int> chainrings;

  /// Dents des pignons, dans l'ordre des positions : le plus grand pignon
  /// d'abord — là aussi, la position 1 est le plus facile.
  final List<int> sprockets;

  /// Circonférence de roue en mètres.
  final double wheelCircumference;

  int? chainringTeeth(Di2Gears g) =>
      g.frontPosition <= chainrings.length ? chainrings[g.frontPosition - 1] : null;

  int? sprocketTeeth(Di2Gears g) =>
      g.rearPosition <= sprockets.length ? sprockets[g.rearPosition - 1] : null;

  double? ratio(Di2Gears g) {
    final front = chainringTeeth(g);
    final rear = sprocketTeeth(g);
    if (front == null || rear == null) return null;
    return front / rear;
  }

  /// Mètres parcourus par tour de pédale.
  double? development(Di2Gears g) {
    final r = ratio(g);
    return r == null ? null : r * wheelCircumference;
  }

  /// Vitesse théorique en m/s pour une cadence donnée.
  ///
  /// Croisée avec la vitesse GPS, elle donne un contrôle de cohérence gratuit :
  /// un écart durable signale une transmission mal configurée ici, ou une
  /// trame Di2 mal décodée.
  double? theoreticalSpeedMs(Di2Gears g, double cadenceRpm) {
    final dev = development(g);
    return dev == null ? null : dev * cadenceRpm / 60;
  }
}
