import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Construit un UUID 128 bits à partir d'un identifiant 16 bits et d'une base
/// vendeur. La base par défaut est celle du Bluetooth SIG.
String uuid128(int short, {String base = _sigBase}) =>
    '0000${short.toRadixString(16).padLeft(4, '0')}-$base';

const _sigBase = '0000-1000-8000-00805f9b34fb';

/// Base propriétaire Shimano — les 12 octets de queue se lisent en ASCII :
/// 53 48 49 4D 41 4E 4F 5F 42 4C 45 00  ->  "SHIMANO_BLE\0"
///
/// Shimano y réutilise la convention 16 bits du SIG, d'où la même fonction de
/// construction que pour les services standards.
const shimanoBase = '5348-494d-414e-4f5f424c4500';

String shimanoUuid(int short) => uuid128(short, base: shimanoBase);

/// Base propriétaire Garmin, utilisée par le radar Varia.
///
/// Contrairement à Shimano, elle ne suit pas la convention 16 bits du SIG : les
/// UUID sont écrits en entier.
const _variaBase = '667b-11e3-949a-0800200c9a66';

String variaUuid(int short) =>
    '${short.toRadixString(16).padLeft(8, '0')}-$_variaBase';

/// Services standards.
class BleServices {
  static final heartRate = Guid(uuid128(0x180D));
  static final cyclingPower = Guid(uuid128(0x1818));
  static final cyclingSpeedCadence = Guid(uuid128(0x1816));
  static final battery = Guid(uuid128(0x180F));
  static final deviceInformation = Guid(uuid128(0x180A));

  /// Service propriétaire Di2 12 vitesses.
  static final di2 = Guid(shimanoUuid(0x18EF));

  /// Service radar du Garmin Varia (RTL5xx / RCT7xx).
  static final variaRadar = Guid(variaUuid(0x6A4E3200));
}

/// Caractéristiques.
class BleCharacteristics {
  static final heartRateMeasurement = Guid(uuid128(0x2A37));
  static final cyclingPowerMeasurement = Guid(uuid128(0x2A63));
  static final cscMeasurement = Guid(uuid128(0x2A5B));

  /// Cycling Power Control Point : le seul canal où l'appli *écrit*. Il porte
  /// la calibration (compensation d'offset) — voir `power_calibration.dart`.
  /// Facultatif dans le profil : un capteur peut publier sa puissance sans
  /// l'exposer.
  static final cyclingPowerControlPoint = Guid(uuid128(0x2A66));
  static final batteryLevel = Guid(uuid128(0x2A19));

  /// Position des vitesses Di2. Format non documenté par Shimano, décodé par
  /// observation — voir `decoders/di2.dart`.
  static final di2Gears = Guid(shimanoUuid(0x2AC1));

  /// Boutons D-Fly (satellites/sprinter) du Di2. Characteristic distincte de
  /// [di2Gears], établie par sniff GATT — voir `decoders/di2_buttons.dart`.
  static final di2Buttons = Guid(shimanoUuid(0x2AC2));

  /// Liste des cibles détectées par le Varia (notify). Format non documenté par
  /// Garmin — voir `decoders/varia.dart`, la disposition reste à confirmer.
  static final variaThreats = Guid(variaUuid(0x6A4E3203));

  /// Second canal du service radar, rôle non établi (état/commande ?).
  static final variaControl = Guid(variaUuid(0x6A4E3201));
}
