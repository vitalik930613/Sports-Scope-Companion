import 'dart:async';

import 'package:flutter/material.dart';

import '../../ble/samples.dart';
import '../di2_button_gesture_policy.dart';

/// Le geste de bouton distant qu'on vient de faire (canal, clic/double-clic/
/// appui long), montré une seconde puis effacé — même patron que
/// [RidePageFlash] (`ride_page_flash.dart`), pour la même raison : une
/// confirmation qui ne se pose qu'au moment où on la cherche, en testant les
/// boutons, pas une pastille permanente sur l'écran de la sortie.
class RideButtonFlash extends StatefulWidget {
  const RideButtonFlash({super.key, this.event});

  /// `null` tant qu'aucun geste n'a encore été résolu — le widget ne s'allume
  /// jamais au montage. [_ButtonGestureFlash.seq] distingue deux gestes
  /// identiques d'affilée (deux clics simples du même canal, par exemple) :
  /// sans lui la valeur ne changerait pas d'une pression à l'autre, et
  /// [didUpdateWidget] ne redéclencherait rien.
  final ButtonGestureFlash? event;

  static const hold = Duration(seconds: 1);
  static const fade = Duration(milliseconds: 220);

  @override
  State<RideButtonFlash> createState() => _RideButtonFlashState();
}

class _RideButtonFlashState extends State<RideButtonFlash> {
  bool _visible = false;
  Timer? _hide;

  @override
  void didUpdateWidget(RideButtonFlash oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.event != null && widget.event?.seq != oldWidget.event?.seq) {
      _show();
    }
  }

  void _show() {
    _hide?.cancel();
    setState(() => _visible = true);
    _hide = Timer(RideButtonFlash.hold, () {
      if (mounted) setState(() => _visible = false);
    });
  }

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    // Rien à montrer avant le premier geste — même garde que [RidePageFlash]
    // pour un profil d'une page : le widget ne réserve rien à l'écran tant
    // que personne n'a touché un bouton.
    if (event == null) return const SizedBox.shrink();

    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: RideButtonFlash.fade,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF101214).withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white24),
          ),
          child: Text(
            '${_channelLabel(event.channel)} · ${_gestureLabel(event.gesture)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w500,
              height: 1.1,
            ),
          ),
        ),
      ),
    );
  }

  static String _channelLabel(Di2ButtonChannel channel) => switch (channel) {
        Di2ButtonChannel.one => 'Canal 1',
        Di2ButtonChannel.two => 'Canal 2',
        Di2ButtonChannel.three => 'Canal 3',
        Di2ButtonChannel.four => 'Canal 4',
      };

  static String _gestureLabel(Di2ButtonGesture gesture) => switch (gesture) {
        Di2ButtonGesture.click => 'Clic',
        Di2ButtonGesture.doubleClick => 'Double-clic',
        Di2ButtonGesture.longPress => 'Appui long',
      };
}

/// Un geste de bouton résolu, avec un numéro de séquence — voir la doc de
/// [RideButtonFlash.event].
@immutable
class ButtonGestureFlash {
  const ButtonGestureFlash(this.channel, this.gesture, this.seq);

  final Di2ButtonChannel channel;
  final Di2ButtonGesture gesture;
  final int seq;
}
