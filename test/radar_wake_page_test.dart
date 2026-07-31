import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_scope_companion/ride/radar_severity.dart';
import 'package:sports_scope_companion/ride/widgets/radar_wake_page.dart';

/// La page qui rallume l'écran d'un cycliste qui ne le regardait pas. Ce qui se
/// vérifie ici n'est pas sa mise en page — elle se juge à l'œil — mais ce
/// qu'elle **dit**, et surtout ce qu'elle ne dit pas quand le radar s'est tu.
void main() {
  Future<void> pump(WidgetTester tester, RadarView view) => tester.pumpWidget(
        MaterialApp(home: Scaffold(body: RadarWakePage(view: view))),
      );

  testWidgets('un véhicule proche : les mètres, en gros', (tester) async {
    await pump(
      tester,
      const RadarView(
        severity: RadarSeverity.close,
        positions: [0.9],
        nearestM: 24,
      ),
    );

    expect(find.text('24 m'), findsOneWidget);
    // Une seule voiture ne se compte pas : « ×1 » ferait chercher la deuxième.
    expect(find.textContaining('×'), findsNothing);
  });

  testWidgets('plusieurs véhicules : le compte s\'écrit', (tester) async {
    await pump(
      tester,
      const RadarView(
        severity: RadarSeverity.approaching,
        positions: [0.4, 0.2, 0.1],
        nearestM: 84,
      ),
    );

    expect(find.text('84 m'), findsOneWidget);
    expect(find.text('×3'), findsOneWidget);
  });

  testWidgets('la voie libre est annoncée : c\'est pourquoi l\'écran s\'éteint',
      (tester) async {
    // Affiché pendant le maintien, une fois le véhicule passé.
    await pump(tester, const RadarView(severity: RadarSeverity.clear));

    expect(find.text('Voie libre'), findsOneWidget);
  });

  testWidgets('un radar perdu ne dit jamais « voie libre »', (tester) async {
    // La règle du dépôt, à l'endroit le plus dangereux où l'enfreindre : on
    // vient de rallumer pour une voiture, et le capteur se tait. Annoncer une
    // route dégagée serait affirmer ce qu'on ne sait plus.
    await pump(tester, RadarView.absent);

    expect(find.text('Voie libre'), findsNothing);
    expect(find.text('Radar perdu'), findsOneWidget);
  });
}
