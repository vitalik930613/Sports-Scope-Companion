import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../dashboard/dashboard_block.dart'
    show BellMode, BellSound, LeaveRideMode, RadarMode, RouteMode, SleepMode, ToggleWorkoutMode;
import '../../dashboard/metric_id.dart';
import '../../dashboard/ride_preset.dart';
import '../../recording/ride_recorder.dart';
import '../blocks/bell_block.dart';
import '../blocks/leave_ride_block.dart';
import '../blocks/radar_block.dart';
import '../blocks/route_block.dart';
import '../blocks/sleep_block.dart';
import '../blocks/toggle_pause_block.dart';
import '../blocks/toggle_workout_block.dart';
import '../radar_severity.dart';
import 'band_metric_tile.dart';
import 'swipe_zone.dart';
import 'workout_band_tile.dart';

/// Le bandeau du bas : les valeurs instantanées de la sortie.
///
/// Présent sur toutes les pages, y compris la carte. Un glissé horizontal
/// dessus **change de jeu de valeurs**, pas de page : le bandeau n'a rien en
/// dessous de lui, donc un geste qui y démarre lui appartient sans ambiguïté, et
/// c'est le seul endroit où l'on peut faire défiler des chiffres sans les
/// perdre de vue. Changer de page, c'est l'affaire des bandes du bord de la
/// carte ; savoir où l'on vient d'arriver, celle de `RidePageFlash`.
///
/// **Il ne porte plus aucun repère de position** — ni la colonne de pastilles de
/// page à son extrémité, ni la rangée de pastilles de jeu de valeurs sur son
/// bord haut. Les deux étaient dessinées à huit et quatre points de côté dans un
/// bandeau de soixante-douze de haut : lisibles à l'arrêt, c'est-à-dire au seul
/// moment où l'on sait déjà où l'on est. Et la colonne des pages débordait dès
/// qu'un profil en comptait quatre — vingt-deux points par pastille, il n'y en
/// avait la place que de trois. Toute la hauteur va donc aux chiffres, qui sont
/// ce qu'on vient y lire.
///
/// **Les jeux de valeurs viennent du profil de sortie**, plus d'une énumération :
/// c'est le site qui dit lesquels, dans quel ordre, et avec quelles mesures. Ce
/// qui ne change pas, c'est la limite de quatre cases — au-delà, les chiffres
/// deviennent trop petits pour être lus d'un coup d'œil en roulant, ce qui est
/// le seul usage du bandeau (garantie tenue par `RideBandSpec.parse`).
///
/// Il ne réutilise pas [MetricTile] : celui-ci empile icône, valeur et unité
/// pour l'écran de diagnostic et réclame une soixantaine de points de haut. Ici
/// chaque point pris est un point de carte perdu.
class RideBottomBand extends StatefulWidget {
  const RideBottomBand({
    super.key,
    required this.bands,
    required this.sources,
    required this.recorder,
    this.radar,
    this.onCalibratePower,
    this.onSleep,
    this.onChooseWorkout,
    this.onLeaveRide,
    this.onChooseRoute,
    this.onClearRoute,
  });

  /// Les jeux de valeurs du profil, dans l'ordre. Au moins un.
  final List<RideBandSpec> bands;

  /// D'où les mesures se lisent — et de quoi elles dépendent.
  final MetricSources sources;

  /// Pour la case `mark_lap` : `isActive` dit si un tour a un sens à marquer,
  /// et `markLap` l'ouvre — voir [MarkLapControl], le même geste posé sur une
  /// page plutôt qu'ici.
  final RideRecorder recorder;

  /// Nul quand le profil a coupé le radar — même source que la page de
  /// données (`DashboardPage.radar`) et le cadre d'alerte, pas une seconde
  /// écoute du capteur.
  final ValueListenable<RadarView>? radar;

  /// Demander la veille, sur un tap de la case `sleep` — voir [SleepControl].
  /// `null` sur un profil sans carte, comme la commande de la grille : rien
  /// à endormir.
  final VoidCallback? onSleep;

  /// Calibrer le capteur de puissance, sur un tap des watts ou de leur zone.
  ///
  /// La case des watts est le seul endroit de l'écran où l'on *constate* une
  /// puissance qui dérive : c'est là qu'on tape, pas dans un menu deux pages
  /// plus loin. Non filtré ici, contrairement au menu de la page de données —
  /// la coquille ne se reconstruit pas quand le capteur finit sa découverte, et
  /// un tap devenu inerte entre-temps se lirait comme une appli figée. C'est la
  /// boîte de dialogue qui dit pourquoi, le cas échéant.
  final VoidCallback? onCalibratePower;

  /// Ouvre le choix de programme d'entraînement, sur un tap de la case
  /// `toggle_workout` — voir [ToggleWorkoutControl]. Toujours utilisable,
  /// contrairement à [onSleep] : un programme se démarre aussi bien sur
  /// home-trainer, sans carte.
  final VoidCallback? onChooseWorkout;

  /// Quitter la sortie, sur un tap de la case `leave_ride` — voir
  /// [LeaveRideControl]. Toujours utilisable, contrairement à [onSleep] :
  /// rentrer a un sens avec ou sans carte.
  final VoidCallback? onLeaveRide;

  /// Changer ou retirer l'itinéraire suivi, sur un tap de la case `route` —
  /// voir [RouteControl]. Nuls dans un profil sans carte, même garde que la
  /// commande de la grille (`DashboardPage.onChooseRoute`/`onClearRoute`).
  final VoidCallback? onChooseRoute;
  final VoidCallback? onClearRoute;

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
  /// Le jeu de valeurs affiché. Il ne suit pas la page : on peut très bien
  /// vouloir ses zones de puissance en gardant la carte sous les yeux.
  int _set = 0;

  /// La liste est refermée sur elle-même — après le dernier revient le premier —
  /// parce qu'un bout de course voudrait dire « glissé sans effet », et un geste
  /// sans effet se prend pour une panne.
  void _onSwipe(int direction) => setState(
        () => _set = (_set + direction) % widget.bands.length,
      );

  @override
  void didUpdateWidget(RideBottomBand oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Changer de profil en cours de route peut raccourcir la liste : sans ce
    // rattrapage, l'index resterait au-delà du dernier jeu et la construction
    // suivante lèverait, en pleine sortie.
    if (_set >= widget.bands.length) _set = 0;
  }

  @override
  Widget build(BuildContext context) {
    return SwipeZone(
      onSwipe: _onSwipe,
      child: Container(
        height: RideBottomBand.heightFor(context),
        decoration: const BoxDecoration(
          color: Color(0xFF101214),
          border: Border(top: BorderSide(color: Colors.white24)),
        ),
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewPaddingOf(context).bottom,
          ),
          child: Row(
            children: [
              for (final (index, slot) in widget.bands[_set].slots.indexed)
                Expanded(child: _slot(slot, index)),
            ],
          ),
        ),
      ),
    );
  }

  /// Noir (le fond du bandeau lui-même) et l'anthracite des cartes ailleurs
  /// dans la sortie — en alternance pour que deux chiffres voisins ne se
  /// confondent pas en une seule masse. La couleur de zone, quand il y en a
  /// une, garde toujours la priorité : c'est elle, l'information.
  static const _alternateBackgrounds = [Color(0xFF101214), Color(0xFF1F2226)];

  Widget _slot(BandSlot? slot, int index) {
    // Une case vide reste dans la rangée — le glissé de largeur du `Row`
    // parent dépend du nombre de cases, pas de leur contenu — mais n'y
    // dessine rien.
    if (slot == null) return const SizedBox.shrink();

    return switch (slot) {
      BandMetricSlot(:final metric, :final color) => _metric(metric, index, color),
      BandActionSlot(:final action, :final color) => _action(action, color),
      BandBellSlot(:final sound, :final color) => _bell(sound, color),
      BandRadarSlot(:final mode, :final color) => _radar(mode, color),
      BandWorkoutSlot(:final mode, :final upcoming, :final color) =>
        _workout(mode, upcoming, index, color),
      BandMarkLapSlot(:final series, :final label, :final color) => _markLap(series, label, color),
    };
  }

  // Même geste que [MarkLapControl] (`mark_lap_block.dart`) : un tour ne veut
  // rien dire hors enregistrement. `ListenableBuilder` et non un simple
  // `onTap` figé au premier rendu : `recorder.isActive` change en cours de
  // sortie (démarrage/pause), sans reconstruire toute la coquille.
  Widget _markLap(String series, String? label, Color? background) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 3, 2, 3),
        child: ListenableBuilder(
          listenable: widget.recorder,
          builder: (context, _) {
            final onTap = widget.recorder.isActive ? () => widget.recorder.markLap(series) : null;
            final color = onTap == null ? Colors.white24 : Colors.white70;
            return Material(
              color: background ?? const Color(0xFF1F2226),
              borderRadius: BorderRadius.circular(6),
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.flag_outlined, color: color, size: 20),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          // Sans label posé par le site, le nom de la série
                          // reste le repère le plus utile — sauf `'default'`,
                          // qui ne veut rien dire pour le cycliste.
                          label ?? (series == 'default' ? 'Tour' : series),
                          maxLines: 1,
                          style: TextStyle(color: color, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );

  // Même marge que `BandMetricTile` : sans elle, l'icône touchait ses
  // voisines alors que chaque case de mesure en garde une.
  Widget _action(BandAction action, Color? color) => switch (action) {
        BandAction.sleep => Padding(
            padding: const EdgeInsets.fromLTRB(2, 3, 2, 3),
            child: SleepControl(onSleep: widget.onSleep, mode: SleepMode.compact, color: color),
          ),
        BandAction.toggleWorkout => Padding(
            padding: const EdgeInsets.fromLTRB(2, 3, 2, 3),
            child: ToggleWorkoutControl(
              recorder: widget.recorder,
              onChooseWorkout: widget.onChooseWorkout,
              mode: ToggleWorkoutMode.compact,
              color: color,
            ),
          ),
        BandAction.leaveRide => Padding(
            padding: const EdgeInsets.fromLTRB(2, 3, 2, 3),
            child: LeaveRideControl(
              onLeaveRide: widget.onLeaveRide,
              mode: LeaveRideMode.compact,
              color: color,
            ),
          ),
        BandAction.route => Padding(
            padding: const EdgeInsets.fromLTRB(2, 3, 2, 3),
            child: RouteControl(
              onChooseRoute: widget.onChooseRoute,
              onClearRoute: widget.onClearRoute,
              nav: widget.sources.nav,
              mode: RouteMode.compact,
              color: color,
            ),
          ),
        BandAction.togglePause => Padding(
            padding: const EdgeInsets.fromLTRB(2, 3, 2, 3),
            child: TogglePauseControl(recorder: widget.recorder, compact: true, color: color),
          ),
      };

  Widget _bell(BellSound sound, Color? color) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 3, 2, 3),
        child: BellControl(mode: BellMode.compact, sound: sound, color: color),
      );

  // Pas de marge supplémentaire : [BlockSurface] (`block_card.dart`) porte
  // déjà son propre padding, comme dans une case de grille.
  Widget _radar(RadarMode mode, Color? color) =>
      RadarBlockView(radar: widget.radar, mode: mode, color: color);

  Widget _metric(MetricId metric, int index, Color? color) {
    final tile = ListenableBuilder(
      listenable: Listenable.merge(metric.dependencies(widget.sources)),
      builder: (context, _) {
        final reading = metric.read(widget.sources);
        return BandMetricTile(
          value: reading.value,
          // Le nom de la mesure, pas son unité : dans une case sans icône,
          // c'est ce qui dit laquelle on regarde (« Cardio », pas « bpm »).
          label: metric.name,
          zoneKey: reading.zoneKey,
          background: reading.background,
          color: color,
          altBackground: _alternateBackgrounds[index % 2],
        );
      },
    );

    final calibrate = widget.onCalibratePower;
    if (calibrate == null || !_isPower(metric)) return tile;

    // Le tap et le glissé du bandeau ne se disputent pas : l'arène donne le
    // geste au tap seulement si le doigt s'est levé sans partir de côté, donc
    // un glissé qui commence sur les watts change bien de jeu de valeurs.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: calibrate,
      child: tile,
    );
  }

  // Même alternance que [_metric] : deux cases voisines ne se confondent pas
  // en une seule masse quand le tronçon ne porte pas de couleur propre.
  Widget _workout(BandWorkoutMode mode, bool upcoming, int index, Color? color) => WorkoutBandTile(
        recorder: widget.recorder,
        mode: mode,
        upcoming: upcoming,
        color: color,
        altBackground: _alternateBackgrounds[index % 2],
      );

  static bool _isPower(MetricId metric) =>
      metric == MetricId.power || metric == MetricId.powerZone;
}
