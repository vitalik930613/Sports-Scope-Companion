import 'package:flutter_test/flutter_test.dart';
import 'package:sports_scope_companion/ride/screen_policy.dart';

/// Assombrir l'écran met la luminosité **globale** du téléphone à 1 %. Se
/// tromper ici, ce n'est pas un défaut d'affichage : c'est un cycliste qui ne
/// voit plus rien et doit s'arrêter.
void main() {
  late ScreenPolicy policy;

  setUp(() => policy = ScreenPolicy());

  test('rien n\'est assombri au départ', () {
    expect(policy.dimmed, isFalse);
  });

  test('sur la carte, la page obtient sa veille', () {
    expect(policy.pageRequested(true), isTrue);
    expect(policy.dimmed, isTrue);
  });

  test('la même demande deux fois ne change rien', () {
    // La page redemande sa veille à chaque rechargement : on ne va pas
    // retoucher la luminosité du système pour autant.
    policy.pageRequested(true);

    expect(policy.pageRequested(true), isFalse);
    expect(policy.dimmed, isTrue);
  });

  test('quitter la carte rallume', () {
    policy.pageRequested(true);

    expect(policy.movedTo(1), isTrue);
    expect(policy.dimmed, isFalse);
  });

  test('revenir sur la carte rend la veille sans que la page redemande', () {
    // C'est tout l'intérêt de retenir la demande plutôt que de la refuser : la
    // page se croit déjà endormie et ne redira rien.
    policy.pageRequested(true);
    policy.movedTo(1);

    expect(policy.movedTo(0), isTrue);
    expect(policy.dimmed, isTrue);
  });

  test('une page de données ne s\'assombrit jamais', () {
    policy.movedTo(1);

    expect(policy.pageRequested(true), isFalse);
    expect(policy.dimmed, isFalse);
  });

  test('la page se réveille pendant qu\'on lit une autre page', () {
    policy.pageRequested(true);
    policy.movedTo(1);
    // Réveil annoncé alors que rien n'était assombri : aucun effet visible…
    expect(policy.pageRequested(false), isFalse);

    // …mais revenir sur la carte ne doit surtout pas la rendormir.
    expect(policy.movedTo(0), isFalse);
    expect(policy.dimmed, isFalse);
  });

  test('un rechargement de page annule la veille', () {
    // Le voile noir est parti avec l'état de la page : sans ça, l'appareil
    // resterait à 1 % pour le reste de la sortie.
    policy.pageRequested(true);

    expect(policy.pageReloaded(), isTrue);
    expect(policy.dimmed, isFalse);
  });

  test('un rechargement hors carte ne rallume rien qui soit éteint', () {
    policy.movedTo(1);

    expect(policy.pageReloaded(), isFalse);
    expect(policy.dimmed, isFalse);
  });
}
