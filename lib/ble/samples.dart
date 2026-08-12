import 'decoders/di2.dart';

/// Une mesure horodatée issue d'un capteur.
///
/// Toutes les valeurs sont nullables : un capteur peut publier une trame
/// partielle (un capteur de puissance sans capteur de cadence, par exemple).
/// L'horodatage est celui de la *réception*, pas celui du capteur — les
/// compteurs d'événements BLE sont relatifs et bouclent sur 16 bits.
sealed class SensorSample {
  const SensorSample(this.at);

  final DateTime at;
}

class HeartRateSample extends SensorSample {
  const HeartRateSample(super.at, this.bpm, {this.rrIntervalsMs = const []});

  final int bpm;

  /// Intervalles R-R en millisecondes, si le capteur les publie.
  /// Base de la variabilité cardiaque — inutile de les jeter, ils ne coûtent
  /// rien à stocker et ne se retrouvent nulle part ailleurs.
  final List<double> rrIntervalsMs;
}

class PowerSample extends SensorSample {
  const PowerSample(super.at, this.watts, {this.balanceLeftPercent});

  final int watts;

  /// Équilibre gauche/droite en pourcentage côté gauche, si publié.
  final double? balanceLeftPercent;
}

class CadenceSample extends SensorSample {
  const CadenceSample(super.at, this.rpm);

  final double rpm;
}

class WheelSpeedSample extends SensorSample {
  const WheelSpeedSample(super.at, this.revolutionsPerSecond);

  final double revolutionsPerSecond;

  /// Vitesse en m/s pour une circonférence de roue donnée (en mètres).
  double speedMs(double wheelCircumference) =>
      revolutionsPerSecond * wheelCircumference;
}

class GearSample extends SensorSample {
  const GearSample(super.at, this.gears);

  final Di2Gears gears;
}

/// Ce que le tableau de bord doit faire d'une pression sur un bouton distant.
///
/// Volontairement pas le code de bouton brut : c'est le futur décodeur (D-Fly
/// du Di2, protocole non encore établi — voir `decoders/di2.dart`) qui
/// connaîtra le mapping matériel, pas [RideShellPage]. Deux valeurs seulement
/// parce que c'est tout ce qu'on sait vouloir en faire aujourd'hui — changer
/// de page, dans un sens ou l'autre.
enum RemoteButton { next, previous }

/// Une pression sur un bouton distant, déjà traduite en [RemoteButton].
class RemoteButtonSample extends SensorSample {
  const RemoteButtonSample(super.at, this.button);

  final RemoteButton button;
}

/// Un véhicule détecté par le radar arrière.
class RadarTarget {
  const RadarTarget({
    required this.id,
    required this.distanceM,
    required this.approachSpeedRaw,
  });

  /// Identifiant attribué par le radar, stable tant que la cible est suivie.
  /// C'est lui qui permet de dire « c'est la même voiture » d'une trame à
  /// l'autre, donc de ne pas ré-alerter en boucle.
  final int id;

  /// Distance en mètres.
  final int distanceM;

  /// Vitesse d'approche, **unité non établie** — voir `decoders/varia.dart`.
  /// Volontairement pas nommée « m/s » tant que ce n'est pas mesuré.
  final int approachSpeedRaw;

  @override
  String toString() => '#$id à ${distanceM}m (v=$approachSpeedRaw)';
}

/// État du radar à un instant donné.
///
/// Contrairement aux autres capteurs, la valeur utile n'est pas un scalaire
/// mais l'ensemble des cibles : une liste vide veut dire « route dégagée »,
/// pas « pas de données ».
class RadarSample extends SensorSample {
  const RadarSample(super.at, this.targets);

  final List<RadarTarget> targets;

  bool get isClear => targets.isEmpty;

  /// La cible la plus proche, celle qui compte pour l'alerte.
  RadarTarget? get nearest {
    if (targets.isEmpty) return null;
    return targets.reduce((a, b) => a.distanceM <= b.distanceM ? a : b);
  }
}

/// Trame non décodée, conservée telle quelle.
///
/// Émise *en plus* de l'échantillon décodé, jamais à la place. C'est le filet
/// de sécurité pour le Di2, dont le format est issu de rétro-ingénierie : le
/// jour où un firmware Shimano change la trame, les sorties déjà enregistrées
/// restent re-décodables a posteriori.
class RawFrame {
  const RawFrame(this.at, this.characteristicUuid, this.bytes);

  final DateTime at;
  final String characteristicUuid;
  final List<int> bytes;

  String get hex => bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join('-');
}
