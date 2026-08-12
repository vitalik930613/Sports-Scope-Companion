import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'decoders/csc.dart';
import 'decoders/cycling_power.dart';
import 'decoders/di2.dart';
import 'decoders/di2_buttons.dart';
import 'decoders/heart_rate.dart';
import 'decoders/varia.dart';
import 'samples.dart';
import 'sensor_uuids.dart';

/// Adaptateur entre une caractéristique GATT et un décodeur.
///
/// [SensorConnection] ne connaît que cette interface : ajouter un capteur ne
/// demande donc pas de toucher à la machine à états.
abstract class CharacteristicDecoder {
  Guid get characteristic;

  /// Convertit une trame en échantillons. Ne doit jamais lever : renvoyer une
  /// liste vide sur une trame incomprise.
  List<SensorSample> decode(List<int> data, DateTime at);

  /// Lire la caractéristique une fois à la connexion, en plus de s'abonner.
  ///
  /// Nécessaire pour les capteurs qui ne notifient que sur *changement* : sans
  /// ça, l'état reste inconnu jusqu'au premier événement. Typiquement le Di2,
  /// dont la position n'arriverait qu'au premier changement de vitesse — soit
  /// potentiellement plusieurs minutes après le départ.
  bool get readOnConnect => false;

  /// Remise à zéro de l'état interne après une reconnexion : les compteurs
  /// cumulés du capteur ont pu boucler ou repartir de zéro pendant la coupure,
  /// et un delta calculé à cheval produirait une cadence absurde.
  void reset() {}
}

class HeartRateCharacteristic extends CharacteristicDecoder {
  final _decoder = HeartRateDecoder();

  @override
  Guid get characteristic => BleCharacteristics.heartRateMeasurement;

  @override
  List<SensorSample> decode(List<int> data, DateTime at) {
    final sample = _decoder.decode(data, at: at);
    return sample == null ? const [] : [sample];
  }
}

class CyclingPowerCharacteristic extends CharacteristicDecoder {
  final _decoder = CyclingPowerDecoder();

  @override
  Guid get characteristic => BleCharacteristics.cyclingPowerMeasurement;

  @override
  List<SensorSample> decode(List<int> data, DateTime at) =>
      _decoder.decode(data, at: at);

  @override
  void reset() => _decoder.reset();
}

class CscCharacteristic extends CharacteristicDecoder {
  final _decoder = CscDecoder();

  @override
  Guid get characteristic => BleCharacteristics.cscMeasurement;

  @override
  List<SensorSample> decode(List<int> data, DateTime at) =>
      _decoder.decode(data, at: at);

  @override
  void reset() => _decoder.reset();
}

class Di2Characteristic extends CharacteristicDecoder {
  @override
  Guid get characteristic => BleCharacteristics.di2Gears;

  @override
  bool get readOnConnect => true;

  @override
  List<SensorSample> decode(List<int> data, DateTime at) {
    final gears = Di2Gears.parse(data);
    return gears == null ? const [] : [GearSample(at, gears)];
  }
}

class Di2ButtonsCharacteristic extends CharacteristicDecoder {
  final _channels = Di2ButtonChannels();

  @override
  Guid get characteristic => BleCharacteristics.di2Buttons;

  @override
  List<SensorSample> decode(List<int> data, DateTime at) => [
        for (final channel in _channels.update(data))
          // Convention du cycliste : canal pair = page suivante, impair =
          // page précédente (voir `ride_shell_page.dart`).
          RemoteButtonSample(
            at,
            channel.isEven ? RemoteButton.next : RemoteButton.previous,
          ),
      ];

  @override
  void reset() => _channels.reset();
}

class VariaRadarCharacteristic extends CharacteristicDecoder {
  final _decoder = VariaDecoder();

  @override
  Guid get characteristic => BleCharacteristics.variaThreats;

  @override
  List<SensorSample> decode(List<int> data, DateTime at) {
    final sample = _decoder.decode(data, at: at);
    return sample == null ? const [] : [sample];
  }
}
