import 'dart:math' as math;
import 'dart:ui' show DisplayFeature, DisplayFeatureType;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../dashboard/dashboard_block.dart' show BellMode, RadarMode, SleepMode, ToggleWorkoutMode;
import '../../dashboard/metric_id.dart';
import '../../dashboard/ride_preset.dart';
import '../../recording/ride_recorder.dart';
import '../blocks/bell_block.dart';
import '../blocks/radar_block.dart';
import '../blocks/sleep_block.dart';
import '../blocks/toggle_workout_block.dart';
import '../radar_severity.dart';
import 'band_metric_tile.dart';
import 'swipe_zone.dart';
import 'workout_band_tile.dart';

/// La bande de l'encoche : jusqu'à une mesure de chaque côté de la caméra
/// selfie, sur l'ancien emplacement de `RadarDistanceBadges` (retiré).
///
/// **Rien par défaut** : contrairement au bandeau du bas, un profil qui n'a
/// jamais touché ce réglage garde une bande invisible — exactement l'état
/// d'aujourd'hui. Branchée dans `RideShellPage` **avant** le cadre d'alerte
/// radar (`RadarFrame`) dans la pile, pour que celui-ci continue de se
/// dessiner par-dessus, comme il le faisait déjà par-dessus le reste de
/// l'écran.
///
/// **Plusieurs jeux, comme le bandeau du bas** ([RideBottomBand]) : un glissé
/// horizontal fait défiler l'un vers l'autre. `SwipeZone` y est branché en
/// `HitTestBehavior.translucent`, pas `opaque` (son défaut) — le tap de cette
/// zone appartient toujours à la page web en dessous, c'est elle qui pilote
/// le rétroéclairage, et `translucent` le laisse passer tout en laissant le
/// glissé horizontal se faire reconnaître pour changer de jeu.
class NotchBand extends StatefulWidget {
  const NotchBand({
    super.key,
    required this.notch,
    required this.sources,
    required this.recorder,
    this.radar,
    this.onSleep,
    this.onChooseWorkout,
  });

  /// Les jeux de la bande, dans l'ordre. Vide (le cas par défaut) laisse la
  /// bande invisible — voir [RidePreset.notch].
  final List<NotchSpec> notch;

  final MetricSources sources;

  /// Pour la case `mark_lap` — même rôle que `RideBottomBand.recorder`.
  final RideRecorder recorder;

  /// Nul quand le profil a coupé le radar — même source que le bandeau du
  /// bas (`RideBottomBand.radar`) et le cadre d'alerte.
  final ValueListenable<RadarView>? radar;

  /// Demander la veille, sur un tap d'un côté réglé sur `sleep` — voir
  /// [SleepControl]. `null` sur un profil sans carte, comme la commande de
  /// la grille : rien à endormir.
  final VoidCallback? onSleep;

  /// Ouvre le choix de programme d'entraînement, sur un tap d'un côté réglé
  /// sur `toggle_workout` — voir [ToggleWorkoutControl]. Toujours
  /// utilisable, contrairement à [onSleep] : un programme se démarre aussi
  /// bien sur home-trainer, sans carte.
  final VoidCallback? onChooseWorkout;

  /// Plancher pour les écrans sans encoche : sans lui, la valeur se collerait
  /// au bord. Un peu plus haut que l'ancienne bande `RadarDistanceBadges`
  /// (46) : la bande porte maintenant un fond et plusieurs jeux, elle a
  /// besoin d'un peu plus de présence.
  static const _minHeight = 60.0;

  /// Ce que la bande occupe réellement, encoche matérielle comprise.
  /// `RideShellPage` s'en sert pour republier l'inset du haut vers la page
  /// web (`_publishInsets`) : sans ça, la page croirait la zone obstruée
  /// aussi courte que l'encoche physique, et sur un écran où [_minHeight]
  /// prend le dessus (encoche absente ou plus courte que ce plancher), la
  /// bannière de virage se dessinerait sous la bande plutôt que juste en
  /// dessous.
  static double heightFor(BuildContext context) =>
      // `viewPadding` et non `padding` : en immersif les barres système sont
      // masquées, mais l'encoche, elle, est toujours là.
      math.max(MediaQuery.viewPaddingOf(context).top, _minHeight);

  @override
  State<NotchBand> createState() => _NotchBandState();
}

class _NotchBandState extends State<NotchBand> {
  /// Le jeu affiché. Même logique que `_RideBottomBandState._set` : il ne
  /// suit ni la page, ni rien d'autre que le doigt.
  int _set = 0;

  /// Refermée sur elle-même, comme le bandeau du bas — un bout de liste
  /// voudrait dire « glissé sans effet ».
  void _onSwipe(int direction) => setState(
        () => _set = (_set + direction) % widget.notch.length,
      );

  @override
  void didUpdateWidget(NotchBand oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Même rattrapage que le bandeau du bas : changer de profil en cours de
    // route peut raccourcir la liste.
    if (_set >= widget.notch.length) _set = 0;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.notch.isEmpty) return const SizedBox.shrink();

    final current = widget.notch[_set];

    // Chaque valeur centrée dans l'espace qui lui reste — à gauche ou à
    // droite de la caméra selfie — plutôt que collée au bord de l'écran.
    // `displayFeatures` donne les bords réels de l'encoche matérielle, en
    // pixels logiques ; sans elle (aucune encoche rapportée par l'OS), les
    // deux valeurs se partagent la largeur en deux moitiés égales.
    final totalWidth = MediaQuery.sizeOf(context).width;
    final cutout = _cutoutOf(context);
    final leftWidth = cutout != null ? cutout.bounds.left : totalWidth / 2;
    final rightWidth = cutout != null ? totalWidth - cutout.bounds.right : totalWidth / 2;
    final gapWidth = cutout != null ? cutout.bounds.width : 0.0;

    return SwipeZone(
      behavior: HitTestBehavior.translucent,
      onSwipe: _onSwipe,
      child: Container(
        height: NotchBand.heightFor(context),
        decoration: const BoxDecoration(
          color: Color(0xFF101214),
          border: Border(bottom: BorderSide(color: Colors.white24)),
        ),
        child: Row(
          children: [
            SizedBox(width: leftWidth, child: Center(child: _slot(current.left))),
            if (gapWidth > 0) SizedBox(width: gapWidth),
            SizedBox(width: rightWidth, child: Center(child: _slot(current.right))),
          ],
        ),
      ),
    );
  }

  static DisplayFeature? _cutoutOf(BuildContext context) {
    for (final feature in MediaQuery.displayFeaturesOf(context)) {
      if (feature.type == DisplayFeatureType.cutout) return feature;
    }
    return null;
  }

  Widget _slot(BandSlot? slot) {
    if (slot == null) return const SizedBox.shrink();

    return switch (slot) {
      BandMetricSlot(:final metric) => _metric(metric),
      BandActionSlot(:final action) => _action(action),
      BandBellSlot(:final sound) => BellControl(mode: BellMode.compact, sound: sound),
      BandRadarSlot(:final mode) => _radar(mode),
      BandWorkoutSlot(:final mode, :final upcoming) => _workout(mode, upcoming),
      BandMarkLapSlot(:final series, :final label) => _markLap(series, label),
    };
  }

  // Même geste que [MarkLapControl] (`mark_lap_block.dart`) et même garde que
  // `RideBottomBand._markLap` : un tour ne veut rien dire hors
  // enregistrement.
  Widget _markLap(String series, String? label) => ListenableBuilder(
        listenable: widget.recorder,
        builder: (context, _) {
          final onTap = widget.recorder.isActive ? () => widget.recorder.markLap(series) : null;
          final color = onTap == null ? Colors.white24 : Colors.white70;
          return FittedBox(
            fit: BoxFit.scaleDown,
            child: Material(
              color: const Color(0xFF1F2226),
              borderRadius: BorderRadius.circular(6),
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.flag_outlined, color: color, size: 18),
                      const SizedBox(width: 4),
                      Text(
                        // Sans label posé par le site, le nom de la série
                        // reste le repère le plus utile — sauf `'default'`,
                        // qui ne veut rien dire pour le cycliste.
                        label ?? (series == 'default' ? 'Tour' : series),
                        maxLines: 1,
                        style: TextStyle(color: color, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );

  // Pas de `FittedBox` ici, à l'inverse de [_metric] : [RadarBlockView] se
  // met déjà à l'échelle de sa case via [BlockSurface] (`block_card.dart`),
  // comme dans une case de grille — l'ajouter mesurerait deux fois.
  Widget _radar(RadarMode mode) => RadarBlockView(radar: widget.radar, mode: mode);

  Widget _metric(MetricId metric) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: ListenableBuilder(
        listenable: Listenable.merge(metric.dependencies(widget.sources)),
        builder: (context, _) {
          final reading = metric.read(widget.sources);
          return BandMetricTile(
            value: reading.value,
            label: metric.name,
            zoneKey: reading.zoneKey,
            background: reading.background,
            // Inverse du bandeau du bas : le libellé au-dessus du chiffre.
            labelFirst: true,
          );
        },
      ),
    );
  }

  Widget _action(BandAction action) => switch (action) {
        BandAction.sleep => SleepControl(onSleep: widget.onSleep, mode: SleepMode.compact),
        BandAction.toggleWorkout => ToggleWorkoutControl(
            recorder: widget.recorder,
            onChooseWorkout: widget.onChooseWorkout,
            mode: ToggleWorkoutMode.compact,
          ),
      };

  // Pas de `FittedBox` externe ici, à l'inverse de [_metric] :
  // [WorkoutBandTile] se met déjà à l'échelle elle-même (voir sa note de
  // classe) — un `FittedBox` de plus l'envelopperait pour rien.
  Widget _workout(BandWorkoutMode mode, bool upcoming) =>
      WorkoutBandTile(recorder: widget.recorder, mode: mode, upcoming: upcoming);
}
