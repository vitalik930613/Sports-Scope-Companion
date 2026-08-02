import 'package:flutter_test/flutter_test.dart';
import 'package:sports_scope_companion/ble/sensor_connection.dart';
import 'package:sports_scope_companion/devices/device_linker.dart';
import 'package:sports_scope_companion/ble/sensor_profile.dart';
import 'package:sports_scope_companion/dashboard/ride_preset.dart';
import 'package:sports_scope_companion/devices/known_device.dart';

/// Qui le balayage a le droit d'aller chercher.
///
/// C'est la seule décision du rattachement qui se teste sans Bluetooth, et
/// c'est aussi la seule qui engage le cycliste : un capteur écarté à la main ne
/// doit jamais revenir tout seul.
void main() {
  KnownDevice device(
    String id, {
    bool autoConnect = true,
    Set<SensorKind> kinds = const {},
  }) =>
      KnownDevice(
        remoteId: id,
        name: id,
        kinds: kinds,
        autoConnect: autoConnect,
      );

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

  /// Le profil de sortie ajoute un filtre — et **un seul sens** : il retire des
  /// appareils, il n'en ajoute jamais. Se tromper de sens ici, c'est un réglage
  /// venu du site qui écrase un geste du cycliste.
  group('le filtre du profil', () {
    test('un capteur dont la capacité est coupée n\'est pas rattaché', () {
      // Le home-trainer : pas de radar, donc pas la peine de réveiller la radio
      // toutes les cinquante secondes pour aller le chercher.
      final missing = devicesToReattach(
        [
          device('radar', kinds: {SensorKind.radar}),
          device('ceinture', kinds: {SensorKind.heartRate}),
        ],
        statuses({}),
        allows: const SensorSettings(radar: false).allows,
      );

      expect(missing.map((d) => d.remoteId), ['ceinture']);
    });

    test('il ne ressuscite jamais un appareil décoché à la main', () {
      // LA règle du sens unique. Le profil garde le cardio, mais le cycliste a
      // décoché cette ceinture-là — vélo prêté, ceinture de quelqu'un d'autre.
      // C'est le geste qui gagne.
      final missing = devicesToReattach(
        [device('ceinture', autoConnect: false, kinds: {SensorKind.heartRate})],
        statuses({}),
        allows: const SensorSettings().allows,
      );

      expect(missing, isEmpty);
    });

    test('un appareil multi-capacités passe si l\'une d\'elles est gardée', () {
      // Un capteur vitesse-cadence, ou un compteur qui expose plusieurs
      // services : couper une seule de ses capacités ne le rend pas inutile.
      final missing = devicesToReattach(
        [
          device('duo', kinds: {SensorKind.speedCadence, SensorKind.power}),
        ],
        statuses({}),
        allows: const SensorSettings(cadence: false).allows,
      );

      expect(missing, hasLength(1));
    });

    test('un appareil sans capacité connue passe toujours', () {
      // Jamais connecté avec succès : on ne sait pas encore ce qu'il sait faire.
      // L'écarter l'empêcherait de se présenter, donc de le découvrir un jour.
      final missing = devicesToReattach(
        [device('neuf')],
        statuses({}),
        allows: const SensorSettings(
          radar: false,
          power: false,
          heartRate: false,
          cadence: false,
          gears: false,
        ).allows,
      );

      expect(missing, hasLength(1));
    });

    test('sans filtre, rien ne change', () {
      final missing = devicesToReattach(
        [device('radar', kinds: {SensorKind.radar})],
        statuses({}),
      );

      expect(missing, hasLength(1));
    });
  });
}
