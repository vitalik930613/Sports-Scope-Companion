import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../ble/samples.dart';
import '../ble/sensor_connection.dart';
import '../ble/sensor_hub.dart';
import '../devices/known_devices_store.dart';
import '../ui/sensor_icons.dart';

/// L'état batterie d'un appareil connu, tel qu'on le dessine.
@immutable
class BatteryStatus {
  const BatteryStatus({
    required this.id,
    required this.label,
    required this.icon,
    required this.connected,
    this.percent,
    this.low = false,
  });

  /// `KnownDevice.remoteId` — jamais affiché, sert seulement de clé.
  final String id;

  final String label;
  final IconData icon;
  final bool connected;

  /// `null` : pas connecté, ou connecté sans le service batterie standard.
  final int? percent;

  /// `percent` sous le seuil du profil de sortie.
  final bool low;

  @override
  bool operator ==(Object other) =>
      other is BatteryStatus &&
      other.id == id &&
      other.label == label &&
      other.icon == icon &&
      other.connected == connected &&
      other.percent == percent &&
      other.low == low;

  @override
  int get hashCode => Object.hash(id, label, icon, connected, percent, low);
}

/// Le pourcentage de batterie de chaque appareil connu, tenu à jour en
/// écoutant chaque connexion.
///
/// La liste des lignes vient de [KnownDevicesStore] — la source stable et
/// écoutable, mise à jour par `DeviceLinker` à chaque connexion réussie
/// (voir `remember()`) — exactement le même schéma que `SensorStatusStrip`
/// sur l'accueil. Un instantané de `SensorHub.connections` ne conviendrait
/// pas : rien ne préviendrait quand un appareil se rattache en cours de
/// sortie (une ceinture cardio enfilée après le départ), et la liste
/// resterait figée jusqu'au prochain rechargement de la page.
class BatteryStatusNotifier extends ValueNotifier<List<BatteryStatus>> {
  BatteryStatusNotifier(
    this._devices,
    this._hub, {
    this.thresholdPercent = 20,
  }) : super(const []) {
    _devices.addListener(_resubscribe);
    _resubscribe();
  }

  final KnownDevicesStore _devices;
  final SensorHub _hub;
  final int thresholdPercent;

  final _percent = <String, int?>{};
  final _statusListeners = <String, VoidCallback>{};
  final _sampleSubs = <String, StreamSubscription<SensorSample>>{};
  final _subscribed = <String, SensorConnection>{};

  /// Reconstruit les abonnements sur ce que le magasin connaît désormais —
  /// appelé à chaque changement du magasin, y compris une reconnexion.
  void _resubscribe() {
    final known = {for (final d in _devices.devices) d.remoteId: d};

    for (final id in _subscribed.keys.toList()) {
      if (!known.containsKey(id)) _unsubscribe(id);
    }

    for (final device in known.values) {
      final connection = _hub.connectionFor(DeviceIdentifier(device.remoteId));
      if (connection == null) continue;
      if (_subscribed[device.remoteId] == connection) continue;
      if (_subscribed.containsKey(device.remoteId)) {
        _unsubscribe(device.remoteId);
      }
      _subscribe(device.remoteId, connection);
    }

    _rebuild();
  }

  void _subscribe(String id, SensorConnection connection) {
    _subscribed[id] = connection;
    void onStatus() => _rebuild();
    connection.status.addListener(onStatus);
    _statusListeners[id] = onStatus;
    _sampleSubs[id] = connection.samples.listen((sample) {
      if (sample is! BatterySample) return;
      _percent[id] = sample.percent;
      _rebuild();
    });
  }

  void _unsubscribe(String id) {
    final connection = _subscribed.remove(id);
    final onStatus = _statusListeners.remove(id);
    if (connection != null && onStatus != null) {
      connection.status.removeListener(onStatus);
    }
    unawaited(_sampleSubs.remove(id)?.cancel());
  }

  void _rebuild() {
    value = [
      for (final device in _devices.devices)
        BatteryStatus(
          id: device.remoteId,
          label: device.name.isEmpty ? '(sans nom)' : device.name,
          icon: iconForDevice(device.kinds),
          connected:
              _subscribed[device.remoteId]?.status.value ==
              SensorStatus.connected,
          percent: _percent[device.remoteId],
          low: _isLow(_percent[device.remoteId]),
        ),
    ];
  }

  bool _isLow(int? percent) => percent != null && percent <= thresholdPercent;

  @override
  void dispose() {
    _devices.removeListener(_resubscribe);
    for (final id in _subscribed.keys.toList()) {
      _unsubscribe(id);
    }
    super.dispose();
  }
}
