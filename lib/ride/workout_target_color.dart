import 'package:flutter/material.dart';

import '../dashboard/metric_id.dart';
import '../training_program/training_program.dart';

/// En dessous du min du step — il faut relancer. Clignote (voir
/// [workoutTargetColorFor]) plutôt qu'un fond fixe : moins alarmant qu'un
/// rouge fixe aurait suggéré, mais toujours visible du coin de l'œil.
const Color kWorkoutBelowTargetColor = Color(0xFF1565C0);

/// Au-dessus du max du step — il faut lever le pied. Clignote aussi, plus
/// urgent que le bleu : c'est celui des deux qui appelle une correction
/// immédiate (sécurité/effort qui dérape), pas juste une relance.
const Color kWorkoutAboveTargetColor = Color(0xFFB3261E);

/// Dans les bornes du step — fixe, volontairement sans clignotement : c'est
/// l'état où on ne veut justement rien attirer l'œil.
const Color kWorkoutInRangeColor = Color(0xFF2E7D32);

/// Les quatre mesures en direct concernées par une cible de programme
/// d'entraînement — leurs variantes zone/moyenne/max/NP ne se lisent pas
/// comme "je suis en train de rouler à cette valeur-là" et n'en ont pas.
const _workoutTargetMetrics = {MetricId.power, MetricId.heartRate, MetricId.cadence, MetricId.speed};

/// Sert à décider, au niveau du widget appelant, s'il faut ajouter le tic de
/// l'enregistreur (`RideRecorder.workoutTargetBlinkOn`) à ses dépendances de
/// rafraîchissement : `power`/`heartRate`/`cadence` ne dépendent sinon que du
/// capteur (`MetricId.dependencies`), qui ne bat pas forcément à la même
/// cadence que le clignotement.
bool isWorkoutTargetMetric(MetricId metric) => _workoutTargetMetrics.contains(metric);

/// Bornes de cible de [milestone] pour [metric] — `null` si `metric` n'en
/// fait pas partie ([isWorkoutTargetMetric]), ou si le step ne porte aucune
/// des deux bornes pour cette mesure.
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

/// Bleu clignotant si [value] est sous le min du step en cours, rouge
/// clignotant si elle dépasse le max, vert fixe si elle est dedans. Une
/// borne absente ne referme pas ce côté-là (min seul défini : bleu si en
/// dessous, jamais rouge). `null` (pas de changement de fond côté appelant,
/// donc retour au fond habituel de la case) sans entraînement actif
/// ([milestone] `null`), sans cible sur ce step pour [metric], sans chiffre
/// ([value] `null`, capteur muet), ou pendant la phase basse du clignotement
/// ([blinkOn] `false`) pour un dépassement — c'est ce qui fait alterner le
/// fond entre la couleur d'alerte et le fond normal plutôt qu'une vraie
/// transparence.
///
/// Prioritaire sur tout le reste côté appelant (couleur fixe de l'éditeur,
/// seuils personnalisés `gaugeThresholds`/`gaugeThresholdColors`) : c'est la
/// valeur de retour qui doit primer dans la chaîne `??` de
/// `MetricView._paint` et des cases de bandeau/encoche — le signal le plus
/// pertinent en plein effort.
Color? workoutTargetColorFor(WorkoutMilestone? milestone, MetricId metric, double? value, {required bool blinkOn}) {
  if (milestone == null || value == null) return null;
  final range = _targetRangeFor(milestone, metric);
  if (range == null) return null;
  final (min, max) = range;
  if (min != null && value < min) return blinkOn ? kWorkoutBelowTargetColor : null;
  if (max != null && value > max) return blinkOn ? kWorkoutAboveTargetColor : null;
  return kWorkoutInRangeColor;
}
