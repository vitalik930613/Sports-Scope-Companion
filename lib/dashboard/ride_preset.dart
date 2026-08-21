import 'package:flutter/foundation.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../ble/sensor_profile.dart';
import '../lighting/auto_lighting.dart';
import '../navigation/screen_dimmer.dart';
import 'companion_icons.dart';
import 'dashboard_block.dart';
import 'grid_layout.dart';
import 'metric_id.dart';

/// Un profil de sortie : le tableau de bord et les réglages d'une pratique.
///
/// Route, VTT, home-trainer n'ont ni les mêmes mesures utiles, ni le même besoin
/// de carte, ni les mêmes capteurs. Le site les décrit, l'appli les applique, et
/// **le choix se fait au départ** — on sait sur quel vélo on monte au moment où
/// l'on monte dessus, pas la veille devant un navigateur.
///
/// Tout ce qui sort de [parse] est **déjà sain** : il n'existe pas d'instance
/// dont les pages débordent, dont deux cellules se recouvrent ou dont le bandeau
/// a six cases. Les garanties sont énumérées sur chaque champ, et chacune est
/// gardée par un test.
@immutable
class RidePreset {
  const RidePreset({
    required this.key,
    required this.name,
    this.description,
    required this.pages,
    required this.bands,
    this.notch = const [],
    this.sensors = const SensorSettings(),
    this.radar = const RadarSettings(),
    this.battery = const BatterySettings(),
    this.climb = const ClimbSettings(),
    this.workout = const WorkoutSettings(),
    this.lighting = const LightingSettings(),
    this.screen = const ScreenSettings(),
    this.traveledPath = const TraveledPathSettings(),
    this.buttons = const ButtonSettings(),
    this.reminders = const [],
  });

  /// Le tableau de bord d'aujourd'hui, mot pour mot.
  ///
  /// C'est le filet de sécurité de toute la chaîne : première installation, site
  /// injoignable, document illisible, profil vidé de ses pages. Il ne peut pas
  /// être vide, il ne dépend d'aucun réseau, et il donne exactement ce que
  /// l'appli donnait avant ce chantier — donc rien de nouveau à apprendre le
  /// jour où le reste tombe.
  static const builtIn = RidePreset(
    key: 'default',
    name: 'Sortie',
    pages: [
      MapPageSpec(),
      ListPageSpec(
        title: 'Effort',
        blocks: [
          ListBlockPlacement(block: RecordingBlock()),
          ListBlockPlacement(block: ZonesBlock(source: ZonesSource.hr)),
          ListBlockPlacement(block: ZonesBlock(source: ZonesSource.power)),
          ListBlockPlacement(block: AveragesBlock()),
          ListBlockPlacement(block: NavStateBlock()),
        ],
      ),
    ],
    bands: [
      RideBandSpec([
        BandMetricSlot(MetricId.duration),
        BandMetricSlot(MetricId.distance),
        BandMetricSlot(MetricId.speed),
        BandMetricSlot(MetricId.power),
      ]),
      RideBandSpec([
        BandMetricSlot(MetricId.heartRate),
        BandMetricSlot(MetricId.hrZone),
        BandMetricSlot(MetricId.power),
        BandMetricSlot(MetricId.powerZone),
      ]),
    ],
  );

  final String key;
  final String name;

  /// Libre, facultative : ce que l'utilisateur a écrit sur le site pour se
  /// souvenir, au départ, pourquoi ce profil-là plutôt qu'un autre. Affichée
  /// telle quelle dans le sélecteur ([NavigationPickerSheet]) — c'est son seul
  /// usage, elle ne pilote rien dans le tableau de bord.
  final String? description;

  /// Les pages, **dans l'ordre où on les fait défiler**. Au moins une, au plus
  /// une carte.
  final List<RidePageSpec> pages;

  /// Les jeux de valeurs du bandeau, dans l'ordre. Au moins un.
  final List<RideBandSpec> bands;

  /// Les jeux de la bande de l'encoche, dans l'ordre — même forme que [bands],
  /// un glissé horizontal fait défiler l'un vers l'autre. Contrairement à
  /// [bands], une liste vide est une valeur normale — un profil qui n'a
  /// jamais touché ce réglage garde un écran identique à celui d'avant qu'il
  /// existe.
  final List<NotchSpec> notch;

  final SensorSettings sensors;
  final RadarSettings radar;
  final BatterySettings battery;
  final ClimbSettings climb;
  final WorkoutSettings workout;
  final LightingSettings lighting;
  final ScreenSettings screen;

  /// Style du trajet réellement parcouru, tel que dessiné par la page — voir
  /// `TraveledPathTracker` (`lib/navigation/traveled_path_tracker.dart`) côté
  /// appli. L'appli ne dessine rien elle-même, elle ne fait que transmettre
  /// ces valeurs telles quelles au pont.
  final TraveledPathSettings traveledPath;

  /// Ce que chaque geste sur chaque canal du D-Fly (Di2) déclenche — voir
  /// `Di2ButtonGesturePolicy` (`lib/ride/`) pour la classification du geste,
  /// et `RideShellPage._performButtonAction` pour l'exécution.
  final ButtonSettings buttons;

  /// Les rappels périodiques — boire, manger, entamer une intervalle — voir
  /// `RideReminderPolicy` (`lib/ride/reminder_policy.dart`) pour le
  /// déclenchement. Une liste vide est une valeur normale, même raison que
  /// [notch] : un profil qui n'a jamais touché ce réglage garde un écran
  /// identique à celui d'avant qu'il existe.
  final List<ReminderSpec> reminders;

  /// Les pages qu'on fait défiler, dans l'ordre.
  List<RidePageSpec> get ridePages {
    final promoted = _promotedPage;
    return [
      for (final page in pages)
        if (!page.menu || identical(page, promoted)) page,
    ];
  }

  /// Les pages rangées derrière le menu d'actions.
  ///
  /// On va les chercher au lieu de tomber dessus : c'est ce qui rend tenable une
  /// page qu'on ne lit **pas** en roulant — un bilan, des répartitions — sans la
  /// mettre à un glissé de la carte.
  List<RidePageSpec> get menuPages {
    final promoted = _promotedPage;
    return [
      for (final page in pages)
        if (page.menu && !identical(page, promoted)) page,
    ];
  }

  /// La page rangée qu'on rend malgré tout au défilement, ou `null` — le cas
  /// ordinaire.
  ///
  /// Une page rangée derrière le menu doit rester joignable, et il y faut une
  /// page du défilement **qui ne soit pas la carte** : c'est l'en-tête d'une
  /// page de données qui porte le menu, la carte n'en dessine pas (tout ce
  /// qu'on y poserait volerait des pixels à ce qu'on y cherche). Deux façons de
  /// se retrouver sans rien, donc, et la seconde est la sournoise :
  ///
  ///  • tout ranger derrière le menu — il ne resterait rien à faire défiler ;
  ///  • ne laisser que la carte — le défilement existe, mais aucune de ses
  ///    pages n'a de menu, et ce qu'on avait rangé n'est atteignable par aucun
  ///    geste.
  ///
  /// Dans les deux cas, la première page rangée reprend sa place. Même règle
  /// côté site (`keep_one_swipeable`), et un test de chaque côté.
  RidePageSpec? get _promotedPage {
    if (pages.any((page) => !page.menu && page is! MapPageSpec)) return null;

    for (final page in pages) {
      if (page.menu) return page;
    }
    // Rien de rangé : un profil qui n'a qu'une carte n'a rien à repêcher.
    return null;
  }

  /// Où se trouve la carte **dans [ridePages]**, `null` quand le profil n'en a
  /// pas.
  ///
  /// C'est ce qui remplace l'ancien « la carte est la page 0 » : elle se place
  /// où l'on veut, et un profil de home-trainer s'en passe complètement.
  ///
  /// L'index porte sur le défilement et non sur [pages] : c'est ce que
  /// manipulent le `PageView`, les pastilles du bandeau et le retour
  /// automatique. Une carte ne peut de toute façon pas être derrière le menu
  /// ([MapPageSpec.menu] est faux par construction), les deux index ne
  /// divergent donc que par les pages rangées avant elle.
  int? get mapPageIndex {
    final swipe = ridePages;
    for (var i = 0; i < swipe.length; i++) {
      if (swipe[i] is MapPageSpec) return i;
    }
    return null;
  }

  bool get hasMap => mapPageIndex != null;

  /// Toutes les clés de série de tours que ce profil peut produire — celles
  /// des pages de tours et celles des boutons « marquer un tour », où qu'ils
  /// soient posés (grille comprise). Sert à peupler `RideRecorder.start`
  /// (paramètre `lapSeries`) : une série doit exister dès le départ de la
  /// sortie, pas seulement à son premier tour marqué, sous peine de perdre ce
  /// qui la précède.
  Set<String> get lapSeries {
    final keys = <String>{};

    void collect(DashboardBlock block) {
      if (block is MarkLapBlock) keys.add(block.series);
    }

    for (final page in pages) {
      switch (page) {
        case LapListPageSpec(:final series, :final layout):
          keys.add(series);
          switch (layout) {
            case LapBlocksLayout(:final blocks):
              for (final placement in blocks) {
                collect(placement.block);
              }
            case LapGridLayout(:final cells):
              for (final cell in cells) {
                collect(cell.block);
              }
          }
        case ListPageSpec(:final blocks):
          for (final placement in blocks) {
            collect(placement.block);
          }
        case GridPageSpec(:final cells):
          for (final cell in cells) {
            collect(cell.block);
          }
        case MapPageSpec():
          break;
      }
    }

    return keys;
  }

  /// Décode un profil du document, ou `null` s'il n'en reste rien d'utilisable.
  static RidePreset? parse(Object? raw) {
    if (raw is! Map) return null;
    final key = raw['key'];
    if (key is! String || key.isEmpty) return null;

    final pages = _pages(raw['pages']);
    final bands = _bands(raw['bands']);

    return RidePreset(
      key: key,
      name: raw['name'] is String && (raw['name'] as String).trim().isNotEmpty
          ? (raw['name'] as String).trim()
          : key,
      description:
          raw['description'] is String && (raw['description'] as String).trim().isNotEmpty
              ? (raw['description'] as String).trim()
              : null,
      // Un profil vidé de toutes ses pages retombe sur la page Effort intégrée :
      // on ne monte jamais une coquille sans contenu, et un écran noir en pleine
      // sortie ne se diagnostique pas au guidon.
      pages: pages.isEmpty ? [RidePreset.builtIn.pages.last] : pages,
      bands: bands.isEmpty ? RidePreset.builtIn.bands : bands,
      notch: _notch(raw['notch']),
      sensors: SensorSettings.parse(raw['sensors']),
      radar: RadarSettings.parse(raw['radar']),
      battery: BatterySettings.parse(raw['battery']),
      climb: ClimbSettings.parse(raw['climb']),
      workout: WorkoutSettings.parse(raw['workout']),
      lighting: LightingSettings.parse(raw['lighting']),
      screen: ScreenSettings.parse(raw['screen']),
      traveledPath: TraveledPathSettings.parse(raw['traveled_path']),
      buttons: ButtonSettings.parse(raw['buttons']),
      reminders: _reminders(raw['reminders']),
    );
  }

  /// Les pages du document, **au plus une carte**.
  ///
  /// Les cartes suivantes sont retirées : deux cartes voudraient dire deux
  /// identités pour un seul WebView, alors que l'instance MapLibre est unique et
  /// doit le rester (la démonter coûte le pointeur de virage, la progression et
  /// les tuiles en mémoire).
  static List<RidePageSpec> _pages(Object? raw) {
    if (raw is! List) return const [];

    final pages = <RidePageSpec>[];
    var mapSeen = false;

    for (final entry in raw) {
      final page = RidePageSpec.parse(entry);
      if (page == null) continue;
      if (page is MapPageSpec) {
        if (mapSeen) continue;
        mapSeen = true;
      }
      pages.add(page);
    }

    return pages;
  }

  static List<RideBandSpec> _bands(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final entry in raw)
        if (RideBandSpec.parse(entry) case final band?) band,
    ];
  }

  static List<NotchSpec> _notch(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final entry in raw)
        if (NotchSpec.parse(entry) case final set?) set,
    ];
  }

  /// Au plus [ReminderSpec.maxCount] : le site borne déjà, mais l'appli
  /// applique ses propres garanties en silence, sur la route, comme partout
  /// ailleurs dans ce document — voir l'entête de [parse].
  static List<ReminderSpec> _reminders(Object? raw) {
    if (raw is! List) return const [];
    final reminders = <ReminderSpec>[];
    for (final entry in raw) {
      if (reminders.length == ReminderSpec.maxCount) break;
      if (ReminderSpec.parse(entry) case final reminder?) reminders.add(reminder);
    }
    return reminders;
  }
}

/// Une page du tableau de bord.
///
/// Trois genres, et pas un seul : la carte n'est pas une grille, et une grille
/// n'est pas une liste. Ce qui les sépare vraiment, c'est le **défilement** —
/// une grille se lit en roulant et doit tenir tout entière, une liste se
/// consulte à l'arrêt et peut être longue.
@immutable
sealed class RidePageSpec {
  const RidePageSpec({
    required this.title,
    this.menu = false,
    this.menuCondition,
    this.menuAutoOpen = false,
    this.icon,
    this.key,
  });

  final String title;

  /// Identifiant stable, choisi sur le site — `null` si le document ne le
  /// fournit pas (contrat plus ancien, ou page qui n'a jamais eu besoin
  /// d'être visée). Contrairement à [title], libre et pas garanti unique,
  /// c'est la seule façon de désigner une page qui survive à une réédition du
  /// profil : un bouton Di2 configuré en « aller à la page X »
  /// (`GoToPageAction`) s'y résout, jamais à un index qui se décale dès que
  /// les pages sont réordonnées.
  final String? key;

  /// L'icône choisie dans l'éditeur pour repérer cette page dans le menu ⋮
  /// (`DashboardPage._menuFor`) — `null` quand la clé est absente ou inconnue
  /// de cette version, et alors le menu retombe sur l'icône déduite du genre
  /// de page (grille ou liste), comme avant ce réglage. Même registre que les
  /// icônes de composant ([companionIcons]) : une seule liste blanche des deux
  /// côtés plutôt qu'un vocabulaire de plus à tenir à jour.
  final FaIconData? icon;

  /// Rangée derrière le menu d'actions plutôt que dans le défilement.
  ///
  /// **Faux par défaut, y compris quand la clé manque** : un document plus
  /// ancien que l'appli garde ses pages là où elles étaient, et une appli plus
  /// ancienne qu'un document ignore la clé et les montre toutes. L'erreur va
  /// donc toujours vers « visible », jamais vers « introuvable » — c'est le seul
  /// sens acceptable pour une page qu'on aurait composée exprès.
  final bool menu;

  /// Seulement quand [menu] est vrai : fait rejoindre le défilement à cette
  /// page, le temps que la condition dure — voir
  /// `RideShellPage._updateConditionalPages`. `null` (absente ou inconnue du
  /// contrat) laisse la page purement statique, comme avant ce réglage.
  final PageMenuCondition? menuCondition;

  /// Bascule automatiquement dessus quand [menuCondition] devient vraie,
  /// plutôt que de seulement la faire rejoindre le défilement. Sans effet si
  /// [menuCondition] est `null`.
  final bool menuAutoOpen;

  static RidePageSpec? parse(Object? raw) {
    if (raw is! Map) return null;
    final title = raw['title'] is String ? raw['title'] as String : null;
    final menu = raw['menu'] == true;
    final menuCondition = PageMenuCondition.parse(raw['menu_condition']);
    final menuAutoOpen = raw['menu_auto_open'] == true;
    final icon = companionIconFor(raw['icon'] is String ? raw['icon'] as String : null);
    final key = raw['key'] is String && (raw['key'] as String).isNotEmpty
        ? raw['key'] as String
        : null;

    return switch (raw['kind']) {
      // Jamais derrière le menu, et pas par oubli : la carte est le WebView
      // peint au fond de la pile pour toute la sortie, pas une page qu'on ouvre
      // et qu'on referme. Elle ne paraît donc jamais dans le menu ⋮ et n'a pas
      // besoin de son icône.
      'map' => MapPageSpec(key: key),
      'grid' => GridPageSpec.parse(
          raw,
          title: title,
          menu: menu,
          menuCondition: menuCondition,
          menuAutoOpen: menuAutoOpen,
          icon: icon,
          key: key,
        ),
      'list' => ListPageSpec.parse(
          raw,
          title: title,
          menu: menu,
          menuCondition: menuCondition,
          menuAutoOpen: menuAutoOpen,
          icon: icon,
          key: key,
        ),
      'laps' => LapListPageSpec.parse(
          raw,
          title: title,
          menu: menu,
          menuCondition: menuCondition,
          menuAutoOpen: menuAutoOpen,
          icon: icon,
          key: key,
        ),
      _ => null,
    };
  }
}

/// Les conditions de sortie qu'une page rangée derrière le menu peut porter
/// pour rejoindre le défilement toute seule — même contrat que
/// `CompanionSettings::MENU_CONDITIONS` côté site.
enum PageMenuCondition {
  /// Un itinéraire est suivi (`NavState.onRoute`).
  routeActive,

  /// La pente sous les roues est négative au-delà d'un seuil
  /// (`RideStats.gradePercent`).
  descending,

  /// Sur un col, ou à son approche (`NavState.climb`, `RouteClimbs`).
  nearCol;

  /// `null` pour une valeur absente ou inconnue de cette version de l'appli —
  /// la page reste alors purement statique, jamais perdue.
  static PageMenuCondition? parse(Object? raw) => switch (raw) {
        'route_active' => routeActive,
        'descending' => descending,
        'near_col' => nearCol,
        _ => null,
      };
}

/// La carte du site.
///
/// Facultative et déplaçable comme les autres pages. Quand elle est là, le
/// WebView est monté et peint **en permanence** au fond de la pile, où qu'elle
/// soit dans l'ordre : c'est une mesure sur route qui l'impose (une vue
/// plateforme démontée cesse de suivre le cycliste), et sa position dans le
/// catalogue n'y change rien.
class MapPageSpec extends RidePageSpec {
  const MapPageSpec({super.key}) : super(title: 'Carte');
}

/// Une grille de `rows` × `cols`, avec fusions.
///
/// **Ne défile pas.** C'est la page qu'on lit en roulant : tout doit tenir, et
/// c'est au mode de chaque composant de s'y plier ([DashboardBlock]).
class GridPageSpec extends RidePageSpec {
  const GridPageSpec({
    required super.title,
    required this.rows,
    required this.cols,
    required this.cells,
    this.dividers = const [],
    super.menu,
    super.menuCondition,
    super.menuAutoOpen,
    super.icon,
    super.key,
  });

  final int rows;
  final int cols;

  /// Les cellules effectivement plaçables : dans la grille, et sans
  /// recouvrement. La première posée gagne (cf. [placedCells]).
  final List<GridCell> cells;

  /// Les séparateurs posés entre les cases — décoratifs, sans effet sur la
  /// géométrie des cellules (cf. [placedDividers]).
  final List<GridDivider> dividers;

  /// Au-delà, les cases deviennent trop petites pour porter un chiffre lisible
  /// en roulant — c'est la même raison qui borne le bandeau à quatre cases.
  static const maxSide = 12;

  static GridPageSpec? parse(
    Map<dynamic, dynamic> raw, {
    String? title,
    bool menu = false,
    PageMenuCondition? menuCondition,
    bool menuAutoOpen = false,
    FaIconData? icon,
    String? key,
  }) {
    final rows = _gridSide(raw['rows']);
    final cols = _gridSide(raw['cols']);
    final cells = _gridCells(raw['cells'], rows: rows, cols: cols);

    // Une grille sans une seule cellule plaçable n'est pas une page vide, c'est
    // une page qui n'a rien à dire : on la retire plutôt que de faire défiler le
    // cycliste jusqu'à un rectangle noir.
    if (cells.isEmpty) return null;

    return GridPageSpec(
      title: title ?? 'Mesures',
      rows: rows,
      cols: cols,
      cells: cells,
      dividers: _gridDividers(raw['dividers'], rows: rows, cols: cols),
      menu: menu,
      menuCondition: menuCondition,
      menuAutoOpen: menuAutoOpen,
      icon: icon,
      key: key,
    );
  }
}

/// Borne un côté de grille à [GridPageSpec.maxSide], partagé avec
/// [LapGridLayout] : les deux grilles obéissent à la même limite de
/// lisibilité en roulant.
int _gridSide(Object? raw) =>
    (raw is num ? raw.toInt() : 1).clamp(1, GridPageSpec.maxSide);

/// Place les cellules d'une entrée `cells`, partagé entre [GridPageSpec] et
/// [LapGridLayout] — même géométrie, seul ce qu'elles contiennent diffère.
List<GridCell> _gridCells(
  Object? raw, {
  required int rows,
  required int cols,
}) {
  return placedCells<GridCell>(
    [
      for (final entry in (raw is List ? raw : []))
        if (GridCell.parse(entry) case final cell?) cell,
    ],
    spanOf: (cell) => cell.span,
    withSpan: (cell, span) => GridCell(span: span, block: cell.block),
    rows: rows,
    cols: cols,
  );
}

/// Place les séparateurs d'une entrée `dividers`, partagé entre [GridPageSpec]
/// et [LapGridLayout] — même géométrie, décorative, que [_gridCells].
List<GridDivider> _gridDividers(
  Object? raw, {
  required int rows,
  required int cols,
}) {
  return placedDividers(
    [
      for (final entry in (raw is List ? raw : []))
        if (GridDivider.parse(entry) case final divider?) divider,
    ],
    rows: rows,
    cols: cols,
  );
}

/// Une cellule posée : où, et quoi.
@immutable
class GridCell {
  const GridCell({required this.span, required this.block});

  final GridSpan span;
  final DashboardBlock block;

  static GridCell? parse(Object? raw) {
    if (raw is! Map) return null;
    final block = DashboardBlock.parse(raw['block']);
    if (block == null) return null;
    return GridCell(span: GridSpan.parse(raw), block: block);
  }
}

/// La page qui défile, celle d'aujourd'hui : une pile de blocs qu'on consulte à
/// l'arrêt d'un col ou au feu rouge.
///
/// Une seule colonne par défaut — la disposition d'avant ce réglage. Le site
/// peut en demander plusieurs ([cols]) ; chaque bloc reste alors par défaut
/// dans la colonne de celui qui le précède, et ne marque une rupture que
/// s'il en a une ([ListBlockPlacement.newColumn]/
/// [ListBlockPlacement.fullWidth], voir [listSegmentsOf]) : jamais de ligne
/// ni d'étendue comme [GridCell], parce qu'une liste n'a pas de hauteur à
/// tenir — chaque colonne empile ses blocs dans l'ordre du document et peut
/// déborder, c'est justement ce qui la distingue d'une grille.
class ListPageSpec extends RidePageSpec {
  const ListPageSpec({
    required super.title,
    required this.blocks,
    this.cols = 1,
    super.menu,
    super.menuCondition,
    super.menuAutoOpen,
    super.icon,
    super.key,
  });

  final List<ListBlockPlacement> blocks;

  /// 1 par défaut, y compris quand la clé est absente (contrat plus ancien) :
  /// la disposition ne change alors en rien. Borné à [maxCols] : au-delà,
  /// une colonne devient trop étroite pour un composant lisible sur un
  /// téléphone en portrait — même borne que le bandeau (`RideBottomBand`,
  /// 1 à 4 mesures).
  final int cols;

  static const maxCols = 4;

  static ListPageSpec? parse(
    Map<dynamic, dynamic> raw, {
    String? title,
    bool menu = false,
    PageMenuCondition? menuCondition,
    bool menuAutoOpen = false,
    FaIconData? icon,
    String? key,
  }) {
    final cols = raw['cols'] is num
        ? (raw['cols'] as num).toInt().clamp(1, maxCols)
        : 1;
    final blocks = [
      for (final entry in (raw['blocks'] is List ? raw['blocks'] as List : []))
        if (ListBlockPlacement.parse(entry) case final placement?) placement,
    ];
    if (blocks.isEmpty) return null;
    return ListPageSpec(
      title: title ?? 'Sortie',
      blocks: blocks,
      cols: cols,
      menu: menu,
      menuCondition: menuCondition,
      menuAutoOpen: menuAutoOpen,
      icon: icon,
      key: key,
    );
  }
}

/// Un bloc de [ListPageSpec], et la rupture qu'il marque éventuellement dans
/// le flux des colonnes — voir [listSegmentsOf].
@immutable
class ListBlockPlacement {
  const ListBlockPlacement({
    this.newColumn = false,
    this.fullWidth = false,
    required this.block,
  });

  /// Passe à la colonne suivante avant de poser ce bloc (retour à la
  /// première après la dernière). Sans effet si [fullWidth] est vrai — un
  /// bloc qui rompt déjà le flux à lui seul n'a plus de colonne à changer.
  final bool newColumn;

  /// Occupe toute la largeur, hors des colonnes : clôt le groupe de
  /// colonnes en cours et fait repartir la suite en première colonne.
  final bool fullWidth;

  final DashboardBlock block;

  /// `newColumn`/`fullWidth` sont **fusionnés dans le bloc lui-même**,
  /// jamais une enveloppe à part comme [GridCell] : une entrée reste le
  /// bloc, avec une clé de plus. Même contrat que
  /// `CompanionSettings.place_list_blocks` (Rails), y compris leur exclusion
  /// mutuelle — `fullWidth` l'emporte quand les deux sont posés.
  ///
  /// Un document d'avant ce réglage porte encore l'ancien `col` par bloc :
  /// ignoré comme n'importe quelle clé inconnue, il retombe sur les deux
  /// ruptures absentes — tous ses blocs se retrouvent dans une seule colonne
  /// qui défile, dégradé plutôt qu'un bloc perdu.
  static ListBlockPlacement? parse(Object? raw) {
    final block = DashboardBlock.parse(raw);
    if (block == null) return null;
    final fullWidth = raw is Map && raw['full_width'] == true;
    final newColumn = !fullWidth && raw is Map && raw['new_column'] == true;
    return ListBlockPlacement(
      newColumn: newColumn,
      fullWidth: fullWidth,
      block: block,
    );
  }
}

/// La page d'une série de tours : une liste déroulante pour choisir le tour,
/// puis des composants dont le contenu dépend de ce choix.
///
/// **La série appartient à la page, pas à chaque composant** : tous les blocs
/// qu'elle porte (répartition par zone, moyennes, bilan) montrent le tour
/// sélectionné *de cette série-là*. Rien n'empêche plusieurs pages sur la même
/// série (chacune garde son propre tour choisi, indépendamment des autres) ni
/// sur des séries différentes — voir `RidePreset.lapSeries`, qui les
/// rassemble toutes pour que `RideRecorder.start` les connaisse dès le départ.
class LapListPageSpec extends RidePageSpec {
  const LapListPageSpec({
    required super.title,
    required this.series,
    required this.layout,
    super.menu,
    super.menuCondition,
    super.menuAutoOpen,
    super.icon,
    super.key,
  });

  final String series;

  /// Défilante ou en grille — voir [LapPageLayout]. Même choix que pour les
  /// pages de mesures ([ListPageSpec] / [GridPageSpec]), et pour la même
  /// raison : un bilan de tour tient parfois en un coup d'œil, parfois pas.
  final LapPageLayout layout;

  static LapListPageSpec? parse(
    Map<dynamic, dynamic> raw, {
    String? title,
    bool menu = false,
    PageMenuCondition? menuCondition,
    bool menuAutoOpen = false,
    FaIconData? icon,
    String? key,
  }) {
    final layout = LapPageLayout.parse(raw);
    // Une page de tours sans le moindre composant n'a rien à montrer une fois
    // le tour choisi : même règle qu'une ListPageSpec vidée.
    if (layout == null) return null;
    return LapListPageSpec(
      title: title ?? 'Tours',
      series: raw['series'] is String ? raw['series'] as String : 'default',
      layout: layout,
      menu: menu,
      menuCondition: menuCondition,
      menuAutoOpen: menuAutoOpen,
      icon: icon,
      key: key,
    );
  }
}

/// Ce que montre une page de tours, une fois le tour choisi.
///
/// **`grid` seulement sur demande explicite** (`layout: 'grid'`) : un document
/// plus ancien que l'appli, ou qui omet la clé, doit retomber sur la liste
/// défilante d'aujourd'hui — jamais sur une grille dont il n'a jamais décrit
/// `rows`/`cols`.
@immutable
sealed class LapPageLayout {
  const LapPageLayout();

  static LapPageLayout? parse(Map<dynamic, dynamic> raw) {
    return raw['layout'] == 'grid'
        ? LapGridLayout.parse(raw)
        : LapBlocksLayout.parse(raw);
  }
}

/// La liste défilante, telle qu'elle existait avant que le choix se pose.
///
/// Mêmes colonnes qu'une [ListPageSpec] ordinaire ([cols], ruptures de
/// [ListBlockPlacement]) : rien ne distingue les deux dispositions une fois
/// le tour choisi, c'est la même page qui défile.
class LapBlocksLayout extends LapPageLayout {
  const LapBlocksLayout(this.blocks, {this.cols = 1});

  final List<ListBlockPlacement> blocks;
  final int cols;

  static LapBlocksLayout? parse(Map<dynamic, dynamic> raw) {
    final cols = raw['cols'] is num
        ? (raw['cols'] as num).toInt().clamp(1, ListPageSpec.maxCols)
        : 1;
    final blocks = [
      for (final entry in (raw['blocks'] is List ? raw['blocks'] as List : []))
        if (ListBlockPlacement.parse(entry) case final placement?) placement,
    ];
    return blocks.isEmpty ? null : LapBlocksLayout(blocks, cols: cols);
  }
}

/// La grille du bilan de tour, `rows` × `cols`, avec fusions — même géométrie
/// que [GridPageSpec], parce que rien ne la distingue d'une grille de mesures
/// une fois le tour choisi : elle **ne défile pas** non plus.
class LapGridLayout extends LapPageLayout {
  const LapGridLayout({
    required this.rows,
    required this.cols,
    required this.cells,
    this.dividers = const [],
  });

  final int rows;
  final int cols;
  final List<GridCell> cells;
  final List<GridDivider> dividers;

  static LapGridLayout? parse(Map<dynamic, dynamic> raw) {
    final rows = _gridSide(raw['rows']);
    final cols = _gridSide(raw['cols']);
    final cells = _gridCells(raw['cells'], rows: rows, cols: cols);
    return cells.isEmpty
        ? null
        : LapGridLayout(
            rows: rows,
            cols: cols,
            cells: cells,
            dividers: _gridDividers(raw['dividers'], rows: rows, cols: cols),
          );
  }
}

/// Ce qu'une case du bandeau ou de la bande de l'encoche peut porter : une
/// mesure comme avant, une commande sans réglage (« mettre en veille »), la
/// sonnette avec son son, ou le radar. Une clé de site unique
/// (`MetricId.fromKey` + `'sleep'`) resterait ambiguë le jour où les
/// catalogues se recouperaient ; `BandSlot` tranche une fois à l'analyse
/// plutôt qu'à chaque lecture par les deux bandes.
@immutable
sealed class BandSlot {
  const BandSlot();

  /// `null` pour une case vide, ou une clé inconnue de cette version de
  /// l'appli — même repli que [MetricId.fromKey], pour la même raison : un
  /// document plus récent que l'appli ne doit rien faire échouer.
  static BandSlot? parse(Object? raw) {
    if (raw is Map && raw['kind'] == 'mark_lap') {
      final series = raw['series'];
      if (series is! String || series.trim().isEmpty) return null;
      final label = raw['label'];
      return BandMarkLapSlot(
        series: series.trim(),
        label: label is String && label.trim().isNotEmpty ? label.trim() : null,
      );
    }
    if (raw == 'sleep') return const BandActionSlot(BandAction.sleep);
    if (raw is String && raw.startsWith('bell_')) {
      return BandBellSlot(_bellSoundOf(raw.substring('bell_'.length)));
    }
    if (raw is String && raw.startsWith('radar_')) {
      return BandRadarSlot(_radarModeOf(raw.substring('radar_'.length)));
    }
    if (raw is String && raw.startsWith('workout_')) {
      return BandWorkoutSlot(_workoutModeOf(raw.substring('workout_'.length)));
    }
    final metric = MetricId.fromKey(raw);
    return metric == null ? null : BandMetricSlot(metric);
  }
}

/// Le son nommé, ou [BellSound.bell] — le son par défaut, pour un son de
/// bande que cette version de l'appli ne connaît pas encore. Même repli
/// qu'un mode de radar de bande ([_radarModeOf]).
BellSound _bellSoundOf(String key) {
  for (final sound in BellSound.values) {
    if (sound.key == key) return sound;
  }
  return BellSound.bell;
}

/// Le mode nommé, ou [RadarMode.distance] — le mode par défaut, pour un mode
/// de bande que cette version de l'appli ne connaît pas encore. Même repli
/// qu'un genre de composant de grille (`DashboardBlock._modeOf`) : une case
/// déjà posée par le site ne doit pas disparaître pour un mode trop récent.
RadarMode _radarModeOf(String key) {
  for (final mode in RadarMode.values) {
    if (mode.key == key) return mode;
  }
  return RadarMode.distance;
}

/// Le mode nommé, ou [BandWorkoutMode.segment] — le mode par défaut, pour une
/// case de tronçon d'entraînement que cette version de l'appli ne connaît pas
/// encore. Même repli qu'un mode de radar de bande ([_radarModeOf]).
BandWorkoutMode _workoutModeOf(String key) {
  for (final mode in BandWorkoutMode.values) {
    if (mode.key == key) return mode;
  }
  return BandWorkoutMode.segment;
}

/// Un rappel périodique : boire, manger, entamer une intervalle — tout ce
/// qu'aucun capteur ne peut rappeler tout seul. Voir `RideReminderPolicy`
/// (`lib/ride/reminder_policy.dart`) pour le déclenchement, et
/// `ReminderBanner` pour l'affichage.
@immutable
class ReminderSpec {
  const ReminderSpec({
    required this.intervalMinutes,
    required this.message,
    this.sound = BellSound.bell,
  });

  /// Au plus douze par profil : au-delà, l'appli défendrait sa propre borne
  /// en silence sur la route plutôt que de composer un tableau de bord
  /// prévisible — même raison que [RideBandSpec.maxMetrics].
  static const maxCount = 12;

  /// Se répète tous les [intervalMinutes] de temps **effectivement roulé**
  /// (`RideRecorder.recorded`), pas d'horloge murale : une pause enregistrée
  /// ne doit ni faire sonner un rappel pendant l'arrêt, ni rattraper d'un
  /// coup à la reprise ce qu'elle a fait manquer.
  final int intervalMinutes;

  /// Le texte du toast, tel qu'écrit sur le site — libre, pas de catalogue.
  final String message;

  /// Même son qu'une sonnette ([BellSound]) et non un catalogue à part :
  /// même liste des deux côtés, et surtout le même flux d'alarme
  /// (`BellPlayer`), qui perce le mode silencieux — exactement ce qu'il faut
  /// à un rappel qu'on ne doit pas rater en roulant.
  final BellSound sound;

  /// Décode un rappel du document, ou `null` s'il n'en reste rien
  /// d'exploitable — un intervalle absent ou nul, ou un message vide, ne
  /// composerait qu'un toast muet ou qui ne sonne jamais.
  static ReminderSpec? parse(Object? raw) {
    if (raw is! Map) return null;
    final interval = raw['interval_minutes'];
    final message = raw['message'];
    if (interval is! num || interval <= 0) return null;
    if (message is! String || message.trim().isEmpty) return null;

    return ReminderSpec(
      intervalMinutes: interval.round(),
      message: message.trim(),
      sound: _bellSoundOf(raw['sound'] is String ? raw['sound'] as String : ''),
    );
  }
}

/// Une mesure, comme toutes les cases du bandeau et de l'encoche avant que
/// `BandSlot` existe.
@immutable
class BandMetricSlot extends BandSlot {
  const BandMetricSlot(this.metric);
  final MetricId metric;
}

/// Les commandes qu'une case peut porter, sans réglage propre. Un `enum` et
/// non un simple bool sur [BandActionSlot], pour qu'une deuxième commande
/// n'ait un jour rien à changer à [BandSlot.parse] ni aux `switch` qui la
/// dessinent.
///
/// `bell` n'y est plus : il a un réglage (le son), donc sa propre classe
/// ([BandBellSlot]) — même raison que [BandRadarSlot] plutôt qu'un radar
/// fondu ici, pour la même faute qu'aurait porté un `"bell"` sans dire lequel
/// des deux sons il joue.
enum BandAction { sleep }

@immutable
class BandActionSlot extends BandSlot {
  const BandActionSlot(this.action);
  final BandAction action;
}

/// Le radar arrière, en case de bandeau ou d'encoche — voir [RadarBlockView]
/// pour le rendu réel des modes. Seul un sous-ensemble de [RadarMode] a un
/// sens dans une case aussi petite : `distance`, `count` et `gauge` — voir
/// `BAND_RADAR_MODES` côté site.
@immutable
class BandRadarSlot extends BandSlot {
  const BandRadarSlot(this.mode);
  final RadarMode mode;
}

/// Les quatre habillages qu'une case de bandeau/encoche peut donner au
/// tronçon d'entraînement en cours — voir `WorkoutBandTile`
/// (`ride/widgets/workout_band_tile.dart`) pour le rendu réel. Un `enum` à
/// part de [RadarMode]/[BellSound] plutôt qu'un mode de composant de page
/// ([BlockMode]) : contrairement à eux, ces quatre habillages n'existent que
/// pour une case de bandeau — [WorkoutSegmentBlock]/[WorkoutRemainingBlock]
/// (les composants de page équivalents) n'ont aucun mode à choisir.
enum BandWorkoutMode {
  /// Le nom du tronçon, avec son icône — même contenu que
  /// [WorkoutSegmentBlock].
  segment('segment'),

  /// Le temps restant avant le prochain jalon, avec l'icône de la sonnette
  /// à sable — même contenu que [WorkoutRemainingBlock].
  remaining('remaining'),

  /// Le tronçon et le temps restant fondus en une icône et un chiffre — pour
  /// la case qui n'a la place que pour un seul texte mais peut encore
  /// montrer les deux informations d'un coup d'œil.
  combo('combo'),

  /// Icône, nom du tronçon et temps restant, tout sur une seule ligne — même
  /// contenu que [combo] et [segment] réunis, pour la case qui a la place
  /// des trois.
  line('line');

  const BandWorkoutMode(this.key);
  final String key;
}

/// Le tronçon d'entraînement en cours, en case de bandeau ou d'encoche — voir
/// [BandWorkoutMode] pour les quatre habillages possibles et
/// `WorkoutBandTile` pour le rendu réel. Préfixée `workout_` comme
/// [BandRadarSlot] est préfixée `radar_` : une clé à part de `METRICS` et
/// `BAND_ACTIONS` dans le même menu déroulant — voir `BAND_WORKOUT` côté
/// site.
@immutable
class BandWorkoutSlot extends BandSlot {
  const BandWorkoutSlot(this.mode);
  final BandWorkoutMode mode;
}

/// La sonnette, en case de bandeau ou d'encoche — voir [BellControl] pour le
/// rendu réel. Une classe à part de [BandActionSlot] plutôt qu'un `BandAction`
/// de plus : elle porte [sound], comme [BandRadarSlot] porte son mode — voir
/// `BAND_BELL` côté site.
@immutable
class BandBellSlot extends BandSlot {
  const BandBellSlot(this.sound);
  final BellSound sound;
}

/// Marquer un tour, en case de bandeau ou d'encoche — voir [MarkLapControl]
/// pour le bouton équivalent posé sur une page. Seule case de bandeau/encoche
/// dont le jeton JSON est un objet plutôt qu'une chaîne (`{"kind":
/// "mark_lap", "series": ..., "label": ...}`) : contrairement au son d'une
/// sonnette ou au mode d'un radar, [series] et [label] sont du texte libre,
/// qu'un préfixe de chaîne ne peut pas porter sans risque d'ambiguïté — voir
/// `CompanionSettings.sanitize_band_lap_slot` côté site.
@immutable
class BandMarkLapSlot extends BandSlot {
  const BandMarkLapSlot({required this.series, this.label});
  final String series;
  final String? label;
}

/// Un jeu de valeurs du bandeau.
///
/// **Quatre cases, pas plus** : au-delà, les chiffres deviennent trop petits
/// pour être lus d'un coup d'œil en roulant, ce qui est le seul usage du
/// bandeau. Ce qui ne tient pas passe dans le jeu suivant, à un glissé de là.
@immutable
class RideBandSpec {
  const RideBandSpec(this.slots);

  static const maxMetrics = 4;

  // Une case peut être vide (`null`) : c'est le site qui décide où, une case
  // du milieu laissée vide ne doit pas recoller celles qui suivent.
  final List<BandSlot?> slots;

  static RideBandSpec? parse(Object? raw) {
    final list = raw is Map ? raw['metrics'] : raw;
    if (list is! List) return null;

    final slots = <BandSlot?>[];
    for (final entry in list) {
      if (slots.length == maxMetrics) break;
      slots.add(BandSlot.parse(entry));
    }

    return slots.every((slot) => slot == null) ? null : RideBandSpec(slots);
  }
}

/// Ce qu'un jeu de la bande de l'encoche affiche, de chaque côté de la caméra
/// selfie.
///
/// [RidePreset.notch] est une liste de jeux, entre lesquels un glissé
/// horizontal fait défiler — même principe que [RideBandSpec] pour le
/// bandeau du bas. Contrairement à lui, une liste vide (ou absente) est un
/// état normal et non un repli : un profil qui n'a jamais touché ce réglage
/// doit laisser la bande invisible, exactement comme avant que ce réglage
/// existe.
@immutable
class NotchSpec {
  const NotchSpec({this.left, this.right});

  final BandSlot? left;
  final BandSlot? right;

  static NotchSpec? parse(Object? raw) {
    if (raw is! Map) return null;
    final left = BandSlot.parse(raw['left']);
    final right = BandSlot.parse(raw['right']);
    return left == null && right == null ? null : NotchSpec(left: left, right: right);
  }
}

/// Les capteurs que ce profil utilise.
///
/// Un home-trainer n'a que faire du GPS — ni du service au premier plan, ni de
/// sa notification, ni de sa batterie — pas plus que du baromètre, du radar ou
/// du capteur de lumière.
///
/// **Absent vaut activé.** Un document plus ancien que l'appli, ou un profil
/// écrit à la main, ne doit jamais éteindre un capteur en silence : l'erreur
/// irait dans le mauvais sens, une sortie sans cardio ne se rattrapant pas.
@immutable
class SensorSettings {
  const SensorSettings({
    this.gps = true,
    this.barometer = true,
    this.light = true,
    this.compass = true,
    this.radar = true,
    this.power = true,
    this.heartRate = true,
    this.cadence = true,
    this.gears = true,
  });

  final bool gps;
  final bool barometer;
  final bool light;
  final bool compass;
  final bool radar;
  final bool power;
  final bool heartRate;
  final bool cadence;
  final bool gears;

  /// Ce profil accepte-t-il cette capacité BLE ?
  ///
  /// **Ne peut que restreindre.** L'appelant garde son propre filtre — le
  /// réglage `autoConnect` de l'appareil — et les deux se composent par un
  /// « et » : un boîtier écarté à la main (vélo prêté, capteur de l'autre vélo)
  /// n'est jamais rattrapé au vol parce qu'un profil garde sa capacité.
  bool allows(SensorKind kind) => switch (kind) {
        SensorKind.heartRate => heartRate,
        SensorKind.power => power,
        SensorKind.speedCadence => cadence,
        SensorKind.gears => gears,
        SensorKind.radar => radar,
        // Jamais réglable, jamais un motif de rattachement ou d'écart à elle
        // seule : une ceinture cardiaque qui publie aussi sa batterie porte
        // `kinds = {heartRate, battery}`, et couper `heart_rate` doit suffire
        // à l'écarter — si `battery` restait « permise » par défaut, l'appareil
        // serait quand même rattrapé au vol (`devicesToReattach` rattache dès
        // qu'*une* capacité détectée est permise).
        SensorKind.battery => true,
      };

  static SensorSettings parse(Object? raw) {
    if (raw is! Map) return const SensorSettings();
    bool on(String key) => raw[key] is bool ? raw[key] as bool : true;

    return SensorSettings(
      gps: on('gps'),
      barometer: on('barometer'),
      light: on('light'),
      compass: on('compass'),
      radar: on('radar'),
      power: on('power'),
      heartRate: on('heart_rate'),
      cadence: on('cadence'),
      gears: on('gears'),
    );
  }
}

/// Le réglage du radar arrière.
///
/// Les valeurs par défaut sont celles de la carte de diagnostic
/// (`ui/radar_card.dart`) et de `radarViewFor` : les deux affichages doivent
/// raconter la même chose du même capteur.
@immutable
class RadarSettings {
  const RadarSettings({
    this.closeM = 40,
    this.rangeM = 140,
    this.overlay = true,
    this.sounds = true,
    this.wakeScreen = true,
    this.wakeHold = const Duration(seconds: 5),
  });

  final double closeM;
  final double rangeM;

  /// L'habillage plein écran : les jauges des gouttières et le cadre qui
  /// s'embrase — le radar par-dessus toutes les pages, qu'on les ait demandées
  /// ou non. Ne gouverne pas la bande de l'encoche, dont le contenu vient du
  /// profil et pas du radar.
  ///
  /// Coupé, **le capteur continue de tourner** : les tonalités restent, le
  /// réveil d'écran aussi, et le radar ne se voit plus que là où le profil a
  /// posé un [RadarBlock]. C'est le réglage de qui veut ses mètres dans une case
  /// et un écran par ailleurs intact.
  ///
  /// Vrai par défaut, y compris quand la clé manque : le site peut être plus
  /// ancien que l'appli, et une alerte perdue en silence est la dernière chose
  /// qu'on veut découvrir sur la route.
  final bool overlay;

  /// Les tonalités d'alerte. Coupées, le radar reste visible — c'est le son
  /// qu'on retire, pas l'information.
  final bool sounds;

  /// Rallumer l'écran quand une voiture remonte.
  final bool wakeScreen;

  /// Le maintien après extinction, qui empêche le rétroéclairage de battre et
  /// laisse le temps de lire « Voie libre ».
  final Duration wakeHold;

  static RadarSettings parse(Object? raw) {
    if (raw is! Map) return const RadarSettings();
    const fallback = RadarSettings();

    return RadarSettings(
      closeM: _double(raw['close_m'], fallback.closeM),
      rangeM: _double(raw['range_m'], fallback.rangeM),
      overlay: raw['overlay'] is bool
          ? raw['overlay'] as bool
          : fallback.overlay,
      sounds: raw['sounds'] is bool ? raw['sounds'] as bool : fallback.sounds,
      wakeScreen: raw['wake_screen'] is bool
          ? raw['wake_screen'] as bool
          : fallback.wakeScreen,
      wakeHold: raw['wake_hold_s'] is num
          ? Duration(seconds: (raw['wake_hold_s'] as num).round())
          : fallback.wakeHold,
    );
  }
}

/// Le seuil d'alerte batterie des capteurs BLE, et son son.
///
/// « Absent vaut activé », même logique que [RadarSettings.sounds] : un
/// document plus ancien que ce réglage ne doit pas faire perdre l'alerte en
/// silence.
@immutable
class BatterySettings {
  const BatterySettings({this.thresholdPercent = 20, this.sounds = true});

  /// En dessous, un appareil est « faible » — voir `BatteryStatus.low`.
  final int thresholdPercent;

  final bool sounds;

  static BatterySettings parse(Object? raw) {
    if (raw is! Map) return const BatterySettings();
    const fallback = BatterySettings();

    return BatterySettings(
      thresholdPercent: raw['threshold_percent'] is num
          ? (raw['threshold_percent'] as num).round().clamp(1, 100)
          : fallback.thresholdPercent,
      sounds: raw['sounds'] is bool ? raw['sounds'] as bool : fallback.sounds,
    );
  }
}

/// Les tonalités de début et de fin de col — voir `ClimbAlertPlayer`
/// (`lib/ride/climb_alert_sound.dart`) pour la lecture, et `ClimbEdgePolicy`
/// (`lib/ride/ride_shell_page.dart`) pour le front qui les déclenche.
///
/// « Absent vaut activé », même logique que [RadarSettings.sounds] et
/// [BatterySettings.sounds] : un document plus ancien que ce réglage ne doit
/// pas faire perdre le son en silence.
@immutable
class ClimbSettings {
  const ClimbSettings({this.sounds = true, this.expandedByDefault = false});

  final bool sounds;

  /// La pastille de col s'ouvre-t-elle en graphique dès l'entrée dans le col,
  /// plutôt que de rester repliée ? Le tap reste libre dans les deux sens
  /// (pastille → graphique, graphique → pastille) : ce réglage ne choisit que
  /// l'état de départ de **chaque nouveau col**, voir `_climbExpanded` dans
  /// `RideShellPage`.
  ///
  /// Faux par défaut, y compris quand la clé manque : un col qui s'ouvre grand
  /// tout seul recouvrirait la carte au moment précis où le cycliste a le plus
  /// besoin de voir la route devant lui — voir la doc de `_climbExpanded`. Un
  /// document plus ancien que ce champ garde donc exactement le comportement
  /// d'avant qu'il existe.
  final bool expandedByDefault;

  static ClimbSettings parse(Object? raw) {
    if (raw is! Map) return const ClimbSettings();
    const fallback = ClimbSettings();

    return ClimbSettings(
      sounds: raw['sounds'] is bool ? raw['sounds'] as bool : fallback.sounds,
      expandedByDefault: raw['expanded_by_default'] is bool
          ? raw['expanded_by_default'] as bool
          : fallback.expandedByDefault,
    );
  }
}

/// Les deux seuls repères visuels d'un programme d'entraînement en dehors
/// des blocs qu'on peut poser sur une page (`workout_segment`/
/// `workout_remaining`) et des sons (`WorkoutCuePlayer`) : la pastille du
/// tronçon en cours, épinglée en haut d'écran quelle que soit la page, et le
/// popup qui paraît 2-3 s au centre à chaque changement de tronçon — voir
/// `WorkoutBadge`/`WorkoutChangePopup` (`lib/ride/widgets/`).
///
/// « Absent vaut activé » pour les deux, même logique que [ClimbSettings.sounds].
@immutable
class WorkoutSettings {
  const WorkoutSettings({this.badge = true, this.popup = true});

  final bool badge;
  final bool popup;

  static WorkoutSettings parse(Object? raw) {
    if (raw is! Map) return const WorkoutSettings();
    const fallback = WorkoutSettings();

    return WorkoutSettings(
      badge: raw['badge'] is bool ? raw['badge'] as bool : fallback.badge,
      popup: raw['popup'] is bool ? raw['popup'] as bool : fallback.popup,
    );
  }
}

/// Les seuils d'éclairage, tels que [AutoLightingPolicy] les attend.
///
/// Transportés et rangés dès maintenant, mais **sans effet visible tant que la
/// politique n'est montée nulle part** : elle est écrite et testée, aucun écran
/// ne la fait encore tourner. Les câbler ici évite d'avoir à refaire le contrat
/// le jour où elle le sera.
@immutable
class LightingSettings {
  const LightingSettings({this.config = const LightingConfig()});

  final LightingConfig config;

  static LightingSettings parse(Object? raw) {
    if (raw is! Map) return const LightingSettings();
    const fallback = LightingConfig();

    return LightingSettings(
      config: LightingConfig(
        nightLux: _double(raw['night_lux'], fallback.nightLux),
        dayLux: _double(raw['day_lux'], fallback.dayLux),
        minimumDwell: raw['dwell_s'] is num
            ? Duration(seconds: (raw['dwell_s'] as num).round())
            : fallback.minimumDwell,
        alertDistanceM: raw['alert_distance_m'] is num
            ? (raw['alert_distance_m'] as num).round()
            : fallback.alertDistanceM,
        flashAtNight: raw['flash_at_night'] is bool
            ? raw['flash_at_night'] as bool
            : fallback.flashAtNight,
        offInDaylight: raw['off_in_daylight'] is bool
            ? raw['off_in_daylight'] as bool
            : fallback.offInDaylight,
        frontDayRunning: raw['front_day_running'] is bool
            ? raw['front_day_running'] as bool
            : fallback.frontDayRunning,
      ),
    );
  }
}

/// Le rétroéclairage en veille.
@immutable
class ScreenSettings {
  const ScreenSettings({this.dimLevel = ScreenDimmer.dimmed});

  /// Borné à 1 % en bas : à zéro, certains appareils coupent franchement le
  /// rétroéclairage, et le bandeau deviendrait illisible même de nuit.
  final double dimLevel;

  static ScreenSettings parse(Object? raw) {
    if (raw is! Map) return const ScreenSettings();
    final level = raw['dim_level'];
    if (level is! num) return const ScreenSettings();
    return ScreenSettings(dimLevel: level.toDouble().clamp(0.01, 1.0));
  }
}

/// Couleur, largeur et opacité de la ligne du trajet parcouru, dessinée par
/// la page — l'appli ne fait que transmettre ces trois valeurs telles
/// quelles au pont, elle n'en a jamais besoin sous forme de `Color` Dart.
@immutable
class TraveledPathSettings {
  const TraveledPathSettings({
    this.color = '#2196F3',
    this.width = 4.0,
    this.opacity = 0.85,
  });

  /// Hexadécimal `#rrggbb`, jamais transformé en `Color` : seule la page le
  /// consomme.
  final String color;
  final double width;

  /// Borné à `[0, 1]` : une valeur hors bornes casserait le rendu MapLibre.
  final double opacity;

  static final _hexColor = RegExp(r'^#[0-9a-fA-F]{6}$');

  static TraveledPathSettings parse(Object? raw) {
    if (raw is! Map) return const TraveledPathSettings();
    const fallback = TraveledPathSettings();

    final rawColor = raw['color'];
    final color = rawColor is String && _hexColor.hasMatch(rawColor)
        ? rawColor
        : fallback.color;

    return TraveledPathSettings(
      color: color,
      width: _double(raw['width'], fallback.width),
      opacity: _double(raw['opacity'], fallback.opacity).clamp(0.0, 1.0),
    );
  }
}

double _double(Object? raw, double fallback) =>
    raw is num ? raw.toDouble() : fallback;

/// Ce qu'un geste sur un bouton distant (D-Fly du Di2) déclenche.
///
/// Un jeton de chaîne par action plutôt qu'un `enum` : certaines portent un
/// réglage (`RingBellAction.sound`, `GoToPageAction.pageKey`), même choix que
/// [BandSlot] pour la même raison — un `enum` à plat ne peut rien porter.
/// `parse` ne lève jamais et rend `null` sur un jeton absent ou inconnu de
/// cette version : un geste sans action assignée ne fait simplement rien.
@immutable
sealed class ButtonAction {
  const ButtonAction();

  static ButtonAction? parse(Object? raw) {
    if (raw is! String) return null;
    if (raw.startsWith('go_to_page:')) {
      final pageKey = raw.substring('go_to_page:'.length);
      return pageKey.isEmpty ? null : GoToPageAction(pageKey);
    }
    // Un jeton de `BellSound` (`bell`, `horn`, `booster`, `horn2`, …) avant le
    // `switch` : même catalogue que `_bellSoundOf`, pour qu'un nouveau son
    // ajouté à l'enum se retrouve automatiquement disponible sur un bouton
    // Di2 sans toucher cette fonction.
    for (final sound in BellSound.values) {
      if (sound.key == raw) return RingBellAction(sound);
    }
    return switch (raw) {
      'next_page' => const NextPageAction(),
      'previous_page' => const PreviousPageAction(),
      'start_lap' => const StartLapAction(),
      'sleep' => const EnterSleepAction(),
      'wake' => const ExitSleepAction(),
      'toggle_sleep' => const ToggleSleepAction(),
      _ => null,
    };
  }
}

class NextPageAction extends ButtonAction {
  const NextPageAction();
}

class PreviousPageAction extends ButtonAction {
  const PreviousPageAction();
}

class RingBellAction extends ButtonAction {
  const RingBellAction(this.sound);
  final BellSound sound;
}

class StartLapAction extends ButtonAction {
  const StartLapAction();
}

class EnterSleepAction extends ButtonAction {
  const EnterSleepAction();
}

/// Voir `NavigationWebController.requestWake`, qui appelle `sleepExit` côté
/// pont (`companionBridge.ts`, dépôt Rails) — sans effet contre un site plus
/// ancien que ce point d'entrée.
class ExitSleepAction extends ButtonAction {
  const ExitSleepAction();
}

/// Un seul bouton pour les deux sens plutôt que deux réglages à poser sur
/// deux gestes — le cas d'usage courant (« un bouton pour la veille ») n'a
/// pas besoin de deux canaux ou de deux gestes distincts pour entrer et
/// sortir. Résolu dans `RideShellPage._performButtonAction`, seul endroit qui
/// connaît l'état courant (`ScreenPolicy.dimmed`) : cette classe ne porte
/// aucune donnée, juste l'intention.
class ToggleSleepAction extends ButtonAction {
  const ToggleSleepAction();
}

/// Anticipation : ne se résout que si une page du profil porte ce
/// [RidePageSpec.key] au moment du geste — sinon sans effet, jamais une
/// erreur, un profil réédité entre-temps ne doit rien casser.
class GoToPageAction extends ButtonAction {
  const GoToPageAction(this.pageKey);
  final String pageKey;
}

/// Les trois gestes qu'un canal du D-Fly peut produire — voir
/// `Di2ButtonGesturePolicy` (`lib/ride/`) pour comment on les distingue.
@immutable
class ButtonGestureActions {
  const ButtonGestureActions({this.click, this.doubleClick, this.longPress});

  final ButtonAction? click;
  final ButtonAction? doubleClick;
  final ButtonAction? longPress;

  static ButtonGestureActions parse(Object? raw) {
    if (raw is! Map) return const ButtonGestureActions();
    return ButtonGestureActions(
      click: ButtonAction.parse(raw['click']),
      doubleClick: ButtonAction.parse(raw['double_click']),
      longPress: ButtonAction.parse(raw['long_press']),
    );
  }
}

/// Ce que les quatre canaux du D-Fly déclenchent, par profil de sortie —
/// seuls 1 et 2 sont câblés sur le matériel testé jusqu'ici, 3 et 4 suivent
/// le même format (voir `ble/decoders/di2_buttons.dart`) et n'ont donc pas de
/// raison d'attendre un futur remaniement pour être configurables.
///
/// Par défaut, exactement le comportement d'avant ce réglage — canal 1 =
/// page précédente, canal 2 = page suivante, sur le clic simple seulement,
/// rien sur 3 et 4 — pour qu'un document sans section `buttons` (site plus
/// ancien, ou [RidePreset.builtIn]) ne change rien à l'existant.
@immutable
class ButtonSettings {
  const ButtonSettings({
    this.channel1 = const ButtonGestureActions(click: PreviousPageAction()),
    this.channel2 = const ButtonGestureActions(click: NextPageAction()),
    this.channel3 = const ButtonGestureActions(),
    this.channel4 = const ButtonGestureActions(),
  });

  final ButtonGestureActions channel1;
  final ButtonGestureActions channel2;
  final ButtonGestureActions channel3;
  final ButtonGestureActions channel4;

  static ButtonSettings parse(Object? raw) {
    if (raw is! Map) return const ButtonSettings();
    const fallback = ButtonSettings();

    ButtonGestureActions channel(String key, ButtonGestureActions fallback) =>
        raw.containsKey(key) ? ButtonGestureActions.parse(raw[key]) : fallback;

    return ButtonSettings(
      channel1: channel('channel1', fallback.channel1),
      channel2: channel('channel2', fallback.channel2),
      channel3: channel('channel3', fallback.channel3),
      channel4: channel('channel4', fallback.channel4),
    );
  }
}
