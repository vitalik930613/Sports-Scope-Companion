import 'package:flutter_test/flutter_test.dart';
import 'package:sports_scope_companion/ride/auto_return_policy.dart';
import 'package:sports_scope_companion/ride/nav_state.dart';

/// Le retour automatique est la fonction la plus difficile à essayer sur la
/// route : il faut un virage, une page ouverte et les deux mains prises. Elle se
/// vérifie donc assise, sur une horloge de papier.
void main() {
  final t0 = DateTime.utc(2026, 7, 30, 10);

  /// Les pages sont des index dans le profil de sortie, et la carte n'est plus
  /// forcément la première : on la met ici en deuxième position, exprès, pour
  /// qu'un retour à zéro par mégarde se voie.
  const mapPage = 1;
  const dataPage = 2;

  NavState nav({
    NavTurnPhase? turn,
    bool offRoute = false,
    bool arrived = false,
    bool onRoute = true,
    DateTime? at,
  }) =>
      NavState(
        at: at ?? t0,
        onRoute: onRoute,
        offRoute: offRoute,
        arrived: arrived,
        turn: turn == null ? null : NavTurn(phase: turn, distM: 120),
      );

  group('RideAlertSource', () {
    test('un virage proche est une alerte, un virage lointain non', () {
      final source = RideAlertSource();

      expect(source.read(nav(turn: NavTurnPhase.far)), RideAlert.none);
      expect(source.read(nav(turn: NavTurnPhase.near)), RideAlert.turn);
      expect(source.read(nav(turn: NavTurnPhase.now)), RideAlert.turn);
    });

    test('le hors-trace passe avant tout le reste', () {
      // Un virage annoncé alors qu'on a quitté le tracé est un virage qu'on ne
      // prendra pas : c'est le hors-trace qu'il faut montrer.
      final source = RideAlertSource();

      expect(
        source.read(nav(turn: NavTurnPhase.now, offRoute: true)),
        RideAlert.offRoute,
      );
    });

    test('l\'arrivée n\'est qu\'une impulsion, jamais un état', () {
      // LE piège du chantier : côté web, `arrived` ne retombe qu'au chargement
      // d'un autre tracé. Pris pour un niveau, il collerait le cycliste sur la
      // carte pour tout le reste de la sortie.
      final source = RideAlertSource();

      expect(source.read(nav(arrived: true)), RideAlert.arrival);
      expect(source.read(nav(arrived: true)), RideAlert.none);
      expect(source.read(nav(arrived: true)), RideAlert.none);
    });

    test('après remise à zéro, une arrivée est une nouvelle arrivée', () {
      final source = RideAlertSource();

      source.read(nav(arrived: true));
      source.reset();

      expect(source.read(nav(arrived: true)), RideAlert.arrival);
    });

    test('en navigation libre, rien n\'alerte', () {
      // Pas de tracé, donc pas de virage à manquer ni de trace à quitter.
      final source = RideAlertSource();

      expect(
        source.read(nav(onRoute: false, turn: NavTurnPhase.now, arrived: true)),
        RideAlert.none,
      );
    });

    test('le chien de garde peut ajouter un virage, pas en retirer un', () {
      final source = RideAlertSource();

      expect(source.read(null, turnImminent: true), RideAlert.turn);
      expect(
        source.read(nav(offRoute: true), turnImminent: true),
        RideAlert.offRoute,
      );
    });
  });

  group('AutoReturnPolicy', () {
    test('une alerte qui s\'allume ramène sur la carte', () {
      final policy = AutoReturnPolicy(mapPage: mapPage);

      final decision = policy.update(
        now: t0,
        currentPage: dataPage,
        alert: RideAlert.turn,
      );

      expect(decision.goTo, mapPage);
    });

    test('une alerte déjà allumée ne déplace plus personne', () {
      // Sinon le cycliste ne pourrait plus quitter la carte tant qu'elle dure —
      // et un hors-trace peut durer des kilomètres.
      final policy = AutoReturnPolicy(mapPage: mapPage);

      policy.update(
        now: t0,
        currentPage: dataPage,
        alert: RideAlert.turn,
      );
      final again = policy.update(
        now: t0.add(const Duration(seconds: 1)),
        currentPage: dataPage,
        alert: RideAlert.turn,
      );

      expect(again.goTo, isNull);
    });

    test('la page revient d\'elle-même une fois le calme retrouvé', () {
      final policy = AutoReturnPolicy(
        mapPage: mapPage,
        holdAfterClear: const Duration(seconds: 8),
      );

      policy.update(
        now: t0,
        currentPage: dataPage,
        alert: RideAlert.turn,
      );
      policy.update(
        now: t0.add(const Duration(seconds: 5)),
        currentPage: mapPage,
        alert: RideAlert.none,
      );

      // Pendant le maintien, rien.
      expect(
        policy
            .update(
              now: t0.add(const Duration(seconds: 12)),
              currentPage: mapPage,
              alert: RideAlert.none,
            )
            .goTo,
        isNull,
      );

      expect(
        policy
            .update(
              now: t0.add(const Duration(seconds: 13)),
              currentPage: mapPage,
              alert: RideAlert.none,
            )
            .goTo,
        dataPage,
      );
    });

    test('un enchaînement de virages ne fait pas la navette', () {
      // En village, `near` clignote. Sans redémarrage du maintien, le cycliste
      // ferait l'aller-retour entre la carte et sa page à chaque virage.
      final policy = AutoReturnPolicy(
        mapPage: mapPage,
        holdAfterClear: const Duration(seconds: 8),
      );

      policy.update(
        now: t0,
        currentPage: dataPage,
        alert: RideAlert.turn,
      );
      policy.update(
        now: t0.add(const Duration(seconds: 4)),
        currentPage: mapPage,
        alert: RideAlert.none,
      );
      // Deuxième virage avant la fin du maintien : le compte repart.
      policy.update(
        now: t0.add(const Duration(seconds: 9)),
        currentPage: mapPage,
        alert: RideAlert.turn,
      );

      expect(
        policy
            .update(
              now: t0.add(const Duration(seconds: 15)),
              currentPage: mapPage,
              alert: RideAlert.none,
            )
            .goTo,
        isNull,
      );
      expect(
        policy
            .update(
              now: t0.add(const Duration(seconds: 24)),
              currentPage: mapPage,
              alert: RideAlert.none,
            )
            .goTo,
        dataPage,
      );
    });

    test('le cycliste garde le dernier mot pendant une alerte', () {
      final policy = AutoReturnPolicy(mapPage: mapPage);

      policy.update(
        now: t0,
        currentPage: dataPage,
        alert: RideAlert.turn,
      );
      // Il repart sur sa page à la main, alerte toujours allumée.
      policy.update(
        now: t0.add(const Duration(seconds: 2)),
        currentPage: dataPage,
        alert: RideAlert.turn,
        userMoved: true,
      );

      // Le virage se rapproche encore : on ne le déplace plus.
      expect(
        policy
            .update(
              now: t0.add(const Duration(seconds: 3)),
              currentPage: dataPage,
              alert: RideAlert.turn,
            )
            .goTo,
        isNull,
      );

      // Et on ne lui doit plus rien : il est déjà où il voulait être.
      policy.update(
        now: t0.add(const Duration(seconds: 6)),
        currentPage: dataPage,
        alert: RideAlert.none,
      );
      expect(
        policy
            .update(
              now: t0.add(const Duration(seconds: 30)),
              currentPage: mapPage,
              alert: RideAlert.none,
            )
            .goTo,
        isNull,
      );
    });

    test('le refus ne vaut que pour l\'alerte en cours', () {
      final policy = AutoReturnPolicy(mapPage: mapPage);

      policy.update(
        now: t0,
        currentPage: dataPage,
        alert: RideAlert.turn,
      );
      policy.update(
        now: t0.add(const Duration(seconds: 2)),
        currentPage: dataPage,
        alert: RideAlert.turn,
        userMoved: true,
      );
      policy.update(
        now: t0.add(const Duration(seconds: 5)),
        currentPage: dataPage,
        alert: RideAlert.none,
      );

      // Nouveau virage, nouvelle chance : refuser une fois n'est pas couper la
      // fonction pour le reste de la sortie.
      expect(
        policy
            .update(
              now: t0.add(const Duration(seconds: 40)),
              currentPage: dataPage,
              alert: RideAlert.turn,
            )
            .goTo,
        mapPage,
      );
    });

    test('une alerte alors qu\'on est déjà sur la carte ne doit rien', () {
      final policy = AutoReturnPolicy(mapPage: mapPage);

      policy.update(
        now: t0,
        currentPage: mapPage,
        alert: RideAlert.turn,
      );
      policy.update(
        now: t0.add(const Duration(seconds: 2)),
        currentPage: mapPage,
        alert: RideAlert.none,
      );

      expect(
        policy
            .update(
              now: t0.add(const Duration(seconds: 30)),
              currentPage: mapPage,
              alert: RideAlert.none,
            )
            .goTo,
        isNull,
      );
    });

    test('sans carte dans le profil, la politique ne déplace jamais rien', () {
      // Le home-trainer : pas de page web, donc pas de virage à annoncer. Un
      // retour automatique n'aurait nulle part où ramener, et le seul
      // déplacement qu'il pourrait décider serait vers une page prise au hasard
      // — arrachée des yeux du cycliste sans qu'il ait rien demandé.
      final policy = AutoReturnPolicy();

      expect(
        policy
            .update(now: t0, currentPage: dataPage, alert: RideAlert.turn)
            .goTo,
        isNull,
      );
      expect(
        policy
            .update(
              now: t0.add(const Duration(minutes: 1)),
              currentPage: dataPage,
              alert: RideAlert.none,
            )
            .goTo,
        isNull,
      );
    });
  });
}
