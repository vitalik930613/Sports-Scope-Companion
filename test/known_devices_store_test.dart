import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sports_scope_companion/ble/sensor_profile.dart';
import 'package:sports_scope_companion/devices/known_device.dart';
import 'package:sports_scope_companion/devices/known_devices_store.dart';

void main() {
  late Directory directory;
  late File file;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('known_devices_test');
    file = File('${directory.path}/known_devices.json');
  });

  tearDown(() => directory.deleteSync(recursive: true));

  Future<KnownDevicesStore> openStore() async {
    final store = KnownDevicesStore(file);
    await store.load();
    return store;
  }

  test('un appareil mémorisé est relu au démarrage suivant', () async {
    final store = await openStore();
    await store.remember('AA:BB:CC:DD:EE:FF',
        name: 'Ceinture', kinds: {SensorKind.heartRate});

    final reopened = await openStore();

    expect(reopened.devices, hasLength(1));
    final device = reopened.devices.single;
    expect(device.remoteId, 'AA:BB:CC:DD:EE:FF');
    expect(device.name, 'Ceinture');
    expect(device.kinds, {SensorKind.heartRate});
    expect(device.autoConnect, isTrue);
    expect(device.lastConnectedAt, isNotNull);
  });

  test('reconnecter le même appareil ne le duplique pas', () async {
    final store = await openStore();
    await store.remember('AA:BB', name: 'Capteur', kinds: {SensorKind.power});
    await store.remember('AA:BB', name: 'Capteur', kinds: {SensorKind.power});

    expect(store.devices, hasLength(1));
  });

  test('une reconnexion sans découverte ne perd pas les capacités connues',
      () async {
    // La connexion peut retomber avant la découverte des services : mémoriser
    // un ensemble vide effacerait ce qu'on savait de l'appareil.
    final store = await openStore();
    await store.remember('AA:BB', name: 'Pédalier', kinds: {SensorKind.power});
    await store.remember('AA:BB', name: '');

    final device = store.devices.single;
    expect(device.kinds, {SensorKind.power});
    expect(device.name, 'Pédalier', reason: 'un nom vide ne doit rien écraser');
  });

  test('un capteur renommé prend son nouveau nom', () async {
    final store = await openStore();
    await store.remember('AA:BB', name: 'HRM');
    await store.remember('AA:BB', name: 'HRM-Pro');

    expect(store.devices.single.name, 'HRM-Pro');
  });

  test('la liste est triée du plus récemment connecté au plus ancien',
      () async {
    final store = await openStore();
    final now = DateTime(2026, 7, 27, 10);
    await store.remember('vieux', name: 'Vieux', at: now);
    await store.remember('recent', name: 'Récent', at: now.add(const Duration(hours: 2)));
    await store.remember('milieu', name: 'Milieu', at: now.add(const Duration(hours: 1)));

    expect(
      store.devices.map((d) => d.remoteId),
      ['recent', 'milieu', 'vieux'],
    );
  });

  test('oublier un appareil le retire du disque', () async {
    final store = await openStore();
    await store.remember('AA:BB', name: 'Radar', kinds: {SensorKind.radar});
    await store.remember('CC:DD', name: 'Cardio');

    await store.forget('AA:BB');

    expect(store.devices.map((d) => d.remoteId), ['CC:DD']);
    expect((await openStore()).devices.map((d) => d.remoteId), ['CC:DD']);
  });

  test('la connexion auto se coupe et se rallume, et survit au redémarrage',
      () async {
    final store = await openStore();
    await store.remember('AA:BB', name: 'Radar');

    await store.setAutoConnect('AA:BB', false);
    expect(store.devices.single.autoConnect, isFalse);
    expect((await openStore()).devices.single.autoConnect, isFalse);

    await store.setAutoConnect('AA:BB', true);
    expect((await openStore()).devices.single.autoConnect, isTrue);
  });

  test('un catalogue illisible ne bloque pas le démarrage', () async {
    file.writeAsStringSync('{ceci n\'est pas du JSON');

    final store = await openStore();

    expect(store.devices, isEmpty);
    // Le fichier reste en place pour inspection, et la première connexion le
    // remplace par un catalogue valide.
    expect(file.existsSync(), isTrue);
    await store.remember('AA:BB', name: 'Cardio');
    expect((await openStore()).devices, hasLength(1));
  });

  test('une entrée corrompue n\'emporte pas les autres', () async {
    file.writeAsStringSync(jsonEncode([
      {'name': 'sans identifiant'},
      {'remoteId': 'AA:BB', 'name': 'Cardio', 'kinds': ['heartRate', 'inconnu']},
      'pas un objet',
    ]));

    final store = await openStore();

    expect(store.devices, hasLength(1));
    expect(store.devices.single.kinds, {SensorKind.heartRate},
        reason: 'un profil inconnu est ignoré, pas fatal');
  });

  test('l\'absence de fichier donne une liste vide', () async {
    expect((await openStore()).devices, isEmpty);
  });

  test('notifie ses auditeurs à chaque changement', () async {
    final store = await openStore();
    var notifications = 0;
    store.addListener(() => notifications++);

    await store.remember('AA:BB', name: 'Cardio');
    await store.setAutoConnect('AA:BB', false);
    await store.forget('AA:BB');

    expect(notifications, 3);
  });

  test('oublier un inconnu ne notifie pas', () async {
    final store = await openStore();
    var notifications = 0;
    store.addListener(() => notifications++);

    await store.forget('jamais vu');

    expect(notifications, 0);
  });

  test('sérialisation : un aller-retour JSON conserve tout', () {
    final device = KnownDevice(
      remoteId: 'AA:BB',
      name: 'Varia',
      kinds: {SensorKind.radar, SensorKind.gears},
      lastConnectedAt: DateTime(2026, 7, 27, 14, 30),
      autoConnect: false,
    );

    final restored = KnownDevice.fromJson(jsonDecode(jsonEncode(device.toJson())))!;

    expect(restored.remoteId, device.remoteId);
    expect(restored.name, device.name);
    expect(restored.kinds, device.kinds);
    expect(restored.lastConnectedAt, device.lastConnectedAt);
    expect(restored.autoConnect, device.autoConnect);
  });
}
