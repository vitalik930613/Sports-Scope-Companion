import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sports_scope_companion/recording/ride_stats.dart';
import 'package:sports_scope_companion/recording/track_point.dart';

/// Un point de sortie, avec le strict minimum renseigné par défaut.
TrackPoint point({
  int second = 0,
  double distanceM = 0,
  double? lat,
  double? lng,
  double? altitudeM,
  double? speedMps,
  int? heartRate,
  int? power,
  double? cadence,
  double? wheelSpeedMps,
}) {
  return TrackPoint(
    at: DateTime.utc(2026, 1, 1).add(Duration(seconds: second)),
    distanceM: distanceM,
    lat: lat,
    lng: lng,
    altitudeM: altitudeM,
    speedMps: speedMps,
    heartRate: heartRate,
    power: power,
    cadence: cadence,
    wheelSpeedMps: wheelSpeedMps,
  );
}

void main() {
  group('dénivelé', () {
    test('une oscillation sous le seuil ne gravit rien', () {
      // Le bug que l'hystérésis existe pour éviter : à l'arrêt, l'altitude GPS
      // oscille. Sans seuil, une pause « gravit » des dizaines de mètres.
      final stats = RideStats();
      for (var i = 0; i < 600; i++) {
        stats.add(point(second: i, altitudeM: 500 + (i.isEven ? 0.5 : -0.5)));
      }

      expect(stats.ascentM, 0);
      expect(stats.descentM, 0);
      expect(stats.hasAltitude, isTrue);
    });

    test('une vraie montée est cumulée', () {
      final stats = RideStats();
      for (var i = 0; i <= 100; i++) {
        stats.add(point(second: i, altitudeM: 500 + i * 2.0));
      }

      expect(stats.ascentM, closeTo(200, 0.001));
      expect(stats.descentM, 0);
    });

    test('montée puis descente sont comptées séparément', () {
      final stats = RideStats();
      for (var i = 0; i <= 50; i++) {
        stats.add(point(second: i, altitudeM: 500 + i * 2.0));
      }
      for (var i = 1; i <= 50; i++) {
        stats.add(point(second: 50 + i, altitudeM: 600 - i * 2.0));
      }

      expect(stats.ascentM, closeTo(100, 0.001));
      expect(stats.descentM, closeTo(100, 0.001));
    });
  });

  group('moyennes et maxima', () {
    test('les canaux absents restent nuls', () {
      final stats = RideStats()..add(point(second: 0, distanceM: 10));

      expect(stats.avgPower, isNull);
      expect(stats.maxPower, isNull);
      expect(stats.avgHeartRate, isNull);
      expect(stats.avgSpeedMps, isNull);
      expect(stats.hasPower, isFalse);
      expect(stats.distanceM, 10);
    });

    test('un trou de capteur ne compte pas comme un zéro', () {
      // Deux points à 200 W encadrant un point sans puissance : la moyenne est
      // 200, pas 133. Un capteur qui décroche ne doit pas faire chuter l'effort.
      final stats = RideStats()
        ..add(point(second: 0, power: 200))
        ..add(point(second: 1))
        ..add(point(second: 2, power: 200));

      expect(stats.avgPower, 200);
      expect(stats.maxPower, 200);
    });

    test('le maximum survit à un point sans valeur ensuite', () {
      final stats = RideStats()
        ..add(point(second: 0, power: 350, heartRate: 180))
        ..add(point(second: 1))
        ..add(point(second: 2, power: 100, heartRate: 120));

      expect(stats.maxPower, 350);
      expect(stats.maxHeartRate, 180);
    });

    test('la vitesse retombe sur le capteur de roue', () {
      // Le GPS d'abord, la roue en secours (tunnel, forêt dense).
      final stats = RideStats()
        ..add(point(second: 0, speedMps: 10, wheelSpeedMps: 4))
        ..add(point(second: 1, wheelSpeedMps: 8));

      expect(stats.avgSpeedMps, closeTo(9, 0.001));
      expect(stats.maxSpeedMps, 10);
    });

    test('la cadence est moyennée puis arrondie', () {
      final stats = RideStats()
        ..add(point(second: 0, cadence: 90.4))
        ..add(point(second: 1, cadence: 91.4));

      expect(stats.avgCadence, 91);
      expect(stats.maxCadence, 91);
    });

    test('première et dernière position sont retenues', () {
      final stats = RideStats()
        ..add(point(second: 0, lat: 46.5, lng: 6.6))
        ..add(point(second: 1))
        ..add(point(second: 2, lat: 46.7, lng: 6.9));

      expect(stats.hasPosition, isTrue);
      expect(stats.firstLat, 46.5);
      expect(stats.lastLng, 6.9);
    });
  });

  group('puissance normalisée', () {
    test('nulle tant que la fenêtre n\'est pas pleine', () {
      final stats = RideStats();
      for (var i = 0; i < 29; i++) {
        stats.add(point(second: i, power: 200));
      }

      expect(stats.normalizedPowerW, isNull);
    });

    test('égale la puissance sur un effort parfaitement régulier', () {
      // À puissance constante, la moyenne glissante vaut la puissance, donc la
      // racine quatrième de la moyenne des puissances quatrièmes aussi.
      final stats = RideStats();
      for (var i = 0; i < 120; i++) {
        stats.add(point(second: i, power: 200));
      }

      expect(stats.normalizedPowerW, 200);
    });

    test('dépasse la moyenne sur un effort en créneaux', () {
      // Tout l'intérêt de la NP : 30 s à 100 W puis 30 s à 300 W coûtent plus
      // cher que 200 W tenus, et la moyenne arithmétique ne le dit pas.
      final stats = RideStats();
      for (var i = 0; i < 600; i++) {
        stats.add(point(second: i, power: (i ~/ 30).isEven ? 100 : 300));
      }

      expect(stats.avgPower, 200);
      expect(stats.normalizedPowerW, greaterThan(210));
    });

    test('la fenêtre est configurable', () {
      final stats = RideStats(normalizedWindow: 3);
      for (var i = 0; i < 3; i++) {
        stats.add(point(second: i, power: 150));
      }

      expect(stats.normalizedPowerW, 150);
    });
  });

  group('cohérence entre le direct et le lot', () {
    test('of() donne le même résultat que add() point par point', () {
      // C'est ce qui garantit que le chiffre lu sur le guidon est celui que le
      // `.fit` contiendra à l'arrivée.
      final random = math.Random(42);
      final points = [
        for (var i = 0; i < 500; i++)
          point(
            second: i,
            distanceM: i * 7.5,
            lat: 46.5 + i * 0.0001,
            lng: 6.6 + i * 0.0001,
            altitudeM: 500 + math.sin(i / 20) * 40 + random.nextDouble(),
            speedMps: 6 + random.nextDouble() * 6,
            heartRate: 120 + random.nextInt(60),
            power: random.nextInt(400),
            cadence: 70 + random.nextDouble() * 30,
          ),
      ];

      final batch = RideStats.of(points);
      final live = RideStats();
      for (final p in points) {
        live.add(p);
      }

      expect(live.distanceM, batch.distanceM);
      expect(live.ascentM, batch.ascentM);
      expect(live.descentM, batch.descentM);
      expect(live.avgPower, batch.avgPower);
      expect(live.maxPower, batch.maxPower);
      expect(live.avgHeartRate, batch.avgHeartRate);
      expect(live.maxHeartRate, batch.maxHeartRate);
      expect(live.avgCadence, batch.avgCadence);
      expect(live.maxCadence, batch.maxCadence);
      expect(live.avgSpeedMps, batch.avgSpeedMps);
      expect(live.maxSpeedMps, batch.maxSpeedMps);
      expect(live.normalizedPowerW, batch.normalizedPowerW);
      expect(live.firstLat, batch.firstLat);
      expect(live.lastLng, batch.lastLng);
    });
  });

  group('histogrammes', () {
    test('chaque mesure tombe dans son palier', () {
      final stats = RideStats();
      for (var i = 0; i < 10; i++) {
        stats.add(point(second: i, heartRate: 142, power: 231));
      }

      // Paliers de 5 bpm et de 25 W, comme le site : 140 et 225.
      expect(stats.hrHistogram, {140: 10});
      expect(stats.powerHistogram, {225: 10});
    });

    test('un zéro n\'est pas une mesure basse', () {
      // Un capteur qui renvoie zéro n'a rien mesuré. Compté, ce zéro gonflerait
      // la zone la plus basse d'un temps qu'on n'a pas passé à pédaler doucement.
      final stats = RideStats();
      stats.add(point(second: 0, power: 0, heartRate: 0));
      stats.add(point(second: 1, power: 200, heartRate: 150));

      expect(stats.powerHistogram, {200: 1});
      expect(stats.hrHistogram, {150: 1});
    });

    test('rejouer une sortie donne le même histogramme qu\'en direct', () {
      // Même garantie que pour les moyennes : ce que l'écran montre pendant la
      // sortie est ce que le `.fit` relu racontera.
      final points = [
        for (var i = 0; i < 90; i++)
          point(second: i, heartRate: 120 + i ~/ 10, power: 180 + i),
      ];
      final live = RideStats();
      for (final p in points) {
        live.add(p);
      }

      expect(RideStats.of(points).hrHistogram, live.hrHistogram);
      expect(RideStats.of(points).powerHistogram, live.powerHistogram);
    });
  });

  group('reset', () {
    test('une nouvelle sortie repart de zéro', () {
      final stats = RideStats();
      for (var i = 0; i < 60; i++) {
        stats.add(point(second: i, distanceM: i * 10.0, power: 250, altitudeM: 500 + i * 3.0));
      }
      stats.reset();

      expect(stats.distanceM, 0);
      expect(stats.ascentM, 0);
      expect(stats.avgPower, isNull);
      expect(stats.maxPower, isNull);
      expect(stats.normalizedPowerW, isNull);
      expect(stats.hasPower, isFalse);
      expect(stats.firstLat, isNull);
      expect(stats.powerHistogram, isEmpty);
      expect(stats.hrHistogram, isEmpty);
    });
  });
}
