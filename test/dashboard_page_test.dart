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
import 'package:sports_scope_companion/dashboard/dashboard_block.dart';
import 'package:sports_scope_companion/dashboard/metric_id.dart';
import 'package:sports_scope_companion/dashboard/ride_preset.dart';
import 'package:sports_scope_companion/ride/nav_state.dart';
import 'package:sports_scope_companion/ride/pages/dashboard_page.dart';
import 'package:sports_scope_companion/ui/zone_colors.dart';
import 'package:sports_scope_companion/training/training_budget_store.dart';

/// La page Effort dit le cumul, là où le bandeau dit l'instant. Ce qui se
/// vérifie ici : elle ne montre rien quand elle ne sait rien, et la répartition
/// se recolore quand les zones arrivent du site en pleine sortie.
///
/// Elle n'est plus écrite en dur : c'est une [ListPageSpec] du profil de sortie,
/// et celle qu'on monte ici est **exactement** la page du profil intégré. Ces
/// tests sont donc aussi la preuve que le repli sur `RidePreset.builtIn` rend
/// bien le tableau de bord d'avant les profils, page comprise.
void main() {
  late Directory root;
  late SensorHub hub;
  late RideRecorder recorder;
  late RiderProfileStore profiles;
  late TrainingBudgetStore budgets;
  late MetricSources sources;
  final nav = ValueNotifier<NavState?>(null);

  /// La page Effort du profil intégré : contrôle d'enregistrement, les deux
  /// répartitions par zone, les moyennes, l'état de navigation.
  final effortPage = RidePreset.builtIn.pages.last;

  const zones = [
    TrainingZone(key: 'z1', lo: 0, hi: 130),
    TrainingZone(key: 'z2', lo: 130, hi: 144),
    TrainingZone(key: 'z3', lo: 144, hi: 150),
    TrainingZone(key: 'z4', lo: 150, hi: 160),
    TrainingZone(key: 'z5', lo: 160),
  ];

  // Sept zones là où le cardio en a cinq : les deux répartitions n'ont ni la
  // même longueur ni le même palier, et rien dans la page ne le déclare — la
  // liste vient du site.
  const powerZones = [
    TrainingZone(key: 'z1', lo: 0, hi: 138),
    TrainingZone(key: 'z2', lo: 138, hi: 188),
    TrainingZone(key: 'z3', lo: 188, hi: 225),
    TrainingZone(key: 'z4', lo: 225, hi: 263),
    TrainingZone(key: 'z5', lo: 263, hi: 300),
    TrainingZone(key: 'z6', lo: 300, hi: 375),
    TrainingZone(key: 'z7', lo: 375),
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

  Future<void> pumpPage(
    WidgetTester tester, {
    List<RidePageSpec> menuPages = const [],
    ValueChanged<int>? onOpenMenuPage,
    VoidCallback? onClose,
    VoidCallback? onChooseRoute,
    VoidCallback? onClearRoute,
    VoidCallback? onCalibratePower,
    VoidCallback? onLeaveRide,
  }) =>
      tester.pumpWidget(
        MaterialApp(
          home: DashboardPage(
            page: effortPage,
            sources: sources,
            menuPages: menuPages,
            onOpenMenuPage: onOpenMenuPage,
            onClose: onClose,
            onChooseRoute: onChooseRoute,
            onClearRoute: onClearRoute,
            onCalibratePower: onCalibratePower,
            onLeaveRide: onLeaveRide,
          ),
        ),
      );

  testWidgets('hors enregistrement, la page annonce l\'attente sans chiffres',
      (tester) async {
    await pumpPage(tester);

    // Chaque répartition nomme sa mesure : la même phrase deux fois de suite se
    // lirait comme un bégaiement de l'appli, et un bloc ne peut pas compter sur
    // son voisin pour le lui éviter — un profil peut n'en poser qu'un.
    expect(
      find.text('Le temps par zone cardio se remplit dès le départ.'),
      findsOneWidget,
    );
    expect(
      find.text('Le temps par zone de puissance se remplit dès le départ.'),
      findsOneWidget,
    );
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

  /// La puissance a sa propre carte, en tout point celle du cardio. Ce qui se
  /// vérifie ici : les deux ne se marchent pas dessus, et l'une peut se remplir
  /// pendant que l'autre attend son premier point.
  group('zones de puissance', () {
    Future<void> pedalling(WidgetTester tester) async {
      await tester.runAsync(() => profiles.record(const RiderProfile(
            lthr: 160,
            hrZones: zones,
            ftpWatts: 250,
            powerZones: powerZones,
          )));
      await tester.runAsync(() => recorder.start());
      // 60 s à 200 W, soit la z3 de ce profil — le palier de 25 W place la
      // mesure sur [200, 225[, dont le milieu tombe bien dans la zone.
      for (var i = 0; i < 60; i++) {
        recorder.stats.add(_point(power: 200, second: i));
      }
    }

    testWidgets('la répartition de puissance a sa carte, et ses sept zones',
        (tester) async {
      await pedalling(tester);
      hub.latestPower.value = 200;

      await pumpPage(tester);

      expect(find.text('Temps par zone de puissance'), findsOneWidget);
      expect(find.text('01:00'), findsOneWidget);
      expect(find.text('100 %'), findsOneWidget);
      // Z6 et Z7 n'existent pas côté cardio : les voir ici prouve que la carte
      // dessine la liste du site et non cinq zones en dur.
      expect(find.text('Z7'), findsOneWidget);
      expect(find.text('00:00'), findsNWidgets(6));
    });

    testWidgets('l\'éclair dit laquelle des deux cartes on lit',
        (tester) async {
      await pedalling(tester);
      // Les deux capteurs parlent, donc les deux cartes ont une ligne courante.
      for (var i = 0; i < 60; i++) {
        recorder.stats.add(_point(heartRate: 155, second: i));
      }
      hub.latestPower.value = 200;
      hub.latestHeartRate.value = 155; // z4 cardio

      await pumpPage(tester);

      // Les deux cartes se ressemblent trait pour trait : sans l'icône, une
      // ligne peinte au milieu de l'écran ne dirait pas de quoi elle parle.
      expect(find.byIcon(Icons.bolt), findsOneWidget);
      expect(find.byIcon(Icons.favorite), findsOneWidget);
    });

    testWidgets('sans capteur de puissance, la carte attend sans zéros',
        (tester) async {
      await tester.runAsync(() => profiles.record(const RiderProfile(
            lthr: 160,
            hrZones: zones,
            ftpWatts: 250,
            powerZones: powerZones,
          )));
      await tester.runAsync(() => recorder.start());
      for (var i = 0; i < 30; i++) {
        recorder.stats.add(_point(heartRate: 135, second: i));
      }

      await pumpPage(tester);

      // Le cardio se remplit pendant que la puissance attend : sept zones à
      // zéro se liraient comme une sortie sans effort.
      expect(find.text('00:30'), findsOneWidget);
      expect(find.text('Pas encore de puissance mesurée.'), findsOneWidget);
    });

    testWidgets('sans FTP connue du site, la page le dit au lieu d\'inventer',
        (tester) async {
      await tester.runAsync(() => profiles.record(const RiderProfile(
            lthr: 160,
            hrZones: zones,
          )));
      await tester.runAsync(() => recorder.start());
      recorder.stats.add(_point(power: 200));

      await pumpPage(tester);

      // Le trou est côté site, et il se comble sur le site : le dire nommément
      // est la seule façon d'y renvoyer le cycliste.
      expect(find.text('FTP inconnue du site : pas de zones.'), findsOneWidget);
    });
  });

  /// La ligne de la zone du moment est peinte de sa couleur : c'est ce qui
  /// rattache le cumul à ce qu'on ressent en pédalant.
  group('zone courante', () {
    /// Le fond de la ligne d'une zone — le [Container] le plus proche du texte
    /// de sa clé, la pastille de couleur n'étant pas un ancêtre de ce texte.
    Color? lineColor(WidgetTester tester, String key) {
      final line = tester.widget<Container>(
        find
            .ancestor(
              of: find.text(key),
              matching: find.byType(Container),
            )
            .first,
      );
      return (line.decoration as BoxDecoration?)?.color;
    }

    Future<void> riding(WidgetTester tester) async {
      await tester.runAsync(() => profiles.record(const RiderProfile(
            lthr: 160,
            hrZones: zones,
          )));
      await tester.runAsync(() => recorder.start());
      for (var i = 0; i < 30; i++) {
        recorder.stats.add(_point(heartRate: 135, second: i));
      }
    }

    testWidgets('la ligne de la zone du moment porte sa couleur',
        (tester) async {
      await riding(tester);
      hub.latestHeartRate.value = 155; // z4

      await pumpPage(tester);

      expect(lineColor(tester, 'Z4'), zoneColors['z4']);
      // Une seule ligne peinte : deux aplats ne diraient plus où l'on est.
      expect(lineColor(tester, 'Z2'), Colors.transparent);
      expect(find.byIcon(Icons.favorite), findsOneWidget);
    });

    testWidgets('elle suit le cardio sans attendre l\'histogramme',
        (tester) async {
      await riding(tester);
      hub.latestHeartRate.value = 155;
      await pumpPage(tester);

      // Le cumul, lui, n'a pas bougé : la zone courante est l'instant, et c'est
      // le hub qui la donne — pas le dernier palier rempli, qui peut dater du
      // col d'il y a une heure.
      hub.latestHeartRate.value = 135;
      await tester.pump();

      expect(lineColor(tester, 'Z2'), zoneColors['z2']);
      expect(lineColor(tester, 'Z4'), Colors.transparent);
    });

    testWidgets('sans cardio, aucune ligne n\'est peinte', (tester) async {
      await riding(tester);

      await pumpPage(tester);

      // Le capteur s'est tu : peindre la dernière zone connue laisserait croire
      // qu'on y est encore, alors que le cardio ne dit plus rien.
      for (final key in ['Z1', 'Z2', 'Z3', 'Z4', 'Z5']) {
        expect(lineColor(tester, key), Colors.transparent);
      }
      expect(find.byIcon(Icons.favorite), findsNothing);
    });
  });

  /// Changer de tracé en pleine sortie : on part sur un itinéraire, on décide de
  /// couper ou de rentrer. La page ne navigue pas elle-même — elle demande à la
  /// coquille, qui possède le WebView.
  group('menu de l\'itinéraire', () {
    /// L'état de navigation est partagé par tout le fichier : le rendre à son
    /// silence évite qu'un test d'ici décide de ce que voit le suivant.
    void onRoute(bool following) {
      addTearDown(() => nav.value = null);
      nav.value = following
          ? NavState(
              at: DateTime.now(),
              onRoute: true,
              offRoute: false,
              arrived: false,
            )
          : null;
    }

    Future<void> openMenu(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
    }

    testWidgets('sans commandes, pas de menu', (tester) async {
      // La page se monte aussi hors d'une sortie : un menu qui ne mènerait
      // nulle part vaut moins que pas de menu.
      await pumpPage(tester);

      expect(find.byIcon(Icons.more_vert), findsNothing);
    });

    testWidgets('on peut choisir un autre itinéraire', (tester) async {
      var chosen = 0;
      onRoute(true);
      await pumpPage(tester, onChooseRoute: () => chosen++);

      await openMenu(tester);
      await tester.tap(find.text('Choisir un autre itinéraire'));
      await tester.pumpAndSettle();

      expect(chosen, 1);
    });

    testWidgets('sur un tracé, on peut le retirer', (tester) async {
      var cleared = 0;
      onRoute(true);
      await pumpPage(tester, onClearRoute: () => cleared++);

      await openMenu(tester);
      await tester.tap(find.text('Retirer l\'itinéraire'));
      await tester.pumpAndSettle();

      expect(cleared, 1);
    });

    testWidgets('la calibration s\'atteint sans quitter la sortie',
        (tester) async {
      // C'est en roulant qu'on voit la puissance dériver : sortir de la
      // navigation pour aller la calibrer coûterait la carte et son démarrage,
      // donc on ne le ferait pas.
      var calibrated = 0;
      onRoute(false);
      await pumpPage(tester, onCalibratePower: () => calibrated++);

      await openMenu(tester);
      await tester.tap(find.text('Calibrer la puissance'));
      await tester.pumpAndSettle();

      expect(calibrated, 1);
    });

    testWidgets('sans capteur calibrable, la commande n\'est pas là',
        (tester) async {
      // La coquille ne passe la commande que si un capteur connecté sait
      // répondre : un menu qui ne peut que dire non se lit comme une panne.
      await pumpPage(tester, onChooseRoute: () {});

      await openMenu(tester);

      expect(find.text('Calibrer la puissance'), findsNothing);
    });

    testWidgets('sans tracé, il n\'y a rien à retirer', (tester) async {
      // En navigation libre — ou tant que la page n'a rien dit — proposer de
      // retirer un itinéraire laisserait croire qu'il y en a un.
      onRoute(false);
      await pumpPage(
        tester,
        onChooseRoute: () {},
        onClearRoute: () {},
      );

      await openMenu(tester);

      expect(find.text('Choisir un autre itinéraire'), findsOneWidget);
      expect(find.text('Retirer l\'itinéraire'), findsNothing);
    });

    testWidgets('rentrer est une commande écrite, pas un geste à deviner',
        (tester) async {
      // Le seul chemin de sortie était le bouton retour du téléphone, sans
      // qu'on sache combien de fois l'appuyer.
      var left = 0;
      await pumpPage(tester, onLeaveRide: () => left++);

      await openMenu(tester);
      await tester.tap(find.text('Revenir à l\'accueil'));
      await tester.pumpAndSettle();

      expect(left, 1);
    });

    // Les pages que le profil range derrière le menu : on va les chercher au
    // lieu de tomber dessus. C'est ce qui rend tenable une page qu'on ne lit pas
    // en roulant — un bilan, des répartitions — sans la mettre à un glissé de la
    // carte.
    const bilan = ListPageSpec(
      title: 'Bilan',
      blocks: [AveragesBlock()],
      menu: true,
    );

    testWidgets('les pages rangées s\'ouvrent depuis le menu', (tester) async {
      var opened = -1;
      await pumpPage(
        tester,
        menuPages: const [bilan],
        onOpenMenuPage: (index) => opened = index,
      );

      await openMenu(tester);
      // Le titre du profil sert de libellé : c'est celui qu'on a écrit dans
      // l'éditeur, donc celui qu'on cherche.
      await tester.tap(find.text('Bilan'));
      await tester.pumpAndSettle();

      expect(opened, 0);
    });

    testWidgets('une page rangée suffit à faire un menu', (tester) async {
      // Sans aucune commande d'itinéraire — un profil de home-trainer — le menu
      // doit quand même exister : c'est le seul chemin vers ces pages.
      await pumpPage(
        tester,
        menuPages: const [bilan],
        onOpenMenuPage: (_) {},
      );

      expect(find.byIcon(Icons.more_vert), findsOneWidget);
    });

    testWidgets('la page ouverte depuis le menu se referme, sans menu',
        (tester) async {
      // Elle n'a aucun voisin : une page du défilement se quitte au glissé,
      // celle-ci n'a que ce bouton. Et pas de menu par-dessus — on referme
      // d'abord, plutôt que d'empiler des pages qu'on quitte une par une en
      // roulant.
      var closed = 0;
      await pumpPage(
        tester,
        onClose: () => closed++,
        menuPages: const [bilan],
        onOpenMenuPage: (_) {},
        onLeaveRide: () {},
      );

      expect(find.byIcon(Icons.more_vert), findsNothing);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(closed, 1);
    });
  });
}

TrackPoint _point({int? heartRate, int? power, int second = 0}) => TrackPoint(
      at: DateTime.utc(2026, 1, 1).add(Duration(seconds: second)),
      distanceM: 0,
      heartRate: heartRate,
      power: power,
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
