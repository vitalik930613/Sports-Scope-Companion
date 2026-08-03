import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sports_scope_companion/account/rider_profile.dart';
import 'package:sports_scope_companion/account/rider_profile_store.dart';
import 'package:sports_scope_companion/ble/sensor_hub.dart';
import 'package:sports_scope_companion/dashboard/dashboard_block.dart';
import 'package:sports_scope_companion/dashboard/grid_layout.dart';
import 'package:sports_scope_companion/dashboard/metric_id.dart';
import 'package:sports_scope_companion/dashboard/ride_preset.dart';
import 'package:sports_scope_companion/recording/gps_fix.dart';
import 'package:sports_scope_companion/recording/gps_source.dart';
import 'package:sports_scope_companion/recording/ride_recorder.dart';
import 'package:sports_scope_companion/recording/ride_store.dart';
import 'package:sports_scope_companion/recording/track_point.dart';
import 'package:sports_scope_companion/ride/nav_state.dart';
import 'package:sports_scope_companion/ride/pages/dashboard_page.dart';
import 'package:sports_scope_companion/training/training_budget.dart';
import 'package:sports_scope_companion/training/training_budget_store.dart';

/// **Rien ne doit déborder de sa case.**
///
/// Un profil décrit sa grille en lignes et en colonnes ; c'est le téléphone qui
/// sait combien de pixels cela fait. Les composants étaient écrits à taille fixe
/// et réclamaient leur hauteur quelle que soit la case : posés dans le rectangle
/// que leur donne `gridRectFor`, ils se peignaient sur la voisine — et le
/// cycliste le découvrait en roulant, sur le seul écran qu'il ne peut plus
/// modifier.
///
/// Ces tests montent donc les pires grilles composables (jusqu'à 6 × 6, le
/// plafond de [GridPageSpec.maxSide]) sur un téléphone ordinaire, avec dans les
/// cases les composants les plus encombrants : la répartition en sept zones, les
/// moyennes en trois cartes, le bouton d'enregistrement, l'état de navigation.
/// **Un débordement fait échouer le test** : `flutter_test` remonte le
/// « RenderFlex overflowed » comme une erreur.
void main() {
  late Directory root;
  late SensorHub hub;
  late RideRecorder recorder;
  late RiderProfileStore profiles;
  late TrainingBudgetStore budgets;
  late MetricSources sources;
  late _FakeGps gps;
  final nav = ValueNotifier<NavState?>(null);

  const zones = [
    TrainingZone(key: 'z1', lo: 0, hi: 130),
    TrainingZone(key: 'z2', lo: 130, hi: 144),
    TrainingZone(key: 'z3', lo: 144, hi: 150),
    TrainingZone(key: 'z4', lo: 150, hi: 160),
    TrainingZone(key: 'z5', lo: 160),
  ];

  // Sept zones : c'est la liste la plus longue qu'un profil du site puisse
  // envoyer, donc la légende la plus haute qu'une case ait à porter.
  const powerZones = [
    TrainingZone(key: 'z1', lo: 0, hi: 138),
    TrainingZone(key: 'z2', lo: 138, hi: 188),
    TrainingZone(key: 'z3', lo: 188, hi: 225),
    TrainingZone(key: 'z4', lo: 225, hi: 263),
    TrainingZone(key: 'z5', lo: 263, hi: 300),
    TrainingZone(key: 'z6', lo: 300, hi: 375),
    TrainingZone(key: 'z7', lo: 375),
  ];

  /// Un téléphone ordinaire, en pixels logiques. C'est de cette taille que
  /// sortent les cases citées dans `block_density_test.dart`.
  const phone = Size(360, 800);

  setUp(() async {
    root = await Directory.systemTemp.createTemp('overflow_test');
    hub = SensorHub();
    gps = _FakeGps();
    recorder = RideRecorder(
      hub: hub,
      store: RideStore(Directory(p.join(root.path, 'rides'))),
      gps: gps,
      tickPeriod: const Duration(seconds: 1),
    );
    profiles = RiderProfileStore(File(p.join(root.path, 'profile.json')));
    budgets = TrainingBudgetStore(File(p.join(root.path, 'budget.json')));
    sources = MetricSources(
      hub: hub,
      recorder: recorder,
      riderProfile: profiles,
      trainingBudget: budgets,
      nav: nav,
    );
  });

  tearDown(() async {
    recorder.dispose();
    await hub.dispose();
    await gps.close();
    await root.delete(recursive: true);
  });

  /// Une sortie en cours, avec des zones des deux côtés et du temps dedans :
  /// c'est l'état où les composants ont le plus à dire, donc celui qui déborde.
  Future<void> riding(WidgetTester tester) async {
    await tester.runAsync(() => profiles.record(const RiderProfile(
          lthr: 160,
          hrZones: zones,
          ftpWatts: 250,
          powerZones: powerZones,
        )));
    await tester.runAsync(() => recorder.start());
    for (var i = 0; i < 60; i++) {
      recorder.stats.add(TrackPoint(
        at: DateTime.utc(2026, 1, 1).add(Duration(seconds: i)),
        distanceM: 0,
        heartRate: 155,
        power: 200,
      ));
    }
    hub.latestHeartRate.value = 155;
    hub.latestPower.value = 200;
    // Le budget de charge dans son état le plus encombrant : un chiffre à quatre
    // caractères de chaque côté du trait, un plafond, et ses deux pastilles.
    await tester.runAsync(() => budgets.record(TrainingBudget(
          date: DateTime.now(),
          day: const DayBudget(done: 124, target: 185, max: 220),
          week: const WeekBudget(
            target: 620,
            done: 418,
            planned: 162,
            remaining: 140,
          ),
          form: const RiderForm(ctl: 62, atl: 74, tsb: -12, zone: 'productive'),
          risk: const InjuryRisk(acwr: 1.18, zone: 'optimal'),
        )));
    nav.value = NavState(
      at: DateTime.now(),
      onRoute: true,
      offRoute: false,
      arrived: false,
      remainingM: 21400,
      remainingGainM: 380,
    );
  }

  Future<void> pumpGrid(
    WidgetTester tester, {
    required int rows,
    required int cols,
    required List<DashboardBlock> blocks,
    ValueChanged<Size>? onGridMeasured,
  }) async {
    tester.view.physicalSize = phone;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // Les composants sont posés à la file, une case chacun : c'est le pire cas,
    // aucun n'a le renfort d'une fusion.
    final cells = <GridCell>[
      for (var i = 0; i < blocks.length && i < rows * cols; i++)
        GridCell(
          span: GridSpan(row: i ~/ cols, col: i % cols),
          block: blocks[i],
        ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: DashboardPage(
          page: GridPageSpec(
            title: 'Mesures',
            rows: rows,
            cols: cols,
            cells: cells,
          ),
          sources: sources,
          onGridMeasured: onGridMeasured,
        ),
      ),
    );
  }

  /// Tout ce qu'un profil peut poser, dans son mode le plus encombrant.
  List<DashboardBlock> everything() => const [
        ZonesBlock(source: ZonesSource.power),
        ZonesBlock(source: ZonesSource.hr),
        AveragesBlock(),
        RecordingBlock(),
        NavStateBlock(),
        TrainingBudgetBlock(),
        TrainingBudgetBlock(mode: TrainingBudgetMode.week),
        MetricBlock(metric: MetricId.duration, mode: MetricMode.gauge),
        MetricBlock(metric: MetricId.power, mode: MetricMode.gauge),
        MetricBlock(metric: MetricId.heartRate, mode: MetricMode.compact),
        MetricBlock(metric: MetricId.speed),
      ];

  for (final side in [2, 3, 4, 6]) {
    testWidgets('une grille de $side × $side ne déborde d\'aucune case',
        (tester) async {
      await riding(tester);
      await pumpGrid(
        tester,
        rows: side,
        cols: side,
        blocks: everything(),
      );

      // Rien à chercher à l'écran : ce test échoue tout seul si un composant
      // dépasse. Une assertion quand même, pour qu'une page vide — qui, elle, ne
      // déborde jamais — ne passe pas pour un succès.
      expect(find.byType(DashboardPage), findsOneWidget);
    });
  }

  testWidgets('hors enregistrement non plus, où tout est phrases',
      (tester) async {
    // Les états vides sont des phrases entières — « FTP inconnue du site : pas
    // de zones. » — et c'est justement ce qui ne rentre pas dans une case.
    await pumpGrid(tester, rows: 4, cols: 3, blocks: everything());

    expect(find.byType(DashboardPage), findsOneWidget);
  });

  testWidgets('la légende des zones cède la place à sa barre, pas l\'inverse',
      (tester) async {
    await riding(tester);
    await pumpGrid(
      tester,
      rows: 3,
      cols: 1,
      blocks: const [ZonesBlock(source: ZonesSource.power)],
    );

    // Une proportion se lit dans une longueur partagée : la barre survit à des
    // tailles où le tableau ne se lirait plus. Ici la case fait 194 de haut,
    // sept lignes de légende en demandent plus du double.
    expect(find.text('Z7'), findsNothing);
    expect(find.text('Temps par zone de puissance'), findsOneWidget);
  });

  testWidgets('dans une pleine page, la légende est là', (tester) async {
    await riding(tester);
    await pumpGrid(
      tester,
      rows: 1,
      cols: 1,
      blocks: const [ZonesBlock(source: ZonesSource.hr)],
    );

    // Le pendant du test précédent : la dégradation n'est pas un appauvrissement
    // permanent, elle suit la place. Cinq zones dans une pleine page tiennent.
    expect(find.text('Z5'), findsOneWidget);
  });

  testWidgets('la grille annonce la place qu\'elle a réellement eue',
      (tester) async {
    // C'est ce que le site attend pour cesser de supposer un téléphone : le
    // rectangle que les cellules se partagent, marges, en-tête et bandeau du bas
    // déjà retirés. Pris ici et nulle part ailleurs — le recalculer depuis
    // `MediaQuery` dupliquerait cette mise en page en un second endroit, qui
    // dériverait au premier réglage changé.
    final measured = <Size>[];
    await riding(tester);
    await pumpGrid(
      tester,
      rows: 2,
      cols: 2,
      blocks: everything(),
      onGridMeasured: measured.add,
    );
    await tester.pump();

    expect(measured, isNotEmpty);
    // Une page de 360 × 800 : il reste la largeur moins les marges, et une
    // hauteur qui a perdu l'en-tête. Les bornes sont larges exprès — ce qu'on
    // vérifie, c'est que la mesure est celle de la grille et non celle de
    // l'écran.
    expect(measured.last.width, lessThan(360));
    expect(measured.last.width, greaterThan(280));
    expect(measured.last.height, lessThan(760));
    expect(measured.last.height, greaterThan(400));
  });

  testWidgets('une page qui défile garde tout ce qu\'elle avait',
      (tester) async {
    await riding(tester);
    tester.view.physicalSize = phone;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: DashboardPage(
          page: ListPageSpec(title: 'Effort', blocks: everything()),
          sources: sources,
        ),
      ),
    );

    // La hauteur y est infinie : aucune raison de retirer quoi que ce soit, et
    // c'est ce que dit `densityFor` d'une contrainte non bornée.
    expect(find.text('Z7'), findsOneWidget);

    // Les moyennes gardent leurs trois cartes. Il faut aller les chercher : une
    // page qui défile ne construit que ce qu'elle montre, et deux répartitions
    // en zones tiennent déjà tout l'écran.
    await tester.scrollUntilVisible(find.text('Cardio'), 200);
    expect(find.text('Cardio'), findsOneWidget);
    expect(find.text('Puissance'), findsOneWidget);
  });
}

/// Un GPS de test : rien ne part tant qu'on ne pousse pas soi-même une position.
class _FakeGps implements GpsSource {
  final _controller = StreamController<GpsFix>.broadcast();

  @override
  Future<void> ensureReady() async {}

  @override
  Stream<GpsFix> watch() => _controller.stream;

  Future<void> close() => _controller.close();
}
