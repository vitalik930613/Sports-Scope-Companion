import 'package:flutter/foundation.dart';

/// Journal de bord temporaire, consultable **sur le téléphone** — pour les
/// essais en sortie, où il n'y a ni ordinateur ni `adb` à portée.
///
/// Volontairement en mémoire et non persistant : un journal de mise au point
/// qui traînerait d'une sortie à l'autre gênerait plus qu'il n'aiderait.
/// Instance unique au niveau de l'application, comme les autres magasins.
class DebugLog {
  DebugLog._();
  static final instance = DebugLog._();

  static const _capacity = 2000;

  final ValueNotifier<List<String>> lines = ValueNotifier(const []);

  /// Range une ligne, la plus récente en tête. Passe aussi par [debugPrint],
  /// pour ne rien perdre quand l'appareil est bel et bien connecté.
  void add(String message) {
    final stamp = DateTime.now().toIso8601String().substring(11, 19);
    final entry = '$stamp  $message';
    debugPrint(entry);
    final next = [entry, ...lines.value];
    if (next.length > _capacity) next.removeRange(_capacity, next.length);
    lines.value = next;
  }

  void clear() => lines.value = const [];
}
