import 'package:font_awesome_flutter/font_awesome_flutter.dart';

/// Le registre des icônes personnalisables d'un bloc `metric` — une clé de
/// `CompanionSettings::ICONS` (dépôt site, `app/models/companion_settings.rb`)
/// vers l'icône FontAwesome qu'elle dessine. Même liste blanche des deux
/// côtés : une clé que le site proposerait sans qu'elle soit ici resterait
/// injoignable, une clé retirée d'ici doit l'être aussi là-bas.
///
/// Les clés sont les classes CSS FontAwesome (`fa-solid fa-heart`), le même
/// vocabulaire que `METRIC_SAMPLES[...].icon` côté site — pas les noms Dart
/// du paquet, qui ne coïncident pas toujours avec le style attendu (le
/// niveau gratuit n'a pas de variante « regular » pour toutes les icônes ;
/// quand elle manque, la seule disponible est prise, quel que soit le style
/// demandé côté site).
const Map<String, FaIconData> companionIcons = {
  'fa-regular fa-clock': FontAwesomeIcons.clock,
  'fa-solid fa-person-biking': FontAwesomeIcons.personBiking,
  'fa-regular fa-circle-pause': FontAwesomeIcons.circlePause,
  'fa-solid fa-ruler-horizontal': FontAwesomeIcons.rulerHorizontal,
  'fa-solid fa-gauge-high': FontAwesomeIcons.gaugeHigh,
  'fa-solid fa-heart': FontAwesomeIcons.solidHeart,
  'fa-regular fa-heart': FontAwesomeIcons.heart,
  'fa-solid fa-bolt': FontAwesomeIcons.bolt,
  'fa-solid fa-rotate': FontAwesomeIcons.rotate,
  'fa-solid fa-arrow-trend-up': FontAwesomeIcons.arrowTrendUp,
  'fa-solid fa-mountain': FontAwesomeIcons.mountain,
  'fa-solid fa-arrow-up-right-dots': FontAwesomeIcons.arrowUpRightDots,
  'fa-solid fa-fire': FontAwesomeIcons.fire,
  'fa-solid fa-chart-column': FontAwesomeIcons.chartColumn,
  'fa-solid fa-gear': FontAwesomeIcons.gear,
  'fa-solid fa-circle-notch': FontAwesomeIcons.circleNotch,
  'fa-solid fa-record-vinyl': FontAwesomeIcons.recordVinyl,
  'fa-solid fa-arrows-left-right': FontAwesomeIcons.arrowsLeftRight,
  'fa-regular fa-flag': FontAwesomeIcons.flag,
  'fa-solid fa-weight-hanging': FontAwesomeIcons.weightHanging,
  'fa-solid fa-star': FontAwesomeIcons.solidStar,
  'fa-solid fa-bell': FontAwesomeIcons.solidBell,
  'fa-solid fa-compass': FontAwesomeIcons.solidCompass,
  'fa-solid fa-wind': FontAwesomeIcons.wind,
  'fa-solid fa-snowflake': FontAwesomeIcons.solidSnowflake,
  'fa-solid fa-sun': FontAwesomeIcons.solidSun,
  'fa-solid fa-moon': FontAwesomeIcons.solidMoon,
  'fa-solid fa-droplet': FontAwesomeIcons.droplet,
  'fa-solid fa-battery-full': FontAwesomeIcons.batteryFull,
  'fa-solid fa-trophy': FontAwesomeIcons.trophy,
  'fa-solid fa-route': FontAwesomeIcons.route,
  'fa-solid fa-bicycle': FontAwesomeIcons.bicycle,
  'fa-solid fa-map': FontAwesomeIcons.solidMap,
};

/// L'icône personnalisée d'un bloc, ou `null` si la clé est absente ou
/// inconnue de cette version — l'appelant retombe alors sur l'icône par
/// défaut de la mesure ([MetricId.icon]), jamais sur une icône manquante.
FaIconData? companionIconFor(String? key) => key == null ? null : companionIcons[key];
