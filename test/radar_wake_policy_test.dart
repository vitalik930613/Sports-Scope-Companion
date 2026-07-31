import 'package:flutter_test/flutter_test.dart';
import 'package:sports_scope_companion/ride/radar_wake_policy.dart';

/// Ce qui se joue ici, c'est le rétroéclairage d'un écran qu'on ne regardait
/// pas : rallumer trop tard n'avertit personne, et battre au rythme d'un capteur
/// hésitant prend plus d'attention que l'alerte n'en mérite.
void main() {
  final t0 = DateTime.utc(2026, 7, 31, 10);

  late RadarWakePolicy policy;

  setUp(() => policy = RadarWakePolicy(hold: const Duration(seconds: 5)));

  test('rien ne réveille un écran que rien ne menace', () {
    expect(policy.update(now: t0, alerting: false), isFalse);
    expect(policy.awake, isFalse);
  });

  test('une voiture rallume, tout de suite', () {
    // Aucun délai à l'allumage : le maintien ne sert qu'à l'extinction.
    expect(policy.update(now: t0, alerting: true), isTrue);
    expect(policy.awake, isTrue);
  });

  test('les trames suivantes ne redisent rien', () {
    policy.update(now: t0, alerting: true);

    expect(
      policy.update(now: t0.add(const Duration(seconds: 1)), alerting: true),
      isFalse,
    );
    expect(policy.awake, isTrue);
  });

  test('la voie libre ne rendort pas avant le maintien', () {
    policy.update(now: t0, alerting: true);

    expect(
      policy.update(now: t0.add(const Duration(seconds: 4)), alerting: false),
      isFalse,
    );
    expect(policy.awake, isTrue);
  });

  test('le maintien écoulé, l\'écran retourne à la veille', () {
    policy.update(now: t0, alerting: true);
    policy.update(now: t0.add(const Duration(seconds: 1)), alerting: false);

    expect(
      policy.update(now: t0.add(const Duration(seconds: 6)), alerting: false),
      isTrue,
    );
    expect(policy.awake, isFalse);
  });

  test('le maintien part de l\'instant où l\'alerte est vue éteinte', () {
    // Et non de la dernière trame qui alertait. Les deux ne diffèrent que si
    // l'appli a cessé d'être appelée — écran coupé, sortie en arrière-plan — et
    // dans ce cas l'écran doit rester allumé le temps qu'on le regarde, pas
    // s'éteindre à la première seconde retrouvée.
    policy.update(now: t0, alerting: true);
    policy.update(now: t0.add(const Duration(seconds: 10)), alerting: false);

    expect(
      policy.update(now: t0.add(const Duration(seconds: 14)), alerting: false),
      isFalse,
    );
    expect(
      policy.update(now: t0.add(const Duration(seconds: 15)), alerting: false),
      isTrue,
    );
  });

  test('une deuxième voiture pendant le maintien rallonge le réveil', () {
    // Une file qui remonte, ou un dépassement en deux temps : l'écran ne doit
    // pas s'éteindre entre deux voitures pour se rallumer aussitôt.
    policy.update(now: t0, alerting: true);
    policy.update(now: t0.add(const Duration(seconds: 2)), alerting: false);
    policy.update(now: t0.add(const Duration(seconds: 3)), alerting: true);

    expect(
      policy.update(now: t0.add(const Duration(seconds: 7)), alerting: false),
      isFalse,
    );
    expect(policy.awake, isTrue);
    // Le maintien court depuis t0+7, la dernière fois qu'on a vu la voie se
    // dégager — pas depuis t0+2, où elle s'était dégagée pour deux secondes.
    expect(
      policy.update(now: t0.add(const Duration(seconds: 12)), alerting: false),
      isTrue,
    );
  });

  test('un radar qui se tait finit par rendre l\'écran à la veille', () {
    // Perdre le capteur en pleine alerte ne doit pas laisser l'écran allumé pour
    // le reste de la sortie : `absent` n'alerte pas, donc le maintien court.
    // Ce que la page affiche pendant ce délai est une autre affaire — surtout
    // pas « voie libre ».
    policy.update(now: t0, alerting: true);

    expect(
      policy.update(now: t0.add(const Duration(seconds: 5)), alerting: false),
      isFalse,
    );
    expect(
      policy.update(now: t0.add(const Duration(seconds: 11)), alerting: false),
      isTrue,
    );
    expect(policy.awake, isFalse);
  });

  test('reset rendort sans transition', () {
    policy.update(now: t0, alerting: true);

    policy.reset();

    expect(policy.awake, isFalse);
    // Et le maintien est parti avec : une alerte à venir repartira de zéro.
    expect(policy.update(now: t0, alerting: false), isFalse);
  });
}
