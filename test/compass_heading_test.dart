import 'package:flutter_test/flutter_test.dart';
import 'package:sports_scope_companion/phone/compass_heading.dart';

/// L'arbitrage boussole / course GPS. Tout est pur : on lui donne des degrés et
/// des vitesses, il dit quel cap afficher et s'il faut croire le magnétomètre.
void main() {
  /// Roule un moment avec un décalage constant entre boussole et course.
  void ride(CompassHeading compass,
      {required double offsetDeg, int fixes = 40, double courseDeg = 90}) {
    for (var i = 0; i < fixes; i++) {
      compass.addCompass(courseDeg + offsetDeg);
      compass.addCourse(courseDeg: courseDeg, speedMps: 8);
    }
  }

  group('en roulant', () {
    test('affiche la course GPS et non la boussole', () {
      // Le guidon peut être tourné, la roue peut chasser : ce qui compte est la
      // direction réellement suivie.
      final compass = CompassHeading();
      compass.addCompass(200);
      compass.addCourse(courseDeg: 90, speedMps: 8);

      expect(compass.headingDeg, 90);
      expect(compass.isFromCompass, isFalse);
    });

    test('ignore une course rendue à l’arrêt', () {
      // Sous le seuil, la course d'un GPS est du bruit pur.
      final compass = CompassHeading();
      compass.addCourse(courseDeg: 42, speedMps: 0.2);
      expect(compass.headingDeg, isNull);
    });
  });

  group('à l’arrêt', () {
    test('ne dit rien tant que la boussole n’a pas fait ses preuves', () {
      // Deux comparaisons ne prouvent rien : on n'affiche pas un cap qu'on n'a
      // pas vérifié.
      final compass = CompassHeading();
      ride(compass, offsetDeg: 0, fixes: 3);
      compass.addCourse(courseDeg: 90, speedMps: 0);

      expect(compass.isTrusted, isFalse);
      expect(compass.headingDeg, isNull);
    });

    test('prend la main une fois la boussole vérifiée', () {
      final compass = CompassHeading();
      ride(compass, offsetDeg: 0);
      compass.addCourse(courseDeg: 90, speedMps: 0);
      compass.addCompass(270);

      expect(compass.isTrusted, isTrue);
      expect(compass.isFromCompass, isTrue);
      expect(compass.headingDeg, closeTo(270, 2));
    });

    test('corrige un téléphone monté de travers', () {
      // Un support qui tient le téléphone à 90° est courant et sinon
      // indétectable : la boussole lirait « est » quand on regarde le nord.
      // L'écart mesuré en roulant est justement ce qu'il faut retrancher.
      final compass = CompassHeading();
      ride(compass, offsetDeg: 90);
      expect(compass.offsetDeg, closeTo(90, 3));

      compass.addCourse(courseDeg: 90, speedMps: 0);
      compass.addCompass(180);
      expect(compass.headingDeg, closeTo(90, 3));
    });

    test('moyenne les écarts par le passage à 360° et non à travers', () {
      // Un décalage qui oscille autour de 0° donne des écarts de 359° et 1° :
      // une moyenne arithmétique sortirait 180°, exactement à l'opposé.
      final compass = CompassHeading();
      for (var i = 0; i < 40; i++) {
        final offset = i.isEven ? 359.0 : 1.0;
        compass.addCompass(90 + offset);
        compass.addCourse(courseDeg: 90, speedMps: 8);
      }
      final offset = compass.offsetDeg!;
      expect(offset < 5 || offset > 355, isTrue,
          reason: 'écart moyen attendu proche de 0°, obtenu $offset');
    });
  });

  group('support aimanté', () {
    test('ne croit pas une boussole qui ne se recoupe pas avec le GPS', () {
      // Le vrai danger : un support magnétique (Quad Lock MAG et consorts)
      // sature le magnétomètre, qui indique alors le nord de l'aimant. Mieux
      // vaut une flèche figée qu'une flèche qui pointe le support.
      final compass = CompassHeading();
      var deg = 0.0;
      for (var i = 0; i < 60; i++) {
        deg = (deg + 137) % 360; // écarts dispersés sur tout le tour
        compass.addCompass(deg);
        compass.addCourse(courseDeg: 90, speedMps: 8);
      }
      compass.addCourse(courseDeg: 90, speedMps: 0);

      expect(compass.isTrusted, isFalse);
      expect(compass.headingDeg, isNull);
    });

    test('un cap bruité mais cohérent reste exploitable', () {
      // On ne cherche pas un compas de marine : ±20° de bruit autour d'un
      // décalage stable doit rester utilisable pour dire « par là ».
      final compass = CompassHeading();
      for (var i = 0; i < 60; i++) {
        final noise = (i % 5 - 2) * 10.0; // −20°..+20°
        compass.addCompass(90 + noise);
        compass.addCourse(courseDeg: 90, speedMps: 8);
      }
      expect(compass.isTrusted, isTrue);
    });
  });

  test('reset oublie le décalage appris', () {
    final compass = CompassHeading();
    ride(compass, offsetDeg: 90);
    compass.reset();

    expect(compass.isTrusted, isFalse);
    expect(compass.offsetDeg, isNull);
    expect(compass.headingDeg, isNull);
  });
}
