import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../dashboard/dashboard_block.dart';
import '../../dashboard/grid_layout.dart';
import '../../dashboard/metric_id.dart';
import '../../dashboard/ride_preset.dart';
import '../blocks/averages_block.dart';
import '../blocks/metric_view.dart';
import '../blocks/nav_state_block.dart';
import '../blocks/radar_block.dart';
import '../blocks/recording_block.dart';
import '../blocks/zones_block.dart';
import '../nav_state.dart';
import '../radar_severity.dart';

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
    this.onChooseRoute,
    this.onClearRoute,
    this.onCalibratePower,
    this.onLeaveRide,
  });

  /// La description de la page. Jamais une [MapPageSpec] : la carte n'est pas
  /// dessinée ici, c'est le WebView au fond de la pile.
  final RidePageSpec page;

  final MetricSources sources;

  /// Nul quand le profil a coupé le radar.
  final ValueListenable<RadarView>? radar;

  /// Changer de tracé, ou retirer celui qu'on suit. Confiés à la coquille, qui
  /// possède le WebView : la page ne sait pas naviguer, elle sait demander.
  ///
  /// Nuls dans un profil sans carte : il n'y a alors aucune page à qui les
  /// adresser, et une commande qui n'aurait que « non » à répondre vaut moins
  /// que pas de commande.
  final VoidCallback? onChooseRoute;
  final VoidCallback? onClearRoute;

  /// Calibrer le capteur de puissance. Fourni par la coquille seulement quand un
  /// capteur connecté sait le faire — le menu ne montre pas une commande qui
  /// n'aurait que « non » à répondre.
  final VoidCallback? onCalibratePower;

  /// Rentrer : fermer la sortie et retrouver l'accueil.
  ///
  /// Écrit en toutes lettres, parce qu'un geste ne répond jamais à la question
  /// « comment on rentre ? ».
  final VoidCallback? onLeaveRide;

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
              const SizedBox(height: 16),
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
        final GridPageSpec grid => _grid(grid),
      };

  /// La grille : chaque cellule à son rectangle, calculé par [gridRectsFor].
  ///
  /// `LayoutBuilder` + `Positioned` plutôt qu'un `Table` — qui ne sait pas
  /// fusionner sans imbriquer — et surtout **pas un `GridView`**, qui défile
  /// alors que cette page ne doit justement pas défiler : elle se lit en
  /// roulant, tout doit tenir à l'écran.
  Widget _grid(GridPageSpec grid) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          final rects = gridRectsFor(
            [for (final cell in grid.cells) cell.span],
            rows: grid.rows,
            cols: grid.cols,
            size: size,
          );

          return Stack(
            children: [
              for (var i = 0; i < grid.cells.length; i++)
                Positioned.fromRect(
                  rect: rects[i],
                  child: _block(grid.cells[i].block),
                ),
            ],
          );
        },
      ),
    );
  }

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
        final AveragesBlock averages =>
          AveragesCard(recorder: sources.recorder, mode: averages.mode),
        final RecordingBlock recording =>
          RecordingControl(recorder: sources.recorder, mode: recording.mode),
        final NavStateBlock nav =>
          NavStateCard(nav: sources.nav, mode: nav.mode),
        final RadarBlock radarBlock =>
          RadarBlockView(radar: radar, mode: radarBlock.mode),
        EmptyBlock() => const SizedBox.shrink(),
      };

  static bool _isPower(MetricId metric) =>
      metric == MetricId.power || metric == MetricId.powerZone;

  /// Le titre, et le menu de l'itinéraire au bout.
  ///
  /// Ici et pas sur la carte : la carte est faite pour être regardée en roulant,
  /// et tout ce qu'on y pose vole des pixels à ce qu'on y cherche.
  Widget _header() {
    return Row(
      children: [
        Expanded(
          child: Text(
            page.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (onChooseRoute != null ||
            onClearRoute != null ||
            onCalibratePower != null ||
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

    // Sans page web, il n'y a pas d'état à écouter et le menu est fixe : un
    // `ValueNotifier` fabriqué ici pour la forme ne serait jamais libéré.
    if (nav == null) return _menuFor(null);

    return ValueListenableBuilder<NavState?>(
      valueListenable: nav,
      builder: (context, state, _) => _menuFor(state),
    );
  }

  Widget _menuFor(NavState? state) => PopupMenuButton<VoidCallback>(
        icon: const Icon(Icons.more_vert, color: Colors.white70),
        tooltip: 'Actions',
        onSelected: (action) => action(),
        itemBuilder: (context) => [
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
          if (onCalibratePower case final calibrate?)
            PopupMenuItem(
              value: calibrate,
              child: const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.bolt),
                title: Text('Calibrer la puissance'),
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
}
