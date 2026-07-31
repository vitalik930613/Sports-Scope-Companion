import 'package:flutter_test/flutter_test.dart';
import 'package:sports_scope_companion/phone/barometric_altitude.dart';

/// L'altimètre barométrique : conversion, calage et lissage. Tout est pur — on
/// lui donne des hectopascals, il rend des mètres.
void main() {
  group('conversion', () {
    test('place le niveau de la mer à zéro en atmosphère standard', () {
      expect(BarometricAltimeter.altitudeFor(BarometricAltimeter.standardSeaLevelHpa),
          closeTo(0, 0.01));
    });

    test('rend les repères connus de l’atmosphère standard', () {
      // ~1000 hPa ≈ 111 m, ~900 hPa ≈ 988 m : les valeurs de table.
      expect(BarometricAltimeter.altitudeFor(1000), closeTo(111, 2));
      expect(BarometricAltimeter.altitudeFor(900), closeTo(988, 3));
    });

    test('seaLevelFor est bien l’inverse de altitudeFor', () {
      // C'est cette réciprocité qui rend le calage juste : on cherche la
      // référence qui place la pression mesurée à l'altitude du GPS.
      final reference = BarometricAltimeter.seaLevelFor(850, 1400);
      expect(BarometricAltimeter.altitudeFor(850, reference), closeTo(1400, 0.01));
    });
  });

  group('mesure', () {
    test('n’a pas d’altitude avant la première pression', () {
      expect(BarometricAltimeter().altitudeM, isNull);
    });

    test('mesure le dénivelé AVANT tout calage', () {
      // Le point de la classe : sans référence l'altitude absolue est fausse,
      // mais ses variations sont justes — et le D+ ne demande rien d'autre.
      // Attendre le GPS perdrait les premières minutes de sortie.
      final altimeter = BarometricAltimeter(smoothing: 1);
      altimeter.addPressure(900);
      final low = altimeter.altitudeM!;
      altimeter.addPressure(880);
      final high = altimeter.altitudeM!;

      expect(altimeter.isCalibrated, isFalse);
      // ~9,3 m par hPa vers 900 hPa (l'écart se creuse avec l'altitude) :
      // 20 hPa valent donc environ 185 m de montée.
      expect(high - low, closeTo(185, 5));
    });

    test('ignore une pression aberrante plutôt que de la propager', () {
      final altimeter = BarometricAltimeter(smoothing: 1);
      altimeter.addPressure(950);
      altimeter.addPressure(0);
      altimeter.addPressure(double.nan);
      expect(altimeter.pressureHpa, 950);
    });

    test('lisse les mesures successives', () {
      final altimeter = BarometricAltimeter(smoothing: 0.5);
      altimeter.addPressure(1000);
      altimeter.addPressure(1002);
      expect(altimeter.pressureHpa, closeTo(1001, 0.001));
    });
  });

  group('calage', () {
    test('aligne l’altitude absolue sur le GPS', () {
      final altimeter = BarometricAltimeter(smoothing: 1);
      altimeter.addPressure(900);
      expect(
          altimeter.calibrateWith(gpsAltitudeM: 1200, accuracyM: 5), isTrue);
      expect(altimeter.altitudeM, closeTo(1200, 0.01));
    });

    test('refuse un point GPS trop imprécis', () {
      // Un point à ±40 m décalerait tout le profil de la sortie.
      final altimeter = BarometricAltimeter(smoothing: 1);
      altimeter.addPressure(900);
      expect(
          altimeter.calibrateWith(gpsAltitudeM: 1200, accuracyM: 40), isFalse);
      expect(altimeter.isCalibrated, isFalse);
    });

    test('refuse de se caler sans pression', () {
      expect(
          BarometricAltimeter().calibrateWith(gpsAltitudeM: 500), isFalse);
    });

    test('ne se cale QU’UNE FOIS par sortie', () {
      // La règle à ne pas défaire : chaque recalage déplace tout le profil d'un
      // coup, et RideStats compte cette marche comme du dénivelé. Recaler
      // régulièrement fabriquerait des centaines de mètres de D+ imaginaire.
      final altimeter = BarometricAltimeter(smoothing: 1);
      altimeter.addPressure(900);
      altimeter.calibrateWith(gpsAltitudeM: 1200, accuracyM: 5);

      expect(altimeter.calibrateWith(gpsAltitudeM: 800, accuracyM: 1), isFalse);
      expect(altimeter.altitudeM, closeTo(1200, 0.01));
    });

    test('un calage ne change pas le dénivelé déjà mesurable', () {
      // Corollaire du précédent : caler ne fait que translater le profil. Deux
      // altimètres, l'un calé l'autre non, doivent voir la MÊME montée.
      final raw = BarometricAltimeter(smoothing: 1);
      final calibrated = BarometricAltimeter(smoothing: 1);
      raw.addPressure(900);
      calibrated.addPressure(900);
      calibrated.calibrateWith(gpsAltitudeM: 1200, accuracyM: 5);

      final rawStart = raw.altitudeM!;
      final calStart = calibrated.altitudeM!;
      raw.addPressure(890);
      calibrated.addPressure(890);

      expect(raw.altitudeM! - rawStart,
          closeTo(calibrated.altitudeM! - calStart, 0.5));
    });

    test('reset rend un altimètre neuf', () {
      final altimeter = BarometricAltimeter(smoothing: 1);
      altimeter.addPressure(900);
      altimeter.calibrateWith(gpsAltitudeM: 1200, accuracyM: 5);
      altimeter.reset();

      expect(altimeter.isCalibrated, isFalse);
      expect(altimeter.altitudeM, isNull);
      expect(altimeter.pressureHpa, isNull);
    });
  });
}
