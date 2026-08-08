import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../account/rider_profile.dart';
import '../account/rider_profile_store.dart';
import '../ble/sensor_hub.dart';
import '../drivetrain.dart';
import '../recording/ride_recorder.dart';
import '../recording/ride_stats.dart';
import '../ride/nav_state.dart';
import '../ride/route_climbs.dart';
import '../training/ride_load.dart';
import '../training/training_budget_store.dart';
import '../ui/formats.dart';

/// Le catalogue des mesures affichables, et **le vocabulaire partagé avec le
/// site** : une clé d'ici est une clé du document de réglages.
///
/// Rien n'y entre qui n'ait une source réelle aujourd'hui (le hub, l'agrégat de
/// l'enregistreur, l'état publié par la page web). Une mesure sans source
/// afficherait un tiret pour toujours, et un tiret permanent se lit comme un
/// capteur en panne — soit exactement la mauvaise information, puisque le trou
/// serait dans l'appli.
///
/// Ajouter une mesure, c'est donc : une valeur ici, sa lecture dans [read], et
/// ses dépendances dans [dependencies]. Le site pourra s'en servir dès qu'il
/// connaîtra la clé ; l'appli plus ancienne, elle, l'ignorera sans broncher.
enum MetricId {
  duration('duration', 'durée', Icons.timer_outlined),
  movingTime('moving_time', 'Durée en mouvement', Icons.directions_bike),
  pauseTime('pause_time', 'Durée pause', Icons.pause_circle_outline),
  distance('distance', 'distance', Icons.straighten),
  speed('speed', 'km/h', Icons.speed),
  speedAvg('speed_avg', 'Vitesse moyenne', Icons.speed),
  speedMax('speed_max', 'km/h max', Icons.speed),
  heartRate('heart_rate', 'bpm', Icons.favorite),
  hrZone('hr_zone', 'zone bpm', Icons.favorite),
  hrAvg('hr_avg', 'bpm moy', Icons.favorite_border),
  hrMax('hr_max', 'bpm max', Icons.favorite_border),
  power('power', 'W', Icons.bolt),
  powerZone('power_zone', 'zone W', Icons.bolt),
  powerAvg('power_avg', 'W moy', Icons.bolt),
  powerNormalized('power_np', 'W NP', Icons.bolt),
  powerMax('power_max', 'W max', Icons.bolt),
  cadence('cadence', 'tr/min', Icons.autorenew),
  cadenceAvg('cadence_avg', 'tr/min moy', Icons.autorenew),
  cadenceMax('cadence_max', 'tr/min max', Icons.autorenew),
  ascent('ascent', 'D+', Icons.trending_up),
  altitude('altitude', 'm', Icons.terrain),
  grade('grade', '% pente', Icons.north_east),
  gradeAvg('grade_avg', '% pente moy', Icons.north_east),
  gradeMax('grade_max', '% pente max', Icons.north_east),
  calories('calories', 'kcal', Icons.local_fire_department),
  caloriesPerHour('calories_per_hour', 'kcal/h', Icons.local_fire_department),
  tss('tss', 'TSS', Icons.bar_chart),
  gears('gears', 'braquet', Icons.settings),
  chainringPosition('chainring_position', 'plateau', Icons.donut_large),
  sprocketPosition('sprocket_position', 'pignon', Icons.album),
  gearRatio('gear_ratio', 'rapport', Icons.compare_arrows),
  routeRemaining('route_remaining', 'Distance restante', Icons.flag_outlined),
  routeRemainingGain('route_remaining_gain', 'D+ restant', Icons.trending_up),
  routeEta('route_eta', 'Durée restante', Icons.schedule);

  const MetricId(this.key, this.unit, this.icon);

  /// La clé du contrat JSON. Écrite à la main plutôt que dérivée de [name] :
  /// renommer une valeur Dart ne doit pas casser les documents déjà servis par
  /// le site.
  final String key;

  /// Ce qui s'écrit sous le chiffre. Court à dessein — c'est une case de
  /// bandeau, pas une légende.
  final String unit;

  final IconData icon;

  /// La mesure de cette clé, ou `null` si le site en nomme une que cette
  /// version ne connaît pas. Tolérant par construction : le site peut être plus
  /// récent que l'appli, et une clé inconnue ne doit rien faire échouer.
  static MetricId? fromKey(Object? raw) {
    if (raw is! String) return null;
    for (final metric in values) {
      if (metric.key == raw) return metric;
    }
    return null;
  }

  /// Cette mesure porte-t-elle une zone d'entraînement ? Sert au rendu, qui
  /// peint alors la case aux couleurs de la zone du moment.
  bool get hasZone => switch (this) {
        MetricId.heartRate ||
        MetricId.hrZone ||
        MetricId.power ||
        MetricId.powerZone =>
          true,
        _ => false,
      };

  /// Les zones dans lesquelles cette mesure se situe, vides quand elle n'en a
  /// pas — ou quand le site ne connaît pas le seuil correspondant.
  ///
  /// Sert au mode jauge, qui a besoin de la **plage** et pas seulement de la
  /// zone du moment : sans plage, il n'y a rien à remplir.
  List<TrainingZone> zonesOf(RiderProfile profile) => switch (this) {
        MetricId.heartRate || MetricId.hrZone => profile.hrZones,
        MetricId.power || MetricId.powerZone => profile.powerZones,
        _ => const [],
      };

  /// De quoi cette mesure dépend, pour n'être reconstruite que quand il le
  /// faut. Une seule liste par mesure, à côté de sa lecture : deux endroits
  /// finiraient par se contredire, et le symptôme serait une case figée que
  /// rien ne rafraîchit.
  List<Listenable> dependencies(MetricSources sources) {
    final nav = sources.nav;
    return switch (this) {
      MetricId.heartRate || MetricId.hrZone => [
          sources.hub.latestHeartRate,
          sources.riderProfile,
        ],
      MetricId.power || MetricId.powerZone => [
          sources.hub.latestPower,
          sources.riderProfile,
        ],
      // Le TSS suit la même cascade que le budget de charge (cf. `rideTss`) :
      // il lui faut donc les seuils en plus de l'agrégat de l'enregistreur.
      MetricId.tss => [sources.recorder, sources.riderProfile],
      MetricId.cadence => [sources.hub.latestCadence],
      MetricId.gears ||
      MetricId.chainringPosition ||
      MetricId.sprocketPosition ||
      MetricId.gearRatio =>
        [sources.hub.latestGears],
      // La vitesse a deux sources et doit suivre les deux : la page quand il y
      // en a une, le GPS de l'enregistreur sinon.
      MetricId.speed => [sources.recorder, if (nav != null) nav],
      MetricId.routeRemaining || MetricId.routeRemainingGain => [
          if (nav != null) nav,
        ],
      // Le temps restant croise la distance qui reste (la page) et la vitesse
      // moyenne en roulant (l'enregistreur) : il lui faut suivre les deux.
      MetricId.routeEta => [sources.recorder, if (nav != null) nav],
      _ => [sources.recorder],
    };
  }

  /// La valeur du moment, mise en forme.
  ///
  /// `null` veut dire « pas de mesure », ce que le rendu écrit **`—` et jamais
  /// `0`** : un zéro se lit comme une mesure, et un capteur muet ne mesure pas
  /// zéro, il ne mesure rien.
  MetricReading read(MetricSources sources) {
    final stats = sources.recorder.stats;
    final active = sources.recorder.isActive;
    final profile = sources.riderProfile.profile;

    return switch (this) {
      // Durée et distance viennent de l'enregistreur et pas de la page : hors
      // enregistrement elles n'existent pas, et un zéro ferait croire à un
      // compteur remis à zéro plutôt qu'à une sortie non lancée.
      MetricId.duration => MetricReading(
          active ? formatDurationHm(sources.recorder.recorded) : null,
        ),
      MetricId.movingTime =>
        MetricReading(active ? formatDurationHm(stats.movingTime) : null),
      // Le complément de la durée en mouvement : arrêts aux feux, ravito,
      // discussion sur le bas-côté. Les deux viennent de la même horloge —
      // `recorded` ne tourne pas non plus pendant une pause manuelle — donc la
      // soustraction ne peut pas passer sous zéro.
      MetricId.pauseTime => MetricReading(
          active
              ? formatDurationHm(sources.recorder.recorded - stats.movingTime)
              : null,
        ),
      // Sans GPS (home-trainer), la distance n'a pas de source : un « 0 m » se
      // lirait comme « je n'ai pas bougé », alors que la question ne se pose
      // même pas. Le tiret dit la bonne chose — on ne mesure pas ça ici.
      MetricId.distance => MetricReading(
          active && sources.recorder.gpsEnabled
              ? formatDistanceKm(sources.recorder.distanceM)
              : null,
        ),
      MetricId.speed => MetricReading(_speed(sources)),
      // Moyenne en roulant, pas la moyenne des échantillons bruts : sans ça,
      // un feu rouge dilue la case pendant que la sortie continue.
      MetricId.speedAvg =>
        MetricReading(_kmhUnit(_movingAvgSpeedMps(stats))),
      MetricId.speedMax => MetricReading(_kmh(stats.maxSpeedMps)),
      MetricId.heartRate => _zoned(
          sources.hub.latestHeartRate.value,
          profile: profile,
          zoneOf: profile.hrZoneFor,
          asZone: false,
          threshold: 'LTHR ?',
          hasZones: profile.hasHrZones,
        ),
      MetricId.hrZone => _zoned(
          sources.hub.latestHeartRate.value,
          profile: profile,
          zoneOf: profile.hrZoneFor,
          asZone: true,
          threshold: 'LTHR ?',
          hasZones: profile.hasHrZones,
        ),
      MetricId.hrAvg => MetricReading(stats.avgHeartRate?.toString()),
      MetricId.hrMax => MetricReading(stats.maxHeartRate?.toString()),
      MetricId.power => _zoned(
          sources.hub.latestPower.value,
          profile: profile,
          zoneOf: profile.powerZoneFor,
          asZone: false,
          threshold: 'FTP ?',
          hasZones: profile.hasPowerZones,
        ),
      MetricId.powerZone => _zoned(
          sources.hub.latestPower.value,
          profile: profile,
          zoneOf: profile.powerZoneFor,
          asZone: true,
          threshold: 'FTP ?',
          hasZones: profile.hasPowerZones,
        ),
      MetricId.powerAvg => MetricReading(stats.avgPower?.toString()),
      MetricId.powerNormalized =>
        MetricReading(stats.normalizedPowerW?.toString()),
      MetricId.powerMax => MetricReading(stats.maxPower?.toString()),
      MetricId.cadence =>
        MetricReading(sources.hub.latestCadence.value?.round().toString()),
      MetricId.cadenceAvg => MetricReading(stats.avgCadence?.toString()),
      MetricId.cadenceMax => MetricReading(stats.maxCadence?.toString()),
      // Le dénivelé n'a de sens qu'une fois la sortie lancée : c'est un cumul,
      // et un cumul avant le départ vaut « rien », pas « zéro mètre ».
      MetricId.ascent => MetricReading(
          active && sources.recorder.gpsEnabled
              ? '${stats.ascentM.round()} m'
              : null,
        ),
      MetricId.altitude => MetricReading(
          sources.recorder.lastFix?.altitudeM?.round().toString(),
        ),
      // La pente vient de l'enregistreur et pas du dernier point : c'est un
      // rapport entre deux endroits du parcours, elle n'existe pas avant le
      // départ ni sur un rouleau, où l'on ne se déplace pas.
      MetricId.grade => MetricReading(active ? _grade(stats) : null),
      // Mêmes bornes que la pente instantanée : hors sortie, ou sur un
      // rouleau sans distance parcourue, la fenêtre ne s'est jamais remplie.
      MetricId.gradeAvg =>
        MetricReading(active ? _roundedGrade(stats.avgGrade) : null),
      MetricId.gradeMax =>
        MetricReading(active ? _roundedGrade(stats.maxGrade) : null),
      MetricId.calories => MetricReading(stats.calories?.toString()),
      MetricId.caloriesPerHour => MetricReading(_caloriesPerHour(stats)),
      MetricId.tss => MetricReading(_tss(stats, profile)),
      MetricId.gears => MetricReading(_gears(sources)),
      MetricId.chainringPosition =>
        MetricReading(sources.hub.latestGears.value?.frontPosition.toString()),
      MetricId.sprocketPosition =>
        MetricReading(sources.hub.latestGears.value?.rearPosition.toString()),
      MetricId.gearRatio => MetricReading(_gearRatio(sources)),
      MetricId.routeRemaining => MetricReading(_remaining(sources)),
      MetricId.routeRemainingGain => MetricReading(_remainingGain(sources)),
      MetricId.routeEta => MetricReading(_eta(sources)),
    };
  }

  /// La vitesse, de la page si elle en publie une, du GPS de l'enregistreur
  /// sinon.
  ///
  /// L'ordre n'est pas arbitraire : la page tient déjà le GPS de la navigation
  /// et publie sa vitesse à chaque position. Le repli sert aux profils **sans
  /// carte** (home-trainer, où il n'y a pas de page web du tout), et il prend la
  /// vitesse Doppler du point plutôt que la dérivée des positions — bien plus
  /// stable, cf. [GpsFix.speedMps].
  ///
  /// Un état périmé ne s'affiche pas : une vitesse figée à 34 km/h à l'arrêt
  /// serait pire que pas de vitesse du tout.
  static String? _speed(MetricSources sources) {
    final now = DateTime.now();
    final nav = sources.nav?.value;
    if (nav != null && !nav.isStale(now)) return _decimal(nav.speedKmh);

    final fix = sources.recorder.lastFix;
    if (fix == null) return null;
    if (now.difference(fix.at) > RideRecorder.fixTtl) return null;
    return _kmh(fix.speedMps);
  }

  /// La pente à l'entier près, signe compris.
  ///
  /// Pas de décimale : la fenêtre qui la mesure ne la donne qu'à un demi-point
  /// près (cf. [RideStats.defaultGradeWindowM]), et une décimale qui danse
  /// pendant qu'on la lit afficherait une précision qu'on n'a pas. Le signe, lui,
  /// reste — c'est la seule chose qui distingue un mur d'un plongeon.
  static String? _grade(RideStats stats) => _roundedGrade(stats.gradePercent);

  static String? _roundedGrade(double? value) => value?.round().toString();

  static String? _remaining(MetricSources sources) {
    final nav = sources.nav?.value;
    if (nav == null || !nav.onRoute || nav.isStale(DateTime.now())) return null;
    return formatDistanceKm(nav.remainingM);
  }

  static String? _remainingGain(MetricSources sources) {
    final nav = sources.nav?.value;
    if (nav == null || !nav.onRoute || nav.isStale(DateTime.now())) return null;
    return '${nav.remainingGainM.round()} m';
  }

  /// Vitesse moyenne « en roulant » : la distance parcourue sur le seul temps
  /// où [RideStats] juge qu'on avançait ([RideStats.movingTime]), pas sur les
  /// échantillons bruts. C'est le même seuil qui sert déjà à corriger le
  /// `total_moving_time` du `.fit` — un feu rouge n'y compte pas non plus.
  /// `null` tant qu'on n'a pas roulé assez pour que ça veuille dire quelque
  /// chose.
  static double? _movingAvgSpeedMps(RideStats stats) {
    final movingS = stats.movingTime.inMilliseconds / 1000;
    if (movingS <= 0) return null;
    return stats.distanceM / movingS;
  }

  /// La dépense énergétique rapportée à l'heure de roulage, et non à l'heure
  /// chronométrée : même raison que [_movingAvgSpeedMps] — un arrêt casse-croûte
  /// n'accumule presque pas de kJ mais continue de faire tourner l'horloge, et
  /// diviser par le temps total ferait chuter le chiffre sans qu'on ait
  /// pédalé moins fort. `null` sans capteur de puissance ([RideStats.calories])
  /// ou tant qu'on n'a pas encore roulé assez pour que le taux veuille dire
  /// quelque chose.
  static String? _caloriesPerHour(RideStats stats) {
    final calories = stats.calories;
    if (calories == null) return null;
    final movingHours = stats.movingTime.inMilliseconds / 1000 / 3600;
    if (movingHours <= 0) return null;
    return (calories / movingHours).round().toString();
  }

  /// Le TSS de la sortie en cours, arrondi — même cascade que le budget de
  /// charge (cf. `rideTss`) : puissance normalisée sur FTP, puis cardio moyen
  /// sur seuil, puis l'intensité par défaut du vélo. `null` tant qu'il n'y a
  /// pas eu de mouvement, jamais un zéro qui se lirait comme un score nul.
  static String? _tss(RideStats stats, RiderProfile profile) =>
      rideTss(stats, profile)?.tss.round().toString();

  /// Temps restant estimé sur l'itinéraire : la distance qui reste (la page)
  /// divisée par la vitesse moyenne en roulant (l'enregistreur). `null` sans
  /// itinéraire suivi, ou tant qu'on n'a pas encore de vitesse à projeter.
  static String? _eta(MetricSources sources) {
    final nav = sources.nav?.value;
    if (nav == null || !nav.onRoute || nav.isStale(DateTime.now())) return null;

    final speedMps = _movingAvgSpeedMps(sources.recorder.stats);
    if (speedMps == null || speedMps <= 0) return null;

    final etaSeconds = nav.remainingM / speedMps;
    return formatDurationHm(Duration(seconds: etaSeconds.round()));
  }

  /// Le braquet en positions — `2 × 7` — et non en dents.
  ///
  /// Les dents demandent de savoir ce qu'il y a sur le vélo ([Drivetrain]), ce
  /// que le Di2 ne dit pas ; la position, elle, est toujours juste. La carte des
  /// valeurs en direct de l'écran des capteurs affiche les deux, parce qu'elle
  /// a la place et qu'on la lit à l'arrêt.
  static String? _gears(MetricSources sources) {
    final gears = sources.hub.latestGears.value;
    if (gears == null) return null;
    return '${gears.frontPosition} × ${gears.rearPosition}';
  }

  /// Le rapport de développement — dents du plateau sur dents du pignon — à une
  /// décimale : c'est ce qui se compare d'un vélo à l'autre, indépendamment de
  /// la circonférence de roue. `null` sans transmission connue pour cette
  /// position ([Drivetrain]), le Di2 ne publiant que des positions.
  static String? _gearRatio(MetricSources sources) {
    final gears = sources.hub.latestGears.value;
    if (gears == null) return null;
    final ratio = sources.drivetrain.ratio(gears);
    return ratio == null ? null : _decimal(ratio);
  }

  static MetricReading _zoned(
    int? value, {
    required RiderProfile profile,
    required TrainingZone? Function(num value) zoneOf,
    required bool asZone,
    required String threshold,
    required bool hasZones,
  }) {
    final zone = value == null ? null : zoneOf(value);
    if (!asZone) {
      return MetricReading(value?.toString(), zoneKey: zone?.key);
    }
    // Le seuil passe avant le capteur : sans zones, aucune mesure n'en donnera
    // jamais, et c'est ça qu'il faut dire — y compris quand le capteur est muet.
    // Le tiret seul se lirait comme un capteur débranché et cacherait la seule
    // des deux causes que le cycliste puisse corriger, sur le site, avant de
    // partir.
    if (!hasZones) return MetricReading(threshold);
    return MetricReading(zone?.key.toUpperCase(), zoneKey: zone?.key);
  }

  static String? _kmh(double? metresPerSecond) =>
      metresPerSecond == null ? null : _decimal(metresPerSecond * 3.6);

  /// La vitesse moyenne porte son unité sur le chiffre lui-même : sa case
  /// affiche un titre (« Vitesse moyenne ») là où les autres cases de vitesse
  /// gardent l'unité en dessous.
  static String? _kmhUnit(double? metresPerSecond) {
    final value = _kmh(metresPerSecond);
    return value == null ? null : '$value km/h';
  }

  static String _decimal(double value) =>
      value.toStringAsFixed(1).replaceAll('.', ',');
}

/// D'où les mesures se lisent.
///
/// Elle porte les **écoutables** et non des valeurs figées : la même instance
/// sert à lire ([MetricId.read]) et à savoir quand se reconstruire
/// ([MetricId.dependencies]), si bien que les deux ne peuvent pas diverger.
@immutable
class MetricSources {
  const MetricSources({
    required this.hub,
    required this.recorder,
    required this.riderProfile,
    required this.trainingBudget,
    this.drivetrain = Drivetrain.road,
    this.nav,
    this.routeClimbs,
  });

  final SensorHub hub;
  final RideRecorder recorder;

  /// Traduit une position Di2 en dents, pour [MetricId.gearRatio]. Même
  /// convention par défaut que [RideRecorder] et `LiveValuesCard` : la
  /// transmission réelle du vélo, pas une hypothèse recalculée ici.
  final Drivetrain drivetrain;

  /// Les seuils du cycliste, d'où sortent les zones. **Jamais une zone calculée
  /// sur un seuil par défaut** : sans seuil, la case l'annonce en toutes lettres.
  final RiderProfileStore riderProfile;

  /// Le budget de charge, calculé par le site et poussé par la page de
  /// navigation. Le magasin est toujours là ; c'est **son contenu** qui peut
  /// manquer (compte tout neuf, jamais connecté), et le composant le dit.
  final TrainingBudgetStore trainingBudget;

  /// Ce que la page web publie de la navigation. **Nul dans un profil sans
  /// carte** : il n'y a alors pas de page pour le dire, et les mesures qui en
  /// dépendent s'abstiennent au lieu de deviner.
  final ValueListenable<NavState?>? nav;

  /// La liste des cols du tracé en cours, poussée par la page. **Nulle dans un
  /// profil sans carte**, même raison que [nav] — voir [ClimbListBlock].
  final ValueListenable<RouteClimbs?>? routeClimbs;
}

/// Une mesure prête à peindre : son texte, et la zone qui la colore.
@immutable
class MetricReading {
  const MetricReading(this.value, {this.zoneKey});

  /// `null` = pas de mesure. Le rendu écrit alors `—`, jamais `0`.
  final String? value;

  /// `z1`…`z7`, ou `null` pour laisser la case sur le fond du tableau de bord.
  /// Une couleur inventée serait pire qu'une couleur absente.
  final String? zoneKey;

  @override
  bool operator ==(Object other) =>
      other is MetricReading &&
      other.value == value &&
      other.zoneKey == zoneKey;

  @override
  int get hashCode => Object.hash(value, zoneKey);
}
