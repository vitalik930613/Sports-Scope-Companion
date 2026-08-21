import 'dart:math' as math;

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
    // `elapsed <= 0` veut dire « le programme vient d'être activé » (cf.
    // `RideRecorder.workoutElapsed`, qui repart de zéro à l'activation) : rien
    // n'a encore pu être franchi, pas même le jalon d'ouverture à offset 0. Le
    // sauter ici l'aurait fait disparaître pour toute la sortie — [read] ne
    // rappelle jamais un jalon une fois `_next` passé devant.
    if (elapsed <= Duration.zero) return;
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

/// Décide quel jalon doit lancer son son d'annonce — décalé plus tôt que
/// son franchissement officiel, pour que la lecture **se termine** au
/// départ du jalon plutôt que de commencer dessus. Un jalon qui dure 30 s
/// suivi d'un son de 5 s : le son part à 25 s, pas à 30.
///
/// Même famille que [WorkoutPolicy] — pure, testable sans widget ni
/// horloge — mais un index séparé : l'annonce d'un jalon précède son
/// franchissement, les deux ne peuvent pas partager un seul curseur. Le
/// franchissement lui-même (splits/`markLap`) reste sur [WorkoutPolicy],
/// inchangé — seul l'instant du bip se décale.
///
/// Le premier jalon (à l'offset 0) n'a rien avant lui : son son, s'il en a
/// un, part immédiatement comme avant — aucune anticipation possible avant
/// le début du programme.
class WorkoutCuePolicy {
  WorkoutCuePolicy({
    required this.milestones,
    required this.soundDuration,
    required Duration elapsed,
  }) {
    if (elapsed <= Duration.zero) return;
    while (_next < milestones.length && _cueOffsetSeconds(_next) <= elapsed.inSeconds) {
      _next++;
    }
  }

  final List<WorkoutMilestone> milestones;

  /// Consultée à chaque lecture plutôt que figée à la construction : les
  /// sons se préchargent en tâche de fond (`WorkoutCuePlayer.warmUp`), leur
  /// durée peut donc n'être connue qu'après coup. Une durée encore inconnue
  /// vaut zéro — l'anticipation est alors nulle, comportement identique à
  /// avant ce mécanisme, jamais un son en retard sur son jalon.
  final Duration Function(WorkoutSound sound) soundDuration;

  int _next = 0;

  /// L'instant, en secondes depuis l'activation, où le son du jalon
  /// [index] doit démarrer pour se terminer pile à son offset. Sans son (ou
  /// pour le premier jalon), c'est l'offset lui-même. Jamais avant le
  /// jalon précédent : un son plus long que le tronçon qui le porte ne doit
  /// pas empiéter sur l'annonce d'avant.
  int _cueOffsetSeconds(int index) {
    final milestone = milestones[index];
    final sound = milestone.sound;
    if (index == 0 || sound == null) return milestone.offsetSeconds;

    final leadMs = soundDuration(sound).inMilliseconds;
    final leadSeconds = (leadMs / 1000).ceil();
    final earliest = milestones[index - 1].offsetSeconds;
    return math.max(earliest, milestone.offsetSeconds - leadSeconds);
  }

  /// Le jalon dont le son doit être lancé **ce tic-ci**, ou `null` — au
  /// plus un par appel, comme [WorkoutPolicy.read].
  WorkoutMilestone? read(Duration elapsed) {
    if (_next >= milestones.length) return null;
    if (_cueOffsetSeconds(_next) > elapsed.inSeconds) return null;
    return milestones[_next++];
  }

  /// Le dernier jalon a-t-il été annoncé ?
  bool get finished => _next >= milestones.length;
}
