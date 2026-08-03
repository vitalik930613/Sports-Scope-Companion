import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_scope_companion/dashboard/dashboard_block.dart';
import 'package:sports_scope_companion/ride/blocks/radar_block.dart';
import 'package:sports_scope_companion/ride/radar_severity.dart';
import 'package:sports_scope_companion/ride/widgets/radar_side_gauge.dart';

/// Le radar posé dans une page de données.
///
/// Ce qui se vérifie ici n'est pas la forme des marques — elle se juge à l'œil,
/// et [RadarSideGauge] a déjà son test — mais **le sens** : une cellule large et
/// une cellule haute ne veulent pas de la même jauge, et le mode est le seul à
/// le dire. Plus la règle qui tient tout le bloc : `absent` n'est pas `clear`.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    required RadarMode mode,
    ValueListenable<RadarView>? radar,
    Size size = const Size(300, 150),
  }) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: RadarBlockView(
                  radar: radar ??
                      ValueNotifier(
                        const RadarView(
                          severity: RadarSeverity.close,
                          positions: [0.7, 0.3],
                          nearestM: 28,
                        ),
                      ),
                  mode: mode,
                ),
              ),
            ),
          ),
        ),
      );

  RotatedBox? rotationOf(WidgetTester tester) {
    final boxes = tester.widgetList<RotatedBox>(
      find.descendant(
        of: find.byType(RadarBlockView),
        matching: find.byType(RotatedBox),
      ),
    );
    return boxes.isEmpty ? null : boxes.single;
  }

  testWidgets('couchée, la jauge est la même tournée d\'un quart de tour',
      (tester) async {
    // Un quart de tour dans le sens des aiguilles : le haut de la gouttière —
    // la roue — devient la droite. Une voiture entre donc par la gauche, comme
    // elle entre par le bas au bord de l'écran.
    await pump(tester, mode: RadarMode.gauge);

    expect(find.byType(RadarSideGauge), findsOneWidget);
    expect(rotationOf(tester)?.quarterTurns, 1);
  });

  testWidgets('debout, elle garde le sens de la gouttière', (tester) async {
    // Pas de rotation du tout : c'est le seul mode où les véhicules sont à la
    // même place que sur les bords de l'écran, et c'est ce qui le justifie.
    await pump(
      tester,
      mode: RadarMode.gaugeVertical,
      size: const Size(150, 300),
    );

    expect(find.byType(RadarSideGauge), findsOneWidget);
    expect(rotationOf(tester), isNull);
  });

  testWidgets('sans radar, le bloc le dit plutôt que d\'annoncer voie libre',
      (tester) async {
    // `absent` n'est pas `clear` : écrire « Voie libre » sans capteur serait la
    // pire information que cet écran puisse donner.
    await pump(
      tester,
      mode: RadarMode.distance,
      radar: ValueNotifier(RadarView.absent),
    );

    expect(find.text('Pas de radar'), findsOneWidget);
    expect(find.text('Voie libre'), findsNothing);
  });
}
