import 'dart:async';

import 'package:flutter/material.dart';

import '../navigation/screen_dimmer.dart';
import 'sleep_hold.dart';

/// Le voile noir de la veille, et le tap qui la lève.
///
/// **Opaque, et c'est le point** : il ne recouvre pas seulement l'écran, il en
/// prend tous les gestes. Un écran endormi qu'on effleure au fond d'une poche
/// ne doit ni changer de page, ni lancer une calibration, ni quitter la sortie.
///
/// Endormir demande un appui long, réveiller ne demande qu'un tap : l'asymétrie
/// est voulue et vient du site (`useSleepHold`). Sortir de veille doit rester le
/// geste le plus facile de l'écran, y compris pour une main gantée.
class SleepVeil extends StatelessWidget {
  const SleepVeil({super.key, required this.onWake});

  final VoidCallback onWake;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onWake,
      child: const ColoredBox(
        color: Colors.black,
        child: Center(
          // À peine lisible, et volontairement : à 1 % de rétroéclairage on ne
          // le voit pas, mais la luminosité met une fraction de seconde à
          // descendre — c'est là que la phrase se lit, et c'est là qu'on se
          // demande si l'appli vient de mourir.
          child: Text(
            'Toucher pour réveiller',
            style: TextStyle(color: Color(0x26FFFFFF), fontSize: 15),
          ),
        ),
      ),
    );
  }
}

/// La veille d'un écran ordinaire : l'appui long l'endort, un tap la lève.
///
/// Tous les écrans l'ont **sauf l'accueil** : c'est celui qu'on ouvre les mains
/// libres, avant de partir, et le seul où un écran qui noircit tout seul se
/// lirait comme une panne. Partout ailleurs — capteurs, compte, sorties — le
/// téléphone peut déjà être sur son support.
///
/// La coquille de sortie, elle, ne se sert pas de cette classe : elle a un
/// arbitre à tenir (le radar interrompt la veille, la page web la demande de son
/// côté) et compose les deux morceaux — [SleepHoldZone] et [SleepVeil] —
/// elle-même.
class ScreenSleep extends StatefulWidget {
  const ScreenSleep({super.key, required this.child, this.screen});

  final Widget child;

  /// Le rétroéclairage, injectable pour les tests. Un par écran et non un
  /// partagé : la veille ne survit pas au démontage de l'écran qui l'a demandée.
  final ScreenDimmer? screen;

  @override
  State<ScreenSleep> createState() => _ScreenSleepState();
}

class _ScreenSleepState extends State<ScreenSleep> {
  late final ScreenDimmer _screen = widget.screen ?? ScreenDimmer();

  bool _asleep = false;

  void _sleep() {
    setState(() => _asleep = true);
    unawaited(_screen.dim());
  }

  void _wake() {
    setState(() => _asleep = false);
    unawaited(_screen.restore());
  }

  @override
  void dispose() {
    // Filet de sécurité : un écran quitté en veille — retour système, page qui
    // se referme d'elle-même — ne doit pas laisser l'appareil à 1 %.
    if (_asleep) unawaited(_screen.restore());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Pas de `PopScope` pour faire du retour système un réveil : l'écran Compte
    // en pose déjà un (défaire une étape de Keycloak), les deux se déclencheraient
    // ensemble, et on se réveillerait sur une page qui a reculé toute seule. Le
    // retour quitte donc l'écran, ce que `dispose` rattrape en rendant la
    // luminosité. La coquille de sortie, elle, tient son bouton retour elle-même
    // et y réveille avant tout le reste.
    return Stack(
      children: [
        SleepHoldZone(
          // On n'endort pas ce qui dort déjà ; le voile prend d'ailleurs tout
          // ce qui passe.
          enabled: !_asleep,
          onSleep: _sleep,
          child: widget.child,
        ),
        if (_asleep) Positioned.fill(child: SleepVeil(onWake: _wake)),
      ],
    );
  }
}
