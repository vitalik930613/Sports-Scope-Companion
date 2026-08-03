import 'dart:async';

import 'package:flutter/material.dart';

/// Le numéro de la page qu'on vient d'atteindre, montré une seconde puis effacé.
///
/// Il remplace les pastilles qui vivaient à l'extrémité du bandeau. Celles-ci
/// disaient la même chose en permanence, mais **en permanence est précisément le
/// problème** : à huit points de côté dans un bandeau de soixante-douze de haut,
/// elles n'étaient lisibles qu'à l'arrêt — donc au seul moment où l'on sait déjà
/// sur quelle page on est — et une colonne d'une pastille par page débordait du
/// bandeau dès qu'un profil en comptait quatre.
///
/// Un repère transitoire répond à la question au moment où elle se pose, c'est-à
/// -dire juste après le glissé, et rend ses pixels au reste du temps. Il est
/// aussi assez gros pour se lire en roulant, ce qu'une pastille ne pouvait pas
/// se permettre d'être.
///
/// **Il ne paraît jamais au montage** : la première page n'est pas un changement
/// de page, et un chiffre qui s'affiche tout seul au départ d'une sortie se lit
/// comme une notification qu'on n'a pas demandée.
class RidePageFlash extends StatefulWidget {
  const RidePageFlash({super.key, required this.page, required this.count});

  /// La page affichée, index dans le défilement. C'est son **changement** qui
  /// déclenche l'affichage — le widget n'a pas besoin de savoir d'où vient le
  /// mouvement (un doigt, le bouton retour, le retour automatique) : dans les
  /// trois cas la page a changé sous les yeux, et dans les trois cas dire
  /// laquelle est utile.
  final int page;

  /// Le nombre de pages du défilement. Les pages rangées derrière le menu n'en
  /// sont pas : on ne les atteint pas en glissant, les compter ici ferait
  /// annoncer « 2 / 5 » à qui n'a que trois pages sous le doigt.
  final int count;

  /// Le temps pendant lequel le numéro reste plein, fondu de sortie en plus.
  /// Une seconde : le temps de lire deux caractères sans que le chiffre ne
  /// s'installe sur la carte.
  static const hold = Duration(seconds: 1);

  /// Le fondu de sortie. Court, mais pas nul : une disparition sèche attire
  /// l'œil autant que l'apparition, et c'est l'apparition qu'on veut voir.
  static const fade = Duration(milliseconds: 220);

  @override
  State<RidePageFlash> createState() => _RidePageFlashState();
}

class _RidePageFlashState extends State<RidePageFlash> {
  bool _visible = false;
  Timer? _hide;

  @override
  void didUpdateWidget(RidePageFlash oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Le seul déclencheur. La coquille se reconstruit pour bien d'autres raisons
    // — le radar, le rétroéclairage, une mesure qui arrive — et un repère qui
    // reparaîtrait à chacune clignoterait sur la carte toute la sortie.
    if (oldWidget.page != widget.page) _show();
  }

  void _show() {
    _hide?.cancel();
    setState(() => _visible = true);
    // Le compte repart de zéro à chaque page : deux glissés rapides doivent
    // laisser le second chiffre une seconde, pas le reliquat du premier.
    _hide = Timer(RidePageFlash.hold, () {
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
    // Rien à montrer avec une page unique : elle ne peut pas changer, et le
    // widget ne s'allumerait jamais de toute façon. C'est surtout la garantie
    // qu'un profil d'une page ne réserve rien à l'écran.
    if (widget.count <= 1) return const SizedBox.shrink();

    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: RidePageFlash.fade,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            // Le même fond que les cartes des pages de données, un peu plus
            // opaque : il se pose aussi sur la carte, où le texte seul se
            // perdrait dans les tuiles claires.
            color: const Color(0xFF101214).withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white24),
          ),
          child: Text(
            '${widget.page + 1} / ${widget.count}',
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
}
