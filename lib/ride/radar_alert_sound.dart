import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'radar_severity.dart';

/// Les trois choses que le radar peut avoir à dire à voix haute.
enum RadarCue {
  /// Un véhicule vient d'entrer en portée.
  approach,

  /// Le plus proche vient de passer sous le seuil de proximité.
  close,

  /// La route est redevenue libre.
  clear;

  String get asset => switch (this) {
        RadarCue.approach => 'sounds/radar_approach.wav',
        RadarCue.close => 'sounds/radar_close.wav',
        RadarCue.clear => 'sounds/radar_clear.wav',
      };
}

/// Décide quand le radar doit parler — et surtout quand il doit se taire.
///
/// Uniquement sur les **escalades** : entrer en portée, puis passer sous le
/// seuil de proximité. Une voiture qui reste derrière ne redit rien, et une
/// voiture qui s'éloigne d'un cran non plus. Un son qu'on entend trop devient un
/// son qu'on n'entend plus, et c'est celui-là qu'on n'entendrait pas le jour où
/// il compte.
///
/// La règle la moins évidente : **perdre le radar ne se dit pas « voie libre ».**
/// Une ceinture qui se décroche, une batterie vide, et le son du dégagement
/// annoncerait une route sûre que personne n'a regardée. Dans le doute, silence.
class RadarAlertVoice {
  RadarSeverity _previous = RadarSeverity.absent;

  RadarCue? read(RadarSeverity severity) {
    final previous = _previous;
    _previous = severity;
    if (severity == previous) return null;

    return switch (severity) {
      // Une voiture peut apparaître déjà proche : c'est le son urgent qu'il
      // faut, pas les deux à la suite.
      RadarSeverity.close => RadarCue.close,
      RadarSeverity.approaching =>
        previous == RadarSeverity.close ? null : RadarCue.approach,
      RadarSeverity.clear =>
        previous == RadarSeverity.absent ? null : RadarCue.clear,
      RadarSeverity.absent => null,
    };
  }

  void reset() => _previous = RadarSeverity.absent;
}

/// Joue les tonalités du radar.
///
/// Un lecteur par son, chargé d'avance : au moment où une voiture arrive, il
/// n'est plus temps d'ouvrir un fichier. Les sons sont courts (moins de 250 ms)
/// et générés par `tool/radar_tones.dart`.
///
/// Sur Android, ils sont déclarés en **guidage de navigation** : c'est ce qui
/// les fait sortir au volume multimédia — le seul qu'un cycliste monte — et
/// baisser la musique le temps du bip au lieu de la couper. Un GPS de voiture ne
/// fait rien d'autre.
///
/// Toute panne audio est avalée : le radar reste visible à l'écran, et une
/// sortie ne s'arrête pas parce qu'un bip n'est pas sorti.
class RadarAlertPlayer {
  final _players = <RadarCue, AudioPlayer>{};

  static final _context = AudioContext(
    android: const AudioContextAndroid(
      contentType: AndroidContentType.sonification,
      usageType: AndroidUsageType.assistanceNavigationGuidance,
      audioFocus: AndroidAudioFocus.gainTransientMayDuck,
    ),
  );

  /// Charge les trois sons. À appeler au montage de la coquille : c'est la
  /// seule seconde de la sortie où l'on a le temps.
  Future<void> warmUp() async {
    try {
      await AudioPlayer.global.setAudioContext(_context);
      for (final cue in RadarCue.values) {
        final player = AudioPlayer()..setReleaseMode(ReleaseMode.stop);
        await player.setSource(AssetSource(cue.asset));
        _players[cue] = player;
      }
    } catch (e) {
      debugPrint('[radar] sons indisponibles : $e');
    }
  }

  void play(RadarCue cue) {
    final player = _players[cue];
    if (player == null) return;
    // Depuis le début, sans attendre : un son déjà en cours est un son qui date
    // d'avant, et c'est celui de maintenant qui compte.
    player.seek(Duration.zero).then((_) => player.resume()).catchError((
      Object e,
    ) {
      debugPrint('[radar] bip perdu : $e');
    });
  }

  Future<void> dispose() async {
    for (final player in _players.values) {
      await player.dispose();
    }
    _players.clear();
  }
}
