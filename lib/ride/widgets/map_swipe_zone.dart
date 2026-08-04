import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// La dérive du doigt qu'un appui tolère avant de n'être plus qu'un glissé.
///
/// Reprise du site (`HOLD_MOVE_TOL_PX`, `useSleepHold.ts` du dépôt Rails), et
/// pour sa raison : on tient 700 ms sur un vélo qui roule, la main n'est pas
/// immobile. Ne sert plus qu'ici — la veille par appui long de l'appli
/// elle-même a été retirée, seule celle de la carte (le site) subsiste — mais
/// [OneFingerHorizontalDragRecognizer] doit encore rendre à la page web
/// exactement les appuis qu'elle saura reconnaître.
const sleepHoldDrift = 16.0;

/// Le glissé horizontal **en plein milieu de la carte**, qui change de page.
///
/// Longtemps impossible : MapLibre déplaçait sa carte au doigt, et le même geste
/// ne pouvait pas vouloir dire deux choses — d'où les bandes des deux bords
/// (`MapEdgeHandle`), seul endroit où l'on ne déplaçait pas la carte. Le site
/// demande maintenant **deux doigts** pour la déplacer, ce qui libère le glissé
/// d'un doigt : c'est ce widget qui le récupère.
///
/// **La règle est donc le nombre de doigts, jamais l'endroit** : un doigt change
/// de page, deux appartiennent à la carte. Tout le reste — l'appui qui réveille
/// l'écran, le pincement, le doigt vertical — traverse jusqu'au WebView, d'où
/// [HitTestBehavior.translucent] et l'absence de `onTap`.
///
/// « Traverse », à condition de **se retirer à temps** : une vue de plateforme
/// met les événements en cache tant qu'un recognizer n'a pas tranché, et ne les
/// lui remet qu'en gagnant son arène. Un tap s'en accommode (l'arène se résout
/// au lever du doigt), un appui immobile jamais — la page ne recevait son
/// `pointerdown` qu'au relâchement, et l'appui long qui met le site en veille ne
/// démarrait donc **jamais** dans l'appli. D'où les deux abandons de
/// [OneFingerHorizontalDragRecognizer], qui rendent le doigt dès qu'il est clair
/// qu'il ne fait pas ce qu'on attendait.
///
/// Le glissé n'est pas *interprété* puis converti en changement de page : il est
/// **transmis tel quel au défilement** ([ScrollPosition.drag], la primitive dont
/// se sert `Scrollable` lui-même). La page suit donc le doigt, se recale au
/// relâchement et se lance à la même vitesse que sur les pages de données. Une
/// première version décidait au relâchement, à partir d'un seuil en pixels : il
/// fallait parcourir la marge de reconnaissance *puis* le seuil sans rien voir
/// bouger, et sur la route ça se lisait comme un écran qui ne répond pas.
///
/// Reste **monté en permanence**, actif ou non ([enabled]) : disparaître à
/// mi-glissé emporterait le recognizer et donc le geste en cours, au moment
/// précis où la page d'à côté arrive.
class MapSwipeZone extends StatefulWidget {
  const MapSwipeZone({
    super.key,
    required this.pages,
    required this.enabled,
  });

  /// Le défilement à mener. Le même contrôleur que la coquille : c'est lui qui
  /// porte l'index brut et la boucle du catalogue.
  final PageController pages;

  /// Faux dès qu'on n'est plus sur la carte — les pages de données prennent
  /// alors leurs glissés elles-mêmes. Ne coupe que le *démarrage* d'un geste :
  /// celui qui est en cours va jusqu'au bout, ses événements ne passant plus par
  /// le test de touche.
  final bool enabled;

  @override
  State<MapSwipeZone> createState() => _MapSwipeZoneState();
}

class _MapSwipeZoneState extends State<MapSwipeZone> {
  /// Les doigts posés sur la carte, arène ou pas. Tenu par un [Listener] et non
  /// par le recognizer : un recognizer ne voit que les pointeurs qu'il suit, et
  /// c'est précisément celui qu'il refuse de suivre qu'il faut compter.
  final _down = <int>{};

  /// Ce geste-ci a-t-il compté un second doigt, ne serait-ce qu'un instant ?
  ///
  /// Double fond du retrait de l'arène, qui peut arriver trop tard : si le
  /// glissé avait déjà gagné quand le second doigt s'est posé, il n'y a plus
  /// moyen de rendre le premier — mais il reste possible de ne pas changer de
  /// page, et c'est bien le pire des deux. **Remis à zéro au premier doigt
  /// posé**, jamais au dernier levé : le glissé se conclut après le lever, et un
  /// drapeau effacé entre-temps ne servirait à rien.
  bool _multi = false;

  /// Le glissé en cours, tel que le voit le défilement.
  Drag? _drag;

  /// La page d'où le geste est parti, pour y revenir si un second doigt arrive.
  int _startPage = 0;

  void _onDown(PointerDownEvent event) {
    if (_down.isEmpty) _multi = false;
    _down.add(event.pointer);
    if (_down.length <= 1) return;

    _multi = true;
    // Le glissé avait déjà commencé : on le rend, et la page repart d'où elle
    // venait. La rendre « à la plus proche » suffirait presque, mais un doigt
    // parti vite peut avoir passé la moitié — et ce doigt-là ne demandait plus
    // la page suivante, il demandait la carte.
    if (_drag != null) {
      _drag!.cancel();
      _drag = null;
      if (widget.pages.hasClients) {
        widget.pages.animateToPage(
          _startPage,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    }
  }

  void _onStart(DragStartDetails details) {
    if (_multi || !widget.pages.hasClients) return;
    _startPage = widget.pages.page?.round() ?? 0;
    _drag = widget.pages.position.drag(details, () => _drag = null);
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !widget.enabled,
      child: RawGestureDetector(
        behavior: HitTestBehavior.translucent,
        gestures: {
          OneFingerHorizontalDragRecognizer:
              GestureRecognizerFactoryWithHandlers<
                  OneFingerHorizontalDragRecognizer>(
            () => OneFingerHorizontalDragRecognizer(
              alone: () => _down.length <= 1,
              debugOwner: this,
            ),
            (recognizer) => recognizer
              ..onStart = _onStart
              ..onUpdate = ((details) => _drag?.update(details))
              ..onEnd = ((details) => _drag?.end(details))
              ..onCancel = (() {
                _drag?.cancel();
                _drag = null;
              }),
          ),
        },
        // Enfant du détecteur, donc **plus profond** : la pile du test de touche
        // se parcourt du plus profond au plus haut, si bien que le compte est
        // déjà à jour quand le recognizer décide du même événement.
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _onDown,
          onPointerUp: (event) => _down.remove(event.pointer),
          onPointerCancel: (event) => _down.remove(event.pointer),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

/// Un glissé horizontal qui n'accepte **qu'un seul doigt à la fois**.
///
/// Sans ça, un `HorizontalDragGestureRecognizer` ordinaire prend tous les
/// pointeurs qui passent : dès que la main part de côté, il gagne les deux
/// arènes et le WebView ne reçoit plus rien — c'est-à-dire que le déplacement à
/// deux doigts, et le pincement avec lui, cesserait de fonctionner.
///
/// Le retrait doit avoir lieu **avant la victoire** : une vue de plateforme ne
/// reçoit ses événements qu'après avoir gagné l'arène, et ce qu'on lui a pris
/// ne se rend pas. En pratique les deux doigts se posent à quelques dizaines de
/// millisecondes l'un de l'autre, bien avant que le premier n'ait parcouru les
/// pixels qui feraient gagner le glissé.
///
/// Il rend aussi le doigt de lui-même dans deux cas où il est déjà sûr de
/// perdre, et c'est ce qui rend la page web utilisable :
///
/// - **le doigt qui ne bouge pas** ([_stillness]) est un appui, donc peut-être
///   la mise en veille du site (700 ms d'immobilité). Attendre le relâchement
///   pour se retirer revenait à ne la lui livrer qu'une fois finie.
/// - **le doigt franchement vertical** appartient à la page (son tiroir de
///   commandes s'ouvre d'un glissé vers le haut). Un glissé horizontal, lui,
///   n'a rien à craindre d'un peu de biais : il faut deux fois plus de vertical
///   que d'horizontal pour abandonner.
///
/// Le compteur d'immobilité **se réarme à chaque mouvement** plutôt que de
/// s'annuler : un glissé qui démarre lentement — la main gantée, le vélo qui
/// tape — garderait sinon sa chance perdue d'avance, et le changement de page
/// se serait mis à rater sur les gestes les plus mous. Et passé la dérive
/// qu'un appui tolère ([sleepHoldDrift]), plus rien n'est rendu : le site ne
/// s'endormirait pas non plus.
class OneFingerHorizontalDragRecognizer extends HorizontalDragGestureRecognizer {
  OneFingerHorizontalDragRecognizer({required this.alone, super.debugOwner});

  /// Combien de temps sans bouger avant de rendre le doigt à la page web.
  ///
  /// Court, parce qu'il retarde d'autant l'appui long du site : le cycliste
  /// tient alors 700 ms + ceci. Mais pas nul — c'est le temps qu'un vrai glissé
  /// met à démarrer.
  static const _stillness = Duration(milliseconds: 150);

  /// Ce qui compte comme « le doigt a bougé ». Sous ce seuil, c'est le tremblé
  /// d'une main posée, pas un geste.
  static const _wiggle = 4.0;

  /// Ce pointeur qui se pose est-il le seul sur la carte ?
  final bool Function() alone;

  Timer? _still;
  Offset _origin = Offset.zero;

  /// Le dernier endroit d'où l'on a réarmé le compteur.
  Offset _last = Offset.zero;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (!alone()) {
      // Deux doigts : tout est à la carte, y compris le premier, qu'on rend en
      // se retirant de son arène.
      resolve(GestureDisposition.rejected);
      return;
    }
    super.addAllowedPointer(event);
    _origin = event.position;
    _last = event.position;
    _armStillness();
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) {
      final drift = event.position - _origin;
      if (drift.dy.abs() > kTouchSlop && drift.dy.abs() > 2 * drift.dx.abs()) {
        // Verticalement franc : c'est un geste de la page, rendu tout de suite.
        _stopStillness();
        resolve(GestureDisposition.rejected);
        return;
      }
      if ((event.position - _last).distance > _wiggle) {
        _last = event.position;
        _armStillness();
      }
    }
    super.handleEvent(event);
  }

  void _armStillness() {
    _still?.cancel();
    _still = Timer(_stillness, _yieldToPage);
  }

  void _stopStillness() {
    _still?.cancel();
    _still = null;
  }

  /// Le doigt est resté en place : à la page web d'en faire ce qu'elle veut.
  void _yieldToPage() {
    _still = null;
    if ((_last - _origin).distance > sleepHoldDrift) return;
    resolve(GestureDisposition.rejected);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _stopStillness();
    super.didStopTrackingLastPointer(pointer);
  }

  @override
  void dispose() {
    _stopStillness();
    super.dispose();
  }
}
