import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../ble/samples.dart';

/// Fabrique des trames radar plausibles, sans radar.
///
/// Le Varia ne se commande pas : pour voir une voiture arriver il faut une
/// voiture, une route et un vélo. Autant dire qu'on ne vérifie ni une couleur,
/// ni un seuil, ni surtout un son en restant assis — et qu'on ne les vérifie pas
/// non plus en roulant, puisqu'on est alors occupé à regarder la route.
///
/// D'où ce générateur : des véhicules qui remontent en boucle, à une cadence
/// qu'on choisit, pour que la jauge, le cadre, les mètres et les trois bips
/// puissent être jugés sur un coin de table.
///
/// Chaque véhicule fait le même trajet — il apparaît au bout de la portée,
/// se rapproche à vitesse constante, disparaît à la roue — et les véhicules sont
/// **répartis également** dans le cycle : à deux ou trois, il y a toujours
/// quelqu'un derrière, ce qui est exactement le cas où l'alerte ne doit **pas**
/// se répéter.
@immutable
class RadarSimulator {
  const RadarSimulator({
    this.cars = 1,
    this.rangeM = 140,
    this.approachMps = 14,
    this.gapS = 2,
  });

  /// Combien de véhicules tournent. Zéro est un cas utile et pas un cas
  /// dégénéré : c'est « radar branché, route dégagée », le seul état qui déclenche
  /// le son du dégagement.
  final int cars;

  /// Portée simulée. La même valeur par défaut que celle de la jauge, pour
  /// qu'un véhicule qui apparaît soit exactement en bas de l'axe.
  final double rangeM;

  /// Vitesse d'approche *relative* : l'écart entre la voiture et le vélo. 14 m/s,
  /// c'est une voiture à 80 qui rattrape un cycliste à 30.
  final double approachMps;

  /// Temps mort entre deux passages d'un même véhicule. C'est lui qui rend la
  /// route momentanément libre, donc lui qui permet d'entendre le troisième son.
  final double gapS;

  /// Durée d'un passage complet, temps mort compris.
  double get cycleS => rangeM / approachMps + gapS;

  /// L'état du radar après [elapsed] de simulation.
  ///
  /// [now] date la trame : c'est ce que lit la péremption de `radarViewFor`, qui
  /// ne doit pas prendre une trame simulée pour un radar muet.
  RadarSample sampleAt(Duration elapsed, {required DateTime now}) {
    final seconds = elapsed.inMilliseconds / 1000;
    final spacing = cycleS / math.max(cars, 1);

    return RadarSample(now, [
      for (var i = 0; i < cars; i++)
        // Le `%` de Dart reste positif : un véhicule dont le décalage n'est pas
        // encore atteint repart du bon endroit du cycle plutôt que de partir en
        // arrière.
        if (((seconds - i * spacing) % cycleS) * approachMps
            case final travelled when travelled <= rangeM)
          RadarTarget(
            id: i + 1,
            distanceM: (rangeM - travelled).round(),
            approachSpeedRaw: approachMps.round(),
          ),
    ]);
  }
}
