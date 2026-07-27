import 'dart:typed_data';

import '../samples.dart';
import 'rev_counter.dart';

/// Cycling Power Measurement (0x2A63).
///
/// Trame à champs optionnels : uint16 de drapeaux, puis sint16 de puissance
/// instantanée, puis les champs présents **dans l'ordre des bits**. Il faut
/// donc parcourir les champs en séquence, chacun décalant le suivant.
///
/// Un capteur de puissance à double capteur publie en général puissance,
/// équilibre G/D et tours de manivelle dans la même trame : inutile d'appairer
/// un capteur de cadence séparé.
class CyclingPowerDecoder {
  final _crank = RevCounter(timeUnitHz: 1024);
  final _wheel = RevCounter(timeUnitHz: 2048, revolutionsBits: 32);

  static const _balancePresent = 1 << 0;
  static const _torquePresent = 1 << 2;
  static const _wheelPresent = 1 << 4;
  static const _crankPresent = 1 << 5;

  /// Décode une trame en 1 à 3 échantillons (puissance, cadence, vitesse roue).
  /// Liste vide si la trame est inexploitable.
  List<SensorSample> decode(List<int> data, {DateTime? at}) {
    if (data.length < 4) return const [];

    final now = at ?? DateTime.now();
    final bytes = ByteData.sublistView(Uint8List.fromList(data));
    final flags = bytes.getUint16(0, Endian.little);

    // La puissance est signée : un capteur peut renvoyer une valeur légèrement
    // négative au repos.
    final watts = bytes.getInt16(2, Endian.little);
    var offset = 4;

    double? balance;
    if (flags & _balancePresent != 0) {
      if (data.length < offset + 1) return const [];
      balance = data[offset] / 2.0; // unité : 1/2 %
      offset += 1;
    }

    if (flags & _torquePresent != 0) offset += 2;

    final samples = <SensorSample>[
      PowerSample(now, watts, balanceLeftPercent: balance),
    ];

    if (flags & _wheelPresent != 0) {
      if (data.length < offset + 6) return samples;
      final revs = bytes.getUint32(offset, Endian.little);
      final time = bytes.getUint16(offset + 4, Endian.little);
      offset += 6;
      final rps = _wheel.update(revs, time);
      if (rps != null) samples.add(WheelSpeedSample(now, rps));
    }

    if (flags & _crankPresent != 0) {
      if (data.length < offset + 4) return samples;
      final revs = bytes.getUint16(offset, Endian.little);
      final time = bytes.getUint16(offset + 2, Endian.little);
      offset += 4;
      final rps = _crank.update(revs, time);
      if (rps != null) samples.add(CadenceSample(now, rps * 60));
    }

    return samples;
  }

  void reset() {
    _crank.reset();
    _wheel.reset();
  }
}
