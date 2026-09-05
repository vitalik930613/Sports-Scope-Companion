import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'battery_status.dart';

/// Décide quand une batterie faible doit se signaler — et se réarmer.
///
/// Uniquement sur le **franchissement à la baisse**, par appareil : un
/// capteur qui reste sous le seuil d'un tic à l'autre ne redit rien, sous
/// peine du même son qu'on entend trop et qu'on finit par ne plus entendre.
/// Réarmé par la recharge (repasse au-dessus du seuil) ou par une
/// déconnexion — un appareil qui disparaît n'est plus « sous le seuil », il
/// est juste absent, et une reconnexion sous le seuil doit donc ré-alerter.
///
/// Rend la liste des appareils qui viennent de franchir le seuil **ce
/// tic-ci**, pas un booléen : c'est elle qui nomme l’alerte plein écran
/// (`BatteryAlertPage`), le son ne jouant qu'une fois même si plusieurs
/// franchissent le seuil au même instant.
class BatteryAlertVoice {
  final _low = <String, bool>{};

  List<BatteryStatus> read(List<BatteryStatus> statuses) {
    final lowered = <BatteryStatus>[];
    final seen = <String>{};

    for (final status in statuses) {
      seen.add(status.id);
      if (!status.connected) {
        _low[status.id] = false;
        continue;
      }
      final wasLow = _low[status.id] ?? false;
      if (status.low && !wasLow) lowered.add(status);
      _low[status.id] = status.low;
    }

    // Un appareil que le magasin ne connaît plus (oublié depuis la sous-page
    // Capteurs) ne doit pas garder un drapeau qui ne correspond plus à rien.
    _low.removeWhere((id, _) => !seen.contains(id));

    return lowered;
  }

  void reset() => _low.clear();
}

/// Joue la tonalité de batterie faible.
///
/// Un seul son, chargé d'avance — même patron que `RadarAlertPlayer` : au
/// moment où une batterie franchit le seuil, il n'est plus temps d'ouvrir un
/// fichier. Même contexte audio Android (guidage de navigation, volume
/// multimédia, baisse la musique le temps du bip). Toute panne est avalée :
/// une sortie ne s'arrête pas parce qu'un bip n'est pas sorti.
class BatteryAlertPlayer {
  AudioPlayer? _player;

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
      final player = AudioPlayer()..setReleaseMode(ReleaseMode.stop);
      await player.setSource(AssetSource('sounds/battery_low.wav'));
      _player = player;
    } catch (e) {
      debugPrint('[batterie] son indisponible : $e');
    }
  }

  void play() {
    final player = _player;
    if (player == null) return;
    player.seek(Duration.zero).then((_) => player.resume()).catchError((
      Object e,
    ) {
      debugPrint('[batterie] bip perdu : $e');
    });
  }

  Future<void> dispose() async {
    await _player?.dispose();
    _player = null;
  }
}
