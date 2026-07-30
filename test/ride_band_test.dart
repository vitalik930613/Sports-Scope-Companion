import 'package:flutter_test/flutter_test.dart';
import 'package:sports_scope_companion/ride/widgets/ride_bottom_band.dart';

/// Le bandeau est la seule chose qu'on regarde sans quitter la route des yeux :
/// un glissé dessus doit toujours changer quelque chose, y compris au bout de la
/// liste.
void main() {
  group('RideBandSet.stepped', () {
    test('avance au jeu suivant', () {
      expect(RideBandSet.ride.stepped(1), RideBandSet.effort);
    });

    test('boucle après le dernier', () {
      expect(RideBandSet.values.last.stepped(1), RideBandSet.values.first);
    });

    test('boucle avant le premier', () {
      // Sans ça, glisser vers la droite depuis le premier jeu ne ferait rien —
      // et un geste sans effet se prend pour une panne.
      expect(RideBandSet.values.first.stepped(-1), RideBandSet.values.last);
    });
  });
}
