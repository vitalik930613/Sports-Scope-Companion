import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../recording/ride_recorder.dart';
import '../nav_state.dart';

/// La page « Effort ».
///
/// Squelette : elle prouve que la coquille tient — on y arrive, on en revient,
/// et elle est opaque comme il faut. Son contenu définitif (barre de zones
/// colorée par la FTP du site, blocs puissance et cardio, graphique de col)
/// viendra ensuite ; les agrégats affichés ici sont déjà les vrais, tirés du
/// même [RideStats] que le fichier `.fit`.
///
/// Opaque, et pas seulement dessinée par-dessus : la carte reste montée et
/// peinte en dessous, mais on ne doit pas la voir transparaître.
class RideSummaryPage extends StatelessWidget {
  const RideSummaryPage({
    super.key,
    required this.recorder,
    required this.nav,
  });

  final RideRecorder recorder;
  final ValueListenable<NavState?> nav;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF16181B),
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            const Text(
              'Effort',
              style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            _stats(),
            const SizedBox(height: 16),
            _navReadout(),
          ],
        ),
      ),
    );
  }

  Widget _stats() => ListenableBuilder(
        listenable: recorder,
        builder: (context, _) {
          final stats = recorder.stats;
          if (!recorder.isActive) {
            return const _Card(
              title: 'Sortie non lancée',
              lines: ['Les moyennes se remplissent dès le départ.'],
            );
          }
          return _Card(
            title: 'Puissance et cardio',
            lines: [
              'Moyenne : ${_or(stats.avgPower)} W · max ${_or(stats.maxPower)} W',
              'Normalisée : ${_or(stats.normalizedPowerW)} W',
              'Cardio : ${_or(stats.avgHeartRate)} bpm moyen · '
                  'max ${_or(stats.maxHeartRate)}',
              'Cadence : ${_or(stats.avgCadence)} tr/min moyen',
              'Dénivelé positif : ${stats.ascentM.round()} m',
            ],
          );
        },
      );

  /// Ce que la page de navigation raconte d'elle-même.
  ///
  /// Provisoire, mais pas gratuit : c'est le seul moyen de vérifier sur la route
  /// que le pont livre bien un état frais quand la carte est masquée — ce dont
  /// dépendra le retour automatique à l'approche d'un virage.
  Widget _navReadout() => ValueListenableBuilder<NavState?>(
        valueListenable: nav,
        builder: (context, state, _) {
          if (state == null) {
            return const _Card(
              title: 'Navigation',
              lines: ['Aucun état reçu de la page.'],
            );
          }
          final turn = state.turn;
          return _Card(
            title: 'Navigation',
            lines: [
              if (!state.onRoute) 'Navigation libre',
              if (state.onRoute)
                'Restant : ${(state.remainingM / 1000).toStringAsFixed(1)} km '
                    '· ${state.remainingGainM.round()} m D+',
              if (turn == null) 'Pas de virage annoncé',
              if (turn != null)
                'Virage ${turn.phase.name} à ${turn.distM.round()} m'
                    '${turn.direction == null ? '' : ' (${turn.direction})'}',
              if (state.offRoute) 'Hors trace',
              if (state.arrived) 'Arrivé',
              if (state.isStale(DateTime.now())) 'État périmé',
            ],
          );
        },
      );

  static String _or(num? value) => value?.toString() ?? '—';
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.lines});

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2226),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 8),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                line,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
        ],
      ),
    );
  }
}
