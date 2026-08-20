import 'dart:collection';

import 'package:flutter/foundation.dart';

/// Un point de la piste : seconde écoulée depuis le départ de l'enregistrement
/// ([RideRecorder.recorded] au moment de la mesure), valeur du capteur.
@immutable
class MetricTrackPoint {
  const MetricTrackPoint(this.elapsedS, this.value);

  final int elapsedS;
  final double value;

  @override
  bool operator ==(Object other) =>
      other is MetricTrackPoint && other.elapsedS == elapsedS && other.value == value;

  @override
  int get hashCode => Object.hash(elapsedS, value);
}

/// Accumule la série temporelle d'une mesure de capteur (cardio, puissance)
/// pendant la sortie en cours, pour le composant de tendance (`MetricTrendCard`,
/// `lib/ride/blocks/metric_trend_block.dart`).
///
/// Deux vues, pour deux besoins qui s'opposent :
///
///  - **toute la sortie** ([points]) : rééchantillonnée en continu, même
///    parade que `RideElevationTrack` — une sortie de plusieurs heures
///    produirait sinon des dizaines de milliers de points pour un graphique
///    qui n'en affiche jamais plus de quelques centaines de pixels de large.
///    La résolution se dégrade donc avec le temps : ce qu'on y cherche est la
///    forme d'ensemble de la sortie, pas la seconde précise.
///  - **les X dernières secondes/minutes** ([recent]) : une fenêtre glissante
///    à pleine résolution. La dégradation ci-dessus la rendrait illisible
///    passé les toutes premières minutes de la sortie, alors que c'est
///    justement là qu'on veut voir chaque à-coup. Bornée à [recentWindowS] :
///    au-delà, un point est trop vieux pour jamais être demandé par une
///    fenêtre récente, et n'a pas à être gardé deux fois.
///
/// Local au téléphone : rien n'est transmis nulle part, même remarque que
/// `RideElevationTrack`.
class RideMetricTrack {
  RideMetricTrack({this.maxPoints = 300, this.recentWindowS = 3600});

  final int maxPoints;

  /// Largeur de [_recent], en secondes — 3600 (1 h) couvre largement toute
  /// fenêtre qu'un profil de sortie pourrait raisonnablement régler ; une
  /// fenêtre plus large que ça n'aurait de toute façon plus rien d'une vue
  /// « récente ».
  final int recentWindowS;

  final List<MetricTrackPoint> _points = [];
  int _minStepS = 1;

  final Queue<MetricTrackPoint> _recent = Queue<MetricTrackPoint>();

  /// Vue d'ensemble de toute la sortie, rééchantillonnée — voir la tête de
  /// classe.
  List<MetricTrackPoint> get points => List.unmodifiable(_points);

  /// Les points des [windowS] dernières secondes, à pleine résolution — vide
  /// si rien n'a encore été mesuré (sortie qui vient de démarrer, capteur qui
  /// vient de décrocher).
  List<MetricTrackPoint> recent(int windowS) {
    if (_recent.isEmpty) return const [];
    final cutoff = _recent.last.elapsedS - windowS;
    return [for (final point in _recent) if (point.elapsedS >= cutoff) point];
  }

  /// `value` à `null` : rien à ajouter — un capteur muet ne mesure pas zéro,
  /// il ne mesure rien, même règle que partout ailleurs dans l'appli. Un zéro
  /// *mesuré* (roue libre sur un capteur de puissance), lui, reste : c'est une
  /// valeur, pas une absence, et une courbe qui l'effacerait mentirait sur ce
  /// qu'on a réellement produit — contrairement à l'histogramme de zones
  /// (`RideStats`), qui l'écarte pour ne pas gonfler la zone la plus basse
  /// d'un temps qui n'a pas été passé à pédaler doucement, une question qui ne
  /// se pose pas ici.
  void add(int elapsedS, num? value) {
    if (value == null) return;
    final point = MetricTrackPoint(elapsedS, value.toDouble());

    _recent.addLast(point);
    while (_recent.isNotEmpty && point.elapsedS - _recent.first.elapsedS > recentWindowS) {
      _recent.removeFirst();
    }

    if (_points.isNotEmpty && elapsedS - _points.last.elapsedS < _minStepS) return;
    _points.add(point);
    if (_points.length > maxPoints * 2) _compact();
  }

  /// Jette un point sur deux et double le pas minimal — même parade que
  /// `RideElevationTrack._compact`.
  void _compact() {
    final kept = <MetricTrackPoint>[];
    for (var i = 0; i < _points.length; i += 2) {
      kept.add(_points[i]);
    }
    if (kept.last != _points.last) kept.add(_points.last);
    _points
      ..clear()
      ..addAll(kept);
    _minStepS *= 2;
  }

  void reset() {
    _points.clear();
    _minStepS = 1;
    _recent.clear();
  }
}
