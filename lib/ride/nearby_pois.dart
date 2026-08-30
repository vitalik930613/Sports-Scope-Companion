import 'package:flutter/foundation.dart';

/// Un point d'intérêt reçu de la page de navigation (message `pois`).
///
/// Réduit à ce que la feuille « POI à proximité » dessine : la distance et le
/// cap sont calculés ici, depuis le GPS de l'appli, jamais reçus — la page ne
/// sait pas où en est exactement le cycliste entre deux trames.
@immutable
class NearbyPoi {
  const NearbyPoi({
    required this.name,
    required this.type,
    required this.lat,
    required this.lng,
  });

  final String name;

  /// Le `type` OSM (`bakery`, `water`, `viewpoint`…) — résolu en catégorie
  /// (icône, libellé, couleur) par `poi_categories.dart`.
  final String type;

  final double lat;
  final double lng;

  static NearbyPoi? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final lat = raw['lat'];
    final lng = raw['lng'];
    final name = raw['name'];
    final type = raw['type'];
    if (lat is! num || lng is! num || type is! String) return null;
    return NearbyPoi(
      name: name is String && name.isNotEmpty ? name : 'Point d\'intérêt',
      type: type,
      lat: lat.toDouble(),
      lng: lng.toDouble(),
    );
  }
}

/// Les POI visibles autour du cycliste, avec l'état courant des cases du filtre.
///
/// `filter` est celui de la **page** (préférences du compte, ou ce que l'appli
/// lui a poussé) : la feuille de filtre part de là, elle n'invente pas un
/// défaut.
@immutable
class NearbyPois {
  const NearbyPois({required this.pois, required this.filter});

  final List<NearbyPoi> pois;
  final Map<String, bool> filter;

  static const empty = NearbyPois(pois: [], filter: {});

  static NearbyPois? fromJson(Map<dynamic, dynamic> json) {
    if (json['type'] != 'pois') return null;

    final rawPois = json['pois'];
    final pois = <NearbyPoi>[];
    if (rawPois is List) {
      for (final entry in rawPois) {
        final poi = NearbyPoi.fromJson(entry);
        if (poi != null) pois.add(poi);
      }
    }

    final rawFilter = json['filter'];
    final filter = <String, bool>{};
    if (rawFilter is Map) {
      rawFilter.forEach((key, value) {
        if (key is String && value is bool) filter[key] = value;
      });
    }

    return NearbyPois(pois: pois, filter: filter);
  }
}

/// L'état des POI à proximité, à écouter comme n'importe quelle mesure.
///
/// Sans carte, personne ne l'alimente ni ne l'écoute — même sort que
/// `NavStateNotifier`.
class NearbyPoisNotifier extends ValueNotifier<NearbyPois> {
  NearbyPoisNotifier() : super(NearbyPois.empty);

  /// Range un message `pois`. Un message illisible est ignoré : on garde le
  /// dernier jeu valable plutôt que de vider la feuille.
  void accept(Map<dynamic, dynamic> json) {
    final next = NearbyPois.fromJson(json);
    if (next != null) value = next;
  }

  void reset() => value = NearbyPois.empty;
}
