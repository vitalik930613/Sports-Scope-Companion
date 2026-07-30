import 'package:flutter_test/flutter_test.dart';
import 'package:sports_scope_companion/ble/samples.dart';
import 'package:sports_scope_companion/ride/radar_severity.dart';

/// Le radar est la seule information de sécurité de l'écran : se tromper ici,
/// c'est afficher « route dégagée » à quelqu'un qui va se déporter.
void main() {
  final now = DateTime.utc(2026, 7, 30, 10);

  RadarSample sampleOf(List<int> distances, {Duration age = Duration.zero}) =>
      RadarSample(now.subtract(age), [
        for (var i = 0; i < distances.length; i++)
          RadarTarget(id: i, distanceM: distances[i], approachSpeedRaw: 0),
      ]);

  test('pas de radar et route dégagée ne sont pas la même chose', () {
    // C'est la distinction qui compte le plus : sans radar, l'écran ne doit
    // surtout pas laisser croire qu'il a regardé derrière.
    expect(radarViewFor(null, now: now).severity, RadarSeverity.absent);
    expect(radarViewFor(sampleOf(const []), now: now).severity,
        RadarSeverity.clear);
  });

  test('un véhicule proche passe au rouge, un véhicule lointain à l\'orange',
      () {
    // Les seuils sont ceux de la carte de diagnostic : les deux affichages
    // doivent raconter la même chose du même capteur.
    expect(radarViewFor(sampleOf(const [30]), now: now).severity,
        RadarSeverity.close);
    expect(radarViewFor(sampleOf(const [90]), now: now).severity,
        RadarSeverity.approaching);
  });

  test('c\'est le plus proche qui donne la gravité', () {
    expect(
      radarViewFor(sampleOf(const [120, 25, 80]), now: now).severity,
      RadarSeverity.close,
    );
  });

  test('les positions vont du plus proche au plus lointain', () {
    final view = radarViewFor(sampleOf(const [120, 25, 80]), now: now);

    // 1 = à la roue, 0 = au bout de la portée : la liste doit donc décroître.
    expect(view.positions.length, 3);
    expect(view.positions[0], greaterThan(view.positions[1]));
    expect(view.positions[1], greaterThan(view.positions[2]));
  });

  test('le nombre de véhicules est celui des pastilles', () {
    // Il vient de `positions` et pas d'un compteur à part : deux comptes
    // finiraient par se contredire, et l'écran annoncerait trois voitures pour
    // deux pastilles.
    expect(radarViewFor(sampleOf(const [120, 25, 80]), now: now).count, 3);
    expect(radarViewFor(sampleOf(const []), now: now).count, 0);
    expect(radarViewFor(null, now: now).count, 0);
  });

  test('les mètres affichés sont ceux du plus proche', () {
    // C'est le seul chiffre du radar qui va à l'écran : s'il désignait une
    // autre voiture que celle de la jauge, les deux se contrediraient.
    expect(radarViewFor(sampleOf(const [120, 25, 80]), now: now).nearestM, 25);
    expect(radarViewFor(sampleOf(const []), now: now).nearestM, isNull);
    expect(radarViewFor(null, now: now).nearestM, isNull);
  });

  test('un véhicule au-delà de la portée reste au pied de la jauge', () {
    // Sans bornage, il sortirait de l'écran par le bas — ou pire, une distance
    // au-delà de la portée donnerait une proximité négative et le ferait
    // dessiner du mauvais côté de l'axe.
    final view = radarViewFor(sampleOf(const [400]), now: now, rangeM: 140);

    expect(view.positions.single, 0);
  });

  test('un radar qui s\'est tu n\'est plus un radar', () {
    // Le hub garde la dernière valeur d'un capteur débranché, exprès. Sur un
    // radar, cette règle laisserait une voiture fantôme à l'écran pour le reste
    // de la sortie.
    final view = radarViewFor(
      sampleOf(const [30], age: const Duration(seconds: 20)),
      now: now,
    );

    expect(view.severity, RadarSeverity.absent);
    expect(view.positions, isEmpty);
  });

  test('seul un véhicule allume le cadre', () {
    expect(radarViewFor(null, now: now).isAlerting, isFalse);
    expect(radarViewFor(sampleOf(const []), now: now).isAlerting, isFalse);
    expect(radarViewFor(sampleOf(const [90]), now: now).isAlerting, isTrue);
  });
}
