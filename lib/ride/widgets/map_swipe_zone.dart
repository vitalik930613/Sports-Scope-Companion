import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

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
class OneFingerHorizontalDragRecognizer extends HorizontalDragGestureRecognizer {
  OneFingerHorizontalDragRecognizer({required this.alone, super.debugOwner});

  /// Ce pointeur qui se pose est-il le seul sur la carte ?
  final bool Function() alone;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (!alone()) {
      // Deux doigts : tout est à la carte, y compris le premier, qu'on rend en
      // se retirant de son arène.
      resolve(GestureDisposition.rejected);
      return;
    }
    super.addAllowedPointer(event);
  }
}
