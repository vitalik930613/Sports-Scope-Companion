import 'package:flutter/foundation.dart';

import 'nav_state.dart';

/// Un col détecté sur le tracé en cours, tel que le site le calcule
/// (`detectClimbs`, routeHelpers.ts). L'appli ne redétecte jamais les cols
/// elle-même : elle affiche la liste reçue, dans l'ordre reçu.
///
/// Volontairement sans son profil gradué (voir [ClimbProfile] dans
/// climb_profile.dart, poussé à part et une seule fois, pour le seul col en
/// cours) — cette liste vaut pour le tracé entier, elle doit rester légère.
@immutable
class RouteClimb {
  const RouteClimb({
    required this.id,
    required this.startDistM,
    required this.gainM,
    required this.lengthM,
    required this.avgGrade,
    this.category,
    this.name,
  });

  /// Clé de dédoublonnage : l'index de départ du col côté site — même
  /// convention que [ClimbProfile.id]. Ne sert qu'à comparer deux entrées
  /// entre elles, jamais affichée.
  final int id;

  /// Distance cumulée depuis le départ du tracé, en mètres — même repère que
  /// [RouteClimbs.totalDistM] et que `remainingM` du message `nav`.
  final double startDistM;
  final double gainM;
  final double lengthM;
  final double avgGrade;
  final String? category;

  /// Nom donné à la main côté site (`routes.climb_names`), absent si le col
  /// n'a jamais été renommé — l'appli garde alors « Col N » à l'affichage.
  final String? name;

  double get endDistM => startDistM + lengthM;

  static RouteClimb? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final startDistM = _toDouble(raw['startDistM']);
    final gainM = _toDouble(raw['gainM']);
    final lengthM = _toDouble(raw['lengthM']);
    final avgGrade = _toDouble(raw['avgGrade']);
    if (id is! num ||
        startDistM == null ||
        gainM == null ||
        lengthM == null ||
        avgGrade == null) {
      return null;
    }
    return RouteClimb(
      id: id.toInt(),
      startDistM: startDistM,
      gainM: gainM,
      lengthM: lengthM,
      avgGrade: avgGrade,
      category: raw['category'] is String ? raw['category'] as String : null,
      name: raw['name'] is String ? raw['name'] as String : null,
    );
  }
}

/// La liste ordonnée des cols du tracé en cours, avec la distance totale du
/// tracé — ce qu'il faut pour situer le cycliste dessus sans lui faire
/// redétecter les cols (voir [traveledDistM]).
///
/// Reçue une fois par tracé (chargement, reroutage) et vidée quand le tracé
/// l'est (voir `companionRouteClimbs`, `RouteNavigation.vue`). Sans
/// persistance, comme [ClimbProfile] : la liste ne vaut que pour la sortie en
/// cours.
@immutable
class RouteClimbs {
  const RouteClimbs({required this.totalDistM, required this.climbs});

  final double totalDistM;

  /// Ordonnés par distance de départ croissante, comme rendus par
  /// `detectClimbs` côté site.
  final List<RouteClimb> climbs;

  static RouteClimbs? fromJson(Object? raw) {
    if (raw is! Map || raw['type'] != 'route_climbs') return null;
    final rawClimbs = raw['climbs'];
    if (rawClimbs is! List) return null;

    // Une entrée illisible est ignorée, pas fatale à toute la liste : le site
    // peut être plus récent que l'appli sur un champ que celle-ci ne connaît
    // pas encore — même tolérance que CompanionSettings.parse.
    final climbs = <RouteClimb>[
      for (final entry in rawClimbs)
        if (RouteClimb.fromJson(entry) case final climb?) climb,
    ];

    return RouteClimbs(
      totalDistM: _toDouble(raw['totalDistM']) ?? 0,
      climbs: climbs,
    );
  }
}

/// La liste des cols du tracé en cours, à écouter comme [ClimbProfileNotifier].
/// Sans persistance : un tracé est une chose de la sortie, jamais quelque
/// chose à retrouver après un redémarrage de l'appli.
class RouteClimbsNotifier extends ValueNotifier<RouteClimbs?> {
  RouteClimbsNotifier() : super(null);

  /// Range un message venu de la page. Un message illisible est ignoré : on
  /// garde la dernière liste valable plutôt que de vider l'écran.
  void accept(Map<dynamic, dynamic> json) {
    final next = RouteClimbs.fromJson(json);
    if (next != null) value = next;
  }

  void reset() => value = null;
}

/// Où en est le cycliste par rapport à un col donné.
enum ClimbStatus {
  /// La fin du col est déjà derrière la position connue.
  done,

  /// La position connue est entre le départ et la fin du col.
  current,

  /// Le col n'a pas encore commencé — ou la position est inconnue, auquel cas
  /// c'est l'état le plus sûr : mieux vaut annoncer un col trop tôt que de
  /// prétendre qu'on y est déjà.
  upcoming,
}

/// La distance déjà parcourue **sur le tracé** (pas la distance GPS de
/// l'enregistreur, qui peut s'en écarter hors trace) — dans le même repère que
/// [RouteClimb.startDistM], puisque dérivée du même `remainingM`/`totalDistM`
/// que le reste de la navigation.
///
/// `null` hors trace ou sur un état périmé : même garde que
/// `MetricId._remaining`, pour ne jamais situer un col sur une position qu'on
/// ne connaît plus.
double? traveledDistM(RouteClimbs list, NavState? nav) {
  if (nav == null || !nav.onRoute || nav.isStale(DateTime.now())) return null;
  final traveled = list.totalDistM - nav.remainingM;
  if (traveled < 0) return 0;
  if (traveled > list.totalDistM) return list.totalDistM;
  return traveled;
}

/// Le statut d'un col donné la distance parcourue sur le tracé. `null`
/// (position inconnue) vaut [ClimbStatus.upcoming] : voir [traveledDistM].
ClimbStatus climbStatusOf(RouteClimb climb, double? traveledM) {
  if (traveledM == null) return ClimbStatus.upcoming;
  if (traveledM >= climb.endDistM) return ClimbStatus.done;
  if (traveledM >= climb.startDistM) return ClimbStatus.current;
  return ClimbStatus.upcoming;
}

double? _toDouble(Object? raw) => raw is num ? raw.toDouble() : null;
