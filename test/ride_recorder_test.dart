import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sports_scope_companion/ble/samples.dart';
import 'package:sports_scope_companion/ble/sensor_hub.dart';
import 'package:sports_scope_companion/drivetrain.dart';
import 'package:sports_scope_companion/recording/gps_fix.dart';
import 'package:sports_scope_companion/recording/gps_source.dart';
import 'package:sports_scope_companion/recording/ride_recorder.dart';
import 'package:sports_scope_companion/recording/ride_store.dart';

void main() {
  late Directory root;
  late RideStore store;
  late SensorHub hub;
  late _FakeGps gps;
  late RideRecorder recorder;

  /// Les positions de test sont datées par rapport à maintenant : [tick] lit
  /// l'horloge réelle pour juger de la fraîcheur d'un point, une date figée
  /// serait toujours périmée.
  late DateTime base;

  setUp(() async {
    base = DateTime.now().toUtc();
    root = await Directory.systemTemp.createTemp('recorder_test');
    store = RideStore(Directory(p.join(root.path, 'rides')));
    hub = SensorHub();
    gps = _FakeGps();
    recorder = RideRecorder(
      hub: hub,
      store: store,
      gps: gps,
      // Les tics sont déclenchés à la main dans les tests : une horloge réelle
      // rendrait chaque assertion dépendante du temps qui passe.
      tickPeriod: const Duration(days: 1),
    );
  });

  tearDown(() async {
    recorder.dispose();
    await hub.dispose();
    await gps.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  /// Une position à [metres] du point de départ, vers le nord.
  GpsFix fixAt(double metres, {required int second, double accuracy = 5}) =>
      GpsFix(
        at: base.add(Duration(seconds: second)),
        // 1° de latitude ≈ 111 195 m.
        lat: 46.5 + metres / 111195,
        lng: 6.6,
        altitudeM: 400,
        speedMps: 8,
        accuracyM: accuracy,
      );

  test('démarrer crée une sortie et la rend active', () async {
    final session = await recorder.start();

    expect(recorder.state, RecorderState.recording);
    expect(recorder.session?.id, session.id);
    expect(await store.list(), hasLength(1));
  });

  test('un GPS indisponible ne laisse pas de sortie derrière lui', () async {
    gps.ready = false;

    await expectLater(recorder.start(), throwsA(isA<GpsUnavailable>()));
    expect(recorder.state, RecorderState.idle);
    expect(await store.list(), isEmpty);
  });

  test('la distance suit les positions reçues', () async {
    await recorder.start();

    recorder.handleFix(fixAt(0, second: 0));
    recorder.handleFix(fixAt(20, second: 1));
    recorder.handleFix(fixAt(45, second: 2));

    expect(recorder.distanceM, closeTo(45, 0.5));
  });

  test('la dérive à l\'arrêt ne fait pas de kilomètres', () async {
    await recorder.start();

    recorder.handleFix(fixAt(0, second: 0));
    for (var i = 1; i <= 60; i++) {
      // Le GPS oscille de quelques décimètres autour du même point.
      recorder.handleFix(fixAt(i.isEven ? 0.4 : 0, second: i));
    }

    expect(recorder.distanceM, 0);
  });

  test('une position trop imprécise ne compte pas', () async {
    await recorder.start();

    recorder.handleFix(fixAt(0, second: 0));
    recorder.handleFix(fixAt(50, second: 1, accuracy: 120));

    expect(recorder.distanceM, 0);
  });

  test('un saut de récepteur recale sans compter', () async {
    await recorder.start();

    recorder.handleFix(fixAt(0, second: 0));
    // 500 m en une seconde : c'est un saut, pas un cycliste.
    recorder.handleFix(fixAt(500, second: 1));
    recorder.handleFix(fixAt(510, second: 2));

    expect(recorder.distanceM, closeTo(10, 0.5));
  });

  test('la pause ne compte ni le temps ni la distance', () async {
    await recorder.start();
    recorder.handleFix(fixAt(0, second: 0));
    recorder.handleFix(fixAt(20, second: 1));
    recorder.tick();

    recorder.pause();
    recorder.handleFix(fixAt(1000, second: 60));
    recorder.tick();
    recorder.tick();

    expect(recorder.state, RecorderState.paused);
    expect(recorder.pointCount, 1);
    expect(recorder.distanceM, closeTo(20, 0.5));

    // À la reprise, on repart du dernier point connu : les mille mètres
    // parcourus en voiture pendant la pause ne s'ajoutent pas.
    recorder.resume();
    recorder.handleFix(fixAt(1010, second: 61));
    recorder.tick();

    expect(recorder.distanceM, closeTo(30, 0.5));
    expect(recorder.pointCount, 2);
  });

  test('un point reprend les capteurs frais et oublie les périmés', () async {
    await recorder.start();
    final now = base.add(const Duration(minutes: 5));

    recorder.handleSample(HeartRateSample(now, 148));
    recorder.handleSample(PowerSample(now, 237));
    // Une ceinture décrochée depuis une minute : sa dernière valeur ne doit
    // plus être recopiée seconde après seconde.
    recorder.handleSample(
        CadenceSample(now.subtract(const Duration(minutes: 1)), 92));
    recorder.handleSample(WheelSpeedSample(now, 4));

    final point = recorder.capture(now);

    expect(point.heartRate, 148);
    expect(point.power, 237);
    expect(point.cadence, isNull);
    expect(point.wheelSpeedMps,
        closeTo(4 * Drivetrain.road.wheelCircumference, 0.001));
  });

  test('une position périmée n\'est pas recopiée', () async {
    await recorder.start();
    recorder.handleFix(fixAt(0, second: 0));

    final point = recorder.capture(base.add(const Duration(minutes: 1)));

    expect(point.lat, isNull);
    expect(point.lng, isNull);
    expect(point.speedMps, isNull);
  });

  test('chaque tic écrit un point sur le disque', () async {
    final session = await recorder.start();
    recorder.handleFix(fixAt(0, second: 0));
    recorder.tick();
    recorder.handleFix(fixAt(12, second: 1));
    recorder.tick();

    final finished = await recorder.stop();

    expect(finished?.pointCount, 2);
    expect(finished?.isFinished, isTrue);
    expect(finished?.distanceM, closeTo(12, 0.5));
    expect(recorder.state, RecorderState.idle);

    final points = await store.points(session.id);
    expect(points, hasLength(2));
    expect(points.last.distanceM, closeTo(12, 0.5));
    expect(points.last.lat, closeTo(46.5 + 12 / 111195, 0.000001));

    // Le résumé sur le disque doit refléter l'arrêt, pas l'état du départ.
    final listed = await store.list();
    expect(listed.single.isFinished, isTrue);
    expect(listed.single.pointCount, 2);
  });

  test('arrêter sans avoir démarré ne fait rien', () async {
    expect(await recorder.stop(), isNull);
  });
}

/// Un GPS de test : rien ne part tant qu'on ne pousse pas soi-même une position.
class _FakeGps implements GpsSource {
  final _controller = StreamController<GpsFix>.broadcast();

  bool ready = true;

  @override
  Future<void> ensureReady() async {
    if (!ready) throw const GpsUnavailable('pas de position');
  }

  @override
  Stream<GpsFix> watch() => _controller.stream;

  Future<void> close() => _controller.close();
}
