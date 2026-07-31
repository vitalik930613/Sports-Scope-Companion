import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_scope_companion/ble/sensor_connection.dart';
import 'package:sports_scope_companion/ble/sensor_hub.dart';
import 'package:sports_scope_companion/ble/sensor_profile.dart';
import 'package:sports_scope_companion/devices/known_devices_store.dart';
import 'package:sports_scope_companion/devices/sensor_link_status.dart';
import 'package:sports_scope_companion/devices/sensor_status_strip.dart';

void main() {
  group('couleur d\'état', () {
    test('vert connecté, orange dans tous les autres cas', () {
      expect(sensorLinkColor(SensorStatus.connected), Colors.teal);
      for (final status in [
        null,
        SensorStatus.connecting,
        SensorStatus.reconnecting,
        SensorStatus.disconnected,
        SensorStatus.failed,
      ]) {
        expect(sensorLinkColor(status), Colors.orange, reason: '$status');
      }
    });

    test('sans connexion, la connexion auto désactivée se dit autrement', () {
      // Un capteur mis de côté n'est pas un capteur en panne : confondre les
      // deux enverrait chercher une ceinture qu'on a soi-même écartée.
      expect(sensorStatusLabel(null), 'hors ligne');
      expect(sensorStatusLabel(null, autoConnect: false),
          'connexion auto désactivée');
    });
  });

  group('SensorStatusStrip', () {
    late Directory directory;
    late KnownDevicesStore devices;
    late SensorHub hub;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('sensor_strip_test');
      devices = KnownDevicesStore(File('${directory.path}/known_devices.json'));
      hub = SensorHub();
    });

    tearDown(() {
      hub.dispose();
      directory.deleteSync(recursive: true);
    });

    Future<void> pumpStrip(WidgetTester tester, {VoidCallback? onTap}) {
      return tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SensorStatusStrip(
            devices: devices,
            hub: hub,
            onTap: onTap ?? () {},
          ),
        ),
      ));
    }

    testWidgets('sans capteur appairé, le dit au lieu de rester vide',
        (tester) async {
      await pumpStrip(tester);

      expect(find.text('Aucun capteur appairé'), findsOneWidget);
    });

    testWidgets('une icône par capteur connu, orange hors connexion',
        (tester) async {
      // Écriture réelle sur disque : le temps est simulé dans un `testWidgets`,
      // une entrée-sortie doit donc passer par `runAsync`.
      await tester.runAsync(() async {
        await devices.remember('AA:BB:CC:DD:EE:01',
            name: 'Ceinture', kinds: {SensorKind.heartRate});
        await devices.remember('AA:BB:CC:DD:EE:02',
            name: 'Pédales', kinds: {SensorKind.power});
      });

      await pumpStrip(tester);

      final dots = tester.widgetList<SensorLinkDot>(find.byType(SensorLinkDot));
      expect(dots, hasLength(2));
      // Aucune connexion ouverte : les deux capteurs sont hors ligne, donc
      // orange — c'est ce qu'on doit voir avant de partir.
      for (final dot in dots) {
        expect(sensorLinkColor(dot.status), Colors.orange);
      }
      expect(find.byIcon(Icons.favorite), findsOneWidget);
      expect(find.byIcon(Icons.bolt), findsOneWidget);
    });

    testWidgets('un capteur appairé après coup apparaît sans redessin externe',
        (tester) async {
      await pumpStrip(tester);
      expect(find.byType(SensorLinkDot), findsNothing);

      await tester.runAsync(() async {
        await devices.remember('AA:BB:CC:DD:EE:03',
            name: 'Radar', kinds: {SensorKind.radar});
      });
      await tester.pump();

      expect(find.byType(SensorLinkDot), findsOneWidget);
    });

    testWidgets('toute la carte ouvre la page des capteurs', (tester) async {
      var taps = 0;
      await pumpStrip(tester, onTap: () => taps++);

      await tester.tap(find.text('Mes capteurs'));
      await tester.pump();

      expect(taps, 1);
    });
  });
}
