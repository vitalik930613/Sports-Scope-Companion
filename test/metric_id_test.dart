import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sports_scope_companion/account/rider_profile.dart';
import 'package:sports_scope_companion/account/rider_profile_store.dart';
import 'package:sports_scope_companion/ble/sensor_hub.dart';
import 'package:sports_scope_companion/dashboard/metric_id.dart';
import 'package:sports_scope_companion/recording/gps_fix.dart';
import 'package:sports_scope_companion/recording/gps_source.dart';
import 'package:sports_scope_companion/recording/ride_recorder.dart';
import 'package:sports_scope_companion/recording/ride_store.dart';
import 'package:sports_scope_companion/ride/nav_state.dart';
import 'package:sports_scope_companion/training/training_budget_store.dart';

/// Le catalogue des mesures : le vocabulaire partagé avec le site.
///
/// L'invariant qui compte est le premier — **toute clé du catalogue se lit** :
/// une mesure sans source afficherait un tiret pour toujours, et un tiret
/// permanent se lit comme un capteur en panne, soit exactement la mauvaise
/// information puisque le trou serait dans l'appli.
void main() {
  late Directory root;
  late SensorHub hub;
  late RideRecorder recorder;
  late RiderProfileStore profile;
  late TrainingBudgetStore budgets;
  late ValueNotifier<NavState?> nav;
  late MetricSources sources;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('metric_test');
    hub = SensorHub();
    recorder = RideRecorder(
      hub: hub,
      store: RideStore(Directory(p.join(root.path, 'rides'))),
      gps: _SilentGps(),
      tickPeriod: const Duration(days: 1),
    );
    profile = RiderProfileStore(File(p.join(root.path, 'profile.json')));
    budgets = TrainingBudgetStore(File(p.join(root.path, 'budget.json')));
    nav = ValueNotifier<NavState?>(null);
    sources = MetricSources(
      hub: hub,
      recorder: recorder,
      riderProfile: profile,
      trainingBudget: budgets,
      nav: nav,
    );
  });

  tearDown(() async {
    nav.dispose();
    recorder.dispose();
    await hub.dispose();
    if (await root.exists()) await root.delete(recursive: true);
  });

  group('le catalogue', () {
    test('les clés sont uniques', () {
      final keys = MetricId.values.map((metric) => metric.key).toSet();
      expect(keys, hasLength(MetricId.values.length));
    });

    test('toute clé se relit', () {
      for (final metric in MetricId.values) {
        expect(MetricId.fromKey(metric.key), metric, reason: metric.key);
      }
    });

    test('une clé inconnue rend null plutôt que de lever', () {
      expect(MetricId.fromKey('pouls_lunaire'), isNull);
      expect(MetricId.fromKey(null), isNull);
      expect(MetricId.fromKey(42), isNull);
    });

    test('toute mesure se lit sans lever, capteurs muets compris', () {
      // Aucun capteur branché, aucun enregistrement, aucune page : c'est l'état
      // du tout premier lancement, et il ne doit rien casser.
      for (final metric in MetricId.values) {
        expect(
          () => metric.read(sources),
          returnsNormally,
          reason: metric.key,
        );
      }
    });

    test('sans mesure, la valeur est absente et jamais zéro', () {
      // Un zéro se lit comme une mesure. Un capteur muet ne mesure pas zéro, il
      // ne mesure rien — et c'est le rendu qui écrira « — ».
      //
      // Les deux cases de zone sont les seules exceptions, et pas par accident :
      // sans seuil connu du site, elles nomment le seuil manquant plutôt que
      // d'afficher un tiret qui se lirait comme un capteur débranché (cf. le
      // groupe « les zones » plus bas).
      const named = {MetricId.hrZone, MetricId.powerZone};

      for (final metric in MetricId.values) {
        if (named.contains(metric)) continue;
        expect(metric.read(sources).value, isNull, reason: metric.key);
      }

      expect(MetricId.hrZone.read(sources).value, 'LTHR ?');
      expect(MetricId.powerZone.read(sources).value, 'FTP ?');
    });

    test('toute mesure déclare au moins une dépendance', () {
      // Sans dépendance, la case ne se reconstruirait jamais : le symptôme
      // serait un chiffre figé, indiscernable d'un capteur qui a décroché.
      for (final metric in MetricId.values) {
        expect(
          metric.dependencies(sources),
          isNotEmpty,
          reason: metric.key,
        );
      }
    });
  });

  group('sans page web', () {
    late MetricSources orphan;

    setUp(() {
      // Le profil home-trainer : pas de carte, donc pas de page pour publier un
      // état de navigation.
      orphan = MetricSources(
      hub: hub,
      recorder: recorder,
      riderProfile: profile,
      trainingBudget: budgets,
      );
    });

    test('les mesures qui viennent du pont s\'abstiennent', () {
      expect(MetricId.routeRemaining.read(orphan).value, isNull);
      expect(MetricId.routeRemainingGain.read(orphan).value, isNull);
    });

    test('la vitesse retombe sur le GPS de l\'enregistreur', () {
      recorder.handleFix(GpsFix(
        at: DateTime.now().toUtc(),
        lat: 46.5,
        lng: 6.6,
        speedMps: 8.5,
      ));

      // 8,5 m/s = 30,6 km/h, virgule française.
      expect(MetricId.speed.read(orphan).value, '30,6');
    });

    test('un point périmé ne laisse pas une vitesse figée à l\'écran', () {
      // Une vitesse de 34 km/h affichée à l'arrêt serait pire que pas de
      // vitesse du tout.
      recorder.handleFix(GpsFix(
        at: DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
        lat: 46.5,
        lng: 6.6,
        speedMps: 8.5,
      ));

      expect(MetricId.speed.read(orphan).value, isNull);
    });

    test('aucune mesure ne dépend d\'un écoutable inexistant', () {
      for (final metric in MetricId.values) {
        expect(
          () => metric.dependencies(orphan),
          returnsNormally,
          reason: metric.key,
        );
      }
    });
  });

  group('les zones', () {
    setUp(() async {
      await profile.record(const RiderProfile(
        lthr: 160,
        hrZones: [
          TrainingZone(key: 'z1', lo: 0, hi: 130),
          TrainingZone(key: 'z4', lo: 150, hi: 160),
          TrainingZone(key: 'z5', lo: 160),
        ],
      ));
    });

    test('la mesure et sa zone sortent du même couple', () {
      hub.latestHeartRate.value = 155;

      expect(MetricId.heartRate.read(sources), const MetricReading('155', zoneKey: 'z4'));
      expect(MetricId.hrZone.read(sources), const MetricReading('Z4', zoneKey: 'z4'));
    });

    test('sans seuil, la case nomme le seuil manquant', () {
      // Et pas le tiret des mesures absentes, qui se lirait comme un capteur
      // débranché alors que le trou est côté site et se comble avant de partir.
      hub.latestPower.value = 210;

      expect(MetricId.powerZone.read(sources).value, 'FTP ?');
      expect(MetricId.powerZone.read(sources).zoneKey, isNull);
      // La mesure, elle, reste affichée : c'est la zone qu'on ne sait pas.
      expect(MetricId.power.read(sources).value, '210');
    });

    test('le seuil manquant passe avant le capteur muet', () {
      // Sans zones, aucune mesure n'en donnera jamais : c'est ça qu'il faut
      // dire, y compris quand le capteur ne dit rien.
      expect(MetricId.powerZone.read(sources).value, 'FTP ?');
    });
  });
}

/// Un GPS qui ne rend jamais de position : les tests injectent les points à la
/// main par [RideRecorder.handleFix].
class _SilentGps implements GpsSource {
  @override
  Future<void> ensureReady() async {}

  @override
  Stream<GpsFix> watch() => const Stream.empty();
}
