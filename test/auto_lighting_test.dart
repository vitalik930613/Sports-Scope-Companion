import 'package:flutter_test/flutter_test.dart';
import 'package:sports_scope_companion/ble/samples.dart';
import 'package:sports_scope_companion/lighting/auto_lighting.dart';

void main() {
  // Lausanne, 26 juillet 2026.
  const lat = 46.52;
  const lon = 6.63;
  final midday = DateTime.utc(2026, 7, 26, 11, 35); // soleil à ~63°
  final night = DateTime.utc(2026, 7, 26, 0, 0); // soleil très bas

  LightingContext ctx(
    DateTime at, {
    RadarSample? radar,
    double? lux,
    FrontLightMode? frontOverride,
    RearLightMode? rearOverride,
    bool located = true,
  }) =>
      LightingContext(
        at: at,
        latitude: located ? lat : null,
        longitude: located ? lon : null,
        lux: lux,
        radar: radar,
        frontOverride: frontOverride,
        rearOverride: rearOverride,
      );

  RadarSample threatAt(DateTime at, int distanceM) => RadarSample(at, [
        RadarTarget(id: 7, distanceM: distanceM, approachSpeedRaw: 10),
      ]);

  group('Ambiance', () {
    test('plein jour : feu de jour devant, clignotant derrière', () {
      final d = AutoLightingPolicy().decide(ctx(midday));
      expect(d.front, FrontLightMode.dayRunning);
      expect(d.rear, RearLightMode.dayFlash);
    });

    test('nuit : faisceau bas devant, feu fixe derrière', () {
      final d = AutoLightingPolicy().decide(ctx(night));
      expect(d.front, FrontLightMode.nightLow);
      expect(d.rear, RearLightMode.nightSteady);
    });

    test('le plein phare ne s\'active jamais tout seul', () {
      final policy = AutoLightingPolicy();
      expect(policy.decide(ctx(night)).front, isNot(FrontLightMode.nightHigh));
      expect(policy.decide(ctx(midday)).front, isNot(FrontLightMode.nightHigh));
    });

    test('le clignotement nocturne arrière doit être demandé', () {
      final policy =
          AutoLightingPolicy(config: const LightingConfig(flashAtNight: true));
      expect(policy.decide(ctx(night)).rear, RearLightMode.nightFlash);
    });

    test('feu de jour avant désactivable', () {
      final policy = AutoLightingPolicy(
          config: const LightingConfig(frontDayRunning: false));
      expect(policy.decide(ctx(midday)).front, FrontLightMode.off);
    });

    test('sans position, aucun avis — et surtout pas une extinction', () {
      final d = AutoLightingPolicy().decide(ctx(midday, located: false));
      expect(d.front, isNull);
      expect(d.rear, isNull);
      expect(d.isEmpty, isTrue);
    });
  });

  group('Lumière mesurée', () {
    test('un tunnel en plein midi allume les feux', () {
      // Ce qu'aucun calcul solaire ne saura jamais : le soleil est à 63°, et on
      // n'y voit rien. C'est toute la raison d'être du capteur.
      final d = AutoLightingPolicy().decide(ctx(midday, lux: 12));
      expect(d.front, FrontLightMode.nightLow);
      expect(d.rear, RearLightMode.nightSteady);
    });

    test('le tunnel n\'attend PAS l\'hystérésis', () {
      // Un tunnel de 200 m se traverse en vingt secondes : attendre les 90 s du
      // maintien reviendrait à en sortir avant que les feux ne s'allument.
      final policy = AutoLightingPolicy();
      policy.decide(ctx(midday));
      final d = policy.decide(ctx(midday.add(const Duration(seconds: 3)), lux: 12));
      expect(d.front, FrontLightMode.nightLow);
    });

    test('mais on ressort du tunnel avec le maintien normal', () {
      // L'asymétrie est délibérée : allumer vite est toujours sûr, éteindre vite
      // ferait battre les feux à chaque tranchée.
      final policy = AutoLightingPolicy();
      policy.decide(ctx(midday, lux: 12));
      final d = policy.decide(ctx(midday.add(const Duration(seconds: 25)), lux: 40000));
      expect(d.front, FrontLightMode.nightLow);
    });

    test('une pénombre ambiguë laisse décider le soleil', () {
      // Entre les deux seuils (ciel couvert, sous-bois, crépuscule clair) la
      // mesure ne tranche rien, et on retombe sur la hauteur du soleil.
      final d = AutoLightingPolicy().decide(ctx(midday, lux: 800));
      expect(d.front, FrontLightMode.dayRunning);
      expect(d.rear, RearLightMode.dayFlash);
    });

    test('un plein soleil mesuré tranche même sans position', () {
      // Sans position il n'y a pas de hauteur solaire à calculer — mais 40 000
      // lux ne laissent aucun doute sur le fait qu'il fait jour.
      final d = AutoLightingPolicy()
          .decide(ctx(midday, lux: 40000, located: false));
      expect(d.front, FrontLightMode.dayRunning);
    });

    test('sans capteur, rien ne change', () {
      // Le repli : un appareil sans lux-mètre se comporte exactement comme avant.
      final d = AutoLightingPolicy().decide(ctx(night, lux: null));
      expect(d.front, FrontLightMode.nightLow);
    });
  });

  group('Hystérésis', () {
    // Ce jour-là à Lausanne, le soleil passe sous 6° entre 18h28 et 18h29 UTC.
    // C'est le crépuscule réel, donc le moment où l'automatisme risque de faire
    // battre les lampes.
    final justBeforeDusk = DateTime.utc(2026, 7, 26, 18, 28);
    final justAfterDusk = DateTime.utc(2026, 7, 26, 18, 29);

    test('ne rebascule pas avant la durée minimale', () {
      final policy = AutoLightingPolicy(
        config: const LightingConfig(minimumDwell: Duration(minutes: 5)),
      );
      final first = policy.decide(ctx(justBeforeDusk));
      expect(first.front, FrontLightMode.dayRunning);
      expect(first.rear, RearLightMode.dayFlash);

      final second = policy.decide(ctx(justAfterDusk));
      expect(second.front, FrontLightMode.dayRunning);
      expect(second.rear, RearLightMode.dayFlash);
    });

    test('bascule une fois la durée écoulée', () {
      final policy = AutoLightingPolicy(
        config: const LightingConfig(minimumDwell: Duration(minutes: 5)),
      );
      policy.decide(ctx(justBeforeDusk));
      final d =
          policy.decide(ctx(justBeforeDusk.add(const Duration(minutes: 6))));
      expect(d.front, FrontLightMode.nightLow);
      expect(d.rear, RearLightMode.nightSteady);
    });
  });

  group('Radar', () {
    test('un véhicule proche escalade l\'arrière immédiatement', () {
      final policy = AutoLightingPolicy(
        config: const LightingConfig(minimumDwell: Duration(hours: 1)),
      );
      policy.decide(ctx(midday));

      final t = midday.add(const Duration(seconds: 1));
      expect(policy.decide(ctx(t, radar: threatAt(t, 80))).rear,
          RearLightMode.alert);
    });

    test('et ne touche pas au phare avant', () {
      final policy = AutoLightingPolicy();
      policy.decide(ctx(night));

      final t = night.add(const Duration(seconds: 1));
      final d = policy.decide(ctx(t, radar: threatAt(t, 30)));
      expect(d.rear, RearLightMode.alert);
      expect(d.front, FrontLightMode.nightLow);
    });

    test('un véhicule lointain ne déclenche rien', () {
      final policy = AutoLightingPolicy(
        config: const LightingConfig(alertDistanceM: 100),
      );
      expect(policy.decide(ctx(midday, radar: threatAt(midday, 250))).rear,
          RearLightMode.dayFlash);
    });

    test('l\'escalade se maintient entre deux trames', () {
      final policy = AutoLightingPolicy(
        config: const LightingConfig(alertHold: Duration(seconds: 10)),
      );
      policy.decide(ctx(midday));

      final t0 = midday.add(const Duration(seconds: 1));
      expect(policy.decide(ctx(t0, radar: threatAt(t0, 50))).rear,
          RearLightMode.alert);

      final t1 = t0.add(const Duration(seconds: 5));
      expect(policy.decide(ctx(t1, radar: RadarSample(t1, const []))).rear,
          RearLightMode.alert);
    });

    test('l\'escalade retombe après le maintien, sans attendre l\'hystérésis',
        () {
      final policy = AutoLightingPolicy(
        config: const LightingConfig(
          alertHold: Duration(seconds: 10),
          minimumDwell: Duration(minutes: 30),
        ),
      );
      policy.decide(ctx(midday));

      final t0 = midday.add(const Duration(seconds: 1));
      policy.decide(ctx(t0, radar: threatAt(t0, 50)));

      final t1 = t0.add(const Duration(seconds: 30));
      expect(policy.decide(ctx(t1, radar: RadarSample(t1, const []))).rear,
          RearLightMode.dayFlash);
    });
  });

  group('Priorité', () {
    test('les choix manuels court-circuitent tout, lampe par lampe', () {
      final policy = AutoLightingPolicy();
      final d = policy.decide(ctx(
        night,
        radar: threatAt(night, 20),
        frontOverride: FrontLightMode.nightHigh,
        rearOverride: RearLightMode.off,
      ));
      expect(d.front, FrontLightMode.nightHigh);
      expect(d.rear, RearLightMode.off);
    });

    test('un override d\'un côté laisse l\'autre automatique', () {
      final policy = AutoLightingPolicy();
      final d = policy.decide(ctx(night, frontOverride: FrontLightMode.off));
      expect(d.front, FrontLightMode.off);
      expect(d.rear, RearLightMode.nightSteady);
    });
  });
}
