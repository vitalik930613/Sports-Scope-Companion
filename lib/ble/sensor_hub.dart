import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'decoders/di2.dart';
import 'samples.dart';
import 'sensor_connection.dart';
import 'sensor_profile.dart';

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
  final latestPowerBalance = ValueNotifier<double?>(null);
  final latestCadence = ValueNotifier<double?>(null);
  final latestGears = ValueNotifier<Di2Gears?>(null);

  /// Dernier état du radar. `null` = pas de radar connecté ; un [RadarSample]
  /// vide = route dégagée. La distinction compte : on n'affiche pas la même
  /// chose dans les deux cas.
  final latestRadar = ValueNotifier<RadarSample?>(null);

  /// Les connexions qui portent cette capacité, dans l'ordre d'ajout.
  ///
  /// Sur les capacités *détectées*, jamais sur ce que l'appareil annonçait au
  /// scan : c'est la découverte des services qui fait foi.
  List<SensorConnection> connectionsWith(SensorKind kind) => [
        for (final connection in _connections)
          if (connection.detectedKinds.value.contains(kind)) connection,
      ];

  /// Une connexion déjà ouverte vers cet appareil, s'il y en a une.
  SensorConnection? connectionFor(DeviceIdentifier remoteId) {
    for (final connection in _connections) {
      if (connection.device.remoteId == remoteId) return connection;
    }
    return null;
  }

  /// Ajoute un capteur et lance sa connexion.
  ///
  /// Ce qu'on lira dessus n'est pas passé en paramètre : la connexion découvre
  /// les capacités de l'appareil et se branche sur tous les profils reconnus
  /// (voir `sensor_profile.dart`). Ajouter un capteur au projet ne touche donc
  /// jamais à ce fichier.
  ///
  /// Redemander un appareil déjà présent renvoie la connexion existante : deux
  /// abonnements sur la même caractéristique doubleraient les échantillons.
  Future<SensorConnection> add(
    BluetoothDevice device, {
    String? label,
  }) async {
    final existing = connectionFor(device.remoteId);
    if (existing != null) return existing;

    final connection = SensorConnection(device: device, label: label);
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
      case PowerSample(:final watts, :final balanceLeftPercent):
        latestPower.value = watts;
        latestPowerBalance.value = balanceLeftPercent;
      case CadenceSample(:final rpm):
        latestCadence.value = rpm;
      case GearSample(:final gears):
        latestGears.value = gears;
      case RemoteButtonSample():
        break; // une impulsion, rien à retenir ici — voir RideShellPage
      case RadarSample():
        latestRadar.value = sample;
      case WheelSpeedSample():
        break;
      case BatterySample():
        break; // par appareil — voir BatteryStatusNotifier, pas un scalaire du hub
    }
    _samples.add(sample);
  }

  /// Ferme la connexion à un appareil et cesse de le suivre.
  ///
  /// Les dernières valeurs affichées ne sont pas remises à zéro : un capteur
  /// débranché en cours de sortie ne doit pas effacer ce qu'il a mesuré.
  Future<void> remove(DeviceIdentifier remoteId) async {
    final connection = connectionFor(remoteId);
    if (connection == null) return;
    _connections.remove(connection);
    await connection.dispose();
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
