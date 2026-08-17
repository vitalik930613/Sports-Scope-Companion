import '../dashboard/ride_preset.dart';

/// Décide quand un rappel du profil est arrivé à échéance — boire, manger,
/// entamer une intervalle.
///
/// Compté sur le temps **effectivement roulé** (`RideRecorder.recorded`),
/// pas sur l'horloge murale : un enregistrement en pause ne doit ni faire
/// sonner un rappel pendant l'arrêt (un café est déjà la pause qu'un rappel
/// « bois de l'eau » aurait demandée), ni rattraper d'un coup à la reprise ce
/// que l'arrêt a fait manquer — seul le multiple de l'intervalle compte,
/// jamais le nombre d'occasions ratées.
///
/// Semée dès la construction sur le temps déjà roulé, et non à zéro : la
/// coquille se démonte et se remonte à chaque aller-retour à l'accueil (voir
/// « Rentrer, et repartir » du guide), et repartir de zéro y rejouerait
/// aussitôt le dernier rappel déjà sonné avant la pause.
class RideReminderPolicy {
  RideReminderPolicy({
    required List<ReminderSpec> reminders,
    required Duration recorded,
  }) : _reminders = reminders {
    for (var i = 0; i < reminders.length; i++) {
      _lastFired[i] = _multipleOf(reminders[i], recorded);
    }
  }

  final List<ReminderSpec> _reminders;
  final _lastFired = <int, int>{};

  static int _multipleOf(ReminderSpec reminder, Duration recorded) {
    if (reminder.intervalMinutes <= 0) return 0;
    return recorded.inMinutes ~/ reminder.intervalMinutes;
  }

  /// Les rappels dont l'intervalle vient de s'écouler **ce tic-ci**, dans
  /// l'ordre du profil — vide la plupart du temps, la plupart des tics ne
  /// franchissant aucun multiple. Deux rappels peuvent tomber ensemble (15
  /// et 30 minutes coïncidant à la demi-heure) : à l'appelant de décider s'il
  /// les montre à la fois ou les met en file.
  List<ReminderSpec> read(Duration recorded) {
    final due = <ReminderSpec>[];
    for (var i = 0; i < _reminders.length; i++) {
      final reminder = _reminders[i];
      if (reminder.intervalMinutes <= 0) continue;
      final multiple = _multipleOf(reminder, recorded);
      if (multiple == 0 || _lastFired[i] == multiple) continue;
      _lastFired[i] = multiple;
      due.add(reminder);
    }
    return due;
  }
}
