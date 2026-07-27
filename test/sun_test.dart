import 'package:flutter_test/flutter_test.dart';
import 'package:sports_scope_companion/lighting/sun.dart';

void main() {
  // Lausanne.
  const lat = 46.52;
  const lon = 6.63;

  double at(DateTime utc) =>
      Sun.elevationDeg(utc: utc, latitude: lat, longitude: lon);

  group('Sun.elevationDeg', () {
    test('midi solaire d\'été : hauteur maximale attendue', () {
      // Le 26 juillet, déclinaison ≈ +19,3°. Hauteur au méridien =
      // 90 - latitude + déclinaison ≈ 62,8°. Midi solaire à Lausanne tombe
      // vers 11h35 UTC.
      final noon = DateTime.utc(2026, 7, 26, 11, 35);
      expect(at(noon), closeTo(62.8, 1.0));
    });

    test('minuit : soleil franchement sous l\'horizon', () {
      expect(at(DateTime.utc(2026, 7, 26, 0, 0)), lessThan(-10));
    });

    test('midi solaire d\'hiver : beaucoup plus bas', () {
      // Solstice d'hiver : déclinaison ≈ -23,4° → 90 - 46,52 - 23,4 ≈ 20,1°.
      final noon = DateTime.utc(2026, 12, 21, 11, 35);
      expect(at(noon), closeTo(20.1, 1.0));
    });

    test('le coucher d\'été encadre 19h15 UTC', () {
      // Coucher vers 21h15 heure locale (UTC+2) fin juillet.
      expect(at(DateTime.utc(2026, 7, 26, 18, 30)), greaterThan(0));
      expect(at(DateTime.utc(2026, 7, 26, 20, 0)), lessThan(0));
    });

    test('la hauteur croît le matin et décroît le soir', () {
      final morning = [8, 9, 10, 11].map((h) =>
          at(DateTime.utc(2026, 7, 26, h))).toList();
      for (var i = 1; i < morning.length; i++) {
        expect(morning[i], greaterThan(morning[i - 1]));
      }

      final evening = [13, 14, 15, 16].map((h) =>
          at(DateTime.utc(2026, 7, 26, h))).toList();
      for (var i = 1; i < evening.length; i++) {
        expect(evening[i], lessThan(evening[i - 1]));
      }
    });

    test('hémisphère sud : saisons inversées', () {
      // Sydney en juillet, c'est l'hiver : soleil bas à midi.
      final noon = DateTime.utc(2026, 7, 26, 2, 0); // ~midi local
      final elevation =
          Sun.elevationDeg(utc: noon, latitude: -33.87, longitude: 151.21);
      expect(elevation, greaterThan(20));
      expect(elevation, lessThan(40));
    });
  });
}
