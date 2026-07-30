import 'package:flutter_test/flutter_test.dart';
import 'package:sports_scope_companion/navigation/route_summary.dart';

/// Le décodage est le seul endroit où l'appli et le site se parlent vraiment :
/// une clé qui bouge côté Rails ne se verrait qu'ici, ou sur un parking.
void main() {
  Map<String, dynamic> payload({
    Object? name = 'Col de la Croix',
    Object? token = 'abc123',
  }) =>
      {
        'id': 42,
        'name': name,
        'share_token': token,
        'distance_m': 34200.0,
        'elevation_gain_m': 1210.0,
        'activity': 'cycling',
        'updated_at': '2026-07-28T14:03:11Z',
      };

  group('fromJson', () {
    test('décode ce qui sert à choisir et à ouvrir', () {
      final route = RouteSummary.fromJson(payload())!;

      expect(route.id, 42);
      expect(route.name, 'Col de la Croix');
      expect(route.shareToken, 'abc123');
      expect(route.distanceM, 34200);
      expect(route.elevationGainM, 1210);
      expect(route.activity, 'cycling');
      expect(route.updatedAt, DateTime.utc(2026, 7, 28, 14, 3, 11));
    });

    test('sans jeton de partage, la ligne est écartée', () {
      // Le jeton est la seule clé dont l'appli dispose pour ouvrir un tracé :
      // afficher une ligne sans lui, ce serait proposer un bouton qui ne fait
      // rien.
      expect(RouteSummary.fromJson(payload(token: null)), isNull);
      expect(RouteSummary.fromJson(payload(token: '')), isNull);
    });

    test('sans nom, la ligne est écartée aussi', () {
      expect(RouteSummary.fromJson(payload(name: '')), isNull);
    });

    test('les mesures manquantes valent zéro, pas une exception', () {
      final route = RouteSummary.fromJson({
        'name': 'Sans mesures',
        'share_token': 'xyz',
      })!;

      expect(route.distanceM, 0);
      expect(route.elevationGainM, 0);
      expect(route.activity, isNull);
      expect(route.updatedAt, isNull);
    });

    test('une charge utile absurde ne lève pas', () {
      expect(RouteSummary.fromJson(null), isNull);
      expect(RouteSummary.fromJson('non'), isNull);
      expect(RouteSummary.fromJson(const []), isNull);
    });
  });

  group('listFromPayload', () {
    test('prend `routes` et ignore l\'historique de consultation', () {
      // `opened` est ce qu'on a ouvert récemment, pas ce qu'on possède : le
      // mélanger doublerait des lignes dans la liste.
      final routes = RouteSummary.listFromPayload({
        'routes': [payload(), payload(name: 'Tour du Léman', token: 'def')],
        'opened': [payload(name: 'Vu ailleurs', token: 'ghi')],
        'total': 2,
      });

      expect(routes.map((r) => r.name), ['Col de la Croix', 'Tour du Léman']);
    });

    test('une entrée illisible n\'emporte pas les autres', () {
      final routes = RouteSummary.listFromPayload({
        'routes': [payload(), 'ceci n\'est pas un itinéraire', payload(token: null)],
      });

      expect(routes.length, 1);
    });

    test('accepte aussi une liste nue — celle du cache', () {
      final routes = RouteSummary.listFromPayload([payload()]);

      expect(routes.single.shareToken, 'abc123');
    });

    test('rend une liste vide plutôt que de lever', () {
      expect(RouteSummary.listFromPayload(null), isEmpty);
      expect(RouteSummary.listFromPayload({'routes': 'oups'}), isEmpty);
    });
  });

  test('un aller-retour par le JSON ne perd rien', () {
    // C'est le chemin du cache : ce qui est écrit sur disque doit se relire à
    // l'identique, sinon la liste hors ligne divergerait de celle du site.
    final original = RouteSummary.fromJson(payload())!;
    final round = RouteSummary.fromJson(original.toJson())!;

    expect(round.name, original.name);
    expect(round.shareToken, original.shareToken);
    expect(round.distanceM, original.distanceM);
    expect(round.elevationGainM, original.elevationGainM);
    expect(round.activity, original.activity);
    expect(round.updatedAt, original.updatedAt);
  });
}
