import 'package:flutter_test/flutter_test.dart';
import 'package:sports_scope_companion/ble/decoders/varia.dart';

/// ⚠️ Ces trames sont **construites**, pas capturées : elles fixent le
/// comportement du décodeur (découpage, robustesse, « route dégagée »), pas la
/// disposition réelle du Varia. À remplacer par de vraies captures dès que le
/// protocole de vérification de `decoders/varia.dart` aura été suivi.
void main() {
  final decoder = VariaDecoder();

  group('VariaDecoder', () {
    test('route dégagée : trame valide, aucune cible', () {
      final sample = decoder.decode([0x01])!;
      expect(sample.isClear, isTrue);
      expect(sample.targets, isEmpty);
      expect(sample.nearest, isNull);
    });

    test('décode une cible', () {
      final sample = decoder.decode([0x01, 0x07, 0x64, 0x0A])!;
      expect(sample.targets, hasLength(1));
      expect(sample.targets.single.id, 7);
      expect(sample.targets.single.distanceM, 100);
      expect(sample.targets.single.approachSpeedRaw, 10);
      expect(sample.isClear, isFalse);
    });

    test('décode plusieurs cibles et désigne la plus proche', () {
      final sample = decoder.decode([
        0x02,
        0x07, 0x64, 0x0A, // #7 à 100 m
        0x08, 0x28, 0x0C, // #8 à 40 m
        0x09, 0x50, 0x05, // #9 à 80 m
      ])!;
      expect(sample.targets, hasLength(3));
      expect(sample.nearest!.id, 8);
      expect(sample.nearest!.distanceM, 40);
    });

    test('ignore le remplissage (id et distance nuls)', () {
      final sample = decoder.decode([
        0x03,
        0x07, 0x64, 0x0A,
        0x00, 0x00, 0x00,
      ])!;
      expect(sample.targets, hasLength(1));
      expect(sample.targets.single.id, 7);
    });

    test('rejette sans lever une trame mal découpée', () {
      expect(decoder.decode([]), isNull);
      // 2 octets après l'en-tête : pas un multiple de 3.
      expect(decoder.decode([0x01, 0x07, 0x64]), isNull);
      // Plus de cibles que le radar n'en suit : découpage forcément faux.
      expect(decoder.decode(List.filled(1 + 9 * 3, 0x11)), isNull);
    });
  });
}
