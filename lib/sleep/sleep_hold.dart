import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// La durée de l'appui qui endort l'écran, **et la même que celle du site**
/// (`SLEEP_HOLD_MS`, `app/javascript/composables/useSleepHold.ts` du dépôt
/// Rails).
///
/// Deux détecteurs pour un seul geste : le site tient la carte, l'appli tient
/// tout le reste (voir `RideShellPage`). Le cycliste, lui, n'en connaît qu'un —
/// deux durées différentes se sentiraient d'une page à l'autre comme un écran
/// qui répond mal.
const sleepHoldDuration = Duration(milliseconds: 700);

/// La dérive du doigt qu'un appui tolère avant de n'être plus qu'un glissé.
///
/// Reprise du site (`HOLD_MOVE_TOL_PX`), et pour sa raison : on tient 700 ms sur
/// un vélo qui roule, la main n'est pas immobile. Lue aussi par le glissé de la
/// carte (`MapSwipeZone`), qui doit rendre à la page web exactement les appuis
/// qu'elle saura reconnaître.
const sleepHoldDrift = 16.0;

/// L'appui long qui met l'écran en veille, avec l'anneau qui se remplit sous le
/// doigt.
///
/// **Le tap n'endort rien**, ni ici ni sur le site : en roulant on tape l'écran
/// pour tout et pour rien — fermer une bulle, viser un bouton qu'on rate, se
/// rattraper sur un cahot — et l'écran s'éteignait au moment précis où on le
/// regardait. Il faut à la veille un geste qu'on ne fait pas par accident.
///
/// L'anneau n'est pas une décoration : c'est ce qui rend le geste réversible.
/// Sans lui, un appui long est un trou noir — rien ne se passe, puis tout se
/// passe. Il dit « ça vient, lève le doigt si ce n'est pas ça que tu veux », et
/// c'est aussi ce qui apprend le geste.
///
/// La couche est **translucide** : elle ne prend que l'appui immobile et laisse
/// passer tout le reste — taps, défilement des pages, glissés du bandeau. Elle
/// gagne son arène à la seconde où l'appui aboutit, ce qui annule au passage le
/// tap qu'aurait vu le widget du dessous : sans ça, un appui sur les watts
/// endormirait l'écran **et** ouvrirait la calibration au relâchement.
class SleepHoldZone extends StatefulWidget {
  const SleepHoldZone({
    super.key,
    required this.onSleep,
    this.enabled = true,
    this.child,
  });

  /// L'appui a abouti. À l'appelant de décider ce que « veille » veut dire chez
  /// lui : la coquille de sortie a un arbitre (radar, demande de la page web),
  /// un écran ordinaire n'a que son voile.
  final VoidCallback onSleep;

  /// Faux là où le geste appartient à quelqu'un d'autre — sur la carte, c'est
  /// le site qui le détecte et qui s'endort lui-même.
  final bool enabled;

  /// Facultatif : la zone sert aussi bien de couche posée dans une pile que
  /// d'enveloppe autour d'un écran entier.
  final Widget? child;

  @override
  State<SleepHoldZone> createState() => _SleepHoldZoneState();
}

class _SleepHoldZoneState extends State<SleepHoldZone>
    with SingleTickerProviderStateMixin {
  /// Créé au montage et non à la première utilisation : un `late final` paresseux
  /// se serait construit **depuis `dispose`** le jour où la zone est démontée
  /// sans qu'aucun appui l'ait touchée, et un ticker qui cherche son `TickerMode`
  /// dans un arbre déjà désactivé est une erreur d'assertion.
  late final AnimationController _fill;

  /// Où le doigt s'est posé, dans les coordonnées de cette couche. `null` : pas
  /// d'appui en cours, donc pas d'anneau.
  Offset? _press;

  @override
  void initState() {
    super.initState();
    _fill = AnimationController(vsync: this, duration: sleepHoldDuration);
  }

  void _onDown(LongPressDownDetails details) {
    setState(() => _press = details.localPosition);
    _fill.forward(from: 0);
  }

  /// Le doigt s'est levé trop tôt, a bougé, ou un autre geste a gagné : rien ne
  /// s'est passé, l'anneau s'efface.
  void _onCancel() {
    _fill.stop();
    setState(() => _press = null);
  }

  void _onStart(LongPressStartDetails details) {
    _fill.stop();
    setState(() => _press = null);
    // Le doigt est encore posé au moment où l'écran noircit : sans retour
    // physique, on ne saurait pas si le geste a abouti ou si l'appli a rendu
    // l'âme. Le site vibre au même instant (`vibrateSleep`).
    //
    // L'échec est avalé : une plateforme sans vibreur n'est pas une raison de
    // rater la veille, qui est le geste, là où la vibration n'en est que
    // l'accusé de réception.
    unawaited(HapticFeedback.mediumImpact().catchError((Object _) {}));
    widget.onSleep();
  }

  @override
  void didUpdateWidget(SleepHoldZone oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Débranchée en plein appui (retour sur la carte, veille qui s'installe) :
    // le recognizer part avec ses gestionnaires et n'annulera plus rien, or un
    // anneau resté sous un doigt qui n'est plus là ne s'effacerait jamais.
    if (!widget.enabled && _press != null) _onCancel();
  }

  @override
  void dispose() {
    _fill.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: widget.enabled
          ? {
              LongPressGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                      LongPressGestureRecognizer>(
                // La tolérance de dérive avant acceptation est celle de Flutter
                // (`kTouchSlop`, 18 pt), à deux points de celle du site : c'est
                // la même main sur le même guidon, et l'écart ne se sent pas.
                () => LongPressGestureRecognizer(
                  duration: sleepHoldDuration,
                  debugOwner: this,
                ),
                (recognizer) => recognizer
                  ..onLongPressDown = _onDown
                  ..onLongPressCancel = _onCancel
                  ..onLongPressStart = _onStart,
              ),
            }
          : const {},
      child: Stack(
        children: [
          // Non positionné, donc c'est lui qui donne sa taille à la pile quand
          // la zone enveloppe un écran. Sans enfant, la couche prend la place
          // qu'on lui donne.
          if (widget.child case final child?) child,
          if (_press case final at?)
            Positioned(
              left: at.dx - _ringSize / 2,
              top: at.dy - _ringSize / 2,
              // L'anneau n'est qu'un témoin : il ne doit rien prendre au doigt
              // qui le fait apparaître.
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _fill,
                  builder: (context, _) => CustomPaint(
                    size: const Size.square(_ringSize),
                    painter: _SleepRingPainter(_fill.value),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

const _ringSize = 76.0;
const _ringStroke = 5.0;

/// L'anneau qui se remplit sous le doigt.
///
/// Doublé d'un liseré sombre : blanc sur blanc, il disparaîtrait sur une carte
/// enneigée ou sur une page claire, c'est-à-dire précisément là où le cycliste
/// se demande si son appui est pris.
class _SleepRingPainter extends CustomPainter {
  const _SleepRingPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - _ringStroke) / 2;
    final circle = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color(0x55000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = _ringStroke + 3,
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color(0x40FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = _ringStroke,
    );
    canvas.drawArc(
      circle,
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = _ringStroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_SleepRingPainter old) => old.progress != progress;
}
