import 'package:flutter_test/flutter_test.dart';
import 'package:sports_scope_companion/navigation/nav_session.dart';

void main() {
  final now = DateTime(2026, 7, 31, 14, 30);

  Map<String, Object?> payload({
    String name = 'Col de la Croix',
    Object? token = 'abc123',
    Duration age = Duration.zero,
  }) =>
      {
        'name': name,
        'token': token,
        't': now.subtract(age).millisecondsSinceEpoch,
      };

  group('lecture du stockage de la page', () {
    test('nom, token et date', () {
      final session = NavSessionSummary.parse(payload(), now: now)!;

      expect(session.name, 'Col de la Croix');
      expect(session.token, 'abc123');
      expect(session.savedAt, now);
      expect(session.label, 'Col de la Croix');
    });

    test('une destination ad hoc n\'a ni nom ni token', () {
      // « Naviguer ici » n'existe nulle part côté serveur : sans un mot à la
      // place du nom vide, la ligne du sélecteur serait nue.
      final session =
          NavSessionSummary.parse(payload(name: '', token: null), now: now)!;

      expect(session.token, isNull);
      expect(session.label, 'Destination');
    });

    test('rien du tout quand il n\'y a rien', () {
      expect(NavSessionSummary.parse(null, now: now), isNull);
    });

    test('une forme inattendue ne se devine pas', () {
      // Le site peut changer son format sans que l'appli le sache. Proposer de
      // reprendre un tracé qu'on n'a pas compris mènerait à la carte nue, sans
      // que personne ne l'ait demandé.
      expect(NavSessionSummary.parse('du texte', now: now), isNull);
      expect(NavSessionSummary.parse(const {'name': 'X'}, now: now), isNull);
      expect(
        NavSessionSummary.parse(const {'name': 'X', 't': 'hier'}, now: now),
        isNull,
      );
    });
  });

  group('péremption', () {
    test('une séance de tout à l\'heure se reprend', () {
      expect(
        NavSessionSummary.parse(
          payload(age: const Duration(hours: 3)),
          now: now,
        ),
        isNotNull,
      );
    });

    test('celle d\'hier, non', () {
      // Même limite que le site (12 h) : au-delà, la page purge l'entrée à la
      // prochaine ouverture. Proposer de reprendre un tracé qu'elle effacerait
      // sous nos yeux donnerait une carte nue.
      expect(
        NavSessionSummary.parse(
          payload(age: const Duration(hours: 13)),
          now: now,
        ),
        isNull,
      );
    });
  });
}
