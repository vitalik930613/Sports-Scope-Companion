import 'package:flutter_test/flutter_test.dart';
import 'package:sports_scope_companion/ble/decoders/di2.dart';
import 'package:sports_scope_companion/drivetrain.dart';

/// Trames capturées sur un groupe Di2 12 vitesses réel.
List<int> hex(String s) =>
    s.split(' ').map((b) => int.parse(b, radix: 16)).toList();

void main() {
  //                              offset : 0  1  2  3  4  5  6
  // Petit plateau, plus grand pignon.
  final smallRingRear1 = hex('00 06 00 01 02 01 0C 00 00 00 06 EE 12 06 00 14 00');
  // Petit plateau, deuxième pignon : seul l'offset 5 change.
  final smallRingRear2 = hex('00 06 00 01 02 02 0C 00 00 00 06 EE 12 06 00 14 00');
  // Grand plateau : seul l'offset 3 change.
  final bigRingRear1 = hex('00 06 00 02 02 01 0C 00 00 00 06 EE 12 06 00 14 00');

  group('Di2Gears.parse', () {
    test('décode le pignon arrière', () {
      expect(Di2Gears.parse(smallRingRear1)!.rearPosition, 1);
      expect(Di2Gears.parse(smallRingRear2)!.rearPosition, 2);
    });

    test('décode les deux compteurs', () {
      final gears = Di2Gears.parse(smallRingRear1)!;
      expect(gears.frontCount, 2);
      expect(gears.rearCount, 12);
    });

    test('décode le plateau, position 1 = petit plateau', () {
      expect(Di2Gears.parse(smallRingRear1)!.frontPosition, 1);
      expect(Di2Gears.parse(smallRingRear1)!.isBigChainring, isFalse);

      expect(Di2Gears.parse(bigRingRear1)!.frontPosition, 2);
      expect(Di2Gears.parse(bigRingRear1)!.isBigChainring, isTrue);
    });

    test('conserve la trame brute', () {
      expect(Di2Gears.parse(smallRingRear1)!.raw, smallRingRear1);
    });

    test('rejette sans lever une trame incohérente', () {
      expect(Di2Gears.parse([]), isNull);
      expect(Di2Gears.parse([0x00, 0x06]), isNull);
      // Pignon 13 sur une cassette de 12.
      expect(
        Di2Gears.parse(hex('00 06 00 01 02 0D 0C 00 00 00 06 EE 12 06 00 14 00')),
        isNull,
      );
      // Plateau 3 sur un double.
      expect(
        Di2Gears.parse(hex('00 06 00 03 02 01 0C 00 00 00 06 EE 12 06 00 14 00')),
        isNull,
      );
    });

    test('valide la position contre le compteur de la trame, pas en dur', () {
      // Un triple hypothétique : plateau 3 sur 3 doit passer.
      final triple = Di2Gears.parse(
          hex('00 06 00 03 03 01 0C 00 00 00 06 EE 12 06 00 14 00'))!;
      expect(triple.frontPosition, 3);
      expect(triple.frontCount, 3);
      expect(triple.isBigChainring, isTrue);
    });
  });

  group('Drivetrain', () {
    const dt = Drivetrain.road; // 34/50, 11-36, 700x28

    test('associe les dents aux positions', () {
      final bigRingSmallSprocket = Di2Gears.parse(
          hex('00 06 00 02 02 0C 0C 00 00 00 06 EE 12 06 00 14 00'))!;
      expect(dt.chainringTeeth(bigRingSmallSprocket), 50);
      expect(dt.sprocketTeeth(bigRingSmallSprocket), 11);

      final smallRingBigSprocket = Di2Gears.parse(smallRingRear1)!;
      expect(dt.chainringTeeth(smallRingBigSprocket), 34);
      expect(dt.sprocketTeeth(smallRingBigSprocket), 36);
    });

    test('calcule le développement', () {
      // 34x36 : le braquet le plus facile, environ 2,02 m par tour de pédale.
      final easiest = Di2Gears.parse(smallRingRear1)!;
      expect(dt.development(easiest), closeTo(2.02, 0.02));
    });

    test('calcule la vitesse théorique', () {
      // 34x36 à 90 tr/min ≈ 3,0 m/s, soit environ 11 km/h.
      final easiest = Di2Gears.parse(smallRingRear1)!;
      expect(dt.theoreticalSpeedMs(easiest, 90), closeTo(3.03, 0.05));
    });

    test('les positions BLE correspondent aux champs FIT du CC600', () {
      // `gear_change` réel : front_gear_num=2 -> 50 dents, rear_gear_num=6 ->
      // 19 dents. Les positions BLE sont les mêmes nombres, sans conversion.
      final bigRing19 = Di2Gears.parse(
          hex('00 06 00 02 02 06 0C 00 00 00 06 EE 12 06 00 14 00'))!;
      expect(bigRing19.frontPosition, 2);
      expect(bigRing19.rearPosition, 6);
      expect(dt.chainringTeeth(bigRing19), 50);
      expect(dt.sprocketTeeth(bigRing19), 19);
    });
  });
}
