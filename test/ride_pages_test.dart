import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_scope_companion/ride/ride_pages.dart';

/// Le changement de page se joue sur un guidon, à une main, souvent gantée : un
/// geste ambigu doit ne rien faire plutôt que de deviner.
void main() {
  group('pageAfterSwipe', () {
    test('une chiquenaude vers la gauche avance d\'une page', () {
      expect(
        pageAfterSwipe(current: 0, dx: -20, velocity: -600, count: 3),
        1,
      );
    });

    test('une chiquenaude vers la droite recule d\'une page', () {
      expect(
        pageAfterSwipe(current: 2, dx: 20, velocity: 600, count: 3),
        1,
      );
    });

    test('un glissé lent mais net compte quand même', () {
      // Le doigt s'arrête avant de se lever : la vitesse est nulle, l'intention
      // ne l'est pas.
      expect(
        pageAfterSwipe(current: 0, dx: -120, velocity: 0, count: 3),
        1,
      );
    });

    test('un tremblement ne change pas de page', () {
      expect(pageAfterSwipe(current: 1, dx: -6, velocity: -30, count: 3), 1);
      expect(pageAfterSwipe(current: 1, dx: 0, velocity: 0, count: 3), 1);
    });

    test('la vitesse l\'emporte sur le déplacement cumulé', () {
      // Parti à gauche, renvoyé à droite avant de lâcher : c'est un retour en
      // arrière. Se tromper ici, c'est emmener le cycliste à l'opposé de ce
      // qu'il vient de demander.
      expect(
        pageAfterSwipe(current: 1, dx: -200, velocity: 900, count: 3),
        0,
      );
    });

    test('on ne dépasse pas les extrémités', () {
      expect(pageAfterSwipe(current: 0, dx: 200, velocity: 900, count: 2), 0);
      expect(pageAfterSwipe(current: 1, dx: -200, velocity: -900, count: 2), 1);
    });

    test('sans nombre de pages, le catalogue fait foi', () {
      // La borne suit l'ajout d'une page au catalogue, sans que l'appelant ait
      // à la répéter.
      final last = RidePage.count - 1;

      expect(pageAfterSwipe(current: 0, dx: -200, velocity: -900), 1);
      expect(pageAfterSwipe(current: last, dx: -200, velocity: -900), last);
    });
  });

  group('physicsForMap', () {
    test('la carte vivante coupe le défilement', () {
      // C'est ce qui rend son glissé horizontal à MapLibre.
      expect(
        physicsForMap(mapLive: true),
        isA<NeverScrollableScrollPhysics>(),
      );
    });

    test('sur une page de données, tout l\'écran ramène à la carte', () {
      expect(physicsForMap(mapLive: false), isA<PageScrollPhysics>());
    });
  });

  group('webInsetsFor', () {
    test('le bas disparaît, le haut reste', () {
      // Le bandeau natif couvre la zone système du bas : la page qui la
      // compenserait encore laisserait une bande vide au-dessus du bandeau.
      final insets = webInsetsFor(
        const EdgeInsets.fromLTRB(0, 44, 0, 34),
      );

      expect(insets.top, 44);
      expect(insets.bottom, 0);
    });

    test('les côtés passent tels quels', () {
      // Une encoche en paysage obstrue un bord, et la carte occupe toute la
      // largeur : la page doit continuer d'en tenir compte.
      final insets = webInsetsFor(const EdgeInsets.fromLTRB(48, 0, 12, 34));

      expect(insets.left, 48);
      expect(insets.right, 12);
    });
  });
}
