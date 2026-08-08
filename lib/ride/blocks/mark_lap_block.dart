import 'package:flutter/material.dart';

import '../../dashboard/dashboard_block.dart';
import '../../recording/ride_recorder.dart';
import 'block_card.dart';

/// Marquer un tour de [series], sans quitter la sortie.
///
/// Pas la même famille que `RecordingControl` bien qu'il s'en inspire (bouton
/// plein ou compact) : marquer un tour n'a ni pause ni reprise, c'est un geste
/// sec, répété autant de fois qu'il y a de tours — jamais rien à confirmer, un
/// tour de trop se corrige en en marquant simplement un autre.
///
/// Peut se poser sur n'importe quelle page, pas seulement une page de tours :
/// c'est en roulant, entre deux mesures, qu'on le cherche.
class MarkLapControl extends StatelessWidget {
  const MarkLapControl({
    super.key,
    required this.recorder,
    required this.series,
    this.mode = MarkLapMode.full,
  });

  final RideRecorder recorder;

  /// La série dans laquelle ce bouton ouvre un nouveau tour. Plusieurs
  /// boutons de séries différentes coexistent sans se fermer l'un l'autre.
  final String series;

  final MarkLapMode mode;

  static const _naturalWidth = 200.0;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: recorder,
      builder: (context, _) {
        final onPressed =
            recorder.isActive ? () => recorder.markLap(series) : null;

        if (mode == MarkLapMode.compact) {
          return Tooltip(
            message: 'Marquer un tour',
            child: Material(
              color: const Color(0xFF1F2226),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: onPressed,
                borderRadius: BorderRadius.circular(12),
                child: const Center(
                  child: Icon(Icons.flag_outlined, color: Colors.white70),
                ),
              ),
            ),
          );
        }

        // `BlockSurface` et non `ScaleToFit` seul : le fond anthracite des
        // cartes de mesure, sinon ce bouton flotte seul sur le noir de la
        // coquille et détonne à côté des cartes voisines.
        return BlockSurface(
          child: SizedBox(
            width: _naturalWidth,
            // `FilledButton` et non `OutlinedButton` (contrairement à la
            // pause) : marquer un tour est un geste positif, pas une pause
            // qu'on hésite à prendre — il porte l'aplat de la même couleur
            // que « Démarrer l'enregistrement », sans quoi il se fond dans le
            // noir de la coquille derrière lui.
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: onPressed,
              icon: const Icon(Icons.flag_outlined),
              label:
                  const Text('Marquer un tour', style: TextStyle(fontSize: 15)),
            ),
          ),
        );
      },
    );
  }
}
