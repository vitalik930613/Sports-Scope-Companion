import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sports_scope_companion/account/rider_profile.dart';
import 'package:sports_scope_companion/account/rider_profile_store.dart';
import 'package:sports_scope_companion/ble/sensor_hub.dart';
import 'package:sports_scope_companion/recording/gps_fix.dart';
import 'package:sports_scope_companion/recording/gps_source.dart';
import 'package:sports_scope_companion/recording/ride_recorder.dart';
import 'package:sports_scope_companion/recording/ride_store.dart';
import 'package:sports_scope_companion/recording/track_point.dart';
import 'package:sports_scope_companion/ride/nav_state.dart';
import 'package:sports_scope_companion/ride/pages/ride_summary_page.dart';

/// La page Effort dit le cumul, là où le bandeau dit l'instant. Ce qui se
/// vérifie ici : elle ne montre rien quand elle ne sait rien, et la répartition
/// se recolore quand les zones arrivent du site en pleine sortie.
void main() {
  late Directory root;
  late SensorHub hub;
  late RideRecorder recorder;
  late RiderProfileStore profiles;
  final nav = ValueNotifier<NavState?>(null);

  const zones = [
    TrainingZone(key: 'z1', lo: 0, hi: 130),
    TrainingZone(key: 'z2', lo: 130, hi: 144),
    TrainingZone(key: 'z3', lo: 144, hi: 150),
    TrainingZone(key: 'z4', lo: 150, hi: 160),
    TrainingZone(key: 'z5', lo: 160),
  ];

  late _FakeGps gps;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('effort_test');
    hub = SensorHub();
    gps = _FakeGps();
    recorder = RideRecorder(
      hub: hub,
      store: RideStore(Directory(p.join(root.path, 'rides'))),
      // Sans GPS injecté, `start()` appellerait le greffon de plateforme, absent
      // en test — l'enregistrement ne démarrerait jamais et la page resterait sur
      // « sortie non lancée » sans qu'on comprenne pourquoi.
      gps: gps,
      // La vraie cadence, et pas une période neutralisante : c'est elle que la
      // page utilise pour convertir les points en temps, donc la fausser ici
      // rendrait les durées affichées incomparables à celles d'une vraie sortie.
      // Le minuteur ne tire jamais : aucun `pump` de ce fichier n'avance
      // l'horloge simulée d'une seconde, les points sont poussés à la main.
      tickPeriod: const Duration(seconds: 1),
    );
    profiles = RiderProfileStore(File(p.join(root.path, 'profile.json')));
  });

  tearDown(() async {
    recorder.dispose();
    await hub.dispose();
    await gps.close();
    await root.delete(recursive: true);
  });

  Future<void> pumpPage(WidgetTester tester) => tester.pumpWidget(
        MaterialApp(
          home: RideSummaryPage(
            recorder: recorder,
            nav: nav,
            riderProfile: profiles,
          ),
        ),
      );

  testWidgets('hors enregistrement, la page annonce l\'attente sans chiffres',
      (tester) async {
    await pumpPage(tester);

    expect(find.text('La répartition se remplit dès le départ.'), findsOneWidget);
    expect(find.text('Sortie non lancée'), findsOneWidget);
    // Pas de zéros : un zéro se lit comme une mesure.
    expect(find.text('0 %'), findsNothing);
  });

  testWidgets('hors enregistrement, la page offre de démarrer', (tester) async {
    await pumpPage(tester);

    expect(find.text('Démarrer l\'enregistrement'), findsOneWidget);

    // Le tap lui-même part dans `runAsync` : `start()` crée le dossier de sortie
    // et ouvre son fichier de points, de vraies entrées-sorties qui n'aboutissent
    // jamais dans le temps simulé d'un test de widget. Déclenché hors de
    // `runAsync`, l'appui resterait suspendu à sa première attente.
    await tester.runAsync(() async {
      await tester.tap(find.text('Démarrer l\'enregistrement'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();

    expect(recorder.isActive, isTrue);
    // Le bouton disparaît de lui-même : la page suit l'enregistreur, elle ne
    // garde pas un bouton qui ne servirait plus qu'à relancer ce qui tourne.
    expect(find.text('Démarrer l\'enregistrement'), findsNothing);
  });

  testWidgets('en enregistrement, on peut suspendre mais pas terminer',
      (tester) async {
    await tester.runAsync(() => recorder.start());

    await pumpPage(tester);

    expect(find.text('Démarrer l\'enregistrement'), findsNothing);
    expect(find.text('Mettre en pause'), findsOneWidget);
    // Une sortie ne se termine pas au guidon : la pause se défait, l'arrêt non.
    expect(find.textContaining('Terminer'), findsNothing);
  });

  testWidgets('la pause se voit, et se défait d\'un tap', (tester) async {
    await tester.runAsync(() => recorder.start());
    await pumpPage(tester);

    await tester.tap(find.text('Mettre en pause'));
    await tester.pump();

    expect(recorder.state, RecorderState.paused);
    // Le compteur figé se lit aussi bien comme « à l'arrêt à un feu » : il faut
    // que la page dise laquelle des deux, sinon on perd la fin de la sortie sans
    // s'en apercevoir.
    expect(find.text('Enregistrement en pause'), findsOneWidget);
    // Les agrégats restent affichés : la sortie n'est pas terminée.
    expect(find.text('Cardio'), findsOneWidget);

    await tester.tap(find.text('Enregistrement en pause'));
    await tester.pump();

    expect(recorder.state, RecorderState.recording);
    expect(find.text('Mettre en pause'), findsOneWidget);
  });

  testWidgets('sans seuil du site, la page le dit au lieu d\'inventer',
      (tester) async {
    await tester.runAsync(() => recorder.start());
    recorder.stats.add(_point(heartRate: 140));

    await pumpPage(tester);

    expect(
      find.text('Seuil cardiaque inconnu du site : pas de zones.'),
      findsOneWidget,
    );
  });

  testWidgets('la répartition se remplit et totalise le temps mesuré',
      (tester) async {
    await tester.runAsync(() => profiles.record(const RiderProfile(
          lthr: 160,
          hrZones: zones,
        )));
    await tester.runAsync(() => recorder.start());
    // 120 s en z2, 60 s en z4 — la cadence de capture vaut une seconde.
    for (var i = 0; i < 120; i++) {
      recorder.stats.add(_point(heartRate: 135, second: i));
    }
    for (var i = 0; i < 60; i++) {
      recorder.stats.add(_point(heartRate: 155, second: 120 + i));
    }

    await pumpPage(tester);

    expect(find.text('02:00'), findsOneWidget); // z2
    expect(find.text('01:00'), findsOneWidget); // z4
    expect(find.text('67 %'), findsOneWidget);
    expect(find.text('33 %'), findsOneWidget);
    // Les zones jamais touchées restent listées : une zone absente se lirait
    // comme une zone qui n'existe pas.
    expect(find.text('00:00'), findsNWidgets(3));
  });

  testWidgets('un profil reçu en pleine sortie recolore le temps déjà écoulé',
      (tester) async {
    await tester.runAsync(() => recorder.start());
    for (var i = 0; i < 30; i++) {
      recorder.stats.add(_point(heartRate: 155, second: i));
    }

    await pumpPage(tester);
    expect(find.textContaining('Seuil cardiaque inconnu'), findsOneWidget);

    // C'est tout l'intérêt de garder un histogramme plutôt qu'un compteur par
    // zone : les 30 s déjà passées trouvent leur zone rétroactivement.
    await tester.runAsync(() => profiles.record(const RiderProfile(
          lthr: 160,
          hrZones: zones,
        )));
    await tester.pump();

    expect(find.text('00:30'), findsOneWidget);
    expect(find.text('100 %'), findsOneWidget);
  });
}

TrackPoint _point({required int heartRate, int second = 0}) => TrackPoint(
      at: DateTime.utc(2026, 1, 1).add(Duration(seconds: second)),
      distanceM: 0,
      heartRate: heartRate,
    );

/// Un GPS de test : rien ne part tant qu'on ne pousse pas soi-même une position.
/// Même faux que `ride_recorder_test`, la page n'en demandant pas davantage.
class _FakeGps implements GpsSource {
  final _controller = StreamController<GpsFix>.broadcast();

  @override
  Future<void> ensureReady() async {}

  @override
  Stream<GpsFix> watch() => _controller.stream;

  Future<void> close() => _controller.close();
}
