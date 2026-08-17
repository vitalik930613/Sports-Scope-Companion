import '../samples.dart';

/// Battery Level (0x2A19) — un seul octet, 0 à 100 %, standardisé par le
/// Bluetooth SIG.
class BatteryDecoder {
  BatterySample? decode(List<int> data, {DateTime? at}) {
    if (data.isEmpty) return null;
    final percent = data[0];
    if (percent > 100) return null; // trame incomprise, jamais un pourcentage
    return BatterySample(at ?? DateTime.now(), percent);
  }
}
