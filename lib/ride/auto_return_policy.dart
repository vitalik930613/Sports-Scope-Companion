import 'package:flutter/foundation.dart';

import 'nav_state.dart';

/// Ce qui mérite qu'on ramène le cycliste sur la carte, par ordre de gravité
/// croissante.
///
/// Rien d'autre n'y a droit : le tableau de bord se consulte quand on l'a
/// décidé, et une page arrachée des yeux sans raison est pire qu'une page qu'on
/// ne regarde pas.
enum RideAlert { none, turn, offRoute, arrival }

/// Traduit l'état de navigation en alerte.
///
/// Toute la subtilité tient en une phrase : **`arrived` est un événement, pas un
/// état.** Côté web, le drapeau ne retombe qu'au chargement d'un autre tracé —
/// pris pour un niveau, il épinglerait le cycliste sur la carte pour tout le
/// reste de la sortie. On n'en garde donc que le front : une impulsion, la
/// première fois qu'on le voit vrai, et plus rien ensuite.
///
/// Les deux autres alertes sont bien des niveaux : on sort d'un hors-trace en
/// revenant sur la trace, et on sort d'un virage en le passant.
class RideAlertSource {
  bool _arrivedSeen = false;

  /// [turnImminent] est le verdict du chien de garde natif ([TurnProximity]) :
  /// il ne parle que quand la page s'est tue, et ne peut qu'*ajouter* une
  /// alerte de virage, jamais en retirer une.
  RideAlert read(NavState? state, {bool turnImminent = false}) {
    final arrival = _arrivalEdge(state);

    if (state != null && state.onRoute) {
      // Hors-trace d'abord : c'est la seule alerte qui dise qu'on ne va nulle
      // part. Un virage annoncé alors qu'on a quitté le tracé est un virage
      // qu'on ne prendra pas.
      if (state.offRoute) return RideAlert.offRoute;
      if (arrival) return RideAlert.arrival;
      if (state.turn?.phase case NavTurnPhase.near || NavTurnPhase.now) {
        return RideAlert.turn;
      }
    }

    return turnImminent ? RideAlert.turn : RideAlert.none;
  }

  bool _arrivalEdge(NavState? state) {
    final arrived = state != null && state.onRoute && state.arrived;
    if (!arrived) {
      _arrivedSeen = false;
      return false;
    }
    if (_arrivedSeen) return false;
    _arrivedSeen = true;
    return true;
  }

  /// La page a rechargé, ou un autre tracé a été ouvert : ce qu'on avait déjà vu
  /// ne vaut plus, une arrivée à venir est une nouvelle arrivée.
  void reset() => _arrivedSeen = false;
}

/// Ce que la politique demande à la coquille : une page, ou rien.
@immutable
class AutoReturnDecision {
  const AutoReturnDecision(this.goTo);

  static const stay = AutoReturnDecision(null);

  /// L'index de la page à afficher dans le profil courant.
  final int? goTo;
}

/// Ramener le cycliste sur la carte quand ça compte, et lui rendre sa page
/// quand c'est passé.
///
/// Classe pure et pilotée par une horloge passée en paramètre : c'est la
/// fonction la plus difficile à essayer sur la route (il faut un virage, une
/// page ouverte et les mains prises), donc celle qui doit se vérifier assise.
///
/// Quatre règles, dans cet ordre :
///
/// 1. **Front montant seulement.** Une alerte qui s'allume alors qu'on est sur
///    une page de données ramène sur la carte. Une alerte déjà allumée n'émet
///    plus rien — sans quoi le cycliste ne pourrait plus quitter la carte tant
///    qu'elle dure.
/// 2. **On rend la page.** Ce qu'on a interrompu, on le restitue :
///    [holdAfterClear] après l'extinction, la page d'où l'on venait revient
///    d'elle-même. Le cycliste n'a pas à se souvenir de ce qu'il regardait.
/// 3. **Le maintien redémarre à chaque alerte.** Un enchaînement de virages en
///    village rallume l'alerte pendant le délai : la carte reste, et la page ne
///    revient que le calme retrouvé. C'est ce qui évite la navette.
/// 4. **Le cycliste gagne.** S'il change de page pendant une alerte, on ne le
///    déplace plus jusqu'à ce qu'elle s'éteigne, et on ne lui doit plus rien :
///    il vient de dire où il voulait être.
///
/// Cinquième cas, qui n'est pas une règle mais une absence : **sans carte dans
/// le profil, la politique est inerte**. Elle ne ramène nulle part et ne doit
/// rien rendre — un home-trainer n'a pas de page web, donc pas de virage à
/// annoncer, et le seul déplacement qu'elle pourrait décider serait vers une
/// page choisie au hasard.
class AutoReturnPolicy {
  AutoReturnPolicy({this.mapPage, this.holdAfterClear = const Duration(seconds: 8)});

  /// Où se trouve la carte dans le profil courant, `null` quand il n'y en a pas.
  final int? mapPage;

  /// Délai entre l'extinction de l'alerte et le retour de la page interrompue.
  /// Assez long pour couvrir la sortie du virage, assez court pour qu'on ne
  /// croie pas la page perdue.
  final Duration holdAfterClear;

  RideAlert _alert = RideAlert.none;

  /// La page qu'on a interrompue et qu'on doit rendre. `null` = on ne doit
  /// rien : soit rien n'a été interrompu, soit le cycliste a repris la main.
  int? _owed;

  DateTime? _clearedAt;
  bool _overridden = false;

  AutoReturnDecision update({
    required DateTime now,
    required int currentPage,
    required RideAlert alert,
    bool userMoved = false,
  }) {
    final mapPage = this.mapPage;
    if (mapPage == null) return AutoReturnDecision.stay;

    if (userMoved) {
      _owed = null;
      if (alert != RideAlert.none) _overridden = true;
    }

    final rising = alert != RideAlert.none && _alert == RideAlert.none;
    final falling = alert == RideAlert.none && _alert != RideAlert.none;
    _alert = alert;

    if (falling) {
      _clearedAt = now;
      // L'alerte est éteinte : le refus du cycliste ne porte plus sur rien, la
      // prochaine aura droit à sa chance.
      _overridden = false;
    }

    if (rising) {
      // Le maintien repart de zéro : tant qu'il se passe quelque chose, la page
      // attend.
      _clearedAt = null;
      if (_overridden || currentPage == mapPage) {
        return AutoReturnDecision.stay;
      }
      _owed = currentPage;
      return AutoReturnDecision(mapPage);
    }

    final owed = _owed;
    final clearedAt = _clearedAt;
    if (alert == RideAlert.none &&
        owed != null &&
        clearedAt != null &&
        // Rendre une page depuis une page serait un déplacement de plus dans le
        // dos du cycliste : on ne restitue que depuis la carte, là où on l'a
        // amené.
        currentPage == mapPage &&
        now.difference(clearedAt) >= holdAfterClear) {
      _owed = null;
      _clearedAt = null;
      return AutoReturnDecision(owed);
    }

    return AutoReturnDecision.stay;
  }

  void reset() {
    _alert = RideAlert.none;
    _owed = null;
    _clearedAt = null;
    _overridden = false;
  }
}
