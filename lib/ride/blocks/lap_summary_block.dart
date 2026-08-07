import 'package:flutter/material.dart';

import '../../account/rider_profile_store.dart';
import '../../dashboard/dashboard_block.dart';
import '../../recording/ride_lap.dart';
import '../../training/ride_load.dart';
import '../../ui/formats.dart';
import 'block_card.dart';

/// Le bilan d'un tour : durée, distance, D+, calories, TSS — ce qu'on
/// demanderait d'un tour entier plutôt qu'à une seule mesure.
///
/// Le TSS suit `rideTss` (`training/ride_load.dart`), déjà générique sur
/// n'importe quelle `RideStats` — celle d'un tour comme celle de la sortie
/// entière, sans qu'il ait fallu y toucher.
///
/// [lap] est `null` avant que la série n'ait le moindre tour (sortie pas
/// commencée, ou série que le profil qui a démarré l'enregistrement n'a pas
/// déclarée) : l'état vide le dit, plutôt que des tirets qu'on prendrait pour
/// des mesures absentes.
class LapSummaryCard extends StatelessWidget {
  const LapSummaryCard({
    super.key,
    required this.lap,
    required this.riderProfile,
    this.mode = LapSummaryMode.cards,
  });

  final RideLap? lap;
  final RiderProfileStore riderProfile;
  final LapSummaryMode mode;

  static const _title = 'Bilan du tour';

  @override
  Widget build(BuildContext context) {
    final lap = this.lap;
    if (lap == null) {
      return const BlockCard(title: _title, lines: ['Pas encore de tour.']);
    }

    return ListenableBuilder(
      listenable: riderProfile,
      builder: (context, _) {
        final tss = rideTss(lap.stats, riderProfile.profile)?.tss;
        final rows = [
          StatRow(
            'Durée',
            formatDurationHm(Duration(seconds: lap.pointCount)),
          ),
          StatRow('Distance', formatDistanceKm(lap.distanceM)),
          StatRow('D+', '${lap.stats.ascentM.round()} m'),
          StatRow('Calories', lap.stats.calories?.toString() ?? '—'),
          StatRow('TSS', tss == null ? '—' : tss.round().toString()),
        ];

        if (mode == LapSummaryMode.list) {
          return BlockCard(
            title: _title,
            lines: [for (final row in rows) '${row.label} ${row.value}'],
          );
        }

        return StatCard(title: _title, rows: rows);
      },
    );
  }
}
