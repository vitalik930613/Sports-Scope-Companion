import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../ble/sensor_connection.dart';
import '../ble/sensor_hub.dart';
import '../ble/sensor_profile.dart';
import '../devices/known_devices_store.dart';
import '../phone/phone_sensors.dart';
import '../ui/sensor_icons.dart';

/// L'état batterie d'un appareil connu, tel qu'on le dessine.
@immutable
class BatteryStatus {
  const BatteryStatus({
    required this.id,
    required this.label,
    required this.icon,
    required this.connected,
    this.kinds = const {},
    this.isPhone = false,
    this.percent,
    this.low = false,
  });

  /// `KnownDevice.remoteId` pour un capteur BLE, `'phone'` pour la batterie du
  /// téléphone lui-même — jamais affiché, sert seulement de clé.
  final String id;

  final String label;
  final IconData icon;

  /// Toujours vrai pour [isPhone] : le téléphone qui fait tourner l'appli
  /// n'est jamais « déconnecté » au sens où l'entend un capteur BLE.
  final bool connected;

  /// Capacités constatées de l'appareil (`KnownDevice.kinds`) — sert à
  /// [BatteryBlockView] à restreindre le mode compact à un capteur précis
  /// (`BatteryBlock.sensor`). Vide pour [isPhone].
  final Set<SensorKind> kinds;

  /// La ligne de la batterie du téléphone lui-même, plutôt qu'un capteur BLE
  /// — voir `BatterySensor.phone`. Pas un [SensorKind] : ce n'est pas un
  /// appareil BLE, `kinds` reste vide.
  final bool isPhone;

  /// `null` : pas connecté, ou connecté sans le service batterie standard —
  /// ou, pour [isPhone], pas encore de première lecture.
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
      setEquals(other.kinds, kinds) &&
      other.isPhone == isPhone &&
      other.percent == percent &&
      other.low == low;

  @override
  int get hashCode => Object.hash(
        id,
        label,
        icon,
        connected,
        Object.hashAllUnordered(kinds),
        isPhone,
        percent,
        low,
      );
}

/// Le pourcentage de batterie de chaque appareil connu, tenu à jour en
/// écoutant chaque connexion — et celui du téléphone lui-même, s'il en est
/// donné un.
///
/// La liste des lignes vient de [KnownDevicesStore] — la source stable et
/// écoutable, mise à jour par `DeviceLinker` à chaque connexion réussie
/// (voir `remember()`) — exactement le même schéma que `SensorStatusStrip`
/// sur l'accueil. Un instantané de `SensorHub.connections` ne conviendrait
/// pas : rien ne préviendrait quand un appareil se rattache en cours de
/// sortie (une ceinture cardio enfilée après le départ), et la liste
/// resterait figée jusqu'au prochain rechargement de la page.
///
/// Le pourcentage lui-même se lit sur `SensorConnection.batteryLevel`, pas sur
/// le flux `samples` : la lecture initiale (`readOnConnect`) arrive souvent
/// bien avant que ce notifieur n'existe (le tableau de bord de sortie se
/// monte après coup), et un flux broadcast ne rejoue rien à qui s'abonne en
/// retard — la première valeur, longtemps la seule, se perdrait en silence.
///
/// [phone] est facultatif et abonné pour de bon, sans `start`/`stop` — au
/// contraire du baromètre ou de la boussole, un intent collant ne réveille
/// rien entre deux trames, il n'y a donc rien à économiser à couper
/// l'abonnement. `null` (widget de test, plateforme non Android) : la ligne
/// téléphone n'apparaît simplement jamais, même repli que pour un appareil
/// BLE jamais appairé.
class BatteryStatusNotifier extends ValueNotifier<List<BatteryStatus>> {
  BatteryStatusNotifier(
    this._devices,
    this._hub, {
    PhoneSensors? phone,
    this.thresholdPercent = 20,
  }) : super(const []) {
    _devices.addListener(_resubscribe);
    _resubscribe();
    if (phone != null) {
      _phoneSub = phone.batteryPercent().listen((percent) {
        _phonePercent = percent;
        _rebuild();
      });
    }
  }

  final KnownDevicesStore _devices;
  final SensorHub _hub;
  final int thresholdPercent;

  final _listeners = <String, VoidCallback>{};
  final _subscribed = <String, SensorConnection>{};

  StreamSubscription<int>? _phoneSub;

  /// `null` tant qu'aucune trame n'est arrivée : pas de ligne téléphone dans
  /// [_rebuild] jusque-là, même convention qu'un appareil BLE pas encore lu.
  int? _phonePercent;

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
    void onChange() => _rebuild();
    connection.status.addListener(onChange);
    connection.batteryLevel.addListener(onChange);
    _listeners[id] = onChange;
  }

  void _unsubscribe(String id) {
    final connection = _subscribed.remove(id);
    final onChange = _listeners.remove(id);
    if (connection != null && onChange != null) {
      connection.status.removeListener(onChange);
      connection.batteryLevel.removeListener(onChange);
    }
  }

  void _rebuild() {
    value = [
      if (_phonePercent != null)
        BatteryStatus(
          id: 'phone',
          label: 'Téléphone',
          icon: Icons.smartphone,
          connected: true,
          isPhone: true,
          percent: _phonePercent,
          low: _isLow(_phonePercent),
        ),
      for (final device in _devices.devices)
        BatteryStatus(
          id: device.remoteId,
          label: device.name.isEmpty ? '(sans nom)' : device.name,
          icon: iconForDevice(device.kinds),
          kinds: device.kinds,
          connected:
              _subscribed[device.remoteId]?.status.value ==
              SensorStatus.connected,
          percent: _subscribed[device.remoteId]?.batteryLevel.value,
          low: _isLow(_subscribed[device.remoteId]?.batteryLevel.value),
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
    unawaited(_phoneSub?.cancel());
    super.dispose();
  }
}

/// Le fond d'une pastille de batterie : rouge à 30 % et en dessous, vert à
/// 100 %, orange à mi-chemin — un dégradé continu plutôt qu'un simple seuil
/// bas/haut, pour voir une batterie décliner avant qu'elle ne passe sous
/// l'alerte ([BatteryStatus.low]). Mêmes teintes que les zones d'entraînement
/// (`ui/zone_colors.dart`, `z5`/`z4`/`z2`) : une seule palette « rouge = ça ne
/// va pas » dans toute l'appli plutôt que d'en inventer une seconde.
Color batteryLevelColor(int percent) {
  const red = Color(0xFFD32F2F);
  const orange = Color(0xFFE8760C);
  const green = Color(0xFF2E9E4F);
  final clamped = percent.clamp(30, 100);
  return clamped <= 65
      ? Color.lerp(red, orange, (clamped - 30) / 35)!
      : Color.lerp(orange, green, (clamped - 65) / 35)!;
}
