import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../ble/sensor_hub.dart';
import '../../recording/ride_recorder.dart';
import '../../ui/formats.dart';
import '../nav_state.dart';
import '../ride_pages.dart';

/// Le bandeau du bas : les valeurs instantanées, et la façon de changer de page.
///
/// Présent sur toutes les pages, y compris la carte — c'est ce qui en fait le
/// bon hôte pour les gestes. La carte occupe tout le reste de l'écran et réclame
/// le glissé horizontal pour se déplacer ; le bandeau, lui, n'a rien en dessous,
/// donc un glissé dessus ne peut vouloir dire qu'une chose.
///
/// Il ne réutilise pas [MetricTile] : celui-ci empile icône, valeur et unité
/// pour l'écran de diagnostic et réclame une soixantaine de points de haut. Ici
/// chaque point pris est un point de carte perdu.
class RideBottomBand extends StatefulWidget {
  const RideBottomBand({
    super.key,
    required this.hub,
    required this.recorder,
    required this.nav,
    required this.pageIndex,
    required this.onGoToPage,
  });

  final SensorHub hub;
  final RideRecorder recorder;
  final ValueListenable<NavState?> nav;

  /// La page affichée, pour les pastilles.
  final int pageIndex;

  /// Demande de changement de page — la coquille possède le contrôleur.
  final void Function(int page) onGoToPage;

  /// Hauteur du contenu, hors zone système. Le bandeau s'étire ensuite de
  /// [MediaQueryData.viewPadding] vers le bas pour que ses valeurs ne passent
  /// pas sous la barre de navigation d'Android.
  static const contentHeight = 72.0;

  /// Ce que le bandeau occupe réellement, zone système comprise. La coquille
  /// s'en sert pour poser le haut de la carte.
  static double heightFor(BuildContext context) =>
      contentHeight + MediaQuery.viewPaddingOf(context).bottom;

  @override
  State<RideBottomBand> createState() => _RideBottomBandState();
}

class _RideBottomBandState extends State<RideBottomBand> {
  /// Déplacement cumulé du glissé en cours. Un geste lent et net doit compter
  /// autant qu'une chiquenaude : la vitesse au relâchement ne suffit pas.
  double _dragged = 0;

  void _onDragEnd(DragEndDetails details) {
    final next = pageAfterSwipe(
      current: widget.pageIndex,
      dx: _dragged,
      velocity: details.velocity.pixelsPerSecond.dx,
    );
    _dragged = 0;
    if (next != widget.pageIndex) widget.onGoToPage(next);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: (_) => _dragged = 0,
      onHorizontalDragUpdate: (d) => _dragged += d.delta.dx,
      onHorizontalDragEnd: _onDragEnd,
      child: Container(
        height: RideBottomBand.heightFor(context),
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewPaddingOf(context).bottom,
        ),
        decoration: const BoxDecoration(
          color: Color(0xFF101214),
          border: Border(top: BorderSide(color: Colors.white24)),
        ),
        child: Row(
          children: [
            Expanded(child: _duration()),
            Expanded(child: _distance()),
            Expanded(child: _speed()),
            Expanded(
              child: _sensor(widget.hub.latestHeartRate, 'bpm'),
            ),
            Expanded(child: _sensor(widget.hub.latestPower, 'W')),
            _PageDots(
              count: RidePage.count,
              current: widget.pageIndex,
              onTap: widget.onGoToPage,
            ),
          ],
        ),
      ),
    );
  }

  /// Durée et distance viennent de l'enregistreur, pas de la page : hors
  /// enregistrement elles n'existent pas, et un zéro ferait croire à un compteur
  /// remis à zéro plutôt qu'à une sortie non lancée.
  Widget _duration() => ListenableBuilder(
        listenable: widget.recorder,
        builder: (context, _) => _BandMetric(
          value: widget.recorder.isActive
              ? formatDuration(widget.recorder.recorded)
              : null,
          label: 'durée',
        ),
      );

  Widget _distance() => ListenableBuilder(
        listenable: widget.recorder,
        builder: (context, _) => _BandMetric(
          value: widget.recorder.isActive
              ? formatDistance(widget.recorder.distanceM)
              : null,
          label: 'distance',
        ),
      );

  /// La vitesse vient de la page : c'est elle qui tient le GPS de la navigation,
  /// et elle la publie déjà à chaque position.
  ///
  /// Un état périmé ne s'affiche pas — une vitesse figée à 34 km/h à l'arrêt
  /// serait pire que pas de vitesse du tout. Le bandeau se redessine à chaque
  /// message, donc le tiret apparaît dès la première seconde qui suit la reprise
  /// d'un autre rafraîchissement.
  Widget _speed() => ValueListenableBuilder<NavState?>(
        valueListenable: widget.nav,
        builder: (context, nav, _) => _BandMetric(
          value: nav == null || nav.isStale(DateTime.now())
              ? null
              : nav.speedKmh.toStringAsFixed(1).replaceAll('.', ','),
          label: 'km/h',
        ),
      );

  Widget _sensor(ValueListenable<int?> listenable, String label) =>
      ValueListenableBuilder<int?>(
        valueListenable: listenable,
        builder: (context, value, _) =>
            _BandMetric(value: value?.toString(), label: label),
      );
}

/// Une valeur du bandeau : le chiffre, puis son unité en dessous.
///
/// Un tiret quand la mesure manque, jamais un zéro — même règle que
/// [MetricTile], pour que le bandeau et l'écran de diagnostic ne racontent pas
/// deux histoires différentes du même capteur muet.
class _BandMetric extends StatelessWidget {
  const _BandMetric({required this.value, required this.label});

  final String? value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Les valeurs sont de longueurs très inégales (« 8 » et « 1:12:34 ») et
        // le bandeau partage sa largeur en parts égales : sans réduction, la
        // durée déborderait sur un téléphone étroit.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value ?? '—',
            maxLines: 1,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w500,
              height: 1.1,
            ),
          ),
        ),
        Text(
          label,
          maxLines: 1,
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
      ],
    );
  }
}

/// Les pastilles de page, à l'extrémité du bandeau.
///
/// Elles disent où on est, et permettent d'y aller directement : le glissé est
/// pratique à deux pages, il le sera moins à cinq.
class _PageDots extends StatelessWidget {
  const _PageDots({
    required this.count,
    required this.current,
    required this.onTap,
  });

  final int count;
  final int current;
  final void Function(int page) onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            GestureDetector(
              onTap: () => onTap(i),
              behavior: HitTestBehavior.opaque,
              // La pastille fait 8 points, sa zone tactile 22 : à vélo, on vise
              // mal.
              child: SizedBox(
                width: 22,
                height: 22,
                child: Center(
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i == current ? Colors.white : Colors.white30,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
