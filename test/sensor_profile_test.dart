import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_scope_companion/ble/sensor_profile.dart';
import 'package:sports_scope_companion/ble/sensor_uuids.dart';

void main() {
  group('kindsFromCharacteristics', () {
    test('reconnaît un capteur mono-profil', () {
      expect(
        kindsFromCharacteristics([BleCharacteristics.heartRateMeasurement]),
        {SensorKind.heartRate},
      );
    });

    test('reconnaît tous les profils d\'un appareil qui en cumule plusieurs',
        () {
      // Cas réel : un capteur de puissance publie aussi la cadence via CSC.
      final kinds = kindsFromCharacteristics([
        BleCharacteristics.cyclingPowerMeasurement,
        BleCharacteristics.cscMeasurement,
      ]);

      expect(kinds, {SensorKind.power, SensorKind.speedCadence});
    });

    test('ignore les caractéristiques inconnues', () {
      final kinds = kindsFromCharacteristics([
        Guid(uuid128(0x2A19)), // niveau de batterie : pas un profil capteur
        BleCharacteristics.variaThreats,
      ]);

      expect(kinds, {SensorKind.radar});
    });

    test('un appareil muet ne donne aucun profil', () {
      expect(kindsFromCharacteristics(const <Guid>[]), isEmpty);
    });
  });

  group('kindsFromServices', () {
    test('classe un appareil sur ce qu\'il annonce au scan', () {
      expect(
        kindsFromServices([BleServices.cyclingPower]),
        {SensorKind.power},
      );
    });

    test('le Di2 qui n\'annonce rien reste non classé', () {
      // Il n'annonce pas son service propriétaire : ne rien trouver au scan est
      // le comportement attendu, la découverte tranchera après connexion.
      expect(kindsFromServices([BleServices.deviceInformation]), isEmpty);
      expect(
        kindsFromCharacteristics([BleCharacteristics.di2Gears]),
        {SensorKind.gears},
      );
    });
  });

  group('decodersFor', () {
    test('instancie un décodeur par profil demandé', () {
      final decoders = decodersFor({SensorKind.heartRate, SensorKind.gears});

      expect(
        decoders.map((d) => d.characteristic),
        containsAll([
          BleCharacteristics.heartRateMeasurement,
          BleCharacteristics.di2Gears,
        ]),
      );
      expect(decoders, hasLength(2));
    });

    test('rend des instances neuves à chaque appel', () {
      // Les décodeurs portent des compteurs cumulés : en partager un entre deux
      // capteurs produirait des deltas calculés à cheval.
      final first = decodersFor({SensorKind.power}).single;
      final second = decodersFor({SensorKind.power}).single;

      expect(identical(first, second), isFalse);
    });

    test('ne renvoie rien pour un ensemble vide', () {
      expect(decodersFor(const <SensorKind>{}), isEmpty);
    });
  });

  test('chaque profil est déclaré une seule fois et porte un libellé', () {
    final kinds = sensorProfiles.map((p) => p.kind).toList();

    expect(kinds.toSet(), hasLength(kinds.length));
    // Tout SensorKind doit avoir son profil : la persistance et l'UI s'en
    // servent pour afficher un appareil sans être connecté.
    expect(kinds.toSet(), SensorKind.values.toSet());
    for (final kind in SensorKind.values) {
      expect(labelFor(kind), isNotEmpty);
    }
  });

  test('knownServices couvre le registre', () {
    expect(knownServices, hasLength(sensorProfiles.length));
    expect(knownServices, contains(BleServices.variaRadar));
  });
}
