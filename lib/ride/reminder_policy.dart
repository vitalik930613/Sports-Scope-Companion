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
///
/// Un rappel qui porte un `count` ne sonne que ses `count` premiers multiples
/// — « calibrer le capteur » (`intervalMinutes: 30, count: 1`) tombe à la 30ᵉ
/// minute et se tait ensuite. Le semis compte pour ça aussi : remonter la
/// coquille après l'échéance ne le rejoue pas, le multiple courant est déjà
/// au-delà de `count`.
///
/// Un rappel qui porte un `startAfterMinutes` ne commence à compter qu'une
/// fois ce délai passé, et son tout premier déclenchement tombe pile à ce
/// délai plutôt qu'un intervalle plus tard — « manger toutes les heures, à
/// partir d'1h30 » sonne à 1h30, 2h30, 3h30… Sans délai (la valeur par
/// défaut, `0`), le premier multiple reste `0` et [read] le passe déjà sous
/// silence : ce cas particulier retombe donc exactement sur la formule
/// d'avant ce réglage, plutôt que de sonner dès la première minute roulée.
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
    final elapsed = recorded.inMinutes - reminder.startAfterMinutes;
    if (elapsed < 0) return 0;
    final steps = elapsed ~/ reminder.intervalMinutes;
    // Avec un délai, le pas `0` (pile au délai) doit sonner : décalé d'un cran
    // pour ne jamais valoir `0`, seul multiple que [read] tait toujours. Sans
    // délai, ce décalage disparaît et on retombe sur `steps` — la formule
    // d'origine, dont le pas `0` (avant le premier intervalle) doit lui rester
    // muet.
    return reminder.startAfterMinutes > 0 ? steps + 1 : steps;
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
      final count = reminder.count;
      if (count != null && multiple > count) continue;
      due.add(reminder);
    }
    return due;
  }
}
