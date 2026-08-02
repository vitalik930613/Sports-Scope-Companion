import 'package:flutter/material.dart';

import '../../dashboard/dashboard_block.dart';
import '../../recording/ride_recorder.dart';
import 'block_card.dart';

/// Les moyennes de la sortie : cardio, puissance, et le reste.
///
/// Tout vient de [RideRecorder] — hors enregistrement il n'y a **rien** à
/// afficher, et le bloc le dit plutôt que d'exhiber des zéros.
class AveragesCard extends StatelessWidget {
  const AveragesCard({
    super.key,
    required this.recorder,
    this.mode = AveragesMode.cards,
  });

  final RideRecorder recorder;
  final AveragesMode mode;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: recorder,
      builder: (context, _) {
        if (!recorder.isActive) {
          return const BlockCard(
            title: 'Sortie non lancée',
            lines: ['Les moyennes se remplissent dès le départ.'],
          );
        }

        final stats = recorder.stats;

        // Le tiret des calories dit « pas de capteur de puissance », le seul cas
        // où l'on ne sait pas : elles se déduisent du travail mécanique, jamais
        // du cardio (cf. RideStats).
        final ride = [
          'Cadence ${_or(stats.avgCadence)} tr/min moyenne',
          'Dénivelé positif ${stats.ascentM.round()} m',
          'Dépense ${_or(stats.calories)} kcal',
        ];
        final cardio = [
          '${_or(stats.avgHeartRate)} bpm moyen',
          'Max ${_or(stats.maxHeartRate)} bpm',
        ];
        final power = [
          '${_or(stats.avgPower)} W moyen',
          'Normalisée ${_or(stats.normalizedPowerW)} W',
          'Max ${_or(stats.maxPower)} W',
        ];

        if (mode == AveragesMode.list) {
          return BlockCard(
            title: 'Moyennes',
            lines: [...cardio, ...power, ...ride],
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // `IntrinsicHeight` et pas un simple `stretch` : dans une liste, la
            // hauteur disponible est infinie, et une colonne étirée vers
            // l'infini fait exploser la mise en page. Il faut donc mesurer la
            // plus haute des deux cartes avant de les aligner.
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: BlockCard(title: 'Cardio', lines: cardio)),
                  const SizedBox(width: 12),
                  Expanded(child: BlockCard(title: 'Puissance', lines: power)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            BlockCard(title: 'Sortie', lines: ride),
          ],
        );
      },
    );
  }

  static String _or(num? value) => value?.toString() ?? '—';
}
