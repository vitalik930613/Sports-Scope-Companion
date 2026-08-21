import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../training_program/training_program.dart';

/// Joue les sons des jalons d'un programme d'entraînement — même patron que
/// `ClimbAlertPlayer` : un lecteur par son, préchargé au montage, pour ne pas
/// ouvrir de fichier au moment du front.
///
/// Même contexte audio que `ClimbAlertPlayer` (guidage de navigation, baisse
/// la musique le temps du bip), **pas** le flux alarme à focus exclusif de
/// `BellPlayer` : un HIIT peut sonner toutes les 30 secondes, un flux qui
/// coupe la musique à chaque fois serait bien plus intrusif qu'un col ou
/// qu'une voiture qui approche, deux événements rares par comparaison.
class WorkoutCuePlayer {
  final _players = <WorkoutSound, AudioPlayer>{};

  /// Durée de chaque son, connue une fois [warmUp] terminé — c'est elle qui
  /// permet à `WorkoutCuePolicy` de faire démarrer le son assez tôt pour
  /// qu'il se termine au départ du jalon plutôt que d'y commencer.
  final _durations = <WorkoutSound, Duration>{};

  /// `Duration.zero` tant que [warmUp] n'a pas résolu ce son (ou a échoué) :
  /// une durée inconnue vaut « pas d'anticipation », jamais un son qui parte
  /// en retard sur son jalon.
  Duration durationOf(WorkoutSound sound) => _durations[sound] ?? Duration.zero;

  static final _context = AudioContext(
    android: const AudioContextAndroid(
      contentType: AndroidContentType.sonification,
      usageType: AndroidUsageType.assistanceNavigationGuidance,
      audioFocus: AndroidAudioFocus.gainTransientMayDuck,
    ),
  );

  Future<void> warmUp() async {
    try {
      await AudioPlayer.global.setAudioContext(_context);
      for (final sound in WorkoutSound.values) {
        final player = AudioPlayer()..setReleaseMode(ReleaseMode.stop);
        await player.setSource(AssetSource(sound.asset));
        _players[sound] = player;
        final duration = await player.getDuration();
        if (duration != null) _durations[sound] = duration;
      }
    } catch (e) {
      debugPrint('[entraînement] sons indisponibles : $e');
    }
  }

  void play(WorkoutSound sound) {
    final player = _players[sound];
    if (player == null) return;
    player.seek(Duration.zero).then((_) => player.resume()).catchError((
      Object e,
    ) {
      debugPrint('[entraînement] bip perdu : $e');
    });
  }

  Future<void> dispose() async {
    for (final player in _players.values) {
      await player.dispose();
    }
    _players.clear();
  }
}
