import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_scope_companion/ride/ride_pages.dart';

/// Le changement de page se joue sur un guidon, à une main, souvent gantée : un
/// geste ambigu doit ne rien faire plutôt que de deviner.
void main() {
  group('swipeDirection', () {
    test('une chiquenaude vers la gauche avance', () {
      expect(swipeDirection(dx: -20, velocity: -600), 1);
    });

    test('une chiquenaude vers la droite recule', () {
      expect(swipeDirection(dx: 20, velocity: 600), -1);
    });

    test('un glissé lent mais net compte quand même', () {
      // Le doigt s'arrête avant de se lever : la vitesse est nulle, l'intention
      // ne l'est pas.
      expect(swipeDirection(dx: -120, velocity: 0), 1);
    });

    test('un tremblement ne dit rien', () {
      expect(swipeDirection(dx: -6, velocity: -30), 0);
      expect(swipeDirection(dx: 0, velocity: 0), 0);
    });

    test('la vitesse l\'emporte sur le déplacement cumulé', () {
      // Parti à gauche, renvoyé à droite avant de lâcher : c'est un retour en
      // arrière. Se tromper ici, c'est emmener le cycliste à l'opposé de ce
      // qu'il vient de demander.
      expect(swipeDirection(dx: -200, velocity: 900), -1);
    });
  });

  group('pageOf', () {
    test('replie l\'index brut sur le catalogue', () {
      expect(pageOf(rawPageOriginFor(2), count: 2), 0);
      expect(pageOf(rawPageOriginFor(2) + 1, count: 2), 1);
    });

    test('l\'origine tombe sur la première page, quel qu\'en soit le nombre', () {
      // Le nombre de pages vient du profil : il peut valoir 1 (home-trainer
      // minimal) comme 6. L'origine doit rester un multiple, sinon la sortie
      // s'ouvrirait au milieu du catalogue.
      for (var count = 1; count <= 6; count++) {
        expect(pageOf(rawPageOriginFor(count), count: count), 0,
            reason: '$count page(s)');
      }
    });

    test('un profil d\'une seule page ne divise jamais par zéro', () {
      expect(pageOf(rawPageOriginFor(1) + 3, count: 1), 0);
      expect(pageOf(7, count: 0), 0);
    });

    test('reculer sous l\'origine repart de la fin', () {
      // C'est toute la boucle : la page qui précède la carte est la dernière.
      // Elle tient au `%` de Dart, qui reste positif là où celui de C ou de
      // JavaScript rendrait un index négatif — et donc un plantage.
      expect(pageOf(-1, count: 3), 2);
      expect(pageOf(-3, count: 3), 0);
    });
  });

  group('rawPageFor', () {
    test('reste sur place quand on y est déjà', () {
      expect(rawPageFor(1, from: 1001, count: 4), 1001);
    });

    test('recule quand la cible est juste avant', () {
      expect(rawPageFor(0, from: 1001, count: 4), 1000);
    });

    test('depuis la dernière page, la carte est juste après', () {
      // Et pas trois pages en arrière : rembobiner tout le catalogue sous les
      // yeux du cycliste serait long et illisible. C'est le seul intérêt de
      // l'index brut par rapport à un simple numéro de page.
      expect(rawPageFor(0, from: 1003, count: 4), 1004);
    });

    test('avance quand c\'est plus court', () {
      expect(rawPageFor(2, from: 1001, count: 4), 1002);
    });

    test('viser une page depuis l\'origine y arrive', () {
      final origin = rawPageOriginFor(3);

      expect(pageOf(rawPageFor(2, from: origin, count: 3), count: 3), 2);
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
