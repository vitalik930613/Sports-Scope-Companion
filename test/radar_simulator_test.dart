import 'package:flutter_test/flutter_test.dart';
import 'package:sports_scope_companion/ride/radar_severity.dart';
import 'package:sports_scope_companion/ride/radar_simulator.dart';

/// Le simulateur sert à valider le radar : s'il ment, il valide un affichage
/// faux et on ne s'en apercevra qu'avec une vraie voiture derrière.
void main() {
  final now = DateTime.utc(2026, 7, 30, 10);

  const oneCar = RadarSimulator(cars: 1, rangeM: 140, approachMps: 14, gapS: 2);

  test('sans voiture, la route est dégagée — pas le radar débranché', () {
    // La nuance vaut la peine : c'est le seul état qui doit jouer le son du
    // dégagement, et le seul qui distingue « j'ai regardé » de « je ne regarde
    // plus ».
    const simulator = RadarSimulator(cars: 0);
    final sample = simulator.sampleAt(Duration.zero, now: now);

    expect(sample.targets, isEmpty);
    expect(radarViewFor(sample, now: now).severity, RadarSeverity.clear);
  });

  test('un véhicule apparaît au bout de la portée et se rapproche', () {
    final start = oneCar.sampleAt(Duration.zero, now: now);
    final later = oneCar.sampleAt(const Duration(seconds: 5), now: now);

    expect(start.targets.single.distanceM, 140);
    // 5 s à 14 m/s : 70 m parcourus.
    expect(later.targets.single.distanceM, 70);
  });

  test('l\'identifiant reste le même pendant tout le passage', () {
    // C'est ce qui permet au radar de dire « c'est la même voiture » — donc de
    // ne pas ré-alerter à chaque trame.
    final start = oneCar.sampleAt(Duration.zero, now: now);
    final later = oneCar.sampleAt(const Duration(seconds: 5), now: now);

    expect(later.targets.single.id, start.targets.single.id);
  });

  test('le temps mort laisse la route libre, puis tout recommence', () {
    // 140 m à 14 m/s = 10 s de passage, puis 2 s de vide, donc un cycle de 12 s.
    expect(
      oneCar.sampleAt(const Duration(seconds: 11), now: now).targets,
      isEmpty,
    );
    expect(
      oneCar.sampleAt(const Duration(seconds: 12), now: now)
          .targets
          .single
          .distanceM,
      140,
    );
  });

  test('à trois, les véhicules sont répartis dans le cycle', () {
    const three = RadarSimulator(cars: 3, rangeM: 140, approachMps: 14, gapS: 2);
    final sample = three.sampleAt(const Duration(seconds: 6), now: now);

    expect(sample.targets.length, 3);
    // Trois identifiants distincts : trois pastilles, pas une seule qui
    // clignote.
    expect(sample.targets.map((t) => t.id).toSet().length, 3);
    // Et trois distances distinctes, sinon elles se superposeraient sur l'axe.
    expect(sample.targets.map((t) => t.distanceM).toSet().length, 3);
  });

  test('à plusieurs, il y a toujours quelqu\'un derrière', () {
    // C'est le cas qui compte pour les sons : une route jamais libre ne doit
    // jamais rejouer l'alerte d'entrée en portée.
    const three = RadarSimulator(cars: 3, rangeM: 140, approachMps: 14, gapS: 2);

    for (var s = 0; s < 40; s++) {
      expect(
        three.sampleAt(Duration(seconds: s), now: now).targets,
        isNotEmpty,
        reason: 'trou dans la circulation à $s s',
      );
    }
  });

  test('la trame est datée de maintenant, sinon elle naîtrait périmée', () {
    // `radarViewFor` jette les trames de plus de six secondes : une trame
    // simulée mal datée n'afficherait jamais rien.
    final sample = oneCar.sampleAt(const Duration(minutes: 5), now: now);

    expect(sample.at, now);
    expect(radarViewFor(sample, now: now).severity, isNot(RadarSeverity.absent));
  });
}
