import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../dashboard/block_density.dart';
import '../../dashboard/dashboard_block.dart';
import '../../ui/formats.dart';
import '../../ui/grade_colors.dart';
import '../nav_state.dart';
import '../route_climbs.dart';
import '../widgets/climb_preview_dialog.dart';
import 'block_card.dart';

/// La liste des cols du tracé, avec un repère « en cours / prochain ».
///
/// **Sans carte dans le profil, [routeClimbs] est nul** : il n'y a alors
/// aucune page web pour publier quoi que ce soit, même raison que
/// [NavStateCard]. [nav] fournit la distance déjà parcourue sur le tracé
/// (voir [traveledDistM]) : sans lui, tous les cols restent « à venir »
/// plutôt que de prétendre situer le cycliste.
class ClimbListCard extends StatelessWidget {
  const ClimbListCard({
    super.key,
    required this.routeClimbs,
    required this.nav,
    this.mode = ClimbListMode.full,
    this.color,
    this.textColor,
  });

  final ValueListenable<RouteClimbs?>? routeClimbs;
  final ValueListenable<NavState?>? nav;
  final ClimbListMode mode;

  /// Fond/texte réglés dans l'éditeur — voir [DashboardBlock.color]/
  /// [DashboardBlock.textColor]. Ne remplacent jamais la couleur de pente du
  /// repère de chaque col ([gradeColorOf]) : c'est une donnée.
  final Color? color;
  final Color? textColor;

  static const _title = 'Cols du tracé';
  static const _naturalWidth = 240.0;

  @override
  Widget build(BuildContext context) {
    final routeClimbs = this.routeClimbs;
    if (routeClimbs == null) {
      return BlockCard(
        title: _title,
        lines: const ['Ce profil roule sans carte.'],
        color: color,
        textColor: textColor,
      );
    }

    final nav = this.nav;
    return ListenableBuilder(
      listenable: Listenable.merge([routeClimbs, if (nav != null) nav]),
      builder: (context, _) {
        final list = routeClimbs.value;
        if (list == null) {
          return BlockCard(
            title: _title,
            lines: const ['Aucun tracé reçu de la page.'],
            color: color,
            textColor: textColor,
          );
        }
        if (list.climbs.isEmpty) {
          return BlockCard(
            title: _title,
            lines: const ['Ce tracé ne compte aucun col.'],
            color: color,
            textColor: textColor,
          );
        }

        final traveledM = traveledDistM(list, nav?.value);
        return mode == ClimbListMode.compact
            ? _compact(list, traveledM)
            : _full(list, traveledM);
      },
    );
  }

  Widget _compact(RouteClimbs list, double? traveledM) {
    RouteClimb? current;
    RouteClimb? next;
    for (final climb in list.climbs) {
      switch (climbStatusOf(climb, traveledM)) {
        case ClimbStatus.current:
          current = climb;
        case ClimbStatus.upcoming:
          next ??= climb;
        case ClimbStatus.done:
          break;
      }
    }

    final String line;
    if (current != null) {
      line = 'En cours : ${_named(current)}${_figures(current)}';
    } else if (next != null && traveledM != null) {
      line = 'Prochain dans '
          '${formatDistanceKm(next.startDistM - traveledM)} : '
          '${_named(next)}${_figures(next)}';
    } else {
      final n = list.climbs.length;
      line = '$n col${n > 1 ? 's' : ''} sur ce tracé';
    }

    return BlockCard(title: _title, lines: [line], color: color, textColor: textColor);
  }

  Widget _full(RouteClimbs list, double? traveledM) {
    final statuses = [
      for (final climb in list.climbs) climbStatusOf(climb, traveledM),
    ];
    final nextIndex = statuses.indexOf(ClimbStatus.upcoming);

    const metrics = BlockMetrics.natural;
    final ink = textColor ?? Colors.white;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.hasBoundedWidth
            ? constraints.maxWidth - metrics.padding * 2
            : _naturalWidth;
        return BlockSurface(
          background: color,
          child: SizedBox(
            width: width,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _title.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: ink.withValues(alpha: 0.7),
                    fontSize: metrics.titleSize,
                  ),
                ),
                SizedBox(height: metrics.gap),
                for (var i = 0; i < list.climbs.length; i++)
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: i == list.climbs.length - 1 ? 0 : metrics.gap * 0.7,
                    ),
                    child: _ClimbRow(
                      index: i + 1,
                      climb: list.climbs[i],
                      status: statuses[i],
                      isNext: i == nextIndex,
                      baseInk: ink,
                      onTap: () => showClimbPreview(
                        context,
                        climb: list.climbs[i],
                        index: i + 1,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Préfixe le nom du col donné à la main, vide sinon : un col jamais nommé
  // retombe sur la seule ligne de chiffres, comme avant ce champ.
  static String _named(RouteClimb climb) =>
      climb.name == null ? '' : '${climb.name} · ';

  static String _figures(RouteClimb climb) =>
      '${formatDistanceKm(climb.lengthM)} · ${climb.gainM.round()} m D+ · '
      '${climb.avgGrade.round()} % moy';
}

/// Une ligne de la liste : le col, sa couleur de pente moyenne (même table que
/// le profil gradué, [gradeColorOf]), et son repère de statut.
class _ClimbRow extends StatelessWidget {
  const _ClimbRow({
    required this.index,
    required this.climb,
    required this.status,
    required this.isNext,
    required this.onTap,
    this.baseInk = Colors.white,
  });

  final int index;
  final RouteClimb climb;
  final ClimbStatus status;
  final bool isNext;
  final VoidCallback onTap;

  /// Le texte réglé dans l'éditeur, ou blanc — voir [ClimbListCard.textColor].
  final Color baseInk;

  @override
  Widget build(BuildContext context) {
    const metrics = BlockMetrics.natural;
    final done = status == ClimbStatus.done;

    return Opacity(
      // Un col déjà grimpé reste lisible, mais s'efface au profit de ceux qui
      // restent : c'est sur eux qu'on revient en roulant.
      opacity: done ? 0.5 : 1,
      // Le tap prévisualise le graphique gradué de CE col, qu'il soit déjà
      // grimpé, en cours ou encore à venir — voir showClimbPreview. Un col
      // n'a rien de plus à faire au tap : pas de sélection, pas de navigation.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 10,
              height: 10,
              margin: const EdgeInsets.only(top: 5),
              decoration: BoxDecoration(
                color: gradeColorOf(climb.avgGrade),
                shape: BoxShape.circle,
              ),
            ),
            SizedBox(width: metrics.gap * 0.6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          '${climb.name ?? 'Col $index'}'
                          '${climb.category == null ? '' : ' · Cat. ${climb.category}'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: baseInk,
                            fontWeight: FontWeight.w600,
                            fontSize: metrics.lineSize,
                          ),
                        ),
                      ),
                      if (status == ClimbStatus.current || isNext) ...[
                        SizedBox(width: metrics.gap * 0.5),
                        _StatusChip(current: status == ClimbStatus.current),
                      ],
                    ],
                  ),
                  Text(
                    '${formatDistanceKm(climb.lengthM)} · '
                    '${climb.gainM.round()} m D+ · '
                    '${climb.avgGrade.round()} % moy',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: baseInk.withValues(alpha: 0.6),
                      fontSize: metrics.unitSize,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// « EN COURS », pleine et orange — c'est là qu'on est. « PROCHAIN », en
/// liseré seulement — c'est ce qui vient, pas encore ce qui compte.
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.current});

  final bool current;

  @override
  Widget build(BuildContext context) {
    const metrics = BlockMetrics.natural;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: current ? const Color(0xFFF97316) : Colors.transparent,
        border: current ? null : Border.all(color: Colors.white38),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        current ? 'EN COURS' : 'PROCHAIN',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: metrics.unitSize * 0.75,
        ),
      ),
    );
  }
}
