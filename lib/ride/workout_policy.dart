import '../training_program/training_program.dart';

/// Décide quel jalon d'un programme d'entraînement vient d'être franchi.
///
/// Même famille que `ClimbEdgePolicy`/`RideReminderPolicy` : une classe pure,
/// testable sans widget ni horloge. Contrairement aux rappels périodiques
/// (intervalles récurrents), les offsets d'un programme sont absolus et
/// strictement croissants — une simple avancée séquentielle suffit, jamais
/// plus d'un jalon franchi par tic.
///
/// Semée dès la construction sur [elapsed] déjà écoulé, et non à zéro : la
/// coquille se démonte et se remonte à chaque aller-retour à l'accueil, et
/// repartir de zéro y rejouerait aussitôt tous les jalons déjà passés — même
/// raison que `RideReminderPolicy`.
///
/// **[elapsed] n'est jamais `RideRecorder.recorded` directement** : un
/// programme peut être activé en cours de sortie, ses offsets comptent depuis
/// l'activation, pas depuis le départ. C'est `RideRecorder.workoutElapsed`
/// qui porte ce calcul (`recorded - workoutStartSeconds`) ; cette classe ne
/// fait que comparer la durée qu'on lui donne aux jalons.
class WorkoutPolicy {
  WorkoutPolicy({required this.milestones, required Duration elapsed}) {
    while (_next < milestones.length &&
        milestones[_next].offsetSeconds <= elapsed.inSeconds) {
      _next++;
    }
  }

  final List<WorkoutMilestone> milestones;
  int _next = 0;

  /// Le jalon franchi **ce tic-ci**, ou `null` — au plus un par appel, les
  /// offsets étant strictement croissants.
  WorkoutMilestone? read(Duration elapsed) {
    if (_next >= milestones.length) return null;
    if (milestones[_next].offsetSeconds > elapsed.inSeconds) return null;
    return milestones[_next++];
  }

  /// Le dernier jalon a-t-il été franchi ?
  bool get finished => _next >= milestones.length;
}
