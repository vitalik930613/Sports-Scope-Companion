import 'dart:async';

import 'package:flutter/foundation.dart';

import '../ble/samples.dart';

/// Ce que le radar arrière dit de la route, en quatre états qui ne se
/// confondent pas.
///
/// [absent] et [clear] sont deux choses différentes et le resteront : pas de
/// radar, ce n'est pas une route dégagée. Afficher « voie libre » sans radar
/// serait la pire information que cet écran puisse donner.
enum RadarSeverity {
  /// Aucun radar, ou un radar qui s'est tu depuis trop longtemps.
  absent,

  /// Radar connecté, rien derrière.
  clear,

  /// Au moins un véhicule suivi.
  approaching,

  /// Le plus proche est à portée de rétroviseur.
  close,
}

/// Le radar tel qu'on le dessine : une gravité, et une position par véhicule.
@immutable
class RadarView {
  const RadarView({
    required this.severity,
    this.positions = const [],
    this.nearestM,
  });

  static const absent = RadarView(severity: RadarSeverity.absent);

  final RadarSeverity severity;

  /// Une valeur par véhicule, du plus proche au plus lointain : c'est une
  /// **proximité**, pas une position à l'écran. **0 = au bout de la portée,
  /// 1 = à la roue.** Où cela se dessine appartient à la jauge, qui les fait
  /// monter du bas vers le haut à mesure qu'un véhicule se rapproche.
  final List<double> positions;

  /// Distance du véhicule le plus proche, en mètres. C'est le seul chiffre du
  /// radar qu'on affiche tel quel — tout le reste est une couleur ou une
  /// position.
  final int? nearestM;

  /// Combien de véhicules sont suivis. Sort de [positions], qui en a déjà un par
  /// véhicule : deux comptes séparés finiraient par se contredire.
  int get count => positions.length;

  /// Y a-t-il quelque chose derrière ? C'est ce qui allume le cadre.
  bool get isAlerting =>
      severity == RadarSeverity.approaching || severity == RadarSeverity.close;

  @override
  bool operator ==(Object other) =>
      other is RadarView &&
      other.severity == severity &&
      other.nearestM == nearestM &&
      listEquals(other.positions, positions);

  @override
  int get hashCode =>
      Object.hash(severity, nearestM, Object.hashAll(positions));
}

/// Traduit une trame radar en quelque chose de dessinable.
///
/// Les seuils sont des paramètres nommés : le jour où l'unité de vitesse
/// d'approche du Varia sera établie (voir `decoders/varia.dart`), les calibrer
/// sera une ligne. Leurs valeurs par défaut sont **celles de la carte de
/// diagnostic** (`ui/radar_card.dart`, rouge sous 40 m, orange sinon) — les deux
/// affichages doivent raconter la même chose du même capteur.
///
/// [staleAfter] n'est pas un détail : le hub garde la dernière valeur d'un
/// capteur débranché, délibérément (une mesure faite reste une mesure faite).
/// Sur un radar, cette règle laisserait une voiture fantôme collée à l'écran
/// pour le reste de la sortie.
RadarView radarViewFor(
  RadarSample? sample, {
  required DateTime now,
  double closeM = 40,
  double rangeM = 140,
  Duration staleAfter = const Duration(seconds: 6),
}) {
  if (sample == null) return RadarView.absent;
  if (now.difference(sample.at) > staleAfter) return RadarView.absent;
  if (sample.isClear) return const RadarView(severity: RadarSeverity.clear);

  final targets = [...sample.targets]
    ..sort((a, b) => a.distanceM.compareTo(b.distanceM));

  return RadarView(
    severity: targets.first.distanceM < closeM
        ? RadarSeverity.close
        : RadarSeverity.approaching,
    positions: [
      for (final target in targets)
        (1 - target.distanceM / rangeM).clamp(0.0, 1.0),
    ],
    nearestM: targets.first.distanceM,
  );
}

/// La vue radar courante, tenue à jour et **capable de se périmer toute seule**.
///
/// Un radar publie une trame par seconde tant qu'il est là. Se contenter
/// d'écouter ses trames suffirait à afficher, mais pas à effacer : une
/// ceinture qui se décroche, une batterie vide, et le dernier véhicule vu
/// resterait à l'écran. D'où l'horloge — qui ne tourne que lorsqu'il y a
/// quelque chose à effacer.
class RadarViewNotifier extends ValueNotifier<RadarView> {
  RadarViewNotifier(
    this._source, {
    this.closeM = 40,
    this.rangeM = 140,
  }) : super(RadarView.absent) {
    _source.addListener(_refresh);
    _refresh();
  }

  final ValueListenable<RadarSample?> _source;

  /// Les seuils du profil de sortie : un VTT n'a pas la même idée de « proche »
  /// qu'une route à 30 km/h de moyenne.
  final double closeM;
  final double rangeM;

  Timer? _timer;

  void _refresh() {
    value = radarViewFor(
      _source.value,
      now: DateTime.now(),
      closeM: closeM,
      rangeM: rangeM,
    );

    if (value.severity == RadarSeverity.absent) {
      _timer?.cancel();
      _timer = null;
    } else {
      _timer ??= Timer.periodic(
        const Duration(seconds: 1),
        (_) => _refresh(),
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _source.removeListener(_refresh);
    super.dispose();
  }
}
