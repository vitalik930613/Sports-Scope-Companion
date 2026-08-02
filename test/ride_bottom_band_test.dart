import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sports_scope_companion/account/rider_profile.dart';
import 'package:sports_scope_companion/account/rider_profile_store.dart';
import 'package:sports_scope_companion/ble/sensor_hub.dart';
import 'package:sports_scope_companion/recording/ride_recorder.dart';
import 'package:sports_scope_companion/recording/ride_store.dart';
import 'package:sports_scope_companion/dashboard/metric_id.dart';
import 'package:sports_scope_companion/dashboard/ride_preset.dart';
import 'package:sports_scope_companion/ride/nav_state.dart';
import 'package:sports_scope_companion/ride/widgets/ride_bottom_band.dart';
import 'package:sports_scope_companion/ui/zone_colors.dart';

/// Les fonds peints entre la racine et ce texte : c'est là que se trouve la
/// couleur de zone, la case étant peinte autour de son chiffre.
List<Color?> _boxColorsBehind(WidgetTester tester, String text) => [
      for (final decorated in tester.widgetList<DecoratedBox>(
        find.ancestor(
          of: find.text(text),
          matching: find.byType(DecoratedBox),
        ),
      ))
        if (decorated.decoration case final BoxDecoration box) box.color,
    ];

/// Le bandeau est la seule partie du tableau de bord qu'on lit en roulant :
/// ce qu'un glissé y fait, et ce que les zones affichent quand on ne sait rien,
/// se vérifient ici plutôt que sur la route.
void main() {
  late Directory root;
  late SensorHub hub;
  late RideRecorder recorder;
  late RiderProfileStore profiles;
  late MetricSources sources;
  final nav = ValueNotifier<NavState?>(null);

  /// Les jeux de valeurs du tableau de bord intégré : « sortie » puis
  /// « effort », exactement ceux d'avant les profils. Le bandeau ne les connaît
  /// plus lui-même — c'est le profil qui les porte — mais son comportement,
  /// lui, n'a pas bougé d'un pouce, et c'est ce que ces tests vérifient.
  final bands = RidePreset.builtIn.bands;

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
    sources = MetricSources(
      hub: hub,
      recorder: recorder,
      riderProfile: profiles,
      nav: nav,
    );
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
                bands: bands,
                sources: sources,
                page: 0,
                pageCount: 2,
                onGoToPage: (_) {},
              ),
            ),
          ),
        ),
      );

  /// Le bandeau avec la calibration branchée, pour les taps sur les watts.
  Future<void> pumpBandWithCalibration(
    WidgetTester tester, {
    required VoidCallback onCalibratePower,
  }) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: RideBottomBand(
                bands: bands,
                sources: sources,
                page: 0,
                pageCount: 2,
                onGoToPage: (_) {},
                onCalibratePower: onCalibratePower,
              ),
            ),
          ),
        ),
      );

  testWidgets('un tap sur les watts demande la calibration', (tester) async {
    var asked = 0;
    await pumpBandWithCalibration(tester, onCalibratePower: () => asked++);

    // Le jeu « sortie » d'abord : c'est celui qu'on a sous les yeux quand une
    // puissance qui dérive se remarque.
    await tester.tap(find.text('W'));
    await tester.pump();
    expect(asked, 1);

    await tester.fling(find.byType(RideBottomBand), const Offset(-200, 0), 800);
    await tester.pumpAndSettle();

    // La case de zone aussi : elle est aussi fausse que le chiffre quand le
    // capteur dérive, et rien ne dit laquelle des deux le doigt vise.
    await tester.tap(find.text('zone W'));
    await tester.pump();
    expect(asked, 2);
  });

  testWidgets('un glissé parti des watts change de jeu, sans calibrer',
      (tester) async {
    var asked = 0;
    await pumpBandWithCalibration(tester, onCalibratePower: () => asked++);

    // Le geste du bandeau reste prioritaire là où il commence : ouvrir une boîte
    // de dialogue en pleine descente parce qu'on a glissé sur la mauvaise case
    // vaudrait mieux ne jamais brancher le tap.
    await tester.fling(find.text('W'), const Offset(-200, 0), 800);
    await tester.pumpAndSettle();

    expect(asked, 0);
    expect(find.text('zone W'), findsOneWidget);
  });

  testWidgets('les autres cases du bandeau ne calibrent rien', (tester) async {
    var asked = 0;
    await pumpBandWithCalibration(tester, onCalibratePower: () => asked++);

    await tester.tap(find.text('km/h'));
    await tester.tap(find.text('durée'));
    await tester.pump();

    expect(asked, 0);
  });

  testWidgets('un glissé change de jeu de valeurs, pas de page',
      (tester) async {
    var pageAsked = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: RideBottomBand(
              bands: bands,
              sources: sources,
              page: 0,
              pageCount: 2,
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

    for (var i = 0; i < bands.length; i++) {
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

  testWidgets('le cardio et sa zone portent la couleur de la zone',
      (tester) async {
    await tester.runAsync(
      () => profiles.record(
        const RiderProfile(
          lthr: 160,
          hrZones: [
            TrainingZone(key: 'z1', lo: 0, hi: 130),
            TrainingZone(key: 'z4', lo: 130, hi: 160),
            TrainingZone(key: 'z5', lo: 160),
          ],
        ),
      ),
    );
    hub.latestHeartRate.value = 140;

    await pumpBand(tester);
    await tester.fling(find.byType(RideBottomBand), const Offset(-200, 0), 800);
    await tester.pumpAndSettle();

    // Les deux cases, pas seulement celle de la zone : c'est le chiffre qu'on
    // regarde en roulant.
    expect(_boxColorsBehind(tester, '140'), contains(zoneColors['z4']));
    expect(_boxColorsBehind(tester, 'Z4'), contains(zoneColors['z4']));

    // La couleur suit la mesure sans qu'on redessine quoi que ce soit d'autre.
    hub.latestHeartRate.value = 175;
    await tester.pump();

    expect(_boxColorsBehind(tester, '175'), contains(zoneColors['z5']));
  });

  testWidgets('la puissance et sa zone portent la couleur de la zone',
      (tester) async {
    await tester.runAsync(
      () => profiles.record(
        const RiderProfile(
          ftpWatts: 250,
          powerZones: [
            TrainingZone(key: 'z1', lo: 0, hi: 150),
            TrainingZone(key: 'z6', lo: 150, hi: 400),
            TrainingZone(key: 'z7', lo: 400),
          ],
        ),
      ),
    );
    hub.latestPower.value = 300;

    await pumpBand(tester);
    await tester.fling(find.byType(RideBottomBand), const Offset(-200, 0), 800);
    await tester.pumpAndSettle();

    // Les deux dernières zones sont celles que le cardio n'a pas : c'est là que
    // le dégradé prolongé se vérifie, pas sur les cinq premières qu'il partage.
    expect(_boxColorsBehind(tester, '300'), contains(zoneColors['z6']));
    expect(_boxColorsBehind(tester, 'Z6'), contains(zoneColors['z6']));

    hub.latestPower.value = 600;
    await tester.pump();

    expect(_boxColorsBehind(tester, '600'), contains(zoneColors['z7']));
  });

  testWidgets('les watts sont peints jusque dans le jeu de la sortie',
      (tester) async {
    // Le jeu « sortie » n'a pas de case de zone : sans couleur sur le chiffre,
    // la seule mesure d'intensité de l'écran qu'on regarde le plus ne dirait
    // rien de l'effort.
    await tester.runAsync(
      () => profiles.record(
        const RiderProfile(
          ftpWatts: 250,
          powerZones: [TrainingZone(key: 'z5', lo: 0)],
        ),
      ),
    );
    hub.latestPower.value = 300;

    await pumpBand(tester);

    expect(find.text('durée'), findsOneWidget);
    expect(_boxColorsBehind(tester, '300'), contains(zoneColors['z5']));
  });

  testWidgets('sans zones connues, aucune case n\'est peinte', (tester) async {
    hub.latestHeartRate.value = 150;

    await pumpBand(tester);
    await tester.fling(find.byType(RideBottomBand), const Offset(-200, 0), 800);
    await tester.pumpAndSettle();

    // Une couleur inventée serait pire qu'une couleur absente : le cycliste la
    // lirait comme une zone.
    final painted = _boxColorsBehind(tester, '150')
        .where(zoneColors.values.contains)
        .toList();
    expect(painted, isEmpty);
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
