import 'package:flutter/foundation.dart';

/// Où en est le prochain virage.
///
/// Repris tel quel du bandeau de la page web : `far` (lointain, discret),
/// `near` (approche — le bandeau violet, orange quand c'est urgent), `now`
/// (on est dessus, confirmation verte).
enum NavTurnPhase { far, near, now }

/// Le prochain virage annoncé par la page.
@immutable
class NavTurn {
  const NavTurn({
    required this.phase,
    required this.distM,
    this.direction,
    this.kind,
    this.exitNumber,
    this.lat,
    this.lng,
  });

  final NavTurnPhase phase;

  /// Distance au virage, **le long du tracé** — pas à vol d'oiseau. Un lacet
  /// peut donc annoncer 150 m pour un virage à 40 m devant soi.
  final double distM;

  final String? direction;
  final String? kind;
  final int? exitNumber;

  /// Position du virage. C'est elle qui permet de juger l'approche avec le GPS
  /// de l'appli quand la page se tait ; nulle en navigation libre ou quand le
  /// tracé n'a pas encore été analysé.
  final double? lat;
  final double? lng;

  bool get hasPosition => lat != null && lng != null;

  static NavTurn? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final distM = _toDouble(raw['distM']);
    if (distM == null) return null;

    return NavTurn(
      phase: _phaseOf(raw['state']),
      distM: distM,
      direction: raw['direction'] is String ? raw['direction'] as String : null,
      kind: raw['kind'] is String ? raw['kind'] as String : null,
      exitNumber: raw['exitNumber'] is num
          ? (raw['exitNumber'] as num).toInt()
          : null,
      lat: _toDouble(raw['lat']),
      lng: _toDouble(raw['lng']),
    );
  }

  /// Un état inconnu vaut `far` : mieux vaut un virage sous-estimé qu'un
  /// message rejeté parce que le site a gagné un état qu'on ne connaît pas.
  static NavTurnPhase _phaseOf(Object? raw) {
    switch (raw) {
      case 'near':
        return NavTurnPhase.near;
      case 'now':
        return NavTurnPhase.now;
      default:
        return NavTurnPhase.far;
    }
  }
}

/// Le col en cours, sans son profil (trop volumineux pour être republié à
/// chaque seconde — il aura son propre message le jour où on le dessinera).
@immutable
class NavClimb {
  const NavClimb({
    required this.ratio,
    required this.remainingGainM,
    required this.grade,
    required this.gainM,
    required this.lengthM,
    this.category,
  });

  final double ratio;
  final double remainingGainM;
  final double grade;
  final double gainM;
  final double lengthM;
  final String? category;

  static NavClimb? fromJson(Object? raw) {
    if (raw is! Map) return null;
    return NavClimb(
      ratio: _toDouble(raw['ratio']) ?? 0,
      remainingGainM: _toDouble(raw['remainingGainM']) ?? 0,
      grade: _toDouble(raw['grade']) ?? 0,
      gainM: _toDouble(raw['gain']) ?? 0,
      lengthM: _toDouble(raw['lengthM']) ?? 0,
      category: raw['category'] is String ? raw['category'] as String : null,
    );
  }
}

/// Ce que la page de navigation dit d'elle-même.
///
/// Reçu ~1 fois par seconde tant que le GPS accroche. La coquille s'en sert pour
/// afficher, et surtout pour décider de revenir sur la carte quand un virage
/// approche.
@immutable
class NavState {
  const NavState({
    required this.at,
    required this.onRoute,
    required this.offRoute,
    required this.arrived,
    this.turn,
    this.speedKmh = 0,
    this.remainingM = 0,
    this.remainingGainM = 0,
    this.climb,
  });

  /// Horodatage du message, tel qu'il a été posé par la page.
  final DateTime at;

  /// Un itinéraire est-il suivi ? Faux en navigation libre, où virages,
  /// hors-trace et arrivée n'ont pas de sens.
  final bool onRoute;
  final bool offRoute;
  final bool arrived;
  final NavTurn? turn;
  final double speedKmh;
  final double remainingM;
  final double remainingGainM;
  final NavClimb? climb;

  /// L'information a-t-elle vieilli ? Au-delà, on ne s'y fie plus : la page a pu
  /// être ralentie, rechargée, ou perdre le GPS. C'est ce qui fait basculer la
  /// décision d'approche sur le GPS de l'appli.
  bool isStale(DateTime now, {Duration after = const Duration(seconds: 5)}) =>
      now.difference(at) > after;

  /// Décode un message `{type:'nav'}`. Tolérant par construction : une charge
  /// utile inattendue rend `null`, jamais une exception — la navigation prime
  /// sur la justesse du tableau de bord.
  static NavState? fromJson(Map<dynamic, dynamic> json) {
    if (json['type'] != 'nav') return null;

    final at = json['at'];
    return NavState(
      at: at is num
          ? DateTime.fromMillisecondsSinceEpoch(at.toInt())
          : DateTime.now(),
      onRoute: json['route'] == true,
      offRoute: json['offRoute'] == true,
      arrived: json['arrived'] == true,
      turn: NavTurn.fromJson(json['turn']),
      speedKmh: _toDouble(json['speedKmh']) ?? 0,
      remainingM: _toDouble(json['remainingM']) ?? 0,
      remainingGainM: _toDouble(json['remainingGainM']) ?? 0,
      climb: NavClimb.fromJson(json['climb']),
    );
  }
}

/// L'état de navigation courant, à écouter comme n'importe quelle mesure.
class NavStateNotifier extends ValueNotifier<NavState?> {
  NavStateNotifier() : super(null);

  /// Range un message venu de la page. Un message illisible est ignoré : on
  /// garde le dernier état valable plutôt que d'effacer l'écran.
  void accept(Map<dynamic, dynamic> json) {
    final next = NavState.fromJson(json);
    if (next != null) value = next;
  }

  void reset() => value = null;
}

double? _toDouble(Object? raw) => raw is num ? raw.toDouble() : null;
