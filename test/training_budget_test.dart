import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sports_scope_companion/account/rider_profile.dart';
import 'package:sports_scope_companion/account/rider_profile_store.dart';
import 'package:sports_scope_companion/ble/sensor_hub.dart';
import 'package:sports_scope_companion/dashboard/dashboard_block.dart';
import 'package:sports_scope_companion/recording/gps_fix.dart';
import 'package:sports_scope_companion/recording/gps_source.dart';
import 'package:sports_scope_companion/recording/ride_recorder.dart';
import 'package:sports_scope_companion/recording/ride_store.dart';
import 'package:sports_scope_companion/recording/track_point.dart';
import 'package:sports_scope_companion/ride/blocks/training_budget_block.dart';
import 'package:sports_scope_companion/training/ride_load.dart';
import 'package:sports_scope_companion/training/training_budget.dart';
import 'package:sports_scope_companion/training/training_budget_store.dart';

/// Le budget de charge : ce qu'il reste à faire aujourd'hui, et jusqu'où on peut
/// aller.
///
/// C'est le seul composant dont la donnée vient du **site** et non des capteurs :
/// la cible du jour, le plafond de fatigue et le risque supposent l'historique
/// complet des sorties, que le téléphone n'a pas. Ce qui se vérifie ici tient donc
/// en trois points :
///
///  • le décodage ne lève jamais et ne fabrique rien (un champ absent vaut zéro,
///    un budget sans date n'est pas un budget) ;
///  • la sortie **en cours** s'ajoute au budget, avec la même cascade que le site —
///    sans quoi la jauge du guidon et la page Performances compteraient deux
///    charges différentes pour une seule sortie ;
///  • le composant dit ce qu'il ne sait pas : pas de budget du tout, ou un budget
///    qui n'est plus celui du jour.
void main() {
  group('TrainingBudget.fromJson', () {
    test('décode ce que le site envoie', () {
      final budget = TrainingBudget.fromJson({
        'date': '2026-08-03',
        'day': {'done': 24, 'target': 85, 'max': 120},
        'week': {'target': 620, 'done': 418, 'planned': 62, 'remaining': 140},
        'form': {'ctl': 62, 'atl': 74, 'tsb': -12, 'zone': 'productive'},
        'risk': {'acwr': 1.18, 'zone': 'optimal'},
      })!;

      expect(budget.date, DateTime(2026, 8, 3));
      expect(budget.day.target, 85);
      expect(budget.day.max, 120);
      expect(budget.week.remaining, 140);
      expect(budget.form.tsb, -12);
      expect(budget.risk.acwr, 1.18);
      expect(budget.risk.zone, 'optimal');
    });

    test('un budget sans date n\'est pas un budget', () {
      // Il est gardé sur disque pour les départs hors ligne : sans date, on ne
      // pourrait pas dire s'il vaut encore, et l'afficher serait le faire passer
      // pour celui d'aujourd'hui.
      expect(TrainingBudget.fromJson({'day': {'target': 85}}), isNull);
      expect(TrainingBudget.fromJson('demain'), isNull);
      expect(TrainingBudget.fromJson(null), isNull);
    });

    test('un champ absent vaut zéro, pas une exception', () {
      // Le site peut être plus ancien que l'appli, ou l'inverse. Même convention
      // que les décodeurs GATT : ce qu'on ne comprend pas disparaît.
      final budget = TrainingBudget.fromJson({'date': '2026-08-03'})!;

      expect(budget.day.done, 0);
      expect(budget.week.target, 0);
      expect(budget.form.zone, isNull);
      // Le ratio, lui, reste NUL et ne tombe pas à zéro : « pas encore de
      // ratio » et « ratio nul » ne se lisent pas pareil.
      expect(budget.risk.acwr, isNull);
    });

    test('survit à l\'aller-retour par le disque', () {
      final budget = TrainingBudget(
        date: DateTime(2026, 8, 3),
        day: const DayBudget(done: 24, target: 85, max: 120),
        week: const WeekBudget(
          target: 620,
          done: 418,
          planned: 62,
          remaining: 140,
        ),
        form: const RiderForm(ctl: 62, atl: 74, tsb: -12, zone: 'productive'),
        risk: const InjuryRisk(acwr: 1.18, zone: 'optimal'),
      );

      final again = TrainingBudget.fromJson(budget.toJson())!;

      expect(again.date, budget.date);
      expect(again.day.max, 120);
      expect(again.form.zone, 'productive');
      expect(again.risk.acwr, 1.18);
    });

    test('isFor ne compare que le jour', () {
      final budget = TrainingBudget.fromJson({'date': '2026-08-03'})!;

      expect(budget.isFor(DateTime(2026, 8, 3, 18, 42)), isTrue);
      expect(budget.isFor(DateTime(2026, 8, 4)), isFalse);
    });
  });

  group('rideTss', () {
    late Directory root;
    late SensorHub hub;
    late RideRecorder recorder;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('budget_test');
      hub = SensorHub();
      recorder = RideRecorder(
        hub: hub,
        store: RideStore(Directory(p.join(root.path, 'rides'))),
        gps: _SilentGps(),
        tickPeriod: const Duration(days: 1),
      );
    });

    tearDown(() async {
      recorder.dispose();
      await hub.dispose();
      await root.delete(recursive: true);
    });

    /// Une heure de sortie, à la puissance et au cardio demandés.
    void ride({int? power, int? heartRate, int seconds = 3600}) {
      final start = DateTime.utc(2026, 1, 1);
      for (var i = 0; i <= seconds; i++) {
        recorder.stats.add(TrackPoint(
          at: start.add(Duration(seconds: i)),
          // Une distance qui avance : sans elle, tout serait compté à l'arrêt et
          // le temps en mouvement resterait nul.
          distanceM: i * 8.0,
          heartRate: heartRate,
          power: power,
        ));
      }
    }

    test('une heure à sa FTP vaut 100 TSS', () {
      // La définition même du TSS, et le repère qui rend tous les autres
      // lisibles : IF = 1, donc 1 h × 1² × 100.
      ride(power: 250);
      final load = rideTss(recorder.stats, const RiderProfile(ftpWatts: 250))!;

      expect(load.source, RideLoadSource.power);
      expect(load.tss, closeTo(100, 2));
    });

    test('le cardio prend le relais sans capteur de puissance', () {
      ride(heartRate: 160);
      final load = rideTss(recorder.stats, const RiderProfile(lthr: 160))!;

      expect(load.source, RideLoadSource.heartRate);
      expect(load.tss, closeTo(100, 2));
    });

    test('sans aucun capteur, l\'intensité par défaut du vélo', () {
      // Sans elle, un cycliste sans capteur verrait une jauge qui ne bouge
      // jamais, alors que sa sortie sera bel et bien comptée par le site — à
      // 0,70² × 100, soit 49 TSS de l'heure.
      ride();
      final load = rideTss(recorder.stats, RiderProfile.empty)!;

      expect(load.source, RideLoadSource.estimated);
      expect(load.tss, closeTo(49, 2));
    });

    test('la puissance prime sur le cardio, comme sur le site', () {
      ride(power: 250, heartRate: 120);
      final load = rideTss(
        recorder.stats,
        const RiderProfile(ftpWatts: 250, lthr: 160),
      )!;

      expect(load.source, RideLoadSource.power);
      expect(load.tss, closeTo(100, 2));
    });

    test('une intensité absurde est bornée', () {
      // Une FTP saisie à 50 W, un cardio qui s'emballe : sans borne, une heure
      // donnerait des milliers de TSS et le plafond du jour n'aurait plus aucun
      // sens. Même borne que `TrainingLoad::INTENSITY_CAP`.
      ride(power: 400);
      final load = rideTss(recorder.stats, const RiderProfile(ftpWatts: 50))!;

      expect(load.tss, closeTo(maxIntensityFactor * maxIntensityFactor * 100, 3));
    });

    test('rien à compter tant que rien n\'a bougé', () {
      // Zéro serait un chiffre, et un chiffre se lit comme une mesure.
      expect(rideTss(recorder.stats, const RiderProfile(ftpWatts: 250)), isNull);
    });
  });

  group('TrainingBudgetCard', () {
    late Directory root;
    late SensorHub hub;
    late RideRecorder recorder;
    late RiderProfileStore profiles;
    late TrainingBudgetStore budgets;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('budget_card_test');
      hub = SensorHub();
      recorder = RideRecorder(
        hub: hub,
        store: RideStore(Directory(p.join(root.path, 'rides'))),
        gps: _SilentGps(),
        tickPeriod: const Duration(days: 1),
      );
      profiles = RiderProfileStore(File(p.join(root.path, 'profile.json')));
      budgets = TrainingBudgetStore(File(p.join(root.path, 'budget.json')));
    });

    tearDown(() async {
      recorder.dispose();
      await hub.dispose();
      await root.delete(recursive: true);
    });

    TrainingBudget budgetOn(DateTime date) => TrainingBudget(
          date: date,
          day: const DayBudget(done: 24, target: 85, max: 120),
          week: const WeekBudget(
            target: 620,
            done: 418,
            planned: 62,
            remaining: 140,
          ),
          form: const RiderForm(ctl: 62, atl: 74, tsb: -12, zone: 'productive'),
          risk: const InjuryRisk(acwr: 1.18, zone: 'optimal'),
        );

    Future<void> pump(
      WidgetTester tester, {
      TrainingBudgetMode mode = TrainingBudgetMode.day,
      Size size = const Size(320, 260),
    }) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: TrainingBudgetCard(
                budgets: budgets,
                recorder: recorder,
                riderProfile: profiles,
                mode: mode,
                now: DateTime(2026, 8, 3, 10),
              ),
            ),
          ),
        ),
      ));
    }

    testWidgets('sans budget, il dit d\'où il devrait venir', (tester) async {
      // Et pas un tiret : le cycliste ne peut rien y faire au guidon, mais il
      // doit pouvoir comprendre en rentrant que c'est le site qu'il n'a pas
      // atteint — pas un capteur qu'il aurait oublié d'allumer.
      await pump(tester);

      expect(
        find.textContaining('page de navigation'),
        findsOneWidget,
      );
    });

    testWidgets('affiche le fait, la cible et le plafond', (tester) async {
      await tester.runAsync(() => budgets.record(budgetOn(DateTime(2026, 8, 3))));
      await pump(tester);

      expect(find.text('24 / 85'), findsOneWidget);
      expect(find.text('max 120'), findsOneWidget);
      expect(find.text('Aujourd\'hui'), findsOneWidget);
      // La fraîcheur signée : « −12 » et pas « 12 », le signe est l'information.
      expect(find.text('-12'), findsOneWidget);
      expect(find.text('1,18'), findsOneWidget);
    });

    testWidgets('ajoute la sortie en cours à ce qui est déjà enregistré',
        (tester) async {
      await tester.runAsync(() => budgets.record(budgetOn(DateTime(2026, 8, 3))));
      await tester.runAsync(() => profiles.record(
            const RiderProfile(ftpWatts: 250),
          ));
      await tester.runAsync(() => recorder.start());

      // Une demi-heure à la FTP : 50 TSS, qui s'ajoutent aux 24 déjà comptés.
      final start = DateTime.utc(2026, 1, 1);
      for (var i = 0; i <= 1800; i++) {
        recorder.stats.add(TrackPoint(
          at: start.add(Duration(seconds: i)),
          distanceM: i * 8.0,
          power: 250,
        ));
      }

      await pump(tester);

      expect(find.text('74 / 85'), findsOneWidget);
    });

    testWidgets('un budget qui n\'est plus celui du jour se date',
        (tester) async {
      // Le cas d'une sortie partie sans réseau : la forme de fond ne bouge pas en
      // une nuit, mais le « déjà fait » est celui d'hier. On l'affiche en le
      // datant plutôt que de le faire passer pour celui d'aujourd'hui.
      await tester.runAsync(() => budgets.record(budgetOn(DateTime(2026, 8, 1))));
      await pump(tester);

      expect(find.text('Aujourd\'hui'), findsNothing);
      expect(find.textContaining('au 1/8'), findsOneWidget);
    });

    testWidgets('la semaine dit sa cible et ce qu\'il reste', (tester) async {
      await tester.runAsync(() => budgets.record(budgetOn(DateTime(2026, 8, 3))));
      await pump(tester, mode: TrainingBudgetMode.week);

      expect(find.text('418 / 620'), findsOneWidget);
      expect(find.text('reste 140'), findsOneWidget);
      expect(find.text('62 prévus'), findsOneWidget);
    });

    testWidgets('dans une case étroite, tout reste, réduit plutôt que retiré',
        (tester) async {
      // Une case de grille de 3 × 3 : 104 de large. Les deux pastilles n'en
      // sont plus retirées — c'est `ScaleToFit` qui réduit la carte entière
      // pour qu'elles y tiennent quand même.
      await tester.runAsync(() => budgets.record(budgetOn(DateTime(2026, 8, 3))));
      await pump(tester, size: const Size(104, 194));

      expect(find.text('24 / 85'), findsOneWidget);
      expect(find.text('max 120'), findsOneWidget);
      expect(find.text('1,18'), findsOneWidget);
    });
  });
}

/// Un GPS qui ne dit rien : l'enregistreur est ici pour ses statistiques, pas
/// pour une trace.
class _SilentGps implements GpsSource {
  @override
  Future<void> ensureReady() async {}

  @override
  Stream<GpsFix> watch() => const Stream.empty();
}
