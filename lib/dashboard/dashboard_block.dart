import 'package:flutter/foundation.dart';

import 'metric_id.dart';

/// Ce qu'on peut poser dans une page du tableau de bord, et **comment ça se
/// dessine**.
///
/// Le mode n'est pas une décoration : le même contenu ne tient pas de la même
/// façon dans un quart d'écran et dans une bande de deux cellules. Une
/// répartition par zone montre sa barre et sa légende quand elle a la place,
/// sa barre seule quand elle n'en a plus — plutôt que de déborder ou de
/// rapetisser jusqu'à l'illisible.
///
/// Hiérarchie scellée : le rendu s'écrit en `switch` exhaustif, et ajouter un
/// composant fait échouer la compilation là où il manque, plutôt que de
/// disparaître silencieusement de l'écran.
///
/// **Rien ici ne lève.** Même convention que les décodeurs GATT : une entrée
/// incomprise rend `null` et disparaît de la page, un mode inconnu retombe sur
/// le mode par défaut du composant. Le site peut être plus récent que l'appli,
/// et une page qui refuserait de se dessiner en pleine sortie serait le pire
/// résultat possible.
@immutable
sealed class DashboardBlock {
  const DashboardBlock();

  /// `null` quand l'entrée ne décrit aucun composant connu.
  static DashboardBlock? parse(Object? raw) {
    if (raw is! Map) return null;

    return switch (raw['kind']) {
      'metric' => MetricBlock.parse(raw),
      'zones' => ZonesBlock.parse(raw),
      'averages' =>
        AveragesBlock(mode: _modeOf(raw['mode'], AveragesMode.values)),
      'lap_zones' => LapZonesBlock.parse(raw),
      'lap_averages' =>
        LapAveragesBlock(mode: _modeOf(raw['mode'], AveragesMode.values)),
      'lap_summary' => LapSummaryBlock(
          mode: _modeOf(raw['mode'], LapSummaryMode.values),
        ),
      'lap_selector' => const LapSelectorBlock(),
      'mark_lap' => MarkLapBlock(
          series: raw['series'] is String ? raw['series'] as String : 'default',
          mode: _modeOf(raw['mode'], MarkLapMode.values),
        ),
      'recording' =>
        RecordingBlock(mode: _modeOf(raw['mode'], RecordingMode.values)),
      'change_route' => ChangeRouteBlock(
          mode: _modeOf(raw['mode'], ChangeRouteMode.values),
        ),
      'clear_route' =>
        ClearRouteBlock(mode: _modeOf(raw['mode'], ClearRouteMode.values)),
      'route' => RouteBlock(mode: _modeOf(raw['mode'], RouteMode.values)),
      'nav_state' =>
        NavStateBlock(mode: _modeOf(raw['mode'], NavStateMode.values)),
      'radar' => RadarBlock(mode: _modeOf(raw['mode'], RadarMode.values)),
      'training_budget' => TrainingBudgetBlock(
          mode: _modeOf(raw['mode'], TrainingBudgetMode.values),
        ),
      'climb_list' =>
        ClimbListBlock(mode: _modeOf(raw['mode'], ClimbListMode.values)),
      'empty' => const EmptyBlock(),
      _ => null,
    };
  }

  /// Le mode nommé, ou **le premier de la liste** — qui est le mode par défaut
  /// du composant, celui qui suppose le plus de place et se lit le mieux.
  static T _modeOf<T extends BlockMode>(Object? raw, List<T> modes) {
    if (raw is String) {
      for (final mode in modes) {
        if (mode.key == raw) return mode;
      }
    }
    return modes.first;
  }
}

/// Le contrat commun des modes : une clé écrite à la main, pour que renommer
/// une valeur Dart ne casse pas les documents déjà servis par le site.
abstract mixin class BlockMode {
  String get key;
}

/// Une mesure du catalogue, seule dans sa cellule.
class MetricBlock extends DashboardBlock {
  const MetricBlock({
    required this.metric,
    this.mode = MetricMode.big,
    this.format = DurationFormat.hm,
    this.min,
    this.max,
  });

  final MetricId metric;
  final MetricMode mode;

  /// N'a d'effet que sur une mesure de durée ([MetricId.duration],
  /// [MetricId.movingTime], [MetricId.pauseTime], [MetricId.routeEta]) —
  /// présent sur toute mesure comme [mode], mais silencieusement ignoré des
  /// autres, plutôt qu'un champ optionnel de plus à défaire au rendu.
  final DurationFormat format;

  /// Bornes de la jauge à plage libre ([MetricMode.gauge] sur une mesure sans
  /// zones d'entraînement), réglées dans l'éditeur. `null` sur un document
  /// plus ancien ou sans ce réglage : [MetricView] retombe alors sur le
  /// chiffre plein cadre, comme avant que ce mode existe pour ces mesures.
  final double? min;
  final double? max;

  /// `null` si la mesure nommée n'existe pas dans cette version : mieux vaut
  /// une cellule vide qu'une case qui affiche un tiret pour toujours.
  static MetricBlock? parse(Map<dynamic, dynamic> raw) {
    final metric = MetricId.fromKey(raw['metric']);
    if (metric == null) return null;

    // Les deux ensemble ou aucun : une seule borne ne dit rien, et le site ne
    // devrait jamais en écrire une sans l'autre — mais l'appli ne lui fait pas
    // confiance pour autant (cf. tête de fichier).
    final rawMin = _toDouble(raw['min']);
    final rawMax = _toDouble(raw['max']);
    final hasRange = rawMin != null && rawMax != null && rawMin < rawMax;

    return MetricBlock(
      metric: metric,
      mode: DashboardBlock._modeOf(raw['mode'], MetricMode.values),
      format: DashboardBlock._modeOf(raw['format'], DurationFormat.values),
      min: hasRange ? rawMin : null,
      max: hasRange ? rawMax : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MetricBlock &&
      other.metric == metric &&
      other.mode == mode &&
      other.format == format &&
      other.min == min &&
      other.max == max;

  @override
  int get hashCode => Object.hash(metric, mode, format, min, max);
}

double? _toDouble(Object? raw) => raw is num ? raw.toDouble() : null;

enum MetricMode with BlockMode {
  /// Le chiffre plein cadre : ce qu'on lit à 30 km/h sans quitter la route des
  /// yeux. Mode par défaut, donc en tête.
  big('big'),

  /// Icône, valeur, unité — la mise en forme de `MetricTile`, pour les cellules
  /// où l'on tient plusieurs mesures.
  compact('compact'),

  /// Une jauge remplie jusqu'à la mesure, quand ce qui compte est la position
  /// dans la plage plutôt que le chiffre exact.
  gauge('gauge'),

  /// L'aplat de la zone du moment, avec la mesure dessus.
  zone('zone'),

  /// Un curseur en position continue sur une plage qui n'est **pas** réglée
  /// dans l'éditeur : le min et le max observés depuis le départ de la sortie
  /// (cadence, cardio, puissance, vitesse, pente), ou la progression vers
  /// l'itinéraire chargé (distance, durée). Contrairement à [gauge], la plage
  /// n'existe qu'en roulant — voir [MetricId.liveRangeOf].
  dynamicGauge('dynamic_gauge');

  const MetricMode(this.key);

  @override
  final String key;
}

/// Comment une mesure de durée écrit ses secondes. `hm` en tête : c'est le
/// format d'avant ce réglage, donc celui sur lequel un document sans cette clé
/// retombe.
enum DurationFormat with BlockMode {
  /// `04:12` — la seconde n'est pas écrite.
  hm('hm'),

  /// `04:12:07` — la seconde compte.
  hms('hms');

  const DurationFormat(this.key);

  @override
  final String key;
}

/// Le temps passé par zone depuis le départ, cardio ou puissance.
class ZonesBlock extends DashboardBlock {
  const ZonesBlock({required this.source, this.mode = ZonesMode.bar});

  final ZonesSource source;
  final ZonesMode mode;

  static ZonesBlock parse(Map<dynamic, dynamic> raw) => ZonesBlock(
        source: switch (raw['source']) {
          'power' => ZonesSource.power,
          // Le cardio par défaut : c'est la répartition qui existe même sans
          // capteur de puissance.
          _ => ZonesSource.hr,
        },
        mode: DashboardBlock._modeOf(raw['mode'], ZonesMode.values),
      );

  @override
  bool operator ==(Object other) =>
      other is ZonesBlock && other.source == source && other.mode == mode;

  @override
  int get hashCode => Object.hash(source, mode);
}

enum ZonesSource { hr, power }

enum ZonesMode with BlockMode {
  /// La barre et sa légende, une ligne par zone. Ce qu'on lit à l'arrêt.
  bar('bar'),

  /// La barre seule : elle garde toute son information — une proportion se lit
  /// dans une longueur partagée — et tient dans la hauteur d'une cellule.
  barOnly('bar_only'),

  /// La légende seule, quand la barre est déjà ailleurs sur la page.
  legend('legend');

  const ZonesMode(this.key);

  @override
  final String key;
}

/// Le temps passé par zone, mais **depuis le début du tour sélectionné**, pas
/// depuis le départ de la sortie.
///
/// Même contenu que [ZonesBlock], et volontairement une classe à part plutôt
/// qu'un paramètre « depuis quand » sur celui-ci : ce bloc n'a de sens que sur
/// une page qui porte un tour sélectionné ([LapListPageSpec.series]), là où
/// [ZonesBlock] peut se poser n'importe où.
class LapZonesBlock extends DashboardBlock {
  const LapZonesBlock({required this.source, this.mode = ZonesMode.bar});

  final ZonesSource source;
  final ZonesMode mode;

  static LapZonesBlock parse(Map<dynamic, dynamic> raw) => LapZonesBlock(
        source: switch (raw['source']) {
          'power' => ZonesSource.power,
          _ => ZonesSource.hr,
        },
        mode: DashboardBlock._modeOf(raw['mode'], ZonesMode.values),
      );

  @override
  bool operator ==(Object other) =>
      other is LapZonesBlock && other.source == source && other.mode == mode;

  @override
  int get hashCode => Object.hash(source, mode);
}

/// Les moyennes de la sortie : cardio, puissance, cadence, D+, calories.
class AveragesBlock extends DashboardBlock {
  const AveragesBlock({this.mode = AveragesMode.cards});

  final AveragesMode mode;

  @override
  bool operator ==(Object other) =>
      other is AveragesBlock && other.mode == mode;

  @override
  int get hashCode => mode.hashCode;
}

enum AveragesMode with BlockMode {
  cards('cards'),
  list('list');

  const AveragesMode(this.key);

  @override
  final String key;
}

/// Les moyennes, mais du tour sélectionné plutôt que de la sortie entière.
/// Même remarque que [LapZonesBlock] : une classe à part parce qu'elle n'a de
/// sens que sur une page de tours.
class LapAveragesBlock extends DashboardBlock {
  const LapAveragesBlock({this.mode = AveragesMode.cards});

  final AveragesMode mode;

  @override
  bool operator ==(Object other) =>
      other is LapAveragesBlock && other.mode == mode;

  @override
  int get hashCode => mode.hashCode;
}

/// Le bilan du tour sélectionné : durée, distance, D+, calories, TSS — ce
/// qu'on demanderait d'un tour entier plutôt qu'à une seule mesure. Le TSS
/// suit `rideTss` (`training/ride_load.dart`), déjà générique sur n'importe
/// quelle `RideStats`, donc valable tel quel sur celle d'un tour.
class LapSummaryBlock extends DashboardBlock {
  const LapSummaryBlock({this.mode = LapSummaryMode.cards});

  final LapSummaryMode mode;

  @override
  bool operator ==(Object other) =>
      other is LapSummaryBlock && other.mode == mode;

  @override
  int get hashCode => mode.hashCode;
}

enum LapSummaryMode with BlockMode {
  cards('cards'),
  list('list');
  const LapSummaryMode(this.key);

  @override
  final String key;
}

/// La liste déroulante qui choisit le tour affiché par les autres composants
/// d'une page Tours ([LapZonesBlock], [LapAveragesBlock], [LapSummaryBlock]).
///
/// **Un composant placé comme un autre, et non un en-tête imposé.** La
/// version d'avant le posait d'office au-dessus de la page ; la hauteur
/// qu'elle prenait n'était alors comptée nulle part, et une page Tours en
/// grille se retrouvait avec moins de place que ce que l'éditeur avait
/// composé — la grille semblait décalée une fois sur le téléphone. En le
/// rendant plaçable comme `lap_summary` ou `metric`, la page qui le porte
/// tient tout entière dans `rows` × `cols` (ou dans sa liste), sans rien caché
/// que l'éditeur ignorerait.
///
/// **Absent, la page reste utilisable** : elle montre alors toujours le tour
/// le plus récent, sans rien à choisir — la même valeur de repli qu'avant
/// qu'un choix explicite n'existe (`_selectedIndex ?? laps.length - 1`, cf.
/// `LapListBody`).
class LapSelectorBlock extends DashboardBlock {
  const LapSelectorBlock();

  @override
  bool operator ==(Object other) => other is LapSelectorBlock;

  @override
  int get hashCode => 0;
}

/// Démarrer, suspendre, reprendre l'enregistrement.
class RecordingBlock extends DashboardBlock {
  const RecordingBlock({this.mode = RecordingMode.full});

  final RecordingMode mode;

  @override
  bool operator ==(Object other) =>
      other is RecordingBlock && other.mode == mode;

  @override
  int get hashCode => mode.hashCode;
}

enum RecordingMode with BlockMode {
  /// Le bouton large, à portée de pouce sur une route bosselée.
  full('full'),

  /// L'icône seule, pour une cellule de grille.
  compact('compact');

  const RecordingMode(this.key);

  @override
  final String key;
}

/// Marquer un tour : clôt le tour courant d'une série et en ouvre un nouveau.
///
/// Peut se poser sur n'importe quelle page, pas seulement une page de tours —
/// c'est en roulant, entre deux mesures, qu'on veut marquer un tour. [series]
/// dit **dans quelle série** ce bouton marque un tour ; plusieurs boutons de
/// séries différentes tournent sans se fermer l'une l'autre (voir
/// `RideRecorder.markLap`). `'default'` sans configuration : c'est aussi la
/// seule série que l'export `.fit` sait porter, le format n'ayant qu'une
/// hiérarchie de tours.
class MarkLapBlock extends DashboardBlock {
  const MarkLapBlock({this.series = 'default', this.mode = MarkLapMode.full});

  final String series;
  final MarkLapMode mode;

  @override
  bool operator ==(Object other) =>
      other is MarkLapBlock && other.series == series && other.mode == mode;

  @override
  int get hashCode => Object.hash(series, mode);
}

enum MarkLapMode with BlockMode {
  /// Le bouton large, à portée de pouce sur une route bosselée.
  full('full'),

  /// L'icône seule, pour une cellule de grille.
  compact('compact');

  const MarkLapMode(this.key);

  @override
  final String key;
}

/// Choisir un autre itinéraire sans quitter la sortie.
///
/// Même geste que « Choisir un autre itinéraire » du menu ⋮
/// (`DashboardPage._actionsMenu`), posé directement sur une page plutôt que
/// rangé dans un menu qu'on n'ouvre presque jamais.
class ChangeRouteBlock extends DashboardBlock {
  const ChangeRouteBlock({this.mode = ChangeRouteMode.full});

  final ChangeRouteMode mode;

  @override
  bool operator ==(Object other) =>
      other is ChangeRouteBlock && other.mode == mode;

  @override
  int get hashCode => mode.hashCode;
}

enum ChangeRouteMode with BlockMode {
  /// Le bouton large, à portée de pouce sur une route bosselée.
  full('full'),

  /// L'icône seule, pour une cellule de grille.
  compact('compact');

  const ChangeRouteMode(this.key);

  @override
  final String key;
}

/// Retirer le tracé qu'on suit, sans quitter la sortie.
///
/// Même geste que « Retirer l'itinéraire » du menu ⋮. Désactivé — jamais
/// masqué — tant qu'aucun tracé n'est suivi : c'est un bouton qu'on a posé
/// exprès sur sa page, et le faire disparaître ferait chercher une case vide
/// plutôt qu'un bouton grisé qui explique pourquoi il ne répond pas.
class ClearRouteBlock extends DashboardBlock {
  const ClearRouteBlock({this.mode = ClearRouteMode.full});

  final ClearRouteMode mode;

  @override
  bool operator ==(Object other) =>
      other is ClearRouteBlock && other.mode == mode;

  @override
  int get hashCode => mode.hashCode;
}

enum ClearRouteMode with BlockMode {
  full('full'),
  compact('compact');

  const ClearRouteMode(this.key);

  @override
  final String key;
}

/// [ChangeRouteBlock] et [ClearRouteBlock], combinés en un seul bouton.
///
/// C'est l'état de la navigation qui décide lequel des deux gestes il pose —
/// retirer le tracé suivi s'il y en a un, en choisir un sinon. Gardé à côté
/// des deux commandes séparées et non à leur place : un profil déjà composé
/// avec elles ne doit rien perdre à l'enregistrement (`CompanionSettings`,
/// site).
///
/// Jamais désactivé, contrairement à [ClearRouteBlock] seul : hors tracé, le
/// bouton propose déjà le geste qui en pose un plutôt que de se griser sans
/// rien pouvoir faire.
class RouteBlock extends DashboardBlock {
  const RouteBlock({this.mode = RouteMode.full});

  final RouteMode mode;

  @override
  bool operator ==(Object other) => other is RouteBlock && other.mode == mode;

  @override
  int get hashCode => mode.hashCode;
}

enum RouteMode with BlockMode {
  full('full'),
  compact('compact');

  const RouteMode(this.key);

  @override
  final String key;
}

/// Ce que la page web raconte d'elle-même. Sans carte dans le profil, il n'y a
/// pas de page pour le dire : le bloc affiche alors qu'il n'attend rien.
class NavStateBlock extends DashboardBlock {
  const NavStateBlock({this.mode = NavStateMode.full});

  final NavStateMode mode;

  @override
  bool operator ==(Object other) =>
      other is NavStateBlock && other.mode == mode;

  @override
  int get hashCode => mode.hashCode;
}

enum NavStateMode with BlockMode {
  full('full'),
  compact('compact');

  const NavStateMode(this.key);

  @override
  final String key;
}

/// Le radar arrière. Ni « voie libre » ni tiret quand il est absent : pas de
/// radar n'est pas une route dégagée, et le bloc le dit.
class RadarBlock extends DashboardBlock {
  const RadarBlock({this.mode = RadarMode.distance});

  final RadarMode mode;

  @override
  bool operator ==(Object other) => other is RadarBlock && other.mode == mode;

  @override
  int get hashCode => mode.hashCode;
}

enum RadarMode with BlockMode {
  /// Les mètres du véhicule le plus proche, en gros.
  distance('distance'),

  /// Les mêmes mètres, sans l'icône ni le `×N` : rien que le chiffre, pour la
  /// cellule qui n'a pas la hauteur d'en placer deux lignes.
  compact('compact'),

  /// Le compte des véhicules suivis : une icône, et le nombre à côté. Pour qui
  /// veut savoir combien remontent, pas à quelle distance est le premier.
  count('count'),

  /// Une icône par véhicule suivi — le compte redit sans chiffre, à l'endroit
  /// où l'on préfère compter d'un coup d'œil que lire un nombre.
  icons('icons'),

  /// Un simple carré de couleur, sans chiffre ni icône : orange pour une
  /// voiture détectée, rouge pour une voiture proche. Ce qui se lit le plus
  /// vite du coin de l'œil, pour la plus petite case de la grille.
  gauge('gauge');

  const RadarMode(this.key);

  @override
  final String key;
}

/// Le budget de charge : ce qu'il reste à faire, et jusqu'où on peut aller.
///
/// **Le seul composant dont la donnée ne vient pas des capteurs.** Elle est
/// calculée par le site — qui seul a l'historique des sorties, l'objectif
/// d'entraînement et la cible de la semaine — et poussée par la page de
/// navigation. Un profil sans carte n'en recevra donc jamais : il n'y a pas de
/// WebView pour la porter, et le composant le dit au lieu d'afficher des zéros.
class TrainingBudgetBlock extends DashboardBlock {
  const TrainingBudgetBlock({this.mode = TrainingBudgetMode.day});

  final TrainingBudgetMode mode;

  @override
  bool operator ==(Object other) =>
      other is TrainingBudgetBlock && other.mode == mode;

  @override
  int get hashCode => mode.hashCode;
}

enum TrainingBudgetMode with BlockMode {
  /// Aujourd'hui : ce qui est déjà encaissé plus la sortie en cours, la cible du
  /// jour, le plafond que la fatigue autorise. Mode par défaut, donc en tête —
  /// c'est celui qui répond à « je continue ou je rentre ? », la question qu'on
  /// se pose au guidon. La semaine, elle, se regarde à l'arrêt.
  day('day'),

  /// La semaine : la cible, ce qui est fait depuis lundi, ce qui est déjà prévu
  /// sur les jours à venir, ce qu'il reste à placer.
  week('week');

  const TrainingBudgetMode(this.key);

  @override
  final String key;
}

/// La liste des cols du tracé, avec un repère « en cours / prochain ».
///
/// Vient de la page comme [NavStateBlock] et [TrainingBudgetBlock], pas d'un
/// capteur — donc absent sans carte dans le profil, comme eux (voir
/// `route_climbs.dart` : sans carte, personne n'alimente la liste).
class ClimbListBlock extends DashboardBlock {
  const ClimbListBlock({this.mode = ClimbListMode.full});

  final ClimbListMode mode;

  @override
  bool operator ==(Object other) =>
      other is ClimbListBlock && other.mode == mode;

  @override
  int get hashCode => mode.hashCode;
}

enum ClimbListMode with BlockMode {
  /// La liste entière, une ligne par col — ce qu'on lit à l'arrêt ou sur une
  /// page qui défile. Mode par défaut, donc en tête.
  full('full'),

  /// Une seule ligne : le col en cours, ou le prochain à venir. Pour la case
  /// de grille qui n'a la place que d'une phrase.
  compact('compact');

  const ClimbListMode(this.key);

  @override
  final String key;
}

/// Une cellule volontairement vide.
///
/// Elle existe pour que « je n'ai rien mis ici » se distingue de « le composant
/// que j'avais mis n'a pas été compris » : la première est un choix de
/// composition, la seconde un symptôme.
class EmptyBlock extends DashboardBlock {
  const EmptyBlock();

  @override
  bool operator ==(Object other) => other is EmptyBlock;

  @override
  int get hashCode => 0;
}
