import 'dart:typed_data';

import '../samples.dart';

/// Heart Rate Measurement (0x2A37) — format standardisé par le Bluetooth SIG.
///
/// Octet 0 = drapeaux :
///   bit 0 : format de la valeur (0 = uint8, 1 = uint16)
///   bit 1-2 : état du contact peau
///   bit 3 : dépense énergétique présente
///   bit 4 : intervalles R-R présents
class HeartRateDecoder {
  HeartRateSample? decode(List<int> data, {DateTime? at}) {
    if (data.isEmpty) return null;

    final bytes = ByteData.sublistView(Uint8List.fromList(data));
    final flags = data[0];
    final isUint16 = flags & 0x01 != 0;

    var offset = 1;
    final int bpm;
    if (isUint16) {
      if (data.length < offset + 2) return null;
      bpm = bytes.getUint16(offset, Endian.little);
      offset += 2;
    } else {
      if (data.length < offset + 1) return null;
      bpm = data[offset];
      offset += 1;
    }

    // Dépense énergétique : présente avant les R-R, doit être sautée pour que
    // les offsets suivants tombent juste.
    if (flags & 0x08 != 0) offset += 2;

    final rr = <double>[];
    if (flags & 0x10 != 0) {
      while (offset + 2 <= data.length) {
        // Unité : 1/1024 s.
        rr.add(bytes.getUint16(offset, Endian.little) * 1000 / 1024);
        offset += 2;
      }
    }

    return HeartRateSample(at ?? DateTime.now(), bpm, rrIntervalsMs: rr);
  }
}
