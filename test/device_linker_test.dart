import 'package:flutter_test/flutter_test.dart';
import 'package:sports_scope_companion/ble/sensor_connection.dart';
import 'package:sports_scope_companion/devices/device_linker.dart';
import 'package:sports_scope_companion/devices/known_device.dart';

/// Qui le balayage a le droit d'aller chercher.
///
/// C'est la seule décision du rattachement qui se teste sans Bluetooth, et
/// c'est aussi la seule qui engage le cycliste : un capteur écarté à la main ne
/// doit jamais revenir tout seul.
void main() {
  KnownDevice device(String id, {bool autoConnect = true}) =>
      KnownDevice(remoteId: id, name: id, autoConnect: autoConnect);

  SensorStatus? Function(String) statuses(Map<String, SensorStatus> byId) =>
      (id) => byId[id];

  test('un capteur connecté n\'est pas rattaché', () {
    final missing = devicesToReattach(
      [device('A'), device('B')],
      statuses({'A': SensorStatus.connected}),
    );

    expect(missing.map((d) => d.remoteId), ['B']);
  });

  test('« connexion… » compte comme manquant', () {
    // C'est l'état où l'attente s'éternise — celui qu'on vient corriger. Le
    // sauter reviendrait à ne jamais rattacher le capteur qu'on cherche.
    final missing = devicesToReattach(
      [device('A')],
      statuses({'A': SensorStatus.connecting}),
    );

    expect(missing, hasLength(1));
  });

  test('une reconnexion en cours compte aussi', () {
    final missing = devicesToReattach(
      [device('A')],
      statuses({'A': SensorStatus.reconnecting}),
    );

    expect(missing, hasLength(1));
  });

  test('un capteur sans connexion ouverte est manquant', () {
    expect(devicesToReattach([device('A')], statuses({})), hasLength(1));
  });

  test('la connexion auto désactivée est respectée, même vu au scan', () {
    // Le réglage est un choix du cycliste — vélo prêté, boîtier de l'autre
    // vélo. Le rattraper au vol parce qu'un scan l'a vu passer viderait le
    // réglage de son sens.
    final missing = devicesToReattach(
      [device('A', autoConnect: false), device('B')],
      statuses({}),
    );

    expect(missing.map((d) => d.remoteId), ['B']);
  });

  test('tout connecté : plus rien à chercher, donc plus de scan', () {
    final missing = devicesToReattach(
      [device('A'), device('B', autoConnect: false)],
      statuses({'A': SensorStatus.connected}),
    );

    expect(missing, isEmpty);
  });
}
