import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../ble/sensor_connection.dart';
import '../ble/sensor_hub.dart';
import 'known_device.dart';
import 'known_devices_store.dart';

/// Relie un appareil au hub et le retient au catalogue.
///
/// Deux écrans font le même geste pour des raisons différentes : l'accueil
/// rattache les capteurs connus au lancement, la page des capteurs connecte
/// celui qu'on vient de taper. Le second est un tap, le premier est silencieux,
/// mais les deux doivent mémoriser exactement de la même façon — un capteur
/// appairé à la main et le même capteur retrouvé au démarrage suivant ne
/// peuvent pas donner deux entrées différentes.
class DeviceLinker {
  const DeviceLinker({required this.hub, required this.devices});

  final SensorHub hub;
  final KnownDevicesStore devices;

  /// Connecte un appareil et le retient dès qu'il a répondu.
  ///
  /// Lève si la demande de connexion échoue : c'est à l'appelant de décider si
  /// ça mérite un message — un tap raté se dit, une reconnexion silencieuse
  /// non.
  Future<SensorConnection> connect(
    BluetoothDevice device, {
    String? label,
  }) async {
    final connection = await hub.add(device, label: label);
    _rememberOnConnect(connection);
    return connection;
  }

  /// Reprend contact avec les capteurs connus, sans scan préalable.
  ///
  /// Un scan est inutile pour se rattacher à une adresse déjà connue. Les
  /// demandes partent toutes en même temps : elles rendent la main aussitôt,
  /// le système rattachant chaque capteur au fur et à mesure qu'il réapparaît.
  ///
  /// Idempotent : le hub renvoie la connexion existante si l'appareil est déjà
  /// suivi, ce qui permet de rappeler la méthode à chaque allumage du
  /// Bluetooth.
  Future<void> reconnectKnown() async {
    if (!await FlutterBluePlus.isSupported) return;

    for (final known in devices.devices) {
      if (!known.autoConnect) {
        // Dit à voix haute : une connexion auto coupée par mégarde dans le menu
        // d'un capteur ressemble en tout point à un capteur en panne, et c'est
        // la première chose à écarter quand « il ne se connecte plus ».
        debugPrint('[devices] ${known.name} : connexion auto désactivée, ignoré');
        continue;
      }
      unawaited(_reconnect(known));
    }
  }

  Future<void> _reconnect(KnownDevice known) async {
    try {
      await connect(
        BluetoothDevice.fromId(known.remoteId),
        label: known.name.isEmpty ? null : known.name,
      );
    } catch (e) {
      // Un capteur hors de portée au lancement est le cas normal, pas une
      // panne : la connexion sera retentée au prochain allumage du Bluetooth,
      // et rien à l'écran ne doit crier pour autant.
      debugPrint('[devices] ${known.name} injoignable : $e');
    }
  }

  Future<void> forget(KnownDevice known) async {
    await hub.remove(DeviceIdentifier(known.remoteId));
    await devices.forget(known.remoteId);
  }

  /// Écrit l'appareil au catalogue à chaque fois qu'il passe à *connecté*.
  ///
  /// À la connexion, pas au tap : tant que l'appareil n'a pas répondu on ne
  /// connaît ni son nom ni ses capacités, et mémoriser une adresse qui ne
  /// répond jamais encombrerait la liste. Les reconnexions repassent par là,
  /// ce qui rafraîchit la date et suffit à trier la liste par usage.
  void _rememberOnConnect(SensorConnection connection) {
    void persist() {
      if (connection.status.value != SensorStatus.connected) return;
      devices.remember(
        connection.device.remoteId.str,
        name: connection.name,
        kinds: connection.detectedKinds.value,
      );
    }

    connection.status.addListener(persist);
    // Les capacités arrivent à la découverte des services, parfois après le
    // passage à « connecté » : les deux notifications déclenchent l'écriture.
    connection.detectedKinds.addListener(persist);
    persist();
  }
}
