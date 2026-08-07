import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_scope_companion/dashboard/dashboard_block.dart';
import 'package:sports_scope_companion/ride/blocks/radar_block.dart';
import 'package:sports_scope_companion/ride/radar_severity.dart';

/// Le radar posé dans une page de données.
///
/// Ce qui se vérifie ici, c'est la règle qui tient tout le bloc : `absent`
/// n'est pas `clear`.
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
