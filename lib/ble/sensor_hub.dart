import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'characteristic_decoder.dart';
import 'decoders/di2.dart';
import 'samples.dart';
import 'sensor_connection.dart';
import 'sensor_uuids.dart';

/// Agrège plusieurs capteurs en un seul flux d'échantillons.
///
/// Le hub ne fait que router : il ne décide ni de l'enregistrement ni de
/// l'affichage. La couche session s'abonne à [samples] et écrit sur disque
/// *avant* que l'UI ne lise [latest…] — un crash ne doit jamais coûter une
/// sortie.
class SensorHub {
  final _connections = <SensorConnection>[];
  final _samples = StreamController<SensorSample>.broadcast();
  final _rawFrames = StreamController<RawFrame>.broadcast();

  Stream<SensorSample> get samples => _samples.stream;
  Stream<RawFrame> get rawFrames => _rawFrames.stream;

  List<SensorConnection> get connections => List.unmodifiable(_connections);

  // Dernières valeurs connues, pour l'affichage.
  final latestHeartRate = ValueNotifier<int?>(null);
  final latestPower = ValueNotifier<int?>(null);
  final latestCadence = ValueNotifier<double?>(null);
  final latestGears = ValueNotifier<Di2Gears?>(null);

  /// Dernier état du radar. `null` = pas de radar connecté ; un [RadarSample]
  /// vide = route dégagée. La distinction compte : on n'affiche pas la même
  /// chose dans les deux cas.
  final latestRadar = ValueNotifier<RadarSample?>(null);

  /// Services à annoncer au scan. Le Di2 n'annonce pas forcément son service
  /// propriétaire dans ses trames de publicité : le filtrer ici le rendrait
  /// invisible, d'où un scan large et un tri sur ce qu'on trouve après
  /// connexion.
  static List<Guid> get knownServices => [
        BleServices.heartRate,
        BleServices.cyclingPower,
        BleServices.cyclingSpeedCadence,
        BleServices.di2,
        BleServices.variaRadar,
      ];

  /// Ajoute un capteur et lance sa connexion.
  ///
  /// [decoders] décrit ce qu'on veut lire dessus ; les caractéristiques
  /// absentes sont simplement ignorées, un même appareil pouvant porter
  /// plusieurs profils (capteur de puissance publiant aussi la cadence).
  Future<SensorConnection> add(
    BluetoothDevice device,
    List<CharacteristicDecoder> decoders, {
    String? label,
  }) async {
    final connection = SensorConnection(
      device: device,
      decoders: decoders,
      label: label,
    );
    _connections.add(connection);

    connection.samples.listen(_onSample, onError: (Object e) {
      debugPrint('[hub] ${connection.name}: $e');
    });
    connection.rawFrames.listen(_rawFrames.add);

    await connection.start();
    return connection;
  }

  void _onSample(SensorSample sample) {
    switch (sample) {
      case HeartRateSample(:final bpm):
        latestHeartRate.value = bpm;
      case PowerSample(:final watts):
        latestPower.value = watts;
      case CadenceSample(:final rpm):
        latestCadence.value = rpm;
      case GearSample(:final gears):
        latestGears.value = gears;
      case RadarSample():
        latestRadar.value = sample;
      case WheelSpeedSample():
        break;
    }
    _samples.add(sample);
  }

  Future<void> dispose() async {
    for (final connection in _connections) {
      await connection.dispose();
    }
    _connections.clear();
    await _samples.close();
    await _rawFrames.close();
  }
}
