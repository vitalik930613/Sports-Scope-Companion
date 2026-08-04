import 'package:flutter/material.dart';

import 'companion_settings_store.dart';
import 'ride_preset.dart';

/// Choisir le profil de la sortie.
///
/// Une feuille plutôt qu'un menu déroulant : les profils portent des noms
/// libres venus du site, et un menu qui déborde de l'écran se manipule mal
/// avec des gants. Partagée entre l'accueil (son propre bouton) et le
/// sélecteur de navigation — un seul geste à maintenir, deux endroits d'où le
/// déclencher.
Future<void> choosePreset(
  BuildContext context,
  CompanionSettingsStore settings,
) async {
  final key = await showModalBottomSheet<String>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final preset in settings.settings.presets)
            ListTile(
              leading: Icon(
                preset.hasMap ? Icons.map_outlined : Icons.home_outlined,
              ),
              title: Text(preset.name),
              subtitle: presetSubtitle(context, preset),
              isThreeLine: preset.description != null,
              selected: preset.key == settings.preset.key,
              onTap: () => Navigator.of(context).pop(preset.key),
            ),
        ],
      ),
    ),
  );

  if (key == null) return;
  await settings.select(key);
}

/// Le sous-titre d'un profil dans le sélecteur.
///
/// La description **vient d'abord**, quand il y en a une : c'est un texte
/// libre écrit sur le site pour justement aider à choisir entre deux profils
/// qui, sinon, ne se distinguent que par leurs pages. Les faits techniques
/// restent en dessous, plus discrets — ils continuent de servir quand il n'y a
/// pas de description, ou en appoint quand il y en a une.
Widget presetSubtitle(BuildContext context, RidePreset preset) {
  final description = preset.description;
  if (description == null) return Text(describePreset(preset));

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(description),
      Text(
        describePreset(preset),
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );
}

/// Ce qu'un profil change, en une ligne.
///
/// Les capteurs coupés sont écrits en toutes lettres ici, parce que c'est le
/// seul endroit où on les voit : la rangée d'état de l'accueil dit ce que les
/// appareils font, pas ce qu'un profil demande, et y ajouter un état visuel de
/// plus ferait trois façons différentes d'être gris.
String describePreset(RidePreset preset) {
  final off = [
    if (!preset.hasMap) 'sans carte',
    if (!preset.sensors.gps) 'sans GPS',
    if (!preset.sensors.radar) 'sans radar',
  ];
  final count = preset.pages.length;
  final pages = '$count page${count > 1 ? 's' : ''}';
  return off.isEmpty ? pages : '$pages · ${off.join(' · ')}';
}
