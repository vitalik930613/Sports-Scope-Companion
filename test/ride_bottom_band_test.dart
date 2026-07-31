import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sports_scope_companion/account/rider_profile.dart';
import 'package:sports_scope_companion/account/rider_profile_store.dart';
import 'package:sports_scope_companion/ble/sensor_hub.dart';
import 'package:sports_scope_companion/recording/ride_recorder.dart';
import 'package:sports_scope_companion/recording/ride_store.dart';
import 'package:sports_scope_companion/ride/nav_state.dart';
import 'package:sports_scope_companion/ride/ride_pages.dart';
import 'package:sports_scope_companion/ride/widgets/ride_bottom_band.dart';

/// Le bandeau est la seule partie du tableau de bord qu'on lit en roulant :
/// ce qu'un glissé y fait, et ce que les zones affichent quand on ne sait rien,
/// se vérifient ici plutôt que sur la route.
void main() {
  late Directory root;
  late SensorHub hub;
  late RideRecorder recorder;
  late RiderProfileStore profiles;
  final nav = ValueNotifier<NavState?>(null);

  setUp(() async {
    root = await Directory.systemTemp.createTemp('band_test');
    hub = SensorHub();
    recorder = RideRecorder(
      hub: hub,
      store: RideStore(Directory(p.join(root.path, 'rides'))),
      // Jamais démarré : le bandeau se contente des compteurs à l'arrêt, et une
      // horloge réelle ferait battre le test pour rien.
      tickPeriod: const Duration(days: 1),
    );
    profiles = RiderProfileStore(File(p.join(root.path, 'profile.json')));
  });

  tearDown(() async {
    recorder.dispose();
    await hub.dispose();
    await root.delete(recursive: true);
  });

  Future<void> pumpBand(WidgetTester tester) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: RideBottomBand(
                hub: hub,
                recorder: recorder,
                nav: nav,
                riderProfile: profiles,
                page: RidePage.navigation,
                onGoToPage: (_) {},
              ),
            ),
          ),
        ),
      );

  testWidgets('un glissé change de jeu de valeurs, pas de page',
      (tester) async {
    var pageAsked = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: RideBottomBand(
              hub: hub,
              recorder: recorder,
              nav: nav,
              riderProfile: profiles,
              page: RidePage.navigation,
              onGoToPage: (_) => pageAsked = true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('durée'), findsOneWidget);
    expect(find.text('zone bpm'), findsNothing);

    await tester.fling(
      find.byType(RideBottomBand),
      const Offset(-200, 0),
      800,
    );
    await tester.pumpAndSettle();

    expect(find.text('zone bpm'), findsOneWidget);
    expect(find.text('zone W'), findsOneWidget);
    expect(find.text('durée'), findsNothing);
    // Le point de tout ce chantier : le bandeau ne déplace plus le tableau de
    // bord, il ne fait que changer ce qu'il montre.
    expect(pageAsked, isFalse);
  });

  testWidgets('le glissé boucle : deux jeux, deux gestes, retour au départ',
      (tester) async {
    await pumpBand(tester);

    for (var i = 0; i < RideBandSet.count; i++) {
      await tester.fling(
        find.byType(RideBottomBand),
        const Offset(-200, 0),
        800,
      );
      await tester.pumpAndSettle();
    }

    expect(find.text('durée'), findsOneWidget);
  });

  testWidgets('sans seuils connus, la zone nomme le seuil qui manque',
      (tester) async {
    hub.latestHeartRate.value = 150;
    hub.latestPower.value = 210;
    await pumpBand(tester);
    await tester.fling(
      find.byType(RideBottomBand),
      const Offset(-200, 0),
      800,
    );
    await tester.pumpAndSettle();

    expect(find.text('150'), findsOneWidget);
    expect(find.text('210'), findsOneWidget);
    // Les deux capteurs parlent, les deux zones ne peuvent pas se calculer :
    // aucun « Z1 » par défaut — le cycliste le lirait comme une mesure — mais
    // pas un tiret muet non plus, qui se lit comme un capteur débranché alors
    // que le trou est côté site.
    expect(find.text('LTHR ?'), findsOneWidget);
    expect(find.text('FTP ?'), findsOneWidget);
    expect(find.text('—'), findsNothing);
  });

  testWidgets('seuil manquant : le nom du seuil passe avant le capteur muet',
      (tester) async {
    // Capteurs muets *et* seuils inconnus : c'est le seuil qu'on annonce.
    // Attendre une mesure pour le dire retarderait l'information jusqu'au
    // moment où le cycliste a les mains prises.
    await pumpBand(tester);
    await tester.fling(
      find.byType(RideBottomBand),
      const Offset(-200, 0),
      800,
    );
    await tester.pumpAndSettle();

    expect(find.text('LTHR ?'), findsOneWidget);
    expect(find.text('FTP ?'), findsOneWidget);
    // Les deux mesures, elles, gardent leur tiret.
    expect(find.text('—'), findsNWidgets(2));
  });

  testWidgets('un seul seuil connu : l\'autre zone reste un tiret',
      (tester) async {
    await tester.runAsync(
      () => profiles.record(
        const RiderProfile(
          lthr: 160,
          hrZones: [TrainingZone(key: 'z1', lo: 0)],
        ),
      ),
    );
    hub.latestHeartRate.value = 120;

    await pumpBand(tester);
    await tester.fling(
      find.byType(RideBottomBand),
      const Offset(-200, 0),
      800,
    );
    await tester.pumpAndSettle();

    expect(find.text('Z1'), findsOneWidget);
    // La FTP manque, mais pas la LTHR : le bandeau ne signale que le trou réel.
    expect(find.text('FTP ?'), findsOneWidget);
    expect(find.text('LTHR ?'), findsNothing);
  });

  testWidgets('avec les seuils du site, la zone suit la mesure', (tester) async {
    // `runAsync` : le profil est écrit sur le disque, et le temps d'un
    // `testWidgets` est simulé — une vraie entrée-sortie attendue dans cette
    // horloge-là ne se termine jamais.
    await tester.runAsync(
      () => profiles.record(
        const RiderProfile(
          lthr: 160,
          hrZones: [
            TrainingZone(key: 'z1', lo: 0, hi: 130),
            TrainingZone(key: 'z2', lo: 130, hi: 155),
            TrainingZone(key: 'z3', lo: 155),
          ],
        ),
      ),
    );
    hub.latestHeartRate.value = 140;

    await pumpBand(tester);
    await tester.fling(
      find.byType(RideBottomBand),
      const Offset(-200, 0),
      800,
    );
    await tester.pumpAndSettle();

    expect(find.text('Z2'), findsOneWidget);

    // Le bandeau suit le capteur sans qu'on le lui redemande : c'est un
    // compteur, pas une capture.
    hub.latestHeartRate.value = 170;
    await tester.pump();

    expect(find.text('Z3'), findsOneWidget);
  });
}
