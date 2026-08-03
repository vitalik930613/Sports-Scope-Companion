import 'package:flutter/material.dart';

import '../../account/rider_profile_store.dart';
import '../../dashboard/block_density.dart';
import '../../dashboard/dashboard_block.dart';
import '../../recording/ride_recorder.dart';
import '../../recording/ride_stats.dart';
import '../../ui/formats.dart';
import '../../ui/zone_colors.dart';
import '../zone_time.dart';
import 'block_card.dart';

/// Le temps passé dans chaque zone depuis le départ, cardio ou puissance.
///
/// Elle répond à une question que le bandeau ne peut pas poser — le bandeau dit
/// l'instant (158 bpm, Z3), celle-ci dit le cumul. C'est ce qu'on regarde à
/// l'arrêt d'un col ou au feu rouge.
///
/// Le calcul part d'un **histogramme** de mesures et non d'un compteur par
/// zone : un profil qui arrive en pleine sortie recolore alors le temps *déjà
/// écoulé*, là où un compteur ne vaudrait que pour la suite.
///
/// Extraite de `ride_summary_page.dart`, où cardio et puissance étaient déjà le
/// même code à deux jeux d'arguments près — l'icône de la ligne courante
/// comprise (cœur / éclair), parce que les deux cartes se ressemblent trop pour
/// qu'on les distingue autrement.
class ZonesCard extends StatelessWidget {
  const ZonesCard({
    super.key,
    required this.source,
    required this.recorder,
    required this.riderProfile,
    this.mode = ZonesMode.bar,
  });

  final ZonesSource source;
  final RideRecorder recorder;
  final RiderProfileStore riderProfile;
  final ZonesMode mode;

  @override
  Widget build(BuildContext context) {
    // Écoute les deux : les histogrammes grossissent à chaque point capturé, et
    // les zones arrivent du site en cours de sortie.
    return ListenableBuilder(
      listenable: Listenable.merge([recorder, riderProfile]),
      builder: (context, _) {
        final profile = riderProfile.profile;
        final hr = source == ZonesSource.hr;

        // Tout vient de l'enregistreur : hors enregistrement il n'y a rien à
        // afficher, et on le dit plutôt que d'exhiber des zéros.
        //
        // Le message **nomme sa mesure**, et ce n'est pas de la coquetterie : la
        // page d'avant les profils fusionnait ses deux cartes vides en une, parce
        // que la même phrase deux fois de suite se lit comme un bégaiement de
        // l'appli. Un bloc composable ne peut pas connaître son voisin — un
        // profil peut n'en poser qu'un, ou les séparer de trois cartes — donc
        // c'est la phrase qui doit se distinguer, pas le contexte.
        if (!recorder.isActive) {
          return BlockCard(
            title: _title,
            lines: [
              hr
                  ? 'Le temps par zone cardio se remplit dès le départ.'
                  : 'Le temps par zone de puissance se remplit dès le départ.',
            ],
          );
        }

        final shares = zoneSharesOf(
          hr ? recorder.stats.hrHistogram : recorder.stats.powerHistogram,
          bucket: hr ? RideStats.hrBucketBpm : RideStats.powerBucketW,
          zones: hr ? profile.hrZones : profile.powerZones,
          perPoint: recorder.tickPeriod,
        );

        // Deux façons d'être vide, et pas le même message : sans zones, aucune
        // mesure n'en donnera jamais, et c'est le site qu'il faut aller voir —
        // pas le capteur.
        if (shares.isEmpty) {
          final noZones = (hr ? profile.hrZones : profile.powerZones).isEmpty;
          // Les états vides n'ont pas de variante compacte : raccourcir un
          // message jusqu'au tiret ferait perdre la seule chose utile qu'il
          // porte, à savoir *pourquoi* il n'y a rien.
          return BlockCard(
            title: _title,
            lines: [
              if (noZones)
                hr
                    ? 'Seuil cardiaque inconnu du site : pas de zones.'
                    : 'FTP inconnue du site : pas de zones.'
              else
                hr
                    ? 'Pas encore de cardio mesuré.'
                    : 'Pas encore de puissance mesurée.',
            ],
          );
        }

        // La zone du moment vient du hub, comme celle du bandeau, et non de
        // l'histogramme : celui-ci ne dit pas *quand* une mesure est tombée, et
        // son dernier palier rempli peut dater du col d'il y a une heure.
        return ValueListenableBuilder<int?>(
          valueListenable:
              hr ? recorder.hub.latestHeartRate : recorder.hub.latestPower,
          builder: (context, value, _) {
            final current = value == null
                ? null
                : (hr ? profile.hrZoneFor(value) : profile.powerZoneFor(value))
                    ?.key;

            return ZoneBreakdown(
              title: _title,
              shares: shares,
              current: current,
              currentIcon: hr ? Icons.favorite : Icons.bolt,
              mode: mode,
            );
          },
        );
      },
    );
  }

  String get _title => source == ZonesSource.hr
      ? 'Temps par zone cardio'
      : 'Temps par zone de puissance';
}

/// La barre des zones, et sa légende.
///
/// Une barre unique plutôt que cinq jauges : ce qu'on cherche à voir, c'est une
/// **proportion** — « j'ai passé la moitié de ma sortie en Z2 » — et une
/// proportion se lit dans une longueur partagée, pas dans cinq longueurs à
/// comparer de tête.
class ZoneBreakdown extends StatelessWidget {
  const ZoneBreakdown({
    super.key,
    required this.title,
    required this.shares,
    required this.currentIcon,
    this.current,
    this.mode = ZonesMode.bar,
  });

  final String title;

  final List<ZoneShare> shares;

  /// La zone où l'on se trouve en ce moment, `null` sans mesure.
  ///
  /// Sa ligne est peinte de sa couleur, tout le long : la légende énumère un
  /// cumul, et sans repère il faut lire le chiffre du bandeau puis retrouver la
  /// ligne correspondante pour savoir où l'on ajoute du temps.
  final String? current;

  /// Ce qui remplace la pastille sur la ligne courante : un cœur ou un éclair.
  /// Les deux cartes se ressemblent trait pour trait — c'est cette icône, autant
  /// que le titre, qui dit laquelle on est en train de lire.
  final IconData currentIcon;

  /// La barre garde toute son information même sans légende — c'est ce qui
  /// permet à un profil de la poser dans une cellule de grille, où les cinq à
  /// sept lignes de la légende ne tiendraient pas.
  ///
  /// C'est un **plafond** : dans une case trop petite, la légende est retirée
  /// même si le profil la demandait (cf. [BlockMetrics.legendFits]).
  final ZonesMode mode;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = BlockMetrics.of(constraints);
        final drawn = [
          for (final share in shares)
            if (share.share > 0) share,
        ];

        // Ce que le profil demande, puis ce que la case permet. La légende part
        // la première : une proportion se lit dans une longueur partagée, donc
        // la barre survit à des tailles où le tableau ne se lirait plus.
        var withBar = mode != ZonesMode.legend;
        final withLegend = mode != ZonesMode.barOnly &&
            metrics.legendFits(
              constraints.maxHeight,
              width: constraints.maxWidth,
              zones: shares.length,
              withBar: withBar,
            );

        // Le mode `legend` suppose que la barre est ailleurs sur la page. Si sa
        // légende ne tient pas, mieux vaut la redire en barre — éventuellement
        // deux fois — que de rendre une carte vide : le doublon se voit et se
        // corrige, la case vide se lit comme une panne.
        if (!withLegend) withBar = true;

        return BlockSurface(
          metrics: metrics,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (metrics.showTitle) ...[
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: metrics.titleSize,
                  ),
                ),
                SizedBox(height: metrics.gap),
              ],
              if (withBar)
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    height: metrics.barHeight,
                    // Les parts sont converties en poids entiers : un `Expanded`
                    // ne prend qu'un `flex` entier, et arrondir au pour mille
                    // garde une zone d'une seconde visible sur une sortie de
                    // trois heures.
                    child: Row(
                      children: [
                        for (final share in drawn)
                          Expanded(
                            flex: (share.share * 1000).round().clamp(1, 1000),
                            child: ColoredBox(
                              color: zoneColorOf(share.key) ?? Colors.white24,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              if (withLegend) ...[
                if (withBar) SizedBox(height: metrics.gap),
                // Toutes les zones sont listées, y compris celles à zéro : une
                // zone absente de la légende se lirait comme une zone qui
                // n'existe pas, alors que c'est une zone qu'on n'a pas touchée —
                // l'information est exactement l'inverse.
                for (final share in shares)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _ZoneLine(
                      share: share,
                      current: share.key == current,
                      currentIcon: currentIcon,
                      metrics: metrics,
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ZoneLine extends StatelessWidget {
  const _ZoneLine({
    required this.share,
    required this.currentIcon,
    required this.metrics,
    this.current = false,
  });

  final ZoneShare share;

  /// Celle où l'on se trouve : la ligne passe sur l'aplat de sa zone.
  final bool current;

  final IconData currentIcon;

  /// Les tailles de la case. La légende n'apparaît que là où elle tient en
  /// entier, mais elle y tient à des tailles différentes : une page qui défile
  /// n'a pas les mêmes qu'une demi-grille.
  final BlockMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final color = zoneColorOf(share.key) ?? Colors.white24;
    final empty = share.share <= 0;

    // Sur l'aplat, le texte reprend la règle du bandeau — le jaune de Z3 veut
    // du noir, sans quoi c'est justement la zone qu'on surveille qui devient
    // illisible.
    final ink = current
        ? foregroundOf(color)
        : (empty ? Colors.white38 : Colors.white);
    final faded = current
        ? ink.withValues(alpha: 0.8)
        : (empty ? Colors.white38 : Colors.white70);

    // Le rembourrage est le même sur toutes les lignes, peintes ou non : la
    // zone courante change en roulant, et une ligne qui s'élargirait au passage
    // ferait sauter toute la légende sous les yeux.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: current ? color : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          // La pastille disparaîtrait dans l'aplat de sa propre couleur : sur la
          // ligne courante, elle cède la place à l'icône, qui dit « c'est ici
          // que ça se passe en ce moment » plutôt que de répéter la couleur.
          SizedBox(
            width: 12,
            height: 12,
            child: current
                ? Icon(currentIcon, size: 12, color: ink)
                : DecoratedBox(
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
          ),
          const SizedBox(width: 10),
          Text(
            share.key.toUpperCase(),
            style: TextStyle(
              color: ink,
              fontSize: metrics.lineSize,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Text(
            formatDuration(share.time),
            style: TextStyle(
              color: ink,
              fontSize: metrics.lineSize,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 44,
            child: Text(
              '${(share.share * 100).round()} %',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: faded,
                fontSize: metrics.lineSize - 1,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
