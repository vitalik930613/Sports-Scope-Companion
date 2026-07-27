import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sports_scope_companion/ble/decoders/di2.dart';
import 'package:sports_scope_companion/ble/samples.dart';
import 'package:sports_scope_companion/ble/sensor_hub.dart';
import 'package:sports_scope_companion/navigation/sensor_bridge.dart';

void main() {
  late SensorHub hub;
  late List<String> sent;
  late SensorBridge bridge;

  setUp(() {
    hub = SensorHub();
    sent = [];
    bridge = SensorBridge(
      hub: hub,
      send: (js) async => sent.add(js),
    );
  });

  tearDown(() async {
    await bridge.dispose();
    await hub.dispose();
  });

  /// Le JSON réellement transmis à la page, extrait de l'appel JavaScript.
  Map<String, dynamic> lastPayload() {
    final js = sent.last;
    final start = js.indexOf('(', js.indexOf('push'));
    final json = js.substring(start + 1, js.lastIndexOf('))'));
    return jsonDecode(json) as Map<String, dynamic>;
  }

  test('sans capteur, l\'état est vide mais complet', () {
    bridge.pushNow();

    final payload = lastPayload();
    expect(payload['heartRate'], isNull);
    expect(payload['power'], isNull);
    expect(payload['cadence'], isNull);
    // La page doit pouvoir distinguer « pas de radar » de « voie dégagée » :
    // l'objet radar est toujours là, c'est `connected` qui tranche.
    expect(payload['radar'], isNotNull);
    expect(payload['radar']['connected'], isFalse);
    expect(payload['radar']['targets'], isEmpty);
    expect(payload['sensors'], isEmpty);
  });

  test('les mesures courantes partent telles quelles', () {
    hub.latestHeartRate.value = 148;
    hub.latestPower.value = 237;
    hub.latestCadence.value = 91.4;

    bridge.pushNow();

    final payload = lastPayload();
    expect(payload['heartRate'], 148);
    expect(payload['power'], 237);
    expect(payload['cadence'], closeTo(91.4, 0.001));
  });

  test('les vitesses partent traduites en dents et en développement', () {
    // Le Di2 ne publie que des positions ; la page web n'a aucun moyen de
    // savoir ce qu'il y a sur le vélo, c'est le pont qui le sait.
    hub.latestGears.value = const Di2Gears(
      frontPosition: 2,
      frontCount: 2,
      rearPosition: 12,
      rearCount: 12,
      raw: [],
    );

    bridge.pushNow();

    final gears = lastPayload()['gears'];
    expect(gears['front'], 2);
    expect(gears['rear'], 12);
    expect(gears['frontTeeth'], 50);
    expect(gears['rearTeeth'], 11);
    expect(gears['ratio'], closeTo(50 / 11, 0.001));
    expect(gears['developmentM'], closeTo(50 / 11 * 2.136, 0.001));
  });

  test('une position hors transmission connue n\'invente pas de braquet', () {
    hub.latestGears.value = const Di2Gears(
      frontPosition: 3, // aucun triple plateau dans la config route
      frontCount: 3,
      rearPosition: 1,
      rearCount: 12,
      raw: [],
    );

    bridge.pushNow();

    final gears = lastPayload()['gears'];
    expect(gears['front'], 3, reason: 'la position brute reste transmise');
    expect(gears['frontTeeth'], isNull);
    expect(gears['ratio'], isNull);
  });

  test('les cibles radar sont transmises avec leur distance', () {
    hub.latestRadar.value = RadarSample(DateTime.now(), const [
      RadarTarget(id: 1, distanceM: 42, approachSpeedRaw: 7),
      RadarTarget(id: 2, distanceM: 90, approachSpeedRaw: 3),
    ]);

    bridge.pushNow();

    final targets = lastPayload()['radar']['targets'] as List;
    expect(targets, hasLength(2));
    expect(targets.first['distanceM'], 42);
    expect(targets.first['id'], 1);
    expect(targets.first['speedMps'], 7);
  });

  test('l\'appel JavaScript ne casse pas si la page n\'a pas de pont', () {
    bridge.pushNow();

    // `?.` : une page plus ancienne, ou pas encore chargée, ignore le message
    // au lieu de lever une exception dans le moteur JS.
    expect(sent.last, startsWith('void (window.sportsScopeCompanion?.push('));
    expect(sent.last, endsWith('));'));
  });

  test('un envoi immédiat n\'est pas bloqué par le plancher anti-rafale', () {
    bridge.pushNow();
    hub.latestHeartRate.value = 150;
    bridge.pushNow();

    expect(sent, hasLength(2));
    expect(lastPayload()['heartRate'], 150);
  });

  test('l\'état est toujours complet, jamais un delta', () {
    // La page peut être rechargée à tout moment : le premier message qui suit
    // doit suffire à la remettre à jour.
    hub.latestHeartRate.value = 120;
    bridge.pushNow();
    hub.latestPower.value = 200;
    bridge.pushNow();

    final payload = lastPayload();
    expect(payload['heartRate'], 120);
    expect(payload['power'], 200);
  });
}
