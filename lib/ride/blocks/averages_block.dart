import 'package:flutter/material.dart';

import '../../dashboard/block_density.dart';
import '../../dashboard/dashboard_block.dart';
import '../../recording/ride_recorder.dart';
import 'block_card.dart';

/// Les moyennes de la sortie : cardio, puissance, cadence, vitesse.
///
/// Tout vient de [RideRecorder] — hors enregistrement il n'y a **rien** à
/// afficher, et le bloc le dit plutôt que d'exhiber des zéros.
///
/// Quatre cartes de même forme, deux par deux : chacune une mesure, et sous son
/// titre les trois chiffres qu'on lui demande — moyen, minimum, maximum —
/// alignés en deux colonnes. Une mesure se lit alors d'un coup d'œil au lieu de
/// se reconstituer de trois phrases dispersées entre deux cartes.
///
/// Le dénivelé et la dépense ont quitté ce bloc en même temps : ce ne sont pas
/// des moyennes, ils n'ont ni minimum ni maximum, et le catalogue les sert déjà
/// en cellule (`MetricId.ascent`, `MetricId.calories`) — comme la puissance
/// normalisée (`MetricId.powerNp`).
///
/// Les quatre cartes demandent une pleine page ; dans une case qui n'en a pas,
/// le bloc passe **de lui-même en liste** — les mêmes chiffres, dans une seule
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

  /// Les quatre cartes tiennent-elles ? Deux rangées de trois lignes — les
  /// quatre cartes ont exactement la même forme, c'est tout l'intérêt.
  ///
  /// La largeur compte autant que la hauteur, et c'est le piège de ce bloc :
  /// chaque rangée coupe la case en deux, et une demi-case étroite ne laisse ni
  /// à « Cadence (tr/min) » ni à « Moyen 84 » de quoi s'écrire — tout y part en
  /// points de suspension, et une carte de points de suspension ne se lit pas
  /// mieux qu'une ligne de liste. Sous la largeur d'une pleine page, on ne
  /// tente donc pas.
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

    final cards = [
      _Stat('Cardio', 'bpm', _or(stats.avgHeartRate), _or(stats.minHeartRate),
          _or(stats.maxHeartRate)),
      _Stat('Puissance', 'W', _or(stats.avgPower), _or(stats.minPower),
          _or(stats.maxPower)),
      _Stat('Cadence', 'tr/min', _or(stats.avgCadence), _or(stats.minCadence),
          _or(stats.maxCadence)),
      _Stat('Vitesse', 'km/h', _kmh(stats.avgSpeedMps), _kmh(stats.minSpeedMps),
          _kmh(stats.maxSpeedMps)),
    ];

    if (mode == AveragesMode.list || !_cardsFit(metrics, constraints)) {
      // En liste, les trois chiffres tiennent sur la ligne de leur mesure :
      // quatre lignes plutôt que douze, et [BlockCard] n'en retire une que
      // lorsqu'il ne reste vraiment plus la place — c'est une mesure entière
      // qui part, pas la moitié d'une.
      return BlockCard(
        title: 'Moyennes',
        lines: [for (final card in cards) card.line],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _row(metrics, cards[0], cards[1]),
        SizedBox(height: metrics.gap),
        _row(metrics, cards[2], cards[3]),
      ],
    );
  }

  /// Deux cartes côte à côte, de même hauteur.
  ///
  /// `IntrinsicHeight` et pas un simple `stretch` : dans une liste, la hauteur
  /// disponible est infinie, et une colonne étirée vers l'infini fait exploser
  /// la mise en page. Il faut donc mesurer la plus haute des deux cartes avant
  /// de les aligner.
  ///
  /// Les cartes reçoivent la densité de la case : sans quoi elles remonteraient
  /// chacune un `LayoutBuilder` sous cet `IntrinsicHeight`, qui ne sait pas
  /// mesurer ce qui n'existe qu'une fois les contraintes connues.
  static Widget _row(BlockMetrics metrics, _Stat left, _Stat right) =>
      IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: left.card(metrics)),
            SizedBox(width: metrics.gap),
            Expanded(child: right.card(metrics)),
          ],
        ),
      );

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

  /// Les mêmes km/h que le catalogue (`MetricId`) : une décimale, la virgule
  /// française. Une sortie ne change pas de chiffres selon la case qui la
  /// montre.
  static String _kmh(double? metresPerSecond) => metresPerSecond == null
      ? '—'
      : (metresPerSecond * 3.6).toStringAsFixed(1).replaceAll('.', ',');
}

/// Une mesure et ses trois chiffres, dans les deux mises en page du bloc.
///
/// Le même objet sert la carte et la ligne : les deux modes ne peuvent donc pas
/// montrer des chiffres différents de la même sortie.
@immutable
class _Stat {
  const _Stat(this.name, this.unit, this.avg, this.min, this.max);

  final String name;
  final String unit;
  final String avg;
  final String min;
  final String max;

  Widget card(BlockMetrics metrics) => StatCard(
        title: '$name ($unit)',
        rows: [
          StatRow('Moyen', avg),
          StatRow('Min', min),
          StatRow('Max', max),
        ],
        metrics: metrics,
      );

  String get line => '$name $avg $unit ($min – $max)';
}
