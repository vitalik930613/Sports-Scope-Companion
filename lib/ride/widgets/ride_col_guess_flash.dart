import 'dart:async';

import 'package:flutter/material.dart';

import '../nav_state.dart';

/// Annonce transitoire d'un col deviné en navigation libre (voir `NavColGuess` et
/// `updateFreeClimbGuess` côté site) : une hypothèse à faible confiance, jamais une
/// certitude — d'où une bannière qui s'efface d'elle-même plutôt qu'une carte
/// persistante comme celle d'un col réel sur itinéraire.
///
/// Même patron visuel et temporel que [RidePageFlash] (pilule, fondu de sortie),
/// mais un texte libre plutôt qu'un numéro de page : les deux widgets répondent à
/// des questions différentes et ne partagent pas de logique au-delà du style.
class RideColGuessFlash extends StatefulWidget {
  const RideColGuessFlash({super.key, required this.guess});

  final NavColGuess? guess;

  static const hold = Duration(seconds: 4);
  static const fade = Duration(milliseconds: 220);

  @override
  State<RideColGuessFlash> createState() => _RideColGuessFlashState();
}

class _RideColGuessFlashState extends State<RideColGuessFlash> {
  bool _visible = false;
  String? _shownName;
  Timer? _hide;

  @override
  void didUpdateWidget(RideColGuessFlash oldWidget) {
    super.didUpdateWidget(oldWidget);
    final name = widget.guess?.name;
    // Ne réagit qu'à un NOUVEAU nom : un flicker null/non-null sur le même col (la
    // pente qui oscille autour du seuil) ne doit pas redéclencher la bannière en
    // boucle, seulement l'apparition d'un col différent (ou du premier).
    if (name != null && name != _shownName) _show(name);
  }

  void _show(String name) {
    _hide?.cancel();
    _shownName = name;
    setState(() => _visible = true);
    _hide = Timer(RideColGuessFlash.hold, () {
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
    final guess = widget.guess;
    if (guess == null) return const SizedBox.shrink();

    final km = (guess.distanceM / 1000).toStringAsFixed(1);
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: RideColGuessFlash.fade,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF101214).withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white24),
          ),
          child: Text(
            'Vous montez peut-être vers ${guess.name} ($km km)',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w500,
              height: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}
