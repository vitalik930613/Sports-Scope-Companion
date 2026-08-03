import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sports_scope_companion/account/rider_profile_store.dart';
import 'package:sports_scope_companion/ble/sensor_hub.dart';
import 'package:sports_scope_companion/dashboard/companion_settings.dart';
import 'package:sports_scope_companion/dashboard/metric_id.dart';
import 'package:sports_scope_companion/dashboard/ride_preset.dart';
import 'package:sports_scope_companion/recording/gps_fix.dart';
import 'package:sports_scope_companion/recording/gps_source.dart';
import 'package:sports_scope_companion/recording/ride_recorder.dart';
import 'package:sports_scope_companion/recording/ride_store.dart';
import 'package:sports_scope_companion/ride/blocks/metric_view.dart';
import 'package:sports_scope_companion/ride/pages/dashboard_page.dart';
import 'package:sports_scope_companion/training/training_budget_store.dart';

/// Une page en grille, montée pour de vrai.
///
/// La géométrie se vérifie ailleurs, sur des nombres (`grid_layout_test`). Ce
/// qu'on vérifie ici, c'est que le document du site arrive bien jusqu'aux
/// pixels : les fusions occupent leur rectangle, la page **ne défile pas**, et
/// une cellule vide reste vide.
void main() {
  late Directory root;
  late SensorHub hub;
  late RideRecorder recorder;
  late RiderProfileStore profiles;
  late TrainingBudgetStore budgets;
  late MetricSources sources;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('grid_test');
    hub = SensorHub();
    recorder = RideRecorder(
      hub: hub,
      store: RideStore(Directory(p.join(root.path, 'rides'))),
      gps: _SilentGps(),
      tickPeriod: const Duration(days: 1),
    );
    profiles = RiderProfileStore(File(p.join(root.path, 'profile.json')));
    budgets = TrainingBudgetStore(File(p.join(root.path, 'budget.json')));
    sources =
        MetricSources(
      hub: hub,
      recorder: recorder,
      riderProfile: profiles,
      trainingBudget: budgets,
    );
  });

  tearDown(() async {
    recorder.dispose();
    await hub.dispose();
    await root.delete(recursive: true);
  });

  /// La grille de l'exemple du contrat : 3 × 3, ligne du milieu fusionnée sur
  /// toute la largeur, et une cellule de deux colonnes en bas.
  GridPageSpec grid() {
    final settings = CompanionSettings.parse({
      'presets': [
        {
          'key': 'route',
          'pages': [
            {
              'kind': 'grid',
              'title': 'Chiffres',
              'rows': 3,
              'cols': 3,
              'cells': [
                {
                  'row': 0,
                  'col': 0,
                  'block': {'kind': 'metric', 'metric': 'speed', 'mode': 'big'},
                },
                {
                  'row': 0,
                  'col': 1,
                  'block': {'kind': 'metric', 'metric': 'distance'},
                },
                {'row': 0, 'col': 2, 'block': {'kind': 'empty'}},
                {
                  'row': 1,
                  'col': 0,
                  'col_span': 3,
                  'block': {'kind': 'metric', 'metric': 'duration'},
                },
                {
                  'row': 2,
                  'col': 0,
                  'col_span': 2,
                  'block': {'kind': 'metric', 'metric': 'power'},
                },
                {
                  'row': 2,
                  'col': 2,
                  'block': {'kind': 'metric', 'metric': 'cadence'},
                },
              ],
            },
          ],
          'bands': [
            {
              'metrics': ['speed'],
            },
          ],
        },
      ],
    });

    return settings.presets.single.pages.single as GridPageSpec;
  }

  Future<void> pumpGrid(WidgetTester tester) => tester.pumpWidget(
        MaterialApp(home: DashboardPage(page: grid(), sources: sources)),
      );

  /// Le rectangle d'une cellule, repéré par l'unité qu'elle affiche.
  Rect rectOf(WidgetTester tester, String unit) => tester.getRect(
        find.ancestor(
          of: find.text(unit),
          matching: find.byType(MetricView),
        ),
      );

  testWidgets('la grille du document arrive jusqu\'aux pixels', (tester) async {
    await pumpGrid(tester);

    // Cinq mesures et une cellule vide : la vide ne dessine rien mais garde sa
    // place, sinon les autres se décaleraient pour la combler.
    expect(find.byType(MetricView), findsNWidgets(5));
    expect(find.text('km/h'), findsOneWidget);
    expect(find.text('durée'), findsOneWidget);
  });

  testWidgets('une ligne fusionnée occupe toute la largeur', (tester) async {
    await pumpGrid(tester);

    final speed = rectOf(tester, 'km/h'); // une colonne
    final duration = rectOf(tester, 'durée'); // trois colonnes

    expect(duration.left, closeTo(speed.left, 0.5));
    expect(duration.width, greaterThan(speed.width * 2.5));
    // Elle est bien sur la ligne du dessous, pas à côté.
    expect(duration.top, greaterThan(speed.bottom));
  });

  testWidgets('une fusion de deux colonnes en vaut deux, gouttière comprise',
      (tester) async {
    await pumpGrid(tester);

    final power = rectOf(tester, 'W'); // deux colonnes
    final cadence = rectOf(tester, 'tr/min'); // une colonne
    final duration = rectOf(tester, 'durée'); // trois colonnes

    // Deux cellules côte à côte et une cellule de deux colonnes couvrent
    // exactement la même largeur : sans la gouttière intérieure, les bords
    // cesseraient de s'aligner d'une ligne à l'autre.
    expect(power.right + 8 + cadence.width, closeTo(duration.right, 0.5));
    expect(power.top, closeTo(cadence.top, 0.5));
  });

  testWidgets('la page en grille ne défile pas', (tester) async {
    // Elle se lit en roulant : tout doit tenir. Un `GridView` ou une `ListView`
    // laisserait une mesure sous le bord de l'écran, invisible et introuvable à
    // 30 km/h.
    await pumpGrid(tester);

    expect(find.byType(Scrollable), findsNothing);
  });

  testWidgets('sans mesure, chaque case porte un tiret et jamais un zéro',
      (tester) async {
    await pumpGrid(tester);

    // Cinq cases, cinq tirets : un zéro se lirait comme une mesure.
    expect(find.text('—'), findsNWidgets(5));
    expect(find.text('0'), findsNothing);
  });
}

/// Un GPS qui ne rend jamais de position.
class _SilentGps implements GpsSource {
  @override
  Future<void> ensureReady() async {}

  @override
  Stream<GpsFix> watch() => const Stream.empty();
}
