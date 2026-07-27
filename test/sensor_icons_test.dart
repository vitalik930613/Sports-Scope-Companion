import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_scope_companion/ble/sensor_profile.dart';
import 'package:sports_scope_companion/ui/sensor_icons.dart';

void main() {
  test('chaque capacité a son icône, et aucune n\'est partagée', () {
    // Deux capteurs différents sous la même icône rendraient la liste
    // illisible : c'est tout l'intérêt de l'icône par type.
    final icons = [for (final kind in SensorKind.values) iconFor(kind)];

    expect(icons.toSet(), hasLength(SensorKind.values.length));
    expect(icons, isNot(contains(unknownSensorIcon)));
  });

  test('un appareil multi-profils prend l\'icône du premier du registre', () {
    // Un capteur de puissance qui publie aussi la cadence reste d'abord un
    // capteur de puissance.
    expect(
      iconForDevice({SensorKind.speedCadence, SensorKind.power}),
      iconFor(SensorKind.power),
    );
  });

  test('un appareil sans capacité connue garde une icône neutre', () {
    expect(iconForDevice(const {}), unknownSensorIcon);
  });

  testWidgets('la rangée affiche une icône et un libellé par capacité',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SensorKindIcons({SensorKind.heartRate, SensorKind.radar}),
      ),
    ));

    expect(find.byIcon(iconFor(SensorKind.heartRate)), findsOneWidget);
    expect(find.byIcon(iconFor(SensorKind.radar)), findsOneWidget);
    expect(find.text(labelFor(SensorKind.heartRate)), findsOneWidget);
    expect(find.byIcon(iconFor(SensorKind.power)), findsNothing);
  });

  testWidgets('sans capacité connue, la rangée le dit', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SensorKindIcons({})),
    ));

    expect(find.text('capacités inconnues'), findsOneWidget);
  });
}
