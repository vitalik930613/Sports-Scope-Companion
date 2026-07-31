import 'package:flutter/material.dart';

/// Les couleurs des zones d'entraînement, telles qu'on les lit au guidon.
///
/// Le dégradé est celui que tout cycliste connaît — bleu, vert, jaune, orange,
/// rouge — parce que la couleur doit se reconnaître avant d'être lue : à
/// 30 km/h, on voit « du rouge » bien avant de déchiffrer « Z5 ».
///
/// Elles sont **saturées, pas transparentes** : un aplat teinté sur le fond
/// sombre du bandeau donne cinq gris à peine différents, mesuré illisible en
/// plein soleil. Le prix à payer est le contraste du texte, d'où [foregroundOf]
/// — le jaune et l'orange demandent un texte noir, les autres du blanc.
///
/// **Une seule table pour le cardio et la puissance**, et pas deux palettes à
/// choisir sur le type de mesure : les cinq zones cardio et les cinq premières
/// zones de puissance disent la même chose au même rang (`z4` est le seuil des
/// deux côtés, `z5` le VO2max), donc leur donner deux couleurs différentes
/// obligerait à apprendre deux codes pour une seule sensation. La puissance
/// prolonge simplement le dégradé au-delà du rouge, dans des violets que le
/// cardio n'atteint jamais : `z6` (anaérobie) et `z7` (neuromusculaire) sont
/// des efforts que la fréquence cardiaque, trop lente, ne sait pas distinguer.
const zoneColors = <String, Color>{
  'z1': Color(0xFF2E6FD6),
  'z2': Color(0xFF2E9E4F),
  'z3': Color(0xFFE0C000),
  'z4': Color(0xFFE8760C),
  'z5': Color(0xFFD32F2F),
  'z6': Color(0xFF8E24AA),
  'z7': Color(0xFF5E35B1),
};

/// Le fond d'une zone, `null` quand on n'en connaît pas la clé — un profil
/// venu d'un site plus récent que l'appli.
Color? zoneColorOf(String? key) => key == null ? null : zoneColors[key];

/// Le texte à poser sur [zoneColorOf], choisi sur la luminance de l'aplat : le
/// blanc disparaît sur le jaune, et c'est justement la zone qu'on regarde quand
/// on cherche à ne pas monter trop haut.
Color foregroundOf(Color background) =>
    background.computeLuminance() > 0.45 ? Colors.black : Colors.white;
