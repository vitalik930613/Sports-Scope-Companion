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
      'recording' =>
        RecordingBlock(mode: _modeOf(raw['mode'], RecordingMode.values)),
      'nav_state' =>
        NavStateBlock(mode: _modeOf(raw['mode'], NavStateMode.values)),
      'radar' => RadarBlock(mode: _modeOf(raw['mode'], RadarMode.values)),
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

  /// La jauge de position, comme dans les gouttières de la carte, mais
  /// **couchée** : la proximité va vers la droite. C'est le sens d'une cellule
  /// large, celle qu'on obtient en fusionnant une ligne de la grille.
  gauge('gauge'),

  /// La même, debout — le sens de la gouttière, la proximité vers le haut.
  /// C'est celui d'une cellule haute, et le seul qui garde les véhicules à la
  /// même place que sur les bords de l'écran : deux affichages du même capteur
  /// ne doivent pas raconter deux histoires.
  gaugeVertical('gauge_vertical');

  const RadarMode(this.key);

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
