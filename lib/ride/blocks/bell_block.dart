import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';

import '../../dashboard/dashboard_block.dart';
import 'action_button.dart';

/// Fait sonner fort le téléphone — pour le retrouver dans un sac ou une
/// poche, ou attirer l'attention de quelqu'un qui roule devant.
///
/// Autonome comme [MarkLapControl] (`mark_lap_block.dart`) : rien à faire
/// remonter jusqu'à `RideShellPage`, un tap suffit à démarrer et à arrêter —
/// contrairement à [SleepControl], qui doit traverser la coquille pour
/// ramener le cycliste sur la carte.
///
/// Son et vibration au flux d'alarme (`AndroidUsageType.alarm`, focus
/// exclusif) plutôt qu'au volume média : c'est le seul flux qui traverse le
/// mode silencieux/Ne pas déranger comme le ferait un réveil, or un
/// téléphone qu'on cherche est justement celui qu'on a mis en silencieux
/// avant de rouler.
///
/// Boucle jusqu'au prochain tap, avec un arrêt de sécurité à 3 secondes — le
/// temps de repérer le bruit sans laisser sonner un téléphone qu'on ne
/// retrouve pas tout de suite.
class BellControl extends StatefulWidget {
  const BellControl({
    super.key,
    this.mode = BellMode.full,
    this.sound = BellSound.bell,
    this.color,
    this.textColor,
  });

  final BellMode mode;
  final BellSound sound;
  final Color? color;
  final Color? textColor;

  @override
  State<BellControl> createState() => _BellControlState();
}

class _BellControlState extends State<BellControl> {
  static final _alarmContext = AudioContext(
    android: const AudioContextAndroid(
      contentType: AndroidContentType.sonification,
      usageType: AndroidUsageType.alarm,
      audioFocus: AndroidAudioFocus.gain,
    ),
  );

  static const _failsafe = Duration(seconds: 3);
  static const _vibrationPattern = [0, 400, 150, 400, 150, 400, 150, 400];
  static const _vibrationIntensities = [0, 255, 0, 255, 0, 255, 0, 255];

  AudioPlayer? _player;
  Timer? _failsafeTimer;
  bool _ringing = false;

  @override
  void dispose() {
    unawaited(_stop());
    super.dispose();
  }

  Future<void> _toggle() => _ringing ? _stop() : _start();

  Future<void> _start() async {
    setState(() => _ringing = true);

    unawaited(
      Vibration.vibrate(
        pattern: _vibrationPattern,
        intensities: _vibrationIntensities,
        repeat: 0,
      ).catchError((Object e) => debugPrint('[sonnette] vibration impossible : $e')),
    );

    try {
      await AudioPlayer.global.setAudioContext(_alarmContext);
      final player = AudioPlayer()..setReleaseMode(ReleaseMode.loop);
      await player.play(AssetSource('sounds/${widget.sound.key}.wav'));
      _player = player;
    } catch (e) {
      debugPrint('[sonnette] son indisponible : $e');
    }

    _failsafeTimer = Timer(_failsafe, _stop);
  }

  Future<void> _stop() async {
    _failsafeTimer?.cancel();
    _failsafeTimer = null;
    unawaited(Vibration.cancel());

    final player = _player;
    _player = null;
    await player?.stop();
    await player?.dispose();

    if (mounted) setState(() => _ringing = false);
  }

  @override
  Widget build(BuildContext context) => DashboardActionButton(
        icon: _ringing ? Icons.notifications_active : Icons.notifications,
        label: 'Faire sonner',
        compact: widget.mode == BellMode.compact,
        onPressed: _toggle,
        color: widget.color,
        textColor: widget.textColor,
      );
}
