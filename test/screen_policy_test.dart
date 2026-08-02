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

  group('réveil radar', () {
    test('une voiture rallume l\'écran en pleine veille', () {
      policy.pageRequested(true);

      expect(policy.radarAwake(true), isTrue);
      expect(policy.dimmed, isFalse);
      // …et il y a alors quelque chose à afficher : sous le voile de la page
      // web, rien ne dit ce qui remonte.
      expect(policy.radarWake, isTrue);
    });

    test('la voiture passée, la veille revient d\'elle-même', () {
      // C'est le point : la demande de la page survit au passage de la voiture.
      // Elle se croit endormie depuis le début et ne redira rien.
      policy.pageRequested(true);
      policy.radarAwake(true);

      expect(policy.radarAwake(false), isTrue);
      expect(policy.dimmed, isTrue);
      expect(policy.radarWake, isFalse);
    });

    test('hors veille, le radar ne recouvre rien', () {
      // La carte est allumée, ses gouttières et ses mètres disent déjà tout :
      // une page radar par-dessus prendrait l'itinéraire au cycliste.
      policy.radarAwake(true);

      expect(policy.radarWake, isFalse);
      expect(policy.dimmed, isFalse);
    });

    test('sur une page de données, le radar ne change rien non plus', () {
      policy.pageRequested(true);
      policy.movedTo(1);

      expect(policy.radarAwake(true), isFalse);
      expect(policy.radarWake, isFalse);
      expect(policy.dimmed, isFalse);
    });

    test('la page qui se réveille pendant l\'alerte reprend l\'écran', () {
      // Un virage approche, ou le cycliste tape sur le voile : la page sort de
      // sa veille et redemande la pleine luminosité. La carte revient, la page
      // radar s'efface — c'est bien la navigation qu'il faut regarder,
      // gouttières comprises.
      policy.pageRequested(true);
      policy.radarAwake(true);

      // Le drapeau rendu est **faux** : le rétroéclairage ne bouge pas, le
      // radar tenait déjà l'écran allumé. C'est tout le piège — la coquille ne
      // peut pas conditionner son rendu à ce drapeau, sinon le noir de la page
      // radar reste jusqu'au passage de la voiture (voir `_applyScreen`).
      expect(policy.pageRequested(false), isFalse);
      expect(policy.radarWake, isFalse);
      expect(policy.dimmed, isFalse);
    });

    test('la voiture passée, une page réveillée ne se rendort pas', () {
      policy.pageRequested(true);
      policy.radarAwake(true);
      policy.pageRequested(false);

      expect(policy.radarAwake(false), isFalse);
      expect(policy.dimmed, isFalse);
    });
  });
}
