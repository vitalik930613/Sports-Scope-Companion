import 'dart:typed_data';

import '../samples.dart';
import 'rev_counter.dart';

/// CSC Measurement (0x2A5B) — capteur vitesse/cadence dédié.
///
/// Un seul octet de drapeaux : bit 0 = données roue, bit 1 = données manivelle.
/// Attention, l'horodatage roue est ici en 1/1024 s, contrairement au profil
/// Cycling Power qui l'exprime en 1/2048 s.
///
/// Utile seulement si le capteur de puissance ne publie pas déjà la cadence.
class CscDecoder {
  final _crank = RevCounter(timeUnitHz: 1024);
  final _wheel = RevCounter(timeUnitHz: 1024, revolutionsBits: 32);

  static const _wheelPresent = 1 << 0;
  static const _crankPresent = 1 << 1;

  List<SensorSample> decode(List<int> data, {DateTime? at}) {
    if (data.isEmpty) return const [];

    final now = at ?? DateTime.now();
    final bytes = ByteData.sublistView(Uint8List.fromList(data));
    final flags = data[0];
    var offset = 1;

    final samples = <SensorSample>[];

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
