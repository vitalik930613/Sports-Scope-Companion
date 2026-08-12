import 'package:flutter/foundation.dart';

import '../ble/sensor_profile.dart';
import '../lighting/auto_lighting.dart';
import '../navigation/screen_dimmer.dart';
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
    this.lighting = const LightingSettings(),
    this.screen = const ScreenSettings(),
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
          RecordingBlock(),
          ZonesBlock(source: ZonesSource.hr),
          ZonesBlock(source: ZonesSource.power),
          AveragesBlock(),
          NavStateBlock(),
        ],
      ),
    ],
    bands: [
      RideBandSpec([
        MetricId.duration,
        MetricId.distance,
        MetricId.speed,
        MetricId.power,
      ]),
      RideBandSpec([
        MetricId.heartRate,
        MetricId.hrZone,
        MetricId.power,
        MetricId.powerZone,
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
  final LightingSettings lighting;
  final ScreenSettings screen;

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
              blocks.forEach(collect);
            case LapGridLayout(:final cells):
              for (final cell in cells) {
                collect(cell.block);
              }
          }
        case ListPageSpec(:final blocks):
          blocks.forEach(collect);
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
      lighting: LightingSettings.parse(raw['lighting']),
      screen: ScreenSettings.parse(raw['screen']),
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
}

/// Une page du tableau de bord.
///
/// Trois genres, et pas un seul : la carte n'est pas une grille, et une grille
/// n'est pas une liste. Ce qui les sépare vraiment, c'est le **défilement** —
/// une grille se lit en roulant et doit tenir tout entière, une liste se
/// consulte à l'arrêt et peut être longue.
@immutable
sealed class RidePageSpec {
  const RidePageSpec({required this.title, this.menu = false});

  final String title;

  /// Rangée derrière le menu d'actions plutôt que dans le défilement.
  ///
  /// **Faux par défaut, y compris quand la clé manque** : un document plus
  /// ancien que l'appli garde ses pages là où elles étaient, et une appli plus
  /// ancienne qu'un document ignore la clé et les montre toutes. L'erreur va
  /// donc toujours vers « visible », jamais vers « introuvable » — c'est le seul
  /// sens acceptable pour une page qu'on aurait composée exprès.
  final bool menu;

  static RidePageSpec? parse(Object? raw) {
    if (raw is! Map) return null;
    final title = raw['title'] is String ? raw['title'] as String : null;
    final menu = raw['menu'] == true;

    return switch (raw['kind']) {
      // Jamais derrière le menu, et pas par oubli : la carte est le WebView
      // peint au fond de la pile pour toute la sortie, pas une page qu'on ouvre
      // et qu'on referme.
      'map' => const MapPageSpec(),
      'grid' => GridPageSpec.parse(raw, title: title, menu: menu),
      'list' => ListPageSpec.parse(raw, title: title, menu: menu),
      'laps' => LapListPageSpec.parse(raw, title: title, menu: menu),
      _ => null,
    };
  }
}

/// La carte du site.
///
/// Facultative et déplaçable comme les autres pages. Quand elle est là, le
/// WebView est monté et peint **en permanence** au fond de la pile, où qu'elle
/// soit dans l'ordre : c'est une mesure sur route qui l'impose (une vue
/// plateforme démontée cesse de suivre le cycliste), et sa position dans le
/// catalogue n'y change rien.
class MapPageSpec extends RidePageSpec {
  const MapPageSpec() : super(title: 'Carte');
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
    super.menu,
  });

  final int rows;
  final int cols;

  /// Les cellules effectivement plaçables : dans la grille, et sans
  /// recouvrement. La première posée gagne (cf. [placedCells]).
  final List<GridCell> cells;

  /// Au-delà, les cases deviennent trop petites pour porter un chiffre lisible
  /// en roulant — c'est la même raison qui borne le bandeau à quatre cases.
  static const maxSide = 12;

  static GridPageSpec? parse(
    Map<dynamic, dynamic> raw, {
    String? title,
    bool menu = false,
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
      menu: menu,
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
class ListPageSpec extends RidePageSpec {
  const ListPageSpec({
    required super.title,
    required this.blocks,
    super.menu,
  });

  final List<DashboardBlock> blocks;

  static ListPageSpec? parse(
    Map<dynamic, dynamic> raw, {
    String? title,
    bool menu = false,
  }) {
    final blocks = [
      for (final entry in (raw['blocks'] is List ? raw['blocks'] as List : []))
        if (DashboardBlock.parse(entry) case final block?) block,
    ];
    if (blocks.isEmpty) return null;
    return ListPageSpec(title: title ?? 'Sortie', blocks: blocks, menu: menu);
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
class LapBlocksLayout extends LapPageLayout {
  const LapBlocksLayout(this.blocks);

  final List<DashboardBlock> blocks;

  static LapBlocksLayout? parse(Map<dynamic, dynamic> raw) {
    final blocks = [
      for (final entry in (raw['blocks'] is List ? raw['blocks'] as List : []))
        if (DashboardBlock.parse(entry) case final block?) block,
    ];
    return blocks.isEmpty ? null : LapBlocksLayout(blocks);
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
  });

  final int rows;
  final int cols;
  final List<GridCell> cells;

  static LapGridLayout? parse(Map<dynamic, dynamic> raw) {
    final rows = _gridSide(raw['rows']);
    final cols = _gridSide(raw['cols']);
    final cells = _gridCells(raw['cells'], rows: rows, cols: cols);
    return cells.isEmpty
        ? null
        : LapGridLayout(rows: rows, cols: cols, cells: cells);
  }
}

/// Un jeu de valeurs du bandeau.
///
/// **Quatre cases, pas plus** : au-delà, les chiffres deviennent trop petits
/// pour être lus d'un coup d'œil en roulant, ce qui est le seul usage du
/// bandeau. Ce qui ne tient pas passe dans le jeu suivant, à un glissé de là.
@immutable
class RideBandSpec {
  const RideBandSpec(this.metrics);

  static const maxMetrics = 4;

  // Une case peut être vide (`null`) : c'est le site qui décide où, une case
  // du milieu laissée vide ne doit pas recoller celles qui suivent.
  final List<MetricId?> metrics;

  static RideBandSpec? parse(Object? raw) {
    final list = raw is Map ? raw['metrics'] : raw;
    if (list is! List) return null;

    final metrics = <MetricId?>[];
    for (final entry in list) {
      if (metrics.length == maxMetrics) break;
      metrics.add(MetricId.fromKey(entry));
    }

    return metrics.every((metric) => metric == null) ? null : RideBandSpec(metrics);
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

  final MetricId? left;
  final MetricId? right;

  static NotchSpec? parse(Object? raw) {
    if (raw is! Map) return null;
    final left = MetricId.fromKey(raw['left']);
    final right = MetricId.fromKey(raw['right']);
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

double _double(Object? raw, double fallback) =>
    raw is num ? raw.toDouble() : fallback;
