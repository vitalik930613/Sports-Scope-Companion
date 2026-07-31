import 'package:flutter_test/flutter_test.dart';
import 'package:sports_scope_companion/account/rider_profile.dart';
import 'package:sports_scope_companion/ride/zone_time.dart';

/// La répartition du temps par zone : le calcul qui sert la barre de la page
/// Effort. Pur, donc vérifiable sans monter un seul widget.
void main() {
  // Les zones d'un cycliste à 160 de LTHR, telles que le site les envoie.
  const zones = [
    TrainingZone(key: 'z1', lo: 0, hi: 130),
    TrainingZone(key: 'z2', lo: 130, hi: 144),
    TrainingZone(key: 'z3', lo: 144, hi: 150),
    TrainingZone(key: 'z4', lo: 150, hi: 160),
    TrainingZone(key: 'z5', lo: 160),
  ];

  List<ZoneShare> shares(Map<int, int> histogram) => zoneSharesOf(
        histogram,
        bucket: 5,
        zones: zones,
        perPoint: const Duration(seconds: 1),
      );

  ZoneShare of(List<ZoneShare> list, String key) =>
      list.firstWhere((share) => share.key == key);

  test('le temps de chaque palier tombe dans sa zone', () {
    // 120 points à 135–139 bpm (z2), 60 à 155–159 (z4).
    final list = shares({135: 120, 155: 60});

    expect(of(list, 'z2').time, const Duration(minutes: 2));
    expect(of(list, 'z4').time, const Duration(minutes: 1));
    expect(of(list, 'z2').share, closeTo(2 / 3, 0.001));
  });

  test('un palier à cheval est tranché par son milieu', () {
    // Le palier 140–144 est entièrement en z2 ; le palier 145–149 en z3. Mais
    // le palier 130–134 chevauche la borne 130 : son milieu (132,5) le range en
    // z2, et pas en z1.
    final list = shares({130: 10});

    expect(of(list, 'z2').time, const Duration(seconds: 10));
    expect(of(list, 'z1').time, Duration.zero);
  });

  test('toutes les zones sont rendues, même celles à zéro', () {
    // La légende doit pouvoir dire « Z5 : 00:00 » — une zone absente se lirait
    // comme une zone qui n'existe pas, ce qui est l'information inverse.
    final list = shares({135: 10});

    expect(list.map((s) => s.key), ['z1', 'z2', 'z3', 'z4', 'z5']);
    expect(of(list, 'z5').share, 0);
  });

  test('les parts totalisent le temps mesuré, pas le temps de sortie', () {
    final list = shares({120: 30, 135: 30, 165: 60});

    expect(list.fold<double>(0, (sum, s) => sum + s.share), closeTo(1, 0.001));
    // La ceinture qui décroche ne crée pas de zone « sans mesure » : ces
    // minutes-là ne sont comptées nulle part, plutôt qu'inventées quelque part.
    expect(
      list.fold<Duration>(Duration.zero, (sum, s) => sum + s.time),
      const Duration(seconds: 120),
    );
  });

  test('une mesure sous la première borne reste dans la première zone', () {
    // Un cardio de repos quand z1 ne part pas de zéro : le temps a bien été
    // passé quelque part, on ne le perd pas.
    final list = zoneSharesOf(
      {40: 20},
      bucket: 5,
      zones: const [TrainingZone(key: 'z1', lo: 100, hi: 130)],
      perPoint: const Duration(seconds: 1),
    );

    expect(of(list, 'z1').time, const Duration(seconds: 20));
  });

  test('sans zones ou sans mesure, il n\'y a rien à dessiner', () {
    // Surtout pas cinq zones à zéro, qui se liraient comme une sortie sans
    // effort alors qu'on ne sait simplement rien.
    expect(zoneSharesOf({135: 10}, bucket: 5, zones: const [], perPoint: const Duration(seconds: 1)), isEmpty);
    expect(shares(const {}), isEmpty);
  });

  test('la cadence de capture est respectée, pas supposée', () {
    final list = zoneSharesOf(
      {135: 100},
      bucket: 5,
      zones: zones,
      perPoint: const Duration(milliseconds: 250),
    );

    expect(of(list, 'z2').time, const Duration(seconds: 25));
  });
}
