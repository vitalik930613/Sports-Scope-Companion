import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../../dashboard/dashboard_block.dart';

/// Fait sonner fort le téléphone — pour le retrouver dans un sac ou une
/// poche, ou attirer l'attention de quelqu'un qui roule devant.
///
/// Extrait de [BellControl] (`bell_block.dart`) pour avoir un déclenchement
/// programmatique, sans widget monté — un geste Di2 configuré en
/// « sonnette »/« klaxon » n'a pas de bouton à lui, seulement une pression à
/// traduire. [BellControl] délègue à une instance qu'il possède ; un
/// répartiteur de gestes en garde une deuxième, indépendante.
///
/// `ChangeNotifier` : le seul consommateur qui a besoin de savoir que l'état
/// change est un widget qui dessine une icône, les autres l'ignorent
/// simplement — même convention que le reste de l'appli (`ChangeNotifier`/
/// `ValueNotifier`, rien d'autre).
///
/// Joue le son une fois, jusqu'au bout — pas de boucle : sonnette, klaxon et
/// booster sont des signaux, pas une alarme à faire cesser. Le minuteur de
/// secours à 7 s (largement plus long que le plus long des trois —
/// `booster.wav`, ~6,3 s ; `bell.wav`/`horn.wav` tiennent tous les deux sous
/// 2 s) ne sert qu'à couvrir un `onPlayerComplete` qui n'arriverait pas :
/// trop court, il coupe le son avant sa fin dans le cas courant, pas
/// seulement dans le cas raté qu'il est censé couvrir. Son au flux d'alarme
/// (`AndroidUsageType.alarm`, focus exclusif) plutôt qu'au volume média :
/// c'est le seul flux qui traverse le mode silencieux/Ne pas déranger, or un
/// téléphone qu'on cherche est justement celui qu'on a mis en silencieux
/// avant de rouler.
class BellPlayer extends ChangeNotifier {
  static final _alarmContext = AudioContext(
    android: const AudioContextAndroid(
      contentType: AndroidContentType.sonification,
      usageType: AndroidUsageType.alarm,
      audioFocus: AndroidAudioFocus.gain,
    ),
  );

  static const _failsafe = Duration(seconds: 7);

  AudioPlayer? _player;
  Timer? _failsafeTimer;
  bool _ringing = false;
  bool _disposed = false;

  bool get ringing => _ringing;

  Future<void> toggle(BellSound sound) => _ringing ? stop() : start(sound);

  Future<void> start(BellSound sound) async {
    _ringing = true;
    _notify();

    try {
      final player = AudioPlayer()..setReleaseMode(ReleaseMode.release);
      player.onPlayerComplete.first.then((_) => stop());
      // `ctx` directement sur `play()` plutôt que `AudioPlayer.global.
      // setAudioContext` : ce dernier changerait le flux par défaut de
      // *tous* les lecteurs de l'appli (radar, virages), pas seulement de
      // celui-ci.
      await player.play(
        AssetSource('sounds/${sound.key}.wav'),
        ctx: _alarmContext,
      );
      _player = player;
    } catch (e) {
      debugPrint('[sonnette] son indisponible : $e');
    }

    _failsafeTimer = Timer(_failsafe, stop);
  }

  Future<void> stop() async {
    _failsafeTimer?.cancel();
    _failsafeTimer = null;

    final player = _player;
    _player = null;
    await player?.stop();
    await player?.dispose();

    _ringing = false;
    _notify();
  }

  // Un timer de sécurité en vol peut encore résoudre `stop()` après que le
  // widget qui possède ce lecteur a disparu (`dispose()` ne peut pas
  // attendre l'arrêt du son) : `notifyListeners()` lèverait alors sur un
  // `ChangeNotifier` déjà disposé.
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(stop());
    super.dispose();
  }
}
