import 'package:flutter_test/flutter_test.dart';
import 'package:sports_scope_companion/ble/power_calibration.dart';

void main() {
  group('réponse du Control Point', () {
    test('succès avec offset', () {
      final result =
          calibrationResponseOf([0x20, 0x0C, 0x01, 0x00, 0x02]) as PowerCalibrationDone;

      expect(result.offset, 512);
      expect(result.message, contains('512'));
    });

    test('un offset négatif est lu signé', () {
      // Une jauge dérive dans les deux sens : lu en uint16, ce -12 sortirait à
      // 65 524 et passerait pour un capteur en panne.
      final result =
          calibrationResponseOf([0x20, 0x0C, 0x01, 0xF4, 0xFF]) as PowerCalibrationDone;

      expect(result.offset, -12);
    });

    test('succès sans offset : acquittement nu, pas un offset nul', () {
      final result = calibrationResponseOf([0x20, 0x0C, 0x01]) as PowerCalibrationDone;

      // `null` et non 0 : zéro est un offset parfaitement valide, l'afficher
      // ferait croire à une mesure qui n'a pas eu lieu.
      expect(result.offset, isNull);
      expect(result.message, isNot(contains('0')));
    });

    test('la variante étendue répond au même endroit', () {
      final result = calibrationResponseOf(
          [0x20, 0x13, 0x01, 0x10, 0x00, 0x01, 0x02, 0x03]) as PowerCalibrationDone;

      expect(result.offset, 16);
    });

    test('procédure non supportée', () {
      final result =
          calibrationResponseOf([0x20, 0x0C, 0x02]) as PowerCalibrationFailed;

      expect(result.error, PowerCalibrationError.notSupported);
    });

    test('paramètre invalide et échec de l\'opération se distinguent', () {
      expect(
        (calibrationResponseOf([0x20, 0x0C, 0x03]) as PowerCalibrationFailed).error,
        PowerCalibrationError.refused,
      );
      // « Le capteur a essayé et n'y arrive pas » : c'est le cas du pied resté
      // sur la pédale, et le message doit envoyer vérifier ça.
      final failed =
          calibrationResponseOf([0x20, 0x0C, 0x04]) as PowerCalibrationFailed;
      expect(failed.error, PowerCalibrationError.failed);
      expect(failed.message, contains('arrêt'));
    });

    test('un code inconnu reste un refus, avec son code en clair', () {
      final result =
          calibrationResponseOf([0x20, 0x0C, 0x42]) as PowerCalibrationFailed;

      expect(result.error, PowerCalibrationError.refused);
      expect(result.message, contains('0x42'));
    });
  });

  group('trames qui ne nous concernent pas', () {
    test('la réponse à une autre procédure est ignorée', () {
      // Longueur de manivelle (0x04) : le Control Point est partagé, et
      // conclure là-dessus afficherait le résultat d'une demande qu'on n'a pas
      // faite.
      expect(calibrationResponseOf([0x20, 0x04, 0x01]), isNull);
    });

    test('une trame qui n\'est pas une réponse est ignorée', () {
      expect(calibrationResponseOf([0x0C, 0x01, 0x01]), isNull);
    });

    test('une trame tronquée est ignorée, jamais une erreur', () {
      // Même contrat que les décodeurs : on n'invente pas un échec à partir
      // d'octets manquants, on attend la vraie réponse jusqu'au délai.
      expect(calibrationResponseOf([]), isNull);
      expect(calibrationResponseOf([0x20]), isNull);
      expect(calibrationResponseOf([0x20, 0x0C]), isNull);
    });
  });
}
