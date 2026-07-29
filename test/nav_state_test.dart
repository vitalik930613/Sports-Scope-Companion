import 'package:flutter_test/flutter_test.dart';
import 'package:sports_scope_companion/ride/nav_state.dart';

/// Une charge utile `nav` complète, telle que la page l'envoie.
Map<String, dynamic> payload({Map<String, dynamic> over = const {}}) => {
      'type': 'nav',
      'at': 1753790000000,
      'route': true,
      'turn': {
        'state': 'near',
        'distM': 128.4,
        'direction': 'left',
        'kind': 'turn',
        'exitNumber': null,
        'lat': 46.52313,
        'lng': 6.63229,
      },
      'offRoute': false,
      'arrived': false,
      'speedKmh': 27.4,
      'remainingM': 18450,
      'remainingGainM': 312,
      'climb': null,
      ...over,
    };

void main() {
  group('décodage', () {
    test('lit un message complet', () {
      final state = NavState.fromJson(payload())!;

      expect(state.onRoute, isTrue);
      expect(state.offRoute, isFalse);
      expect(state.arrived, isFalse);
      expect(state.speedKmh, 27.4);
      expect(state.remainingM, 18450);
      expect(state.at.millisecondsSinceEpoch, 1753790000000);
      expect(state.turn!.phase, NavTurnPhase.near);
      expect(state.turn!.distM, 128.4);
      expect(state.turn!.lat, 46.52313);
      expect(state.turn!.hasPosition, isTrue);
    });

    test('lit le col quand il y en a un', () {
      final state = NavState.fromJson(payload(over: {
        'climb': {
          'ratio': 0.42,
          'remainingGainM': 210,
          'grade': 6.4,
          'gain': 780,
          'lengthM': 12400,
          'category': '2',
        },
      }))!;

      expect(state.climb!.ratio, 0.42);
      expect(state.climb!.gainM, 780);
      expect(state.climb!.category, '2');
    });

    test('ignore un message d’un autre type', () {
      expect(NavState.fromJson({'type': 'screen', 'state': 'dimmed'}), isNull);
    });

    test('ne jette pas sur une charge utile vide', () {
      expect(NavState.fromJson({}), isNull);
    });
  });

  group('tolérance', () {
    test('un état de virage inconnu retombe sur « lointain »', () {
      // Le site peut gagner un état que cette version de l'appli ne connaît
      // pas : mieux vaut un virage sous-estimé qu'un message rejeté.
      final state = NavState.fromJson(payload(over: {
        'turn': {'state': 'imminent', 'distM': 12.0},
      }))!;

      expect(state.turn!.phase, NavTurnPhase.far);
      expect(state.turn!.distM, 12.0);
    });

    test('un virage de mauvais type est ignoré, pas fatal', () {
      final state = NavState.fromJson(payload(over: {'turn': 'oui'}))!;

      expect(state.turn, isNull);
      expect(state.onRoute, isTrue);
    });

    test('un virage sans distance est ignoré', () {
      final state = NavState.fromJson(payload(over: {
        'turn': {'state': 'near'},
      }))!;

      expect(state.turn, isNull);
    });

    test('un virage sans position reste exploitable', () {
      // Sans coordonnées, le chien de garde natif ne peut rien faire — mais la
      // page, elle, continue de dire où on en est.
      final state = NavState.fromJson(payload(over: {
        'turn': {'state': 'near', 'distM': 90.0},
      }))!;

      expect(state.turn!.hasPosition, isFalse);
      expect(state.turn!.phase, NavTurnPhase.near);
    });

    test('un horodatage manquant vaut maintenant', () {
      final before = DateTime.now();
      final state = NavState.fromJson(payload(over: {'at': null}))!;

      expect(state.at.isBefore(before.subtract(const Duration(seconds: 1))),
          isFalse);
    });

    test('les champs numériques manquants valent zéro', () {
      final state = NavState.fromJson({'type': 'nav'})!;

      expect(state.speedKmh, 0);
      expect(state.remainingM, 0);
      expect(state.onRoute, isFalse);
      expect(state.turn, isNull);
      expect(state.climb, isNull);
    });
  });

  group('fraîcheur', () {
    test('un état récent est frais', () {
      final now = DateTime.now();
      final state = NavState(
        at: now.subtract(const Duration(seconds: 2)),
        onRoute: true,
        offRoute: false,
        arrived: false,
      );

      expect(state.isStale(now), isFalse);
    });

    test('un état vieux de plus de cinq secondes a vieilli', () {
      final now = DateTime.now();
      final state = NavState(
        at: now.subtract(const Duration(seconds: 6)),
        onRoute: true,
        offRoute: false,
        arrived: false,
      );

      expect(state.isStale(now), isTrue);
    });

    test('le seuil est réglable', () {
      final now = DateTime.now();
      final state = NavState(
        at: now.subtract(const Duration(seconds: 6)),
        onRoute: true,
        offRoute: false,
        arrived: false,
      );

      expect(state.isStale(now, after: const Duration(seconds: 30)), isFalse);
    });
  });

  group('NavStateNotifier', () {
    test('range un message valable', () {
      final notifier = NavStateNotifier();
      notifier.accept(payload());

      expect(notifier.value!.turn!.phase, NavTurnPhase.near);
    });

    test('garde le dernier état valable sur un message illisible', () {
      // Effacer l'écran parce qu'un message est mal formé serait pire que de
      // montrer une information d'il y a une seconde.
      final notifier = NavStateNotifier();
      notifier.accept(payload());
      notifier.accept({'type': 'nav', 'turn': 'bogus', 'at': 'hier'});

      expect(notifier.value, isNotNull);
      notifier.accept({'type': 'autre_chose'});
      expect(notifier.value, isNotNull);
    });

    test('notifie ses auditeurs', () {
      final notifier = NavStateNotifier();
      var calls = 0;
      notifier.addListener(() => calls++);

      notifier.accept(payload());

      expect(calls, 1);
    });
  });
}
