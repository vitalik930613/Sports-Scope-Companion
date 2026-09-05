import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../dashboard/companion_icons.dart';
import '../../dashboard/ride_preset.dart' show BandWorkoutMode;
import '../../recording/ride_recorder.dart';
import '../../ui/formats.dart';
import '../../ui/zone_colors.dart';

/// Une case de bandeau ou d'encoche dérivée du tronçon d'entraînement en
/// cours — même source que [WorkoutSegmentCard]/[WorkoutRemainingCard]
/// (`RideRecorder.activeWorkout`/`workoutElapsed`,
/// `TrainingProgram.milestoneAt`/`remainingAt`), mais au langage visuel du
/// bandeau plutôt que d'une carte de page — voir [BandMetricTile], dont elle
/// reprend le fond de zone (ici la couleur du tronçon) et l'alternance
/// noir/anthracite en repli.
///
/// Cinq habillages ([BandWorkoutMode]) : le nom du tronçon, le compte à
/// rebours, les deux fondus en une icône et un chiffre, les trois — icône,
/// nom et chiffre — sur une seule ligne, ou l'icône seule. Pas de libellé
/// séparé (« Tronçon », « Restant ») : la case est trop étroite pour se le
/// permettre en plus de l'icône, qui porte déjà le sens.
///
/// **Jamais de [Flexible]/[Expanded].** `NotchBand` pose sa case dans un
/// `FittedBox` qui mesure son enfant sans aucune contrainte (voir
/// `RenderFittedBox`) : un `Flexible` hérite alors d'une largeur infinie et
/// lève à l'exécution (« incoming width constraints are unbounded »). Chaque
/// ligne se met donc à l'échelle elle-même, avec son propre `FittedBox`
/// autour d'un `Row` de taille naturelle (`mainAxisSize: min`) — sûr que la
/// case l'entoure d'une contrainte bornée (`RideBottomBand`) ou d'aucune
/// (`NotchBand`), et qui rend d'ailleurs le `FittedBox` externe de
/// `NotchBand._workout` inutile : cette case sait déjà se réduire seule.
class WorkoutBandTile extends StatelessWidget {
  const WorkoutBandTile({
    super.key,
    required this.recorder,
    required this.mode,
    this.upcoming = false,
    this.color,
    this.altBackground,
  });

  final RideRecorder recorder;
  final BandWorkoutMode mode;

  /// Montre le tronçon qui suivra celui en cours
  /// ([TrainingProgram.nextMilestoneAt]/[TrainingProgram.nextSegmentDurationAt])
  /// plutôt que le tronçon en cours — même bascule que sur
  /// [WorkoutSegmentCard]/[WorkoutRemainingCard], voir [BandWorkoutSlot.upcoming].
  final bool upcoming;

  /// Fond réglé dans l'éditeur pour cette case (`BandSlot.color`) — sous la
  /// couleur du tronçon (une donnée), mais au-dessus de l'alternance — voir
  /// [BandMetricTile.color].
  final Color? color;

  /// Le noir ou l'anthracite de l'alternance, quand le tronçon ne porte pas
  /// de couleur propre — voir [BandMetricTile.altBackground].
  final Color? altBackground;

  static const _finished = 'Terminé';

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: recorder,
        builder: (context, _) {
          final program = recorder.activeWorkout;
          final elapsed = recorder.workoutElapsed;
          final milestone = program != null && elapsed != null
              ? (upcoming ? program.nextMilestoneAt(elapsed) : program.milestoneAt(elapsed))
              : null;
          final remaining = program != null && elapsed != null
              ? (upcoming ? program.nextSegmentDurationAt(elapsed) : program.remainingAt(elapsed))
              : null;

          final zoneColor = milestone?.color ?? color;
          final foreground =
              milestone?.textColor ?? (zoneColor == null ? Colors.white : foregroundOf(zoneColor));

          final icon = workoutMilestoneIconFor(milestone?.icon);

          final segmentName = milestone?.segmentName;
          final segmentLabel = (segmentName == null || segmentName.isEmpty) ? '—' : segmentName;
          // `upcoming` n'a pas de « Terminé » : ce tronçon n'a pas commencé,
          // il n'y a rien à annoncer de fini — juste un tiret quand sa durée
          // n'est pas connue (dernier de la timeline, programme absent).
          final remainingLabel = program == null
              ? '—'
              : (remaining == null ? (upcoming ? '—' : _finished) : formatDuration(remaining));

          final content = switch (mode) {
            BandWorkoutMode.combo => _combo(icon, remainingLabel, foreground),
            BandWorkoutMode.line => _line(icon, segmentLabel, remainingLabel, foreground),
            BandWorkoutMode.segment => _iconValue(icon, segmentLabel, foreground),
            BandWorkoutMode.remaining => _iconValue(icon, remainingLabel, foreground),
            BandWorkoutMode.icon => _iconOnly(icon, foreground),
          };

          final surface = zoneColor ?? altBackground;
          if (surface == null) return content;

          return Container(
            margin: const EdgeInsets.fromLTRB(2, 3, 2, 3),
            decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(6)),
            child: content,
          );
        },
      );

  /// [BandWorkoutMode.combo] : une seule ligne, icône du tronçon et compte à
  /// rebours — pas de titre séparé, la case n'a la place que pour l'un des
  /// deux textes mais montre les deux informations d'un coup d'œil.
  Widget _combo(FaIconData icon, String remaining, Color foreground) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: _fit([
          FaIcon(icon, size: 18, color: foreground.withValues(alpha: 0.85)),
          const SizedBox(width: 6),
          Text(
            remaining,
            maxLines: 1,
            style: TextStyle(color: foreground, fontSize: 22, fontWeight: FontWeight.w500),
          ),
        ]),
      );

  /// [BandWorkoutMode.line] : icône, nom du tronçon et compte à rebours, tout
  /// sur une seule ligne — même contenu que [WorkoutBadge], au langage
  /// visuel du bandeau plutôt que d'une pastille flottante.
  Widget _line(FaIconData icon, String segment, String remaining, Color foreground) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: _fit([
          FaIcon(icon, size: 16, color: foreground.withValues(alpha: 0.85)),
          const SizedBox(width: 6),
          Text(
            segment,
            maxLines: 1,
            style: TextStyle(color: foreground, fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 8),
          Text(
            remaining,
            maxLines: 1,
            style: TextStyle(color: foreground, fontSize: 16, fontWeight: FontWeight.w500),
          ),
        ]),
      );

  /// [BandWorkoutMode.segment]/[BandWorkoutMode.remaining] : l'icône et la
  /// valeur seules, sans libellé — l'icône du tronçon (la même dans les deux
  /// modes) porte déjà la distinction entre les deux.
  Widget _iconValue(FaIconData icon, String value, Color foreground) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: _fit([
          FaIcon(icon, size: 14, color: foreground.withValues(alpha: 0.85)),
          const SizedBox(width: 4),
          Text(
            value,
            maxLines: 1,
            style: TextStyle(color: foreground, fontSize: 20, fontWeight: FontWeight.w500),
          ),
        ]),
      );

  /// [BandWorkoutMode.icon] : l'icône du tronçon seule, sans aucun texte —
  /// pour la case qui n'a la place que pour un symbole.
  Widget _iconOnly(FaIconData icon, Color foreground) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: _fit([FaIcon(icon, size: 22, color: foreground.withValues(alpha: 0.85))]),
      );

  /// Une ligne à taille naturelle (`mainAxisSize: min`, jamais de
  /// [Flexible]), réduite si besoin par le [FittedBox] qui l'entoure — voir
  /// la note de classe sur pourquoi jamais l'inverse.
  static Widget _fit(List<Widget> row) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(mainAxisSize: MainAxisSize.min, children: row),
      );
}
