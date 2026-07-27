import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'characteristic_decoder.dart';
import 'sensor_uuids.dart';

/// Ce qu'un appareil sait mesurer.
///
/// C'est la granularité utile partout ailleurs : un même boîtier peut porter
/// plusieurs profils (un capteur de puissance publie souvent la cadence), et
/// c'est ce qu'on retient d'un appareil connu — pas son modèle commercial.
enum SensorKind { heartRate, power, speedCadence, gears, radar }

/// Un profil relie une capacité à ce qu'il faut lire en GATT pour l'obtenir.
///
/// Ajouter un capteur = ajouter une entrée dans [sensorProfiles]. Ni
/// [SensorConnection], ni le hub, ni l'UI n'ont à être touchés.
class SensorProfile {
  SensorProfile({
    required this.kind,
    required this.label,
    required this.service,
    required this.characteristic,
    required this.decoder,
  });

  final SensorKind kind;
  final String label;

  /// Service annoncé au scan — sert d'indice *avant* connexion.
  final Guid service;

  /// Caractéristique effectivement lue. C'est elle qui fait foi après
  /// connexion : un appareil peut exposer le service sans la caractéristique
  /// (une ceinture qui annonce le service batterie sans niveau lisible).
  final Guid characteristic;

  final CharacteristicDecoder Function() decoder;
}

/// Le registre. Ordre d'affichage compris.
final sensorProfiles = <SensorProfile>[
  SensorProfile(
    kind: SensorKind.heartRate,
    label: 'Cardio',
    service: BleServices.heartRate,
    characteristic: BleCharacteristics.heartRateMeasurement,
    decoder: HeartRateCharacteristic.new,
  ),
  SensorProfile(
    kind: SensorKind.power,
    label: 'Puissance',
    service: BleServices.cyclingPower,
    characteristic: BleCharacteristics.cyclingPowerMeasurement,
    decoder: CyclingPowerCharacteristic.new,
  ),
  SensorProfile(
    kind: SensorKind.speedCadence,
    label: 'Vitesse/cadence',
    service: BleServices.cyclingSpeedCadence,
    characteristic: BleCharacteristics.cscMeasurement,
    decoder: CscCharacteristic.new,
  ),
  SensorProfile(
    kind: SensorKind.gears,
    label: 'Vitesses Di2',
    service: BleServices.di2,
    characteristic: BleCharacteristics.di2Gears,
    decoder: Di2Characteristic.new,
  ),
  SensorProfile(
    kind: SensorKind.radar,
    label: 'Radar',
    service: BleServices.variaRadar,
    characteristic: BleCharacteristics.variaThreats,
    decoder: VariaRadarCharacteristic.new,
  ),
];

SensorProfile? profileFor(SensorKind kind) {
  for (final profile in sensorProfiles) {
    if (profile.kind == kind) return profile;
  }
  return null;
}

String labelFor(SensorKind kind) => profileFor(kind)?.label ?? kind.name;

/// Services à annoncer si on filtre un scan.
///
/// On ne filtre pas, justement : le Di2 n'annonce pas son service propriétaire
/// dans ses trames de publicité, filtrer le rendrait invisible. La liste sert
/// à *classer* ce qu'on voit passer, pas à l'exclure.
List<Guid> get knownServices => [for (final p in sensorProfiles) p.service];

/// Ce qu'un appareil annonce savoir faire, d'après ses services de publicité.
///
/// Résultat indicatif : vide ne veut pas dire « rien à offrir », seulement
/// « rien d'annoncé ». La vérité vient de [kindsFromCharacteristics] après
/// connexion.
Set<SensorKind> kindsFromServices(Iterable<Guid> services) {
  final advertised = services.toSet();
  return {
    for (final profile in sensorProfiles)
      if (advertised.contains(profile.service)) profile.kind,
  };
}

/// Ce qu'un appareil sait faire, d'après les caractéristiques découvertes.
Set<SensorKind> kindsFromCharacteristics(Iterable<Guid> characteristics) {
  final present = characteristics.toSet();
  return {
    for (final profile in sensorProfiles)
      if (present.contains(profile.characteristic)) profile.kind,
  };
}

/// Instancie un décodeur neuf par capacité retenue.
///
/// Neuf à chaque appel : les décodeurs portent un état (compteurs cumulés,
/// dernier horodatage), en partager un entre deux connexions produirait des
/// deltas à cheval sur deux capteurs.
List<CharacteristicDecoder> decodersFor(Iterable<SensorKind> kinds) {
  final wanted = kinds.toSet();
  return [
    for (final profile in sensorProfiles)
      if (wanted.contains(profile.kind)) profile.decoder(),
  ];
}
