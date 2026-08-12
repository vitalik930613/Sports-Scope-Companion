import 'package:flutter/material.dart';

import '../../account/rider_profile.dart';
import '../../account/rider_profile_store.dart';
import '../../dashboard/block_density.dart';
import '../../dashboard/dashboard_block.dart';
import '../../recording/ride_recorder.dart';
import '../../recording/ride_stats.dart';
import '../../ui/zone_colors.dart';
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
/// Le mode choisi (`cards`/`list`) est un **ordre**, plus un plafond : le
/// profil qui a demandé les quatre cartes les obtient toujours, quitte à ce
/// que [ScaleToFit] les réduise pour tenir dans une case étroite.
class AveragesCard extends StatelessWidget {
  const AveragesCard({
    super.key,
    required this.recorder,
    required this.riderProfile,
    this.mode = AveragesMode.cards,
    this.statsOverride,
    this.color,
    this.textColor,
  });

  final RideRecorder recorder;
  final AveragesMode mode;

  /// Les seuils du cycliste : c'est d'eux que sortent les zones qui colorent
  /// le cardio et la puissance ci-dessous — même source que le bandeau et
  /// [ZonesCard], jamais une zone calculée sur un seuil par défaut.
  final RiderProfileStore riderProfile;

  /// Cible d'autres agrégats que ceux de la sortie entière — ceux d'un tour,
  /// par exemple (`RideLap.stats`). `recorder` reste nécessaire même alors :
  /// c'est encore lui qui dit si la sortie est active.
  final RideStats? statsOverride;

  /// Fond/texte réglés dans l'éditeur — voir [DashboardBlock.color]/
  /// [DashboardBlock.textColor]. Ne remplacent jamais les couleurs de zone
  /// des chiffres (`_zoneBg`) : ce sont des données.
  final Color? color;
  final Color? textColor;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([recorder, riderProfile]),
        builder: (context, _) => _paint(),
      );

  Widget _paint() {
    if (!recorder.isActive) {
      return BlockCard(
        title: 'Sortie non lancée',
        lines: const ['Les moyennes se remplissent dès le départ.'],
        color: color,
        textColor: textColor,
      );
    }

    final stats = statsOverride ?? recorder.stats;
    final profile = riderProfile.profile;

    final cards = [
      _Stat('Cardio', 'bpm', _or(stats.avgHeartRate), _or(stats.minHeartRate),
          _or(stats.maxHeartRate),
          icon: Icons.favorite,
          avgBackground: _zoneBg(profile.hrZoneFor, stats.avgHeartRate),
          minBackground: _zoneBg(profile.hrZoneFor, stats.minHeartRate),
          maxBackground: _zoneBg(profile.hrZoneFor, stats.maxHeartRate)),
      _Stat('Puissance', 'W', _or(stats.avgPower), _or(stats.minPower),
          _or(stats.maxPower),
          icon: Icons.bolt,
          avgBackground: _zoneBg(profile.powerZoneFor, stats.avgPower),
          minBackground: _zoneBg(profile.powerZoneFor, stats.minPower),
          maxBackground: _zoneBg(profile.powerZoneFor, stats.maxPower)),
      _Stat('Cadence', 'tr/min', _or(stats.avgCadence), _or(stats.minCadence),
          _or(stats.maxCadence), icon: Icons.autorenew),
      _Stat('Vitesse', 'km/h', _kmh(stats.avgSpeedMps), _kmh(stats.minSpeedMps),
          _kmh(stats.maxSpeedMps), icon: Icons.speed),
    ];

    if (mode == AveragesMode.list) {
      // En liste, les trois chiffres tiennent sur la ligne de leur mesure :
      // quatre lignes plutôt que douze.
      return BlockCard(
        title: 'Moyennes',
        lines: [for (final card in cards) card.line],
        color: color,
        textColor: textColor,
      );
    }

    // Pas de `SizedBox` de largeur fixe ni de `ScaleToFit` global ici : les
    // deux `Row` ci-dessous, avec leurs `Expanded`, remplissent d'elles-mêmes
    // toute la largeur que leur donne la case (liste ou grille, les deux la
    // bornent déjà). Une mise à l'échelle unique sur les quatre cartes à la
    // fois — l'ancienne façon — les rétrécissait *ensemble* dès que la
    // hauteur de la case manquait, même quand sa largeur suffisait large-
    // ment ; c'était le bug (la grille laissait des bandes vides sur les
    // côtés que la liste ne montrait pas).
    //
    // Seule la hauteur diffère entre les deux mises en page : bornée par la
    // case en grille (`DashboardGrid`), jamais en liste (`ListView`). En
    // grille, chaque ligne prend sa moitié via `Expanded` plutôt que d'être
    // mise à l'échelle avec l'autre — c'est alors chaque `StatCard`, par son
    // propre `ScaleToFit` (dans `BlockSurface`), qui réduit son texte si son
    // quart de case est trop bas. Une réduction confinée à la carte
    // concernée plutôt qu'une seule réduction globale sur les quatre.
    final gap = SizedBox(height: BlockMetrics.natural.gap);
    return LayoutBuilder(
      builder: (context, constraints) => constraints.hasBoundedHeight
          ? Column(
              children: [
                Expanded(child: _row(cards[0], cards[1], color, textColor)),
                gap,
                Expanded(child: _row(cards[2], cards[3], color, textColor)),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _row(cards[0], cards[1], color, textColor),
                gap,
                _row(cards[2], cards[3], color, textColor),
              ],
            ),
    );
  }

  /// Deux cartes côte à côte. Les deux ont désormais toujours la même forme —
  /// un titre, trois lignes — donc pas besoin de mesurer laquelle est la plus
  /// haute pour aligner l'autre dessus.
  static Widget _row(_Stat left, _Stat right, Color? color, Color? textColor) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: left.card(color: color, textColor: textColor)),
          SizedBox(width: BlockMetrics.natural.gap),
          Expanded(child: right.card(color: color, textColor: textColor)),
        ],
      );

  /// La couleur de la zone d'un chiffre — même table que le bandeau et
  /// [ZonesCard] (`z1` bleu … `z5` rouge, `z6`/`z7` violets pour la
  /// puissance) : `null` sans seuil connu (le site n'a rien envoyé) ou pour
  /// une valeur sous la première zone, auquel cas la ligne garde le texte
  /// blanc uni plutôt qu'une couleur inventée.
  static Color? _zoneBg(TrainingZone? Function(num) zoneFor, num? value) =>
      value == null ? null : zoneColorOf(zoneFor(value)?.key);

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
  const _Stat(this.name, this.unit, this.avg, this.min, this.max,
      {required this.icon,
      this.avgBackground,
      this.minBackground,
      this.maxBackground});

  final String name;
  final String unit;
  final String avg;
  final String min;
  final String max;
  final IconData icon;
  final Color? avgBackground;
  final Color? minBackground;
  final Color? maxBackground;

  Widget card({Color? color, Color? textColor}) => StatCard(
        title: name,
        unit: unit,
        icon: icon,
        rows: [
          StatRow('Moyen', avg, background: avgBackground),
          StatRow('Min', min, background: minBackground),
          StatRow('Max', max, background: maxBackground),
        ],
        color: color,
        textColor: textColor,
      );

  String get line => '$name $avg $unit ($min – $max)';
}
