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
