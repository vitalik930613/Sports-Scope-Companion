import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sports_scope_companion/ble/samples.dart';
import 'package:sports_scope_companion/ble/sensor_hub.dart';
import 'package:sports_scope_companion/dashboard/ride_preset.dart';
import 'package:sports_scope_companion/drivetrain.dart';
import 'package:sports_scope_companion/recording/gps_fix.dart';
import 'package:sports_scope_companion/recording/gps_source.dart';
import 'package:sports_scope_companion/recording/ride_recorder.dart';
import 'package:sports_scope_companion/phone/phone_sensors.dart';
import 'package:sports_scope_companion/recording/ride_store.dart';

void main() {
  late Directory root;
  late RideStore store;
  late SensorHub hub;
  late _FakeGps gps;
  late _FakePhone phone;
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
    phone = _FakePhone();
    recorder = RideRecorder(
      hub: hub,
      store: store,
      gps: gps,
      phone: phone,
      // Les tics sont déclenchés à la main dans les tests : une horloge réelle
      // rendrait chaque assertion dépendante du temps qui passe.
      tickPeriod: const Duration(days: 1),
    );
  });

  tearDown(() async {
    recorder.dispose();
    await hub.dispose();
    await gps.close();
    await phone.close();
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

  /// Le profil de home-trainer : pas de GPS du tout.
  ///
  /// Ce n'est pas une dégradation à subir mais un mode à part entière — sur un
  /// rouleau, la trace ne dirait rien, et le cardio et la puissance disent tout.
  group('sans GPS', () {
    const noGps = SensorSettings(gps: false);

    test('la sortie démarre sans attendre de position', () async {
      // Le récepteur est déclaré indisponible : avec GPS, `start()` lèverait.
      // Sans, il ne demande rien — ni permission, ni service au premier plan,
      // ni première position.
      gps.ready = false;

      final session = await recorder.start(sensors: noGps);

      expect(session, isNotNull);
      expect(recorder.state, RecorderState.recording);
      expect(recorder.gpsEnabled, isFalse);
    });

    test('les points s\'écrivent sans coordonnées', () async {
      await recorder.start(sensors: noGps);
      hub.latestPower.value = 210;
      recorder.handleSample(PowerSample(DateTime.now().toUtc(), 210));

      final point = recorder.capture(DateTime.now());

      // Un point sans position est une information, pas un trou : c'est ce que
      // le format admet déjà, et c'est ce qui porte la sortie ici.
      expect(point.lat, isNull);
      expect(point.lng, isNull);
      expect(point.power, 210);
    });

    test('aucune position n\'arrive, même si le récepteur en émet', () async {
      // Le flux n'est pas écouté du tout : le service au premier plan et sa
      // notification n'ont aucune raison d'exister sur un rouleau.
      await recorder.start(sensors: noGps);
      gps.emit(fixAt(0, second: 0));
      await Future<void>.delayed(Duration.zero);

      expect(recorder.lastFix, isNull);
      expect(recorder.distanceM, 0);
    });

    test('avec GPS, rien ne change', () async {
      await recorder.start();

      expect(recorder.gpsEnabled, isTrue);
    });
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
    // 15 m et non 10 : un pas pile au plancher [_minStepM] dépendrait de
    // l'arrondi de la formule de distance plutôt que de démontrer qu'il
    // compte.
    recorder.handleFix(fixAt(515, second: 2));

    expect(recorder.distanceM, closeTo(15, 0.5));
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
    // parcourus en voiture pendant la pause ne s'ajoutent pas. 1015 et non
    // 1010 pour la même raison que le test du saut de récepteur : rester
    // loin du plancher [_minStepM], pas pile dessus.
    recorder.resume();
    recorder.handleFix(fixAt(1015, second: 61));
    recorder.tick();

    expect(recorder.distanceM, closeTo(35, 0.5));
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

  group('baromètre', () {
    test('écrit l\'altitude barométrique et la pression brute', () async {
      await recorder.start();
      recorder.handlePressure(900);
      recorder.handleFix(fixAt(0, second: 0));

      final point = recorder.capture(DateTime.now());
      expect(point.pressureHpa, closeTo(900, 0.01));
      // Calée sur l'altitude GPS du point (400 m) au premier calage.
      expect(point.baroAltitudeM, closeTo(400, 1));
      // L'altitude GPS reste écrite à côté : les deux ont des défauts opposés,
      // et une sortie déjà enregistrée doit rester rejouable avec l'une ou
      // l'autre.
      expect(point.altitudeM, 400);
    });

    test('mesure le dénivelé sans attendre le moindre point GPS', () async {
      // Sans calage l'altitude absolue est fausse — ses variations, non. C'est
      // ce qui permet de compter le D+ des premières minutes.
      await recorder.start();
      recorder.handlePressure(900);
      final low = recorder.capture(DateTime.now()).baroAltitudeM!;
      recorder.handlePressure(890);
      final high = recorder.capture(DateTime.now()).baroAltitudeM!;

      expect(high, greaterThan(low));
    });

    test('ne recale JAMAIS l\'altitude en cours de sortie', () async {
      // La règle non négociable : un recalage déplace tout le profil d'un coup,
      // et RideStats compte cette marche comme du dénivelé.
      await recorder.start();
      recorder.handlePressure(900);
      recorder.handleFix(fixAt(0, second: 0));
      final first = recorder.capture(DateTime.now()).baroAltitudeM!;

      // Un point GPS très différent arrive plus tard : sans effet.
      recorder.handleFix(GpsFix(
        at: base.add(const Duration(seconds: 30)),
        lat: 46.5,
        lng: 6.6,
        altitudeM: 1800,
        speedMps: 8,
        accuracyM: 3,
      ));
      expect(recorder.capture(DateTime.now()).baroAltitudeM, closeTo(first, 0.01));
    });

    test('une pression périmée ne fige pas l\'altitude', () async {
      // Un baromètre qui décroche laisserait sinon un plateau parfaitement
      // plat — invisible à la lecture, et zéro dénivelé.
      await recorder.start();
      recorder.handlePressure(900);

      final later = DateTime.now().add(RideRecorder.sensorTtl * 2);
      final point = recorder.capture(later);
      expect(point.pressureHpa, isNull);
      expect(point.baroAltitudeM, isNull);
    });

    test('sans baromètre, le point est celui d\'avant', () async {
      final plain = RideRecorder(
        hub: hub,
        store: store,
        gps: gps,
        tickPeriod: const Duration(days: 1),
      );
      addTearDown(plain.dispose);
      await plain.start();
      plain.handleFix(fixAt(0, second: 0));

      final point = plain.capture(DateTime.now());
      expect(point.baroAltitudeM, isNull);
      expect(point.pressureHpa, isNull);
      expect(point.altitudeM, 400);
      await plain.stop();
    });
  });
}

/// Des capteurs de téléphone de test : seul le baromètre sert à l'enregistreur.
class _FakePhone implements PhoneSensors {
  final _pressure = StreamController<double>.broadcast();

  @override
  Future<PhoneSensorAvailability> available() async => const PhoneSensorAvailability(
      pressure: true, light: true, heading: true, battery: true);

  @override
  Stream<double> pressureHpa() => _pressure.stream;

  @override
  Stream<double> lux() => const Stream.empty();

  @override
  Stream<double> headingDeg() => const Stream.empty();

  @override
  Stream<int> batteryPercent() => const Stream.empty();

  @override
  Future<void> setLocation({
    required double lat,
    required double lng,
    double altitudeM = 0,
  }) async {}

  Future<void> close() => _pressure.close();
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

  /// Émet une position. Le flux est diffusé : sans abonné, l'émission tombe
  /// dans le vide — ce qui est exactement ce qu'on veut vérifier quand le
  /// profil coupe le GPS.
  void emit(GpsFix fix) => _controller.add(fix);

  Future<void> close() => _controller.close();
}
