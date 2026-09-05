import 'package:flutter/material.dart';

import '../../ui/zone_colors.dart';

/// Une valeur affichée en case : le chiffre, puis son unité en dessous.
///
/// Un tiret quand la mesure manque, jamais un zéro — même règle que
/// [MetricTile], pour que le bandeau, la bande de l'encoche et l'écran de
/// diagnostic ne racontent pas deux histoires différentes du même capteur
/// muet.
///
/// Partagé entre [RideBottomBand] et `NotchBand` : même langage visuel (fond
/// de zone, `FittedBox`) pour deux cases qui ne diffèrent que par leur taille.
class BandMetricTile extends StatelessWidget {
  const BandMetricTile({
    super.key,
    required this.value,
    required this.label,
    this.zoneKey,
    this.background,
    this.color,
    this.altBackground,
    this.labelFirst = false,
  });

  final String? value;
  final String label;

  /// Le libellé au-dessus du chiffre plutôt qu'en dessous — l'inverse du
  /// bandeau du bas. Utilisé par `NotchBand` : dans une bande plus basse et
  /// plus proche du regard, savoir *quelle* mesure on lit avant de lire son
  /// chiffre se lit mieux d'un coup d'œil.
  final bool labelFirst;

  /// `z1`…`z7` pour peindre la case aux couleurs de la zone, `null` pour la
  /// laisser sur le fond de la case.
  final String? zoneKey;

  /// Couleur de fond directe (la pente, sur sa tranche de difficulté), quand
  /// la mesure ne se range pas en zone d'entraînement. Même priorité que
  /// [MetricView] : elle l'emporte sur l'alternance noir/anthracite.
  final Color? background;

  /// Fond réglé dans l'éditeur pour cette case (`BandSlot.color`) — sous la
  /// couleur de zone/mesure ([background]/[zoneKey]), qui reste la donnée,
  /// mais au-dessus de l'alternance ([altBackground]).
  final Color? color;

  /// Le noir ou l'anthracite de l'alternance, quand la case ne porte pas de
  /// zone — c'est elle qui recule dès qu'une zone donne une vraie couleur.
  final Color? altBackground;

  @override
  Widget build(BuildContext context) {
    final zoneColor = background ?? zoneColorOf(zoneKey) ?? color;
    final foreground = zoneColor == null ? Colors.white : foregroundOf(zoneColor);

    final valueText = FittedBox(
      fit: BoxFit.scaleDown,
      // Les valeurs sont de longueurs très inégales (« 8 » et « 1:12:34 ») et
      // la case partage sa largeur en parts égales : sans réduction, la
      // durée déborderait sur un téléphone étroit.
      child: Text(
        value ?? '—',
        maxLines: 1,
        style: TextStyle(
          color: foreground,
          fontSize: 24,
          fontWeight: FontWeight.w500,
          height: 1.1,
        ),
      ),
    );

    final labelText = Text(
      label,
      maxLines: 1,
      // Sur un aplat de zone, le libellé passe de « discret » à « lisible » :
      // le blanc à 54 % disparaît sur le jaune comme sur le rouge.
      style: TextStyle(
        color: zoneColor == null ? Colors.white54 : foreground.withValues(alpha: 0.75),
        fontSize: 11,
      ),
    );

    final content = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: labelFirst ? [labelText, valueText] : [valueText, labelText],
    );

    final surface = zoneColor ?? altBackground;
    if (surface == null) return content;

    return Container(
      margin: const EdgeInsets.fromLTRB(2, 3, 2, 3),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(6),
      ),
      child: content,
    );
  }
}
