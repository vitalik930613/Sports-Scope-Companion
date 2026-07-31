import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_scope_companion/ride/radar_severity.dart';
import 'package:sports_scope_companion/ride/widgets/radar_distance_badges.dart';

/// La lisibilité des chiffres se juge à l'œil ; ce qui se vérifie ici, c'est que
/// leur fond **dise la gravité** — rouge, orange, ou pas de pastille du tout.
/// C'est la seule chose du radar qu'on regarde vraiment, elle ne doit pas
/// dépendre de ce que la carte a mis dessous.
void main() {
  Future<void> pump(WidgetTester tester, RadarView view) => tester.pumpWidget(
        MaterialApp(home: Scaffold(body: RadarDistanceBadges(view: view))),
      );

  /// Les fonds réellement peints. `Scaffold` et `MaterialApp` posent leurs
  /// propres `Container` : il faut partir des pastilles.
  List<Color?> fills(WidgetTester tester) => tester
      .widgetList<Container>(
        find.descendant(
          of: find.byType(RadarDistanceBadges),
          matching: find.byType(Container),
        ),
      )
      .map((box) => (box.decoration as BoxDecoration?)?.color)
      .toList();

  testWidgets('sans radar, la bande du haut reste noire', (tester) async {
    await pump(tester, RadarView.absent);

    expect(fills(tester), isEmpty);
  });

  testWidgets('route dégagée, aucune pastille non plus', (tester) async {
    // Un radar qui répond « rien derrière » n'a rien à écrire en haut : la
    // pastille est réservée à ce qui approche.
    await pump(tester, const RadarView(severity: RadarSeverity.clear));

    expect(fills(tester), isEmpty);
  });

  testWidgets('un véhicule qui approche : deux pastilles orange', (
    tester,
  ) async {
    await pump(
      tester,
      const RadarView(
        severity: RadarSeverity.approaching,
        positions: [0.3],
        nearestM: 96,
      ),
    );

    // Deux, de part et d'autre de l'encoche : on ne sait pas de quel côté les
    // yeux reviendront de la route.
    expect(fills(tester), [const Color(0xFFFFA726), const Color(0xFFFFA726)]);
    expect(find.text('96 m'), findsNWidgets(2));
  });

  testWidgets('à portée de rétroviseur, elles passent au rouge', (tester) async {
    await pump(
      tester,
      const RadarView(
        severity: RadarSeverity.close,
        positions: [0.9, 0.5],
        nearestM: 22,
      ),
    );

    expect(fills(tester), [const Color(0xFFEF5350), const Color(0xFFEF5350)]);
    // Le compte vient de `positions`, pas d'un second décompte.
    expect(find.text('2'), findsNWidgets(2));
  });
}
