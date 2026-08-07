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
      'nav_state' =>
        NavStateBlock(mode: _modeOf(raw['mode'], NavStateMode.values)),
      'radar' => RadarBlock(mode: _modeOf(raw['mode'], RadarMode.values)),
      'training_budget' => TrainingBudgetBlock(
          mode: _modeOf(raw['mode'], TrainingBudgetMode.values),
        ),
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
  const MetricBlock({required this.metric, this.mode = MetricMode.big});

  final MetricId metric;
  final MetricMode mode;

  /// `null` si la mesure nommée n'existe pas dans cette version : mieux vaut
  /// une cellule vide qu'une case qui affiche un tiret pour toujours.
  static MetricBlock? parse(Map<dynamic, dynamic> raw) {
    final metric = MetricId.fromKey(raw['metric']);
    if (metric == null) return null;
    return MetricBlock(
      metric: metric,
      mode: DashboardBlock._modeOf(raw['mode'], MetricMode.values),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MetricBlock && other.metric == metric && other.mode == mode;

  @override
  int get hashCode => Object.hash(metric, mode);
}

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
  zone('zone');

  const MetricMode(this.key);

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
