import 'package:flutter/foundation.dart';

/// Un ravitaillement possible **sur le tracé suivi**, reçu de la page de
/// navigation (message `resupply`).
///
/// Distinct d'un [NearbyPoi] : la page a déjà projeté le POI sur la polyligne
/// du tracé, `remainingM` est donc la distance **le long du tracé** depuis la
/// position courante — pas à vol d'oiseau — et le point est forcément devant.
/// `detourM` est l'écart entre le POI et le tracé (à faire en plus, aller).
@immutable
class ResupplyStop {
  const ResupplyStop({
    required this.name,
    required this.type,
    required this.remainingM,
    required this.detourM,
  });

  final String name;

  /// Le `type` OSM (`water`, `food`, `bakery`) — voir `RESUPPLY_TYPES` côté
  /// site. Résolu en libellé/icône ici, recopié à la main (fac-similé).
  final String type;

  final double remainingM;
  final double detourM;

  static ResupplyStop? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'];
    final type = raw['type'];
    final remainingM = raw['remainingM'];
    final detourM = raw['detourM'];
    if (type is! String || remainingM is! num) return null;
    return ResupplyStop(
      name: name is String && name.isNotEmpty ? name : 'Ravitaillement',
      type: type,
      remainingM: remainingM.toDouble(),
      detourM: detourM is num ? detourM.toDouble() : 0,
    );
  }
}

/// Les ravitaillements à venir sur le tracé, triés par distance croissante.
///
/// Sans carte, personne ne l'alimente ni ne l'écoute — même sort que
/// [NearbyPoisNotifier] / [NavStateNotifier].
@immutable
class RouteResupply {
  const RouteResupply({required this.stops});

  final List<ResupplyStop> stops;

  static const empty = RouteResupply(stops: []);

  static RouteResupply? fromJson(Map<dynamic, dynamic> json) {
    if (json['type'] != 'resupply') return null;
    final raw = json['stops'];
    final stops = <ResupplyStop>[];
    if (raw is List) {
      for (final entry in raw) {
        final stop = ResupplyStop.fromJson(entry);
        if (stop != null) stops.add(stop);
      }
    }
    return RouteResupply(stops: stops);
  }
}

class RouteResupplyNotifier extends ValueNotifier<RouteResupply> {
  RouteResupplyNotifier() : super(RouteResupply.empty);

  /// Range un message `resupply`. Un message illisible est ignoré : on garde
  /// le dernier jeu valable — mais un `stops: []` explicite (tracé retiré,
  /// plus rien devant) est bien pris en compte.
  void accept(Map<dynamic, dynamic> json) {
    final next = RouteResupply.fromJson(json);
    if (next != null) value = next;
  }

  void reset() => value = RouteResupply.empty;
}
