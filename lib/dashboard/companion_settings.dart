import 'package:flutter/foundation.dart';

import 'ride_preset.dart';

/// Le document de réglages du compte : les profils de sortie, tels que le site
/// les décrit.
///
/// **[parse] ne lève jamais et rend toujours quelque chose d'utilisable** — même
/// convention que les décodeurs GATT et `CompanionRelease.parse`, et pour une
/// raison plus forte encore : ce document décide de ce qui s'affiche pendant la
/// sortie. Un site plus récent, une réponse tronquée, du HTML d'erreur à la
/// place du JSON, et l'appli doit quand même ouvrir un tableau de bord.
///
/// Le pire résultat imaginable n'est pas « mes réglages ne sont pas arrivés »,
/// c'est un écran noir au départ d'un col : d'où le repli sur
/// [RidePreset.builtIn], qui est le tableau de bord d'avant ce chantier.
@immutable
class CompanionSettings {
  const CompanionSettings(this.presets, {this.colDetection = true});

  /// Ce qu'on affiche quand le site n'a rien pu dire.
  static const fallback = CompanionSettings([RidePreset.builtIn]);

  /// Au moins un profil, toujours, et jamais deux fois la même clé.
  final List<RidePreset> presets;

  /// Réglage global (pas par profil) : deviner un col en navigation libre et
  /// l'annoncer (voir `RideColGuessFlash`). Activé par défaut côté site
  /// (`CompanionSettings.defaults`, dépôt Rails) — même valeur ici pour qu'un
  /// document non encore reçu (juste après l'installation) ne coupe rien.
  final bool colDetection;

  /// Le profil de cette clé, ou **le premier** à défaut.
  ///
  /// Pas d'exception ni de `null` : la clé retenue sur disque peut désigner un
  /// profil que le site a supprimé depuis, et découvrir ça au moment de partir
  /// ne doit pas empêcher de partir.
  RidePreset select(String? key) {
    for (final preset in presets) {
      if (preset.key == key) return preset;
    }
    return presets.first;
  }

  /// Le profil dont l'activité correspond à celle de l'itinéraire qu'on ouvre,
  /// ou `null` — aucune activité à comparer, ou aucun profil marqué pour elle.
  ///
  /// Sert à présélectionner le profil quand on choisit un itinéraire dans
  /// [NavigationPickerSheet] : ouvrir un tracé de rando fait partir le profil
  /// rando, sans un geste de plus. Le premier qui correspond gagne — même règle
  /// d'ordre que partout ailleurs dans ce document. Ne retombe jamais sur un
  /// profil par défaut : sans correspondance, c'est au choix courant de rester.
  RidePreset? presetForActivity(String? activity) {
    if (activity == null || activity.isEmpty) return null;
    for (final preset in presets) {
      if (preset.activity == activity) return preset;
    }
    return null;
  }

  static CompanionSettings parse(Object? raw) {
    if (raw is! Map) return fallback;

    final presets = <RidePreset>[];
    final keys = <String>{};

    for (final entry in (raw['presets'] is List ? raw['presets'] as List : [])) {
      final preset = RidePreset.parse(entry);
      if (preset == null) continue;
      // Première clé gagnante : c'est l'ordre du document qui tranche, donc
      // celui que l'éditeur du site affichera. Deux profils homonymes rendraient
      // le choix au départ ambigu, et le choix retenu sur disque indéterminé.
      if (!keys.add(preset.key)) continue;
      presets.add(preset);
    }

    if (presets.isEmpty) return fallback;
    return CompanionSettings(
      presets,
      colDetection: raw['col_detection'] != false,
    );
  }
}
