import 'package:flutter/material.dart';

import '../dashboard/metric_id.dart';
import '../training_program/training_program.dart';

/// En dessous du min du step — il faut relancer.
const Color kWorkoutBelowTargetColor = Color(0xFFE8890C);

/// Au-dessus du max du step — il faut lever le pied.
const Color kWorkoutAboveTargetColor = Color(0xFFB3261E);

/// Dans les bornes du step.
const Color kWorkoutInRangeColor = Color(0xFF2E7D32);

/// Bornes de cible de [milestone] pour [metric] — seules les quatre mesures en
/// direct (puissance, cardio, cadence, vitesse) se lisent comme "je suis en
/// train de rouler à cette valeur-là" ; leurs variantes zone/moyenne/max/NP
/// n'ont pas de cible instantanée. `null` si `metric` n'en fait pas partie,
/// ou si le step ne porte aucune des deux bornes pour cette mesure.
(double?, double?)? _targetRangeFor(WorkoutMilestone milestone, MetricId metric) {
  final range = switch (metric) {
    MetricId.power => (milestone.minPower, milestone.maxPower),
    MetricId.heartRate => (milestone.minHeartRate, milestone.maxHeartRate),
    MetricId.cadence => (milestone.minCadence, milestone.maxCadence),
    MetricId.speed => (milestone.minSpeedKmh, milestone.maxSpeedKmh),
    _ => null,
  };
  if (range == null || (range.$1 == null && range.$2 == null)) return null;
  return range;
}

/// Orange si [value] est sous le min du step en cours, rouge si elle dépasse
/// le max, vert si elle est dedans. Une borne absente ne referme pas ce
/// côté-là (min seul défini : orange si en dessous, jamais rouge). `null`
/// (pas de changement de fond côté appelant) sans entraînement actif
/// ([milestone] `null`), sans cible sur ce step pour [metric], ou sans
/// chiffre ([value] `null`, capteur muet).
///
/// Prioritaire sur tout le reste côté appelant (couleur fixe de l'éditeur,
/// seuils personnalisés `gaugeThresholds`/`gaugeThresholdColors`) : c'est la
/// valeur de retour qui doit primer dans la chaîne `??` de
/// `MetricView._paint` et des cases de bandeau/encoche — le signal le plus
/// pertinent en plein effort.
Color? workoutTargetColorFor(WorkoutMilestone? milestone, MetricId metric, double? value) {
  if (milestone == null || value == null) return null;
  final range = _targetRangeFor(milestone, metric);
  if (range == null) return null;
  final (min, max) = range;
  if (min != null && value < min) return kWorkoutBelowTargetColor;
  if (max != null && value > max) return kWorkoutAboveTargetColor;
  return kWorkoutInRangeColor;
}
