import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../recording/gps_fix.dart';
import '../nearby_pois.dart';
import '../poi_categories.dart';

/// La feuille « POI à proximité » : le pendant natif du panneau POI de la page
/// web (NavControlsPanel), masqué dans l'appli.
///
/// Deux choses : les cases de catégories (elles pilotent la carte, via
/// `setPoiFilter`) et la liste des POI visibles, triés et fléchés depuis la
/// position courante. La liste vient du site (message `pois`, déjà filtré et
/// plafonné) ; la distance et le cap sont calculés ici, à chaque tic, depuis le
/// dernier point GPS de l'enregistreur.
///
/// Une feuille et pas une page de la coquille : on la consulte à l'arrêt ou d'un
/// coup d'œil, elle se referme d'un geste, et le bandeau / le radar / le cadre
/// d'alerte restent dessous pendant qu'elle est ouverte (`showModalBottomSheet`
/// ne pousse pas de route plein écran ici).
class NearbyPoisSheet extends StatefulWidget {
  const NearbyPoisSheet({
    super.key,
    required this.notifier,
    required this.latestFix,
    required this.compassReading,
    required this.onFilter,
  });

  final NearbyPoisNotifier notifier;

  /// Le dernier point GPS accepté par l'enregistreur — même source que le chien
  /// de garde de la coquille. `null` tant qu'aucun point n'est arrivé.
  final GpsFix? Function() latestFix;

  /// `(cap corrigé, calibrage vérifié)` de la boussole, ou `null`. Sert à
  /// orienter les flèches : sans elle, elles pointent le nord.
  final ValueListenable<(double, bool)?> compassReading;

  /// Appelé avec la liste des clés de catégorie à afficher quand le cycliste
  /// coche/décoche une case.
  final void Function(List<String> visibleKeys) onFilter;

  @override
  State<NearbyPoisSheet> createState() => _NearbyPoisSheetState();
}

class _NearbyPoisSheetState extends State<NearbyPoisSheet> {
  /// Les catégories cochées. Local et pas relu du site à chaque message : les
  /// cases suivent l'intention du cycliste, la liste en dessous suit le site.
  late final Set<String> _visible = _initialVisible();

  Timer? _tick;

  Set<String> _initialVisible() {
    final filter = widget.notifier.value.filter;
    // Filtre vide (site muet, ou plus ancien que ce champ) : on montre tout,
    // jamais rien — l'erreur va vers « visible », comme pour les pages de menu.
    if (filter.isEmpty) return {for (final c in poiCategories) c.key};
    return {
      for (final entry in filter.entries)
        if (entry.value) entry.key,
    };
  }

  @override
  void initState() {
    super.initState();
    // Rafraîchit distances et flèches en roulant. La liste elle-même se
    // redessine sur le `ValueListenableBuilder` du notifier.
    _tick = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _toggle(String key) {
    setState(() {
      if (!_visible.add(key)) _visible.remove(key);
    });
    // Ordre du registre, pour un résultat stable côté page.
    widget.onFilter([
      for (final c in poiCategories)
        if (_visible.contains(c.key)) c.key,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (context, scrollController) => Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                const Icon(Icons.place_outlined),
                const SizedBox(width: 8),
                Text(
                  'POI à proximité',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final category in poiCategories)
                  FilterChip(
                    label: Text(category.label),
                    avatar: FaIcon(
                      category.icon,
                      size: 14,
                      color: _visible.contains(category.key)
                          ? category.color
                          : null,
                    ),
                    selected: _visible.contains(category.key),
                    onSelected: (_) => _toggle(category.key),
                  ),
              ],
            ),
          ),
          const Divider(height: 16),
          Expanded(
            child: ValueListenableBuilder<NearbyPois>(
              valueListenable: widget.notifier,
              builder: (context, state, _) {
                final rows = _rows(state.pois);
                if (rows.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Aucun POI autour de vous pour ces catégories.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  controller: scrollController,
                  itemCount: rows.length,
                  itemBuilder: (context, i) => _tile(rows[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Les POI à montrer : ceux des catégories cochées, triés par distance
  /// croissante. La page a déjà filtré et plafonné ; on re-filtre ici parce que
  /// les cases peuvent changer avant que le prochain message n'arrive.
  List<_PoiRow> _rows(List<NearbyPoi> pois) {
    final fix = widget.latestFix();
    final rows = <_PoiRow>[];
    for (final poi in pois) {
      final category = poiCategoryForType(poi.type);
      if (!_visible.contains(category.key)) continue;
      final distanceM = fix == null
          ? null
          : GpsFix.haversineM(fix.lat, fix.lng, poi.lat, poi.lng);
      final bearingDeg = fix == null
          ? null
          : _bearingDeg(fix.lat, fix.lng, poi.lat, poi.lng);
      rows.add(_PoiRow(
        poi: poi,
        category: category,
        distanceM: distanceM,
        bearingDeg: bearingDeg,
      ));
    }
    rows.sort((a, b) =>
        (a.distanceM ?? double.infinity).compareTo(b.distanceM ?? double.infinity));
    return rows;
  }

  Widget _tile(_PoiRow row) {
    final heading = widget.compassReading.value?.$1;
    // Flèche : cap vers le POI moins cap du cycliste (nord si pas de boussole).
    final rotation = row.bearingDeg == null
        ? null
        : ((row.bearingDeg! - (heading ?? 0)) * math.pi / 180);

    return ListTile(
      dense: true,
      leading: FaIcon(row.category.icon, color: row.category.color, size: 18),
      title: Text(row.poi.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(row.category.label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (row.distanceM != null)
            Text(
              _formatDistance(row.distanceM!),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          if (rotation != null) ...[
            const SizedBox(width: 6),
            Transform.rotate(
              angle: rotation,
              child: const Icon(Icons.navigation, size: 18),
            ),
          ],
        ],
      ),
    );
  }
}

@immutable
class _PoiRow {
  const _PoiRow({
    required this.poi,
    required this.category,
    required this.distanceM,
    required this.bearingDeg,
  });

  final NearbyPoi poi;
  final PoiCategory category;
  final double? distanceM;
  final double? bearingDeg;
}

/// Cap initial (°, 0 = nord) du point 1 vers le point 2.
double _bearingDeg(double lat1, double lng1, double lat2, double lng2) {
  final phi1 = lat1 * math.pi / 180;
  final phi2 = lat2 * math.pi / 180;
  final dLambda = (lng2 - lng1) * math.pi / 180;
  final y = math.sin(dLambda) * math.cos(phi2);
  final x = math.cos(phi1) * math.sin(phi2) -
      math.sin(phi1) * math.cos(phi2) * math.cos(dLambda);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

String _formatDistance(double m) {
  if (m < 950) return '${m.round()} m';
  return '${(m / 1000).toStringAsFixed(m < 9500 ? 1 : 0)} km';
}
