import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../dashboard/dashboard_block.dart';
import '../../dashboard/metric_id.dart';
import '../../dashboard/ride_preset.dart';
import '../blocks/averages_block.dart';
import '../blocks/change_route_block.dart';
import '../blocks/clear_route_block.dart';
import '../blocks/climb_list_block.dart';
import '../blocks/mark_lap_block.dart';
import '../blocks/metric_view.dart';
import '../blocks/nav_state_block.dart';
import '../blocks/radar_block.dart';
import '../blocks/recording_block.dart';
import '../blocks/route_block.dart';
import '../blocks/training_budget_block.dart';
import '../blocks/zones_block.dart';
import '../nav_state.dart';
import '../offline_map_state.dart';
import '../radar_severity.dart';
import '../widgets/dashboard_grid.dart';
import 'lap_list_page.dart';

/// Une page de données du tableau de bord, telle que le profil la décrit.
///
/// Elle remplace l'ancienne page Effort écrite en dur : le titre, les composants
/// et leur disposition viennent maintenant du site. Ce qui n'en vient **pas**,
/// et ne doit pas en venir, c'est le menu d'actions — c'est le seul chemin nommé
/// pour sortir d'une sortie, et un profil mal composé ne doit pas pouvoir
/// enfermer le cycliste dans son propre tableau de bord.
///
/// Opaque, et pas seulement dessinée par-dessus : la carte reste montée et
/// peinte en dessous quand le profil en a une, mais on ne doit pas la voir
/// transparaître.
class DashboardPage extends StatelessWidget {
  const DashboardPage({
    super.key,
    required this.page,
    required this.sources,
    this.radar,
    this.menuPages = const [],
    this.onOpenMenuPage,
    this.onClose,
    this.onChooseRoute,
    this.onClearRoute,
    this.offlineMap,
    this.onDownloadOffline,
    this.onCalibratePower,
    this.debugClimbActive = false,
    this.onSimulateClimb,
    this.onLeaveRide,
    this.onGridMeasured,
  });

  /// La description de la page. Jamais une [MapPageSpec] : la carte n'est pas
  /// dessinée ici, c'est le WebView au fond de la pile.
  final RidePageSpec page;

  final MetricSources sources;

  /// Nul quand le profil a coupé le radar.
  final ValueListenable<RadarView>? radar;

  /// Les pages que le profil range derrière le menu, dans son ordre.
  ///
  /// Elles s'ajoutent en tête des actions : ce sont les seules qu'on vienne
  /// chercher pour *regarder* quelque chose, les autres commandes agissent. Une
  /// page qu'on a ouverte depuis là n'en reçoit pas la liste — on referme avant
  /// d'en ouvrir une autre, plutôt que d'empiler des pages qu'on quitte ensuite
  /// une par une, en roulant.
  final List<RidePageSpec> menuPages;

  /// Ouvrir la n-ième de [menuPages]. Confiée à la coquille, qui possède la pile
  /// et sait la refermer sur une alerte.
  final ValueChanged<int>? onOpenMenuPage;

  /// Refermer cette page pour retrouver le défilement.
  ///
  /// Non nulle **seulement** sur une page ouverte depuis le menu, et c'est ce
  /// qui distingue les deux usages : une page du défilement se quitte au glissé,
  /// celle-ci n'a aucun voisin. Sans ce bouton, la seule sortie serait le bouton
  /// retour du téléphone — invisible en immersif, et le dernier geste qu'on
  /// cherche à tâtons sur un guidon.
  final VoidCallback? onClose;

  /// Changer de tracé, ou retirer celui qu'on suit. Confiés à la coquille, qui
  /// possède le WebView : la page ne sait pas naviguer, elle sait demander.
  ///
  /// Nuls dans un profil sans carte : il n'y a alors aucune page à qui les
  /// adresser, et une commande qui n'aurait que « non » à répondre vaut moins
  /// que pas de commande.
  final VoidCallback? onChooseRoute;
  final VoidCallback? onClearRoute;

  /// Où en est la carte hors-ligne du tracé affiché, poussée par la page — voir
  /// `OfflineMapNotifier`. Le téléchargement lui-même reste entièrement côté
  /// site ; ceci ne sert qu'à afficher une entrée de menu à jour (prête, en
  /// cours, périmée, en échec). Nul dans un profil sans carte, même raison que
  /// [onChooseRoute].
  final ValueListenable<OfflineMapState?>? offlineMap;

  /// Ouvrir la boîte de téléchargement hors ligne. Nulle tant qu'aucune archive
  /// n'est envisageable ici (pas de tracé suivi, ou page trop ancienne) : voir
  /// `OfflineMapState.supported`.
  final VoidCallback? onDownloadOffline;

  /// Calibrer le capteur de puissance. Fourni par la coquille seulement quand un
  /// capteur connecté sait le faire — le menu ne montre pas une commande qui
  /// n'aurait que « non » à répondre.
  final VoidCallback? onCalibratePower;

  /// Un col simulé est-il actuellement affiché par-dessus la sortie ?
  ///
  /// Change le libellé et l'icône de la commande, à la manière de « Carte hors
  /// ligne » avec son propre état — sans ça, une commande qui reste toujours
  /// « Simuler un col » ferait croire qu'elle démarre une nouvelle simulation à
  /// chaque tap plutôt que d'arrêter celle en cours.
  final bool debugClimbActive;

  /// Basculer le col de démonstration (voir climb_debug_data.dart), affiché
  /// par la coquille par-dessus la carte, le bandeau et le radar réels — pour
  /// juger la pastille et le graphique gradué dans une vraie sortie, sans
  /// attendre de grimper un col. Nulle raison de le cacher en usage normal :
  /// c'est le même genre de banc d'essai que la calibration de puissance, pas
  /// un réglage caché derrière un flag de build.
  final VoidCallback? onSimulateClimb;

  /// Rentrer : fermer la sortie et retrouver l'accueil.
  ///
  /// Écrit en toutes lettres, parce qu'un geste ne répond jamais à la question
  /// « comment on rentre ? ».
  final VoidCallback? onLeaveRide;

  /// La place qu'une grille a réellement eue, une fois posée.
  ///
  /// C'est **ici** qu'on la prend et nulle part ailleurs : le rectangle que rend
  /// `LayoutBuilder` est celui que les cellules se partagent, marges, en-tête et
  /// bandeau du bas déjà retirés. Le recalculer depuis `MediaQuery` dupliquerait
  /// cette mise en page en un second endroit, qui dériverait au premier réglage
  /// changé — et une mesure fausse vaut moins qu'une mesure absente, parce que
  /// le site la croirait.
  ///
  /// Le site s'en sert pour dimensionner les aperçus de son éditeur : il compose
  /// en lignes et en colonnes, alors que ce qui décide de ce qu'un composant
  /// peut dessiner, ce sont des pixels.
  final ValueChanged<Size>? onGridMeasured;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF16181B),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(),
              // Moins d'écart qu'avant : un titre discret n'a pas besoin d'être
              // détaché de ce qu'il nomme, et cette page ne doit pas défiler.
              const SizedBox(height: 8),
              Expanded(child: _body()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() => switch (page) {
        // La carte ne passe jamais par ici : la coquille la peint au fond de la
        // pile, et cette page-ci n'est même pas construite pour elle.
        MapPageSpec() => const SizedBox.shrink(),
        final ListPageSpec list => ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              for (final block in list.blocks)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _block(block),
                ),
            ],
          ),
        final GridPageSpec grid => DashboardGrid(
            rows: grid.rows,
            cols: grid.cols,
            cells: grid.cells,
            cellBuilder: _block,
            onMeasured: onGridMeasured,
          ),
        final LapListPageSpec laps => LapListBody(
            spec: laps,
            sources: sources,
            onGridMeasured: onGridMeasured,
          ),
      };

  /// Le composant d'un bloc. `switch` exhaustif sur la hiérarchie scellée :
  /// ajouter un composant fait échouer la compilation ici, plutôt que de le
  /// laisser disparaître silencieusement de l'écran.
  Widget _block(DashboardBlock block) => switch (block) {
        final MetricBlock metric => MetricView(
            metric: metric.metric,
            sources: sources,
            mode: metric.mode,
            // Le tap des watts ouvre la calibration : c'est là qu'on *constate*
            // une puissance qui dérive, et non dans un menu deux pages plus loin.
            onTap: _isPower(metric.metric) ? onCalibratePower : null,
          ),
        final ZonesBlock zones => ZonesCard(
            source: zones.source,
            recorder: sources.recorder,
            riderProfile: sources.riderProfile,
            mode: zones.mode,
          ),
        final AveragesBlock averages => AveragesCard(
            recorder: sources.recorder,
            riderProfile: sources.riderProfile,
            mode: averages.mode,
          ),
        final RecordingBlock recording =>
          RecordingControl(recorder: sources.recorder, mode: recording.mode),
        final MarkLapBlock markLap => MarkLapControl(
            recorder: sources.recorder,
            series: markLap.series,
            mode: markLap.mode,
          ),
        // Ces quatre-là n'ont de sens que sur une LapListPageSpec, qui les
        // rend elle-même avec le tour choisi (`LapListBody._block`) — ici, sur
        // une page ordinaire, il n'existe ni tour sélectionné à leur donner,
        // ni liste de tours à faire choisir. Posés par erreur hors d'une page
        // de tours, ils disparaissent plutôt que d'afficher des tirets qui se
        // liraient comme des mesures absentes.
        LapZonesBlock() ||
        LapAveragesBlock() ||
        LapSummaryBlock() ||
        LapSelectorBlock() =>
          const SizedBox.shrink(),
        final ChangeRouteBlock changeRoute => ChangeRouteControl(
            onChooseRoute: onChooseRoute,
            mode: changeRoute.mode,
          ),
        final ClearRouteBlock clearRoute => ClearRouteControl(
            onClearRoute: onClearRoute,
            nav: sources.nav,
            mode: clearRoute.mode,
          ),
        final RouteBlock route => RouteControl(
            onChooseRoute: onChooseRoute,
            onClearRoute: onClearRoute,
            nav: sources.nav,
            mode: route.mode,
          ),
        final NavStateBlock nav =>
          NavStateCard(nav: sources.nav, mode: nav.mode),
        final RadarBlock radarBlock =>
          RadarBlockView(radar: radar, mode: radarBlock.mode),
        final TrainingBudgetBlock budget => TrainingBudgetCard(
            budgets: sources.trainingBudget,
            recorder: sources.recorder,
            riderProfile: sources.riderProfile,
            mode: budget.mode,
          ),
        final ClimbListBlock climbs => ClimbListCard(
            routeClimbs: sources.routeClimbs,
            nav: sources.nav,
            mode: climbs.mode,
          ),
        EmptyBlock() => const SizedBox.shrink(),
      };

  static bool _isPower(MetricId metric) =>
      metric == MetricId.power || metric == MetricId.powerZone;

  /// Le titre, et le menu de l'itinéraire au bout.
  ///
  /// Ici et pas sur la carte : la carte est faite pour être regardée en roulant,
  /// et tout ce qu'on y pose vole des pixels à ce qu'on y cherche.
  ///
  /// **Discret, et plus petit que ce qu'il surplombe.** Il était à 26 gras et
  /// blanc, soit le plus gros texte de la page — plus gros que les chiffres du
  /// bandeau, qui sont pourtant ce qu'on lit à 30 km/h. Or on ne consulte jamais
  /// un titre : on sait sur quelle page on vient de glisser, il ne fait que la
  /// nommer. Il se lit donc comme une étiquette, du même gris que les titres de
  /// cartes, et rend ses pixels à la grille.
  Widget _header() {
    return Row(
      children: [
        Expanded(
          child: Text(
            page.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        // Sur une page ouverte depuis le menu : la seule commande est d'en
        // sortir. Pas de menu d'actions par-dessus — on referme d'abord, et la
        // page qu'on retrouve porte tout le reste.
        if (onClose case final close?)
          IconButton(
            onPressed: close,
            icon: const Icon(Icons.close, color: Colors.white70),
            tooltip: 'Fermer',
          )
        else if (menuPages.isNotEmpty ||
            onChooseRoute != null ||
            onClearRoute != null ||
            onDownloadOffline != null ||
            onCalibratePower != null ||
            onSimulateClimb != null ||
            onLeaveRide != null)
          _actionsMenu(),
      ],
    );
  }

  /// Les actions rares de la sortie : changer de tracé, le retirer, calibrer la
  /// puissance, rentrer.
  ///
  /// Un menu et pas des boutons : ce sont des actions rares — on part avec son
  /// itinéraire et un capteur qu'on croit juste — et des aplats de plus en tête
  /// de page attireraient le pouce au détriment de ce qu'on vient réellement
  /// chercher.
  ///
  /// « Retirer » n'apparaît que s'il y a quelque chose à retirer, et c'est la
  /// page web qui le dit : elle seule sait ce qu'elle suit vraiment, y compris
  /// un tracé restauré depuis son stockage ou une destination posée à la main
  /// sur la carte. Sans état reçu, on ne prétend pas savoir.
  Widget _actionsMenu() {
    final nav = sources.nav;
    final offline = offlineMap;

    // Sans page web, il n'y a pas d'état à écouter et le menu est fixe : un
    // `Listenable` fabriqué ici pour la forme ne serait jamais libéré.
    final listenables = <Listenable>[
      if (nav != null) nav,
      if (offline != null) offline,
    ];
    if (listenables.isEmpty) return _menuFor(null, null);

    return ListenableBuilder(
      listenable: Listenable.merge(listenables),
      builder: (context, _) => _menuFor(nav?.value, offline?.value),
    );
  }

  Widget _menuFor(NavState? state, OfflineMapState? offline) =>
      PopupMenuButton<VoidCallback>(
        icon: const Icon(Icons.more_vert, color: Colors.white70),
        tooltip: 'Actions',
        onSelected: (action) => action(),
        itemBuilder: (context) => [
          // Les pages rangées ici d'abord, et séparées de ce qui suit : ce sont
          // les seules entrées qui ouvrent quelque chose à regarder, les autres
          // agissent sur la sortie. Le titre du profil sert de libellé — c'est
          // celui qu'on a écrit dans l'éditeur, donc celui qu'on cherche.
          if (onOpenMenuPage case final open?) ...[
            for (final (index, menuPage) in menuPages.indexed)
              PopupMenuItem(
                value: () => open(index),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    switch (menuPage) {
                      GridPageSpec() => Icons.grid_view,
                      LapListPageSpec(layout: LapGridLayout()) =>
                        Icons.grid_view,
                      _ => Icons.view_agenda_outlined,
                    },
                  ),
                  title: Text(menuPage.title),
                ),
              ),
            if (menuPages.isNotEmpty) const PopupMenuDivider(),
          ],
          if (onChooseRoute case final choose?)
            PopupMenuItem(
              value: choose,
              child: const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.route),
                title: Text('Choisir un autre itinéraire'),
              ),
            ),
          if (onClearRoute case final clear? when state?.onRoute == true)
            PopupMenuItem(
              value: clear,
              child: const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.layers_clear),
                title: Text('Retirer l\'itinéraire'),
              ),
            ),
          // `offline?.supported` : pas de tracé suivi, ou page trop ancienne
          // pour connaître ce message — une commande qui n'aurait que « non »
          // à répondre ne doit pas paraître, même raison que les deux
          // commandes de tracé au-dessus.
          if (onDownloadOffline case final download?
              when offline?.supported == true)
            PopupMenuItem(
              value: download,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(offline!.downloading
                    ? Icons.downloading
                    : offline.ready && !offline.stale
                        ? Icons.offline_pin
                        : Icons.download_for_offline_outlined),
                title: const Text('Carte hors ligne'),
                subtitle: Text(_offlineSubtitle(offline)),
              ),
            ),
          if (onCalibratePower case final calibrate?)
            PopupMenuItem(
              value: calibrate,
              child: const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.bolt),
                title: Text('Calibrer la puissance'),
              ),
            ),
          if (onSimulateClimb case final simulate?)
            PopupMenuItem(
              value: simulate,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  debugClimbActive ? Icons.layers_clear : Icons.landscape,
                ),
                title: Text(
                  debugClimbActive ? 'Arrêter le col simulé' : 'Simuler un col',
                ),
              ),
            ),
          // En dernier, après un séparateur : les autres commandes restent dans
          // la sortie, celle-ci en sort. Les mettre au même rang ferait quitter
          // la navigation d'un pouce qui visait « calibrer ».
          if (onLeaveRide case final leave?) ...[
            const PopupMenuDivider(),
            PopupMenuItem(
              value: leave,
              child: const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.home_outlined),
                title: Text('Revenir à l\'accueil'),
              ),
            ),
          ],
        ],
      );

  /// Le sous-titre de l'entrée « Carte hors ligne » : où ça en est, jamais
  /// « oui/non » — c'est justement ce qui manque au panneau web pour qu'on
  /// n'ait pas besoin de l'ouvrir pour vérifier.
  static String _offlineSubtitle(OfflineMapState offline) {
    if (offline.downloading) return '${offline.pct} %';
    if (offline.errored) return 'Échec, à refaire';
    if (offline.stale) return 'Tracé modifié, à mettre à jour';
    if (offline.ready) return 'Prête';
    if (offline.mb > 0) return '~${offline.mb.toStringAsFixed(0)} Mo';
    return 'Pour rouler sans réseau';
  }
}
