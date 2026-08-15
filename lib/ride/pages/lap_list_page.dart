import 'package:flutter/material.dart';

import '../../dashboard/dashboard_block.dart';
import '../../dashboard/metric_id.dart';
import '../../dashboard/ride_preset.dart';
import '../../recording/ride_lap.dart';
import '../blocks/averages_block.dart';
import '../blocks/lap_summary_block.dart';
import '../blocks/mark_lap_block.dart';
import '../blocks/metric_view.dart';
import '../blocks/zones_block.dart';
import '../climb_profile.dart' show climbLapSeries;
import '../route_climbs.dart';
import '../widgets/dashboard_grid.dart';

/// Le corps d'une page de tours : ses composants, dont le sélecteur de tour
/// s'il en porte un.
///
/// **Le sélecteur n'est plus un en-tête imposé** : c'est un composant
/// ([LapSelectorBlock]) comme un autre, posé où l'éditeur l'a mis. La version
/// d'avant le dessinait d'office au-dessus de la page, et sa hauteur n'était
/// alors comptée nulle part — une page Tours en grille se retrouvait avec
/// moins de place que ce que l'éditeur avait composé, et la grille semblait
/// décalée une fois sur le téléphone. En le rendant plaçable, la page tient
/// tout entière dans ce qu'elle déclare (`rows` × `cols`, ou sa liste), sans
/// rien de caché.
///
/// `StatefulWidget` parce que c'est le seul endroit du tableau de bord qui a
/// besoin d'un état mutable en dehors de `RidePageSpec`/`DashboardBlock`
/// (immuables, décodés une fois du document du site) — le tour sélectionné.
/// Une occurrence par page : deux pages de tours, sur la même série ou non,
/// gardent chacune son propre choix.
class LapListBody extends StatefulWidget {
  const LapListBody({
    super.key,
    required this.spec,
    required this.sources,
    this.onGridMeasured,
  });

  final LapListPageSpec spec;
  final MetricSources sources;

  /// Passé tel quel à [DashboardGrid] quand [LapListPageSpec.layout] est une
  /// [LapGridLayout] : même contrat que la grille de mesures, la taille
  /// mesurée ne dépend pas de ce que la grille contient.
  final ValueChanged<Size>? onGridMeasured;

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

        return _body(laps, selected);
      },
    );
  }

  /// Une liste défilante ([LapBlocksLayout], le cas d'avant ce chantier) ou
  /// une grille qui tient tout entière ([LapGridLayout]) — même choix, et
  /// pour la même raison, qu'entre [ListPageSpec] et [GridPageSpec] sur une
  /// page de mesures.
  Widget _body(List<RideLap> laps, int selected) =>
      switch (widget.spec.layout) {
        final LapBlocksLayout list => ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              for (final block in list.blocks)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _block(block, laps: laps, selected: selected),
                ),
            ],
          ),
        final LapGridLayout grid => DashboardGrid(
            rows: grid.rows,
            cols: grid.cols,
            cells: grid.cells,
            dividers: grid.dividers,
            cellBuilder: (block) =>
                _block(block, laps: laps, selected: selected),
            onMeasured: widget.onGridMeasured,
          ),
      };

  /// Le contrôle fermé : le fond anthracite des cartes, et un tap ouvre le
  /// choix en plein écran plutôt qu'un menu qui se referme au moindre cahot
  /// avant qu'on ait pu viser la bonne ligne — voir [_LapPickerPage].
  Widget _selector(
    List<RideLap> laps,
    int selected, {
    Color? color,
    Color? textColor,
  }) {
    final ink = textColor ?? Colors.white;

    return Material(
      color: color ?? const Color(0xFF1F2226),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _pickLap(laps, selected),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _lapLabel(laps, selected, series: widget.spec.series,
                      routeClimbs: widget.sources.routeClimbs?.value),
                  style: TextStyle(color: ink, fontSize: 16),
                ),
              ),
              Icon(Icons.arrow_drop_down, color: ink.withValues(alpha: 0.7)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickLap(List<RideLap> laps, int selected) async {
    final routeClimbs = widget.sources.routeClimbs?.value;
    final labels = [
      for (var i = 0; i < laps.length; i++)
        _lapLabel(laps, i, series: widget.spec.series, routeClimbs: routeClimbs),
    ];
    final picked = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _LapPickerPage(labels: labels, selected: selected),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _selectedIndex = picked);
  }

  /// `switch` **non exhaustif** — délibérément, contrairement à celui de
  /// `DashboardPage._block()` : un composant sans intérêt sur une page de
  /// tours (changer d'itinéraire…) disparaît plutôt que d'afficher quelque
  /// chose qui n'a pas de sens ici, même tolérance qu'une clé inconnue.
  ///
  /// `MetricBlock` se dessine ici comme partout ailleurs (même `MetricView`),
  /// mais avec `sources` **borné au tour affiché**
  /// ([MetricSources.forLap]) : une mesure cumulée (durée, distance,
  /// dénivelé, moyenne, calories, TSS…) lit alors *ce tour*, pas la sortie
  /// entière — c'est tout l'intérêt de la poser ici plutôt que sur une page
  /// de mesures ordinaire. Une mesure instantanée (cardio, cadence, vitesse
  /// du moment…) reste celle de maintenant, tour affiché ou non : voir
  /// `MetricId.read`.
  ///
  /// `MarkLapBlock` **fait exception** et se dessine comme partout ailleurs :
  /// c'est en consultant les tours qu'on a le plus de raisons d'en marquer un
  /// nouveau. Sa série (`markLap.series`) n'a par contre **aucun lien** avec
  /// celle de la page (`widget.spec.series`) — ce sont deux réglages
  /// indépendants de l'éditeur, et rien ici ne les assortit. Un bouton posé
  /// avec une série différente de celle affichée marque bien un tour, mais
  /// pas dans la liste qu'on a sous les yeux ; c'est à l'éditeur du site de
  /// les poser cohérents.
  Widget _block(
    DashboardBlock block, {
    required List<RideLap> laps,
    required int selected,
  }) {
    // Seul `LapSelectorBlock` a besoin de la liste entière : les autres ne
    // lisent que le tour déjà choisi.
    if (block is LapSelectorBlock) {
      return _selector(laps, selected, color: block.color, textColor: block.textColor);
    }

    final lap = laps[selected];
    return switch (block) {
      final MetricBlock metric => MetricView(
          metric: metric.metric,
          sources: widget.sources.forLap(lap),
          layout: metric.layout,
          format: metric.format,
          icon: metric.icon,
          label: metric.label,
          min: metric.min,
          max: metric.max,
          color: metric.color,
          textColor: metric.textColor,
        ),
      final LapZonesBlock zones => ZonesCard(
          source: zones.source,
          recorder: widget.sources.recorder,
          riderProfile: widget.sources.riderProfile,
          mode: zones.mode,
          statsOverride: lap.stats,
          color: zones.color,
          textColor: zones.textColor,
        ),
      final LapAveragesBlock averages => AveragesCard(
          recorder: widget.sources.recorder,
          riderProfile: widget.sources.riderProfile,
          mode: averages.mode,
          statsOverride: lap.stats,
          color: averages.color,
          textColor: averages.textColor,
        ),
      final LapSummaryBlock summary => LapSummaryCard(
          lap: lap,
          riderProfile: widget.sources.riderProfile,
          mode: summary.mode,
          color: summary.color,
          textColor: summary.textColor,
        ),
      final MarkLapBlock markLap => MarkLapControl(
          recorder: widget.sources.recorder,
          series: markLap.series,
          mode: markLap.mode,
          color: markLap.color,
          textColor: markLap.textColor,
        ),
      _ => const SizedBox.shrink(),
    };
  }
}

/// Le libellé d'un tour : « en cours » pour le dernier, seul encore ouvert.
/// Partagé entre le contrôle fermé et la page de choix, pour qu'ils ne
/// disent jamais deux choses différentes du même tour.
///
/// Sur la série `cols` (`climbLapSeries`), un tour qui couvre une montée
/// ([RideLap.climbId] posé) reprend **le nom du col**, comme le composant
/// Cols du tracé ([ClimbListCard]) — même repli « Col N » quand il n'a jamais
/// été renommé côté site, et le même N : la position du col dans
/// [RouteClimbs.climbs], pas l'index du tour. Un tracé entre deux cols, sans
/// [RideLap.climbId], garde « Tour N » — nommer aussi ces tours-là suggérerait
/// une montée qui n'existe pas.
String _lapLabel(
  List<RideLap> laps,
  int index, {
  required String series,
  RouteClimbs? routeClimbs,
}) {
  final suffix = index == laps.length - 1 ? ' (en cours)' : '';

  if (series == climbLapSeries && routeClimbs != null) {
    final climbId = laps[index].climbId;
    final climbIndex = climbId == null
        ? -1
        : routeClimbs.climbs.indexWhere((climb) => climb.id == climbId);
    if (climbIndex != -1) {
      final climb = routeClimbs.climbs[climbIndex];
      return '${climb.name ?? 'Col ${climbIndex + 1}'}$suffix';
    }
  }

  return 'Tour ${index + 1}$suffix';
}

/// Le choix d'un tour en plein écran.
///
/// Un menu déroulant classique se referme au premier tressaut du guidon avant
/// qu'on ait pu viser la bonne ligne, et ses lignes sont trop serrées pour un
/// doigt qui vise mal sur une route bosselée. Ici chaque tour occupe toute la
/// largeur de l'écran : une seule cible possible, impossible à manquer.
class _LapPickerPage extends StatelessWidget {
  const _LapPickerPage({required this.labels, required this.selected});

  /// Un libellé par tour, déjà résolu ([_lapLabel]) — cette page n'a pas
  /// besoin de connaître les cols du tracé pour se contenter de les afficher.
  final List<String> labels;
  final int selected;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Choisir un tour'),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        // Du dernier tour au premier : c'est celui qu'on vient de rouler
        // qu'on cherche le plus souvent, autant l'avoir sous le pouce sans
        // faire défiler toute la sortie.
        itemCount: labels.length,
        itemBuilder: (context, i) => _tile(context, labels.length - 1 - i),
      ),
    );
  }

  Widget _tile(BuildContext context, int index) {
    final isSelected = index == selected;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: isSelected ? const Color(0xFF2E7D32) : const Color(0xFF1F2226),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.of(context).pop(index),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    labels[index],
                    style: const TextStyle(color: Colors.white, fontSize: 18),
                  ),
                ),
                if (isSelected)
                  const Icon(Icons.check, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
