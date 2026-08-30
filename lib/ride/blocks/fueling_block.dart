import 'package:flutter/material.dart';

import '../../recording/ride_recorder.dart';
import '../../ui/formats.dart';
import 'block_card.dart';

/// Le minuteur de ravitaillement — voir `FuelingBlock` (`dashboard_block.dart`).
///
/// Le compte à rebours se cale sur le temps écoulé depuis le départ
/// (`elapsed % interval`) : il repart tout seul à chaque échéance, sans geste
/// à faire. Pas d'accusé de réception (« j'ai mangé, décale la prochaine ») —
/// ça demanderait un état qui ne survivrait pas à un changement de page ;
/// une cadence fixe suffit à ne pas oublier de manger.
///
/// Ne lit aucun capteur : seulement l'horloge de l'enregistreur. « Conseillé »
/// est le cumul de la cible rapporté au temps **en roulant** (`movingTime`) —
/// un arrêt long ne gonfle pas le besoin.
class FuelingCard extends StatelessWidget {
  const FuelingCard({
    super.key,
    required this.recorder,
    required this.carbsPerHour,
    required this.intervalMin,
    this.color,
    this.textColor,
  });

  final RideRecorder recorder;
  final int carbsPerHour;
  final int intervalMin;
  final Color? color;
  final Color? textColor;

  static const _title = 'Ravitaillement';
  static const _dueBackground = Color(0xFFC62828);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: recorder,
      builder: (context, _) {
        if (!recorder.isActive) {
          return BlockCard(
            title: _title,
            lines: const ['Sortie non lancée.'],
            color: color,
            textColor: textColor,
          );
        }

        final intervalS = intervalMin * 60;
        final sinceLast = recorder.recorded.inSeconds % intervalS;
        final toNext = Duration(seconds: intervalS - sinceLast);
        final due = toNext.inSeconds <= 60;

        final movingHours =
            recorder.stats.movingTime.inMilliseconds / 3600000;
        final advisedG = (carbsPerHour * movingHours).round();

        final rows = <StatRow>[
          StatRow(
            'Prochaine prise',
            due ? 'Maintenant' : formatDuration(toNext),
            background: due ? _dueBackground : null,
          ),
          StatRow('Cible', '$carbsPerHour g/h'),
          StatRow('Conseillé', '~$advisedG g'),
        ];

        return StatCard(
          title: _title,
          rows: rows,
          color: color,
          textColor: textColor,
        );
      },
    );
  }
}
