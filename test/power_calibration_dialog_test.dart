import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_scope_companion/ble/power_calibration.dart';
import 'package:sports_scope_companion/ui/power_calibration_dialog.dart';

void main() {
  Future<void> pumpDialog(
    WidgetTester tester, {
    PowerCalibrationRunner? run,
    String sensorName = 'Assioma',
    String? unavailable,
  }) {
    return tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PowerCalibrationDialog(
          sensorName: sensorName,
          run: run,
          unavailable: unavailable,
        ),
      ),
    ));
  }

  testWidgets('la consigne est là avant le geste', (tester) async {
    await pumpDialog(tester, run: () async => const PowerCalibrationDone());

    expect(find.text('Assioma'), findsOneWidget);
    expect(find.textContaining('pédales'), findsOneWidget);
    expect(find.text('Calibrer'), findsOneWidget);
  });

  testWidgets('sans capteur connecté, rien à lancer', (tester) async {
    await pumpDialog(tester, run: null);

    expect(find.textContaining('Aucun capteur de puissance'), findsOneWidget);
    // Pas de bouton qui ne pourrait qu'échouer.
    expect(find.text('Calibrer'), findsNothing);
    expect(find.text('Fermer'), findsOneWidget);
  });

  testWidgets('un capteur qui ne se calibre pas le dit, sans parler de panne',
      (tester) async {
    // Ouvert depuis le bandeau, où le tap ne filtre rien : la boîte doit
    // distinguer « réveille le capteur » de « ce boîtier ne sait pas », sinon
    // on cherche une panne là où il n'y a qu'un protocole absent.
    await pumpDialog(
      tester,
      run: null,
      unavailable: 'Ce capteur n\'expose pas la calibration en Bluetooth : '
          'elle passe par l\'application du fabricant.',
    );

    expect(find.textContaining('n\'expose pas la calibration'), findsOneWidget);
    expect(find.textContaining('Aucun capteur de puissance'), findsNothing);
    expect(find.text('Calibrer'), findsNothing);
  });

  testWidgets('pendant la mesure, le bouton ne repart pas', (tester) async {
    final gate = Completer<PowerCalibrationResult>();
    await pumpDialog(tester, run: () => gate.future);

    await tester.tap(find.text('Calibrer'));
    await tester.pump();

    expect(find.textContaining('Mesure en cours'), findsOneWidget);
    // Deux calibrations en vol se répondraient dans le désordre : le second
    // résultat écraserait le premier sans qu'on sache lequel on lit.
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);

    gate.complete(const PowerCalibrationDone(offset: 42));
    await tester.pump();

    expect(find.textContaining('offset 42'), findsOneWidget);
    expect(find.text('Recommencer'), findsOneWidget);
  });

  testWidgets('un refus du capteur est affiché tel quel', (tester) async {
    await pumpDialog(
      tester,
      run: () async =>
          const PowerCalibrationFailed(PowerCalibrationError.failed),
    );

    await tester.tap(find.text('Calibrer'));
    await tester.pump();

    // La consigne reste sous les yeux : c'est elle qu'on relit après un échec.
    expect(find.textContaining('pédales'), findsWidgets);
    expect(find.textContaining('n\'a pas pu se calibrer'), findsOneWidget);
  });

  testWidgets('recommencer efface le résultat précédent', (tester) async {
    var attempt = 0;
    final gate = Completer<PowerCalibrationResult>();
    await pumpDialog(tester, run: () {
      attempt++;
      return attempt == 1
          ? Future.value(const PowerCalibrationDone(offset: 7))
          : gate.future;
    });

    await tester.tap(find.text('Calibrer'));
    await tester.pump();
    expect(find.textContaining('offset 7'), findsOneWidget);

    await tester.tap(find.text('Recommencer'));
    await tester.pump();

    // Un « calibré » resté affiché pendant la seconde mesure se lirait comme
    // le sien.
    expect(find.textContaining('offset 7'), findsNothing);
    expect(find.textContaining('Mesure en cours'), findsOneWidget);

    gate.complete(const PowerCalibrationDone(offset: 9));
    await tester.pump();
    expect(find.textContaining('offset 9'), findsOneWidget);
  });
}
