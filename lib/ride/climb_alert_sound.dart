import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Les deux instants qu'un col peut avoir à annoncer.
enum ClimbCue {
  start,
  end;

  String get asset => switch (this) {
        ClimbCue.start => 'sounds/start.wav',
        ClimbCue.end => 'sounds/end.wav',
      };
}

/// Joue les tonalités de col — même patron que `RadarAlertPlayer` : un
/// lecteur par son, chargé d'avance, pour ne pas ouvrir de fichier au moment
/// du front. Le front lui-même vient de [ClimbEdgePolicy] (déjà stabilisé,
/// voir `ride_shell_page.dart`), cette classe ne fait que sonner.
///
/// Même contexte audio que le radar (guidage de navigation, volume
/// multimédia, baisse la musique le temps du bip) : un début ou une fin de
/// col n'a pas plus vocation à couper ce qu'on écoute qu'une voiture qui
/// approche.
class ClimbAlertPlayer {
  final _players = <ClimbCue, AudioPlayer>{};

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
      for (final cue in ClimbCue.values) {
        final player = AudioPlayer()..setReleaseMode(ReleaseMode.stop);
        await player.setSource(AssetSource(cue.asset));
        _players[cue] = player;
      }
    } catch (e) {
      debugPrint('[col] sons indisponibles : $e');
    }
  }

  void play(ClimbCue cue) {
    final player = _players[cue];
    if (player == null) return;
    player.seek(Duration.zero).then((_) => player.resume()).catchError((
      Object e,
    ) {
      debugPrint('[col] bip perdu : $e');
    });
  }

  Future<void> dispose() async {
    for (final player in _players.values) {
      await player.dispose();
    }
    _players.clear();
  }
}
