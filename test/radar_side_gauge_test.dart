import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_scope_companion/ride/radar_severity.dart';
import 'package:sports_scope_companion/ride/widgets/radar_side_gauge.dart';

/// La forme des marques se juge à l'œil ; ce qui se vérifie ici, c'est qu'il y
/// en ait quand il faut, et **rien du tout** quand il n'y a pas de radar.
void main() {
  Future<void> pump(WidgetTester tester, RadarView view) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                for (final side in RadarGaugeSide.values)
                  Positioned(
                    left: side == RadarGaugeSide.left ? 0 : null,
                    right: side == RadarGaugeSide.right ? 0 : null,
                    top: 0,
                    bottom: 0,
                    child: SizedBox(
                      width: RadarSideGauge.width,
                      child: RadarSideGauge(view: view, side: side),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );

  /// Ce que la jauge peint réellement. `find.byType(CustomPaint)` seul ne dirait
  /// rien : Material en pose déjà un pour son propre compte.
  final painted = find.descendant(
    of: find.byType(RadarSideGauge),
    matching: find.byType(CustomPaint),
  );

  testWidgets('sans radar, les deux gouttières sont vides', (tester) async {
    // Pas de piste, pas de place réservée : sans Varia, l'écran doit être
    // exactement celui d'avant.
    await pump(tester, RadarView.absent);

    expect(painted, findsNothing);
  });

  testWidgets('radar branché, une jauge peinte à chaque bord', (tester) async {
    await pump(tester, const RadarView(severity: RadarSeverity.clear));

    expect(painted, findsNWidgets(2));
  });

  testWidgets('les deux bords pointent chacun vers le leur', (tester) async {
    await pump(
      tester,
      const RadarView(
        severity: RadarSeverity.close,
        positions: [0.8, 0.3],
        nearestM: 28,
      ),
    );

    // Deux jauges, et surtout deux côtés **différents** : le même des deux
    // bords voudrait dire deux triangles pointant du même côté.
    expect(
      tester
          .widgetList<RadarSideGauge>(find.byType(RadarSideGauge))
          .map((gauge) => gauge.side)
          .toSet(),
      {RadarGaugeSide.left, RadarGaugeSide.right},
    );
    expect(painted, findsNWidgets(2));
  });
}
