import 'package:flutter/material.dart';

import '../../dashboard/block_density.dart';
import '../../dashboard/dashboard_block.dart';
import '../../recording/ride_recorder.dart';
import 'block_card.dart';

/// Les moyennes de la sortie : cardio, puissance, et le reste.
///
/// Tout vient de [RideRecorder] — hors enregistrement il n'y a **rien** à
/// afficher, et le bloc le dit plutôt que d'exhiber des zéros.
///
/// Les trois cartes demandent une pleine page ; dans une case qui n'en a pas, le
/// bloc passe **de lui-même en liste** — les mêmes chiffres, dans une seule
/// carte, dont [BlockCard] retire ensuite les lignes qui ne tiennent pas. Le
/// mode du profil reste un plafond : on ne montre jamais plus que ce qu'il
/// demande.
class AveragesCard extends StatelessWidget {
  const AveragesCard({
    super.key,
    required this.recorder,
    this.mode = AveragesMode.cards,
  });

  final RideRecorder recorder;
  final AveragesMode mode;

  /// Les trois cartes tiennent-elles ? La rangée du haut fait la hauteur de la
  /// plus longue des deux (trois lignes, celle de la puissance), la carte du bas
  /// en fait trois aussi.
  ///
  /// La largeur compte autant que la hauteur, et c'est le piège de ce bloc : la
  /// rangée du haut coupe la case en deux, si bien que « Normalisée 236 W » se
  /// replie sur trois lignes dans une demi-case étroite et fait grandir la carte
  /// bien au-delà de ce qu'on avait mesuré. Sous la largeur d'une pleine page,
  /// on ne tente pas.
  static const _cardsWidth = 280.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => ListenableBuilder(
        listenable: recorder,
        builder: (context, _) =>
            _paint(BlockMetrics.of(constraints), constraints),
      ),
    );
  }

  Widget _paint(BlockMetrics metrics, BoxConstraints constraints) {
    if (!recorder.isActive) {
      return const BlockCard(
        title: 'Sortie non lancée',
        lines: ['Les moyennes se remplissent dès le départ.'],
      );
    }

    final stats = recorder.stats;

    // Le tiret des calories dit « pas de capteur de puissance », le seul cas où
    // l'on ne sait pas : elles se déduisent du travail mécanique, jamais du
    // cardio (cf. RideStats).
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

    if (mode == AveragesMode.list || !_cardsFit(metrics, constraints)) {
      return BlockCard(
        title: 'Moyennes',
        lines: [...cardio, ...power, ...ride],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // `IntrinsicHeight` et pas un simple `stretch` : dans une liste, la
        // hauteur disponible est infinie, et une colonne étirée vers l'infini
        // fait exploser la mise en page. Il faut donc mesurer la plus haute des
        // deux cartes avant de les aligner.
        //
        // Les cartes reçoivent la densité de la case : sans quoi elles
        // remonteraient chacune un `LayoutBuilder` sous cet `IntrinsicHeight`,
        // qui ne sait pas mesurer ce qui n'existe qu'une fois les contraintes
        // connues.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: BlockCard(
                  title: 'Cardio',
                  lines: cardio,
                  metrics: metrics,
                ),
              ),
              SizedBox(width: metrics.gap),
              Expanded(
                child: BlockCard(
                  title: 'Puissance',
                  lines: power,
                  metrics: metrics,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: metrics.gap),
        BlockCard(title: 'Sortie', lines: ride, metrics: metrics),
      ],
    );
  }

  static bool _cardsFit(BlockMetrics metrics, BoxConstraints constraints) {
    if (constraints.maxWidth < _cardsWidth) return false;
    if (!constraints.hasBoundedHeight) return true;

    final card = metrics.padding * 2 +
        metrics.titleHeight +
        metrics.gap +
        3 * metrics.lineHeight;

    return constraints.maxHeight >= card * 2 + metrics.gap;
  }

  static String _or(num? value) => value?.toString() ?? '—';
}
