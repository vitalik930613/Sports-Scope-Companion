import 'package:flutter/material.dart';

import '../../dashboard/dashboard_block.dart';
import '../../dashboard/metric_id.dart';
import '../../dashboard/ride_preset.dart';
import '../../recording/ride_lap.dart';
import '../blocks/averages_block.dart';
import '../blocks/lap_summary_block.dart';
import '../blocks/zones_block.dart';

/// Le corps d'une page de tours : liste déroulante, puis les composants du
/// tour choisi.
///
/// `StatefulWidget` parce que c'est le seul endroit du tableau de bord qui a
/// besoin d'un état mutable en dehors de `RidePageSpec`/`DashboardBlock`
/// (immuables, décodés une fois du document du site) — le tour sélectionné.
/// Une occurrence par page : deux pages de tours, sur la même série ou non,
/// gardent chacune son propre choix.
class LapListBody extends StatefulWidget {
  const LapListBody({super.key, required this.spec, required this.sources});

  final LapListPageSpec spec;
  final MetricSources sources;

  @override
  State<LapListBody> createState() => _LapListBodyState();
}

class _LapListBodyState extends State<LapListBody> {
  /// `null` tant qu'aucun choix explicite n'a été fait : on suit alors le
  /// tour courant. Dès qu'on en choisit un dans la liste déroulante, ce choix
  /// est gardé même quand un nouveau tour démarre — le cycliste garde le
  /// dernier mot, même principe que le retour automatique sur la carte.
  int? _selectedIndex;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.sources.recorder,
      builder: (context, _) {
        final laps = widget.sources.recorder.lapsOf(widget.spec.series);

        if (laps.isEmpty) {
          return const Center(
            child: Text(
              'Pas encore de tour.',
              style: TextStyle(color: Colors.white70),
            ),
          );
        }

        final selected =
            (_selectedIndex ?? laps.length - 1).clamp(0, laps.length - 1);
        final lap = laps[selected];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _selector(laps, selected),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  for (final block in widget.spec.blocks)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _block(block, lap),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _selector(List<RideLap> laps, int selected) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<int>(
        value: selected,
        dropdownColor: const Color(0xFF1F2226),
        style: const TextStyle(color: Colors.white),
        iconEnabledColor: Colors.white70,
        isExpanded: true,
        items: [
          for (var i = 0; i < laps.length; i++)
            DropdownMenuItem(
              value: i,
              child: Text(
                i == laps.length - 1
                    ? 'Tour ${i + 1} (en cours)'
                    : 'Tour ${i + 1}',
              ),
            ),
        ],
        onChanged: (index) => setState(() => _selectedIndex = index),
      ),
    );
  }

  /// `switch` **non exhaustif** — délibérément, contrairement à celui de
  /// `DashboardPage._block()` : seuls les composants qui dépendent d'un tour
  /// ont un sens ici. Un `MarkLapBlock` posé sur cette page par erreur
  /// marquerait un tour de *sa propre* série, indépendante de
  /// `widget.spec.series` — pas absurde, mais pas ce qu'on attend d'une page
  /// qui *lit* des tours ; il disparaît donc, même tolérance qu'une clé
  /// inconnue.
  Widget _block(DashboardBlock block, RideLap lap) => switch (block) {
        final LapZonesBlock zones => ZonesCard(
            source: zones.source,
            recorder: widget.sources.recorder,
            riderProfile: widget.sources.riderProfile,
            mode: zones.mode,
            statsOverride: lap.stats,
          ),
        final LapAveragesBlock averages => AveragesCard(
            recorder: widget.sources.recorder,
            mode: averages.mode,
            statsOverride: lap.stats,
          ),
        final LapSummaryBlock summary => LapSummaryCard(
            lap: lap,
            riderProfile: widget.sources.riderProfile,
            mode: summary.mode,
          ),
        _ => const SizedBox.shrink(),
      };
}
