import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../account/rider_profile.dart';
import '../account/rider_profile_store.dart';
import '../ble/sensor_hub.dart';
import '../drivetrain.dart';
import '../lighting/sun.dart';
import '../recording/ride_lap.dart';
import '../recording/ride_recorder.dart';
import '../recording/ride_stats.dart';
import '../ride/climb_profile.dart';
import '../ride/nav_state.dart';
import '../ride/route_climbs.dart';
import '../ride/route_profile.dart';
import '../training/ride_load.dart';
import '../training/training_budget_store.dart';
import '../training/wprime_balance.dart';
import '../ui/formats.dart';
import '../ui/grade_colors.dart';
import 'dashboard_block.dart' show DurationFormat;

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
  duration('duration', 'Durée', '', Icons.timer_outlined),
  movingTime('moving_time', 'Temps en mouvement', '', Icons.directions_bike),
  pauseTime('pause_time', 'Durée pause', '', Icons.pause_circle_outline),
  distance('distance', 'Distance', 'km', Icons.straighten),
  speed('speed', 'Vitesse', 'km/h', Icons.speed),
  speedAvg('speed_avg', 'Vitesse moyenne', 'km/h', Icons.speed),
  speedMax('speed_max', 'Vitesse max', 'km/h', Icons.speed),
  speedMin('speed_min', 'Vitesse minimum', 'km/h', Icons.speed),
  heartRate('heart_rate', 'Cardio', 'bpm', Icons.favorite),
  hrZone('hr_zone', 'Zone cardio', 'bpm', Icons.favorite),
  hrAvg('hr_avg', 'Cardio moyen', 'bpm', Icons.favorite_border),
  hrMax('hr_max', 'Cardio max', 'bpm', Icons.favorite_border),
  hrMin('hr_min', 'Cardio minimum', 'bpm', Icons.favorite_border),
  power('power', 'Puissance', 'W', Icons.bolt),
  powerZone('power_zone', 'Zone de puissance', 'W', Icons.bolt),
  powerAvg('power_avg', 'Puissance moyenne', 'W', Icons.bolt),
  powerNormalized('power_np', 'Puissance normalisée', 'W', Icons.bolt),
  powerMax('power_max', 'Puissance max', 'W', Icons.bolt),
  powerMin('power_min', 'Puissance minimum', 'W', Icons.bolt),
  powerBalance('power_balance', 'Équilibre G/D', '%', Icons.balance),
  cadence('cadence', 'Cadence', 'tr/min', Icons.autorenew),
  cadenceAvg('cadence_avg', 'Cadence moyenne', 'tr/min', Icons.autorenew),
  cadenceMax('cadence_max', 'Cadence max', 'tr/min', Icons.autorenew),
  cadenceMin('cadence_min', 'Cadence minimum', 'tr/min', Icons.autorenew),
  ascent('ascent', 'Dénivelé positif', 'm', Icons.trending_up),
  altitude('altitude', 'Altitude', 'm', Icons.terrain),
  altitudeAvg('altitude_avg', 'Altitude moyenne', 'm', Icons.terrain),
  altitudeMax('altitude_max', 'Altitude max', 'm', Icons.terrain),
  grade('grade', 'Pente', '%', Icons.north_east),
  gradeAvg('grade_avg', 'Pente moyenne', '%', Icons.north_east),
  gradeMax('grade_max', 'Pente max', '%', Icons.north_east),
  gradeMin('grade_min', 'Pente minimum', '%', Icons.north_east),
  climbRate('climb_rate', 'Vitesse ascensionnelle', 'm/h', Icons.upgrade),
  climbRateAvg('climb_rate_avg', 'Vitesse ascensionnelle moyenne', 'm/h', Icons.upgrade),
  climbRateMax('climb_rate_max', 'Vitesse ascensionnelle max', 'm/h', Icons.upgrade),
  calories('calories', 'Calories', 'kcal', Icons.local_fire_department),
  caloriesPerHour('calories_per_hour', 'Calories par heure', 'kcal/h', Icons.local_fire_department),
  tss('tss', 'TSS', 'TSS', Icons.bar_chart),
  gears('gears', 'Braquet', '', Icons.settings),
  chainringPosition('chainring_position', 'Plateau', '', Icons.donut_large),
  sprocketPosition('sprocket_position', 'Pignon', '', Icons.album),
  gearRatio('gear_ratio', 'Rapport', '', Icons.compare_arrows),
  routeRemaining('route_remaining', 'Distance restante', 'km', Icons.flag_outlined),
  routeRemainingGain('route_remaining_gain', 'D+ restant', 'm', Icons.trending_up),
  routeEta('route_eta', 'Temps restant', '', Icons.schedule),
  routeArrivalTime('route_arrival_time', 'Heure d\'arrivée', '', Icons.schedule),
  daylightRemaining('daylight_remaining', 'Lumière du jour restante', '', Icons.wb_twilight),
  efficiencyFactor('efficiency_factor', 'Facteur d\'efficacité', '', Icons.insights),
  variabilityIndex('variability_index', 'Indice de variabilité', '', Icons.show_chart),
  aerobicDecoupling('decoupling', 'Découplage aérobie', '%', Icons.timeline),
  wprimeBalance('wprime_balance', 'Réserve W′', 'kJ', Icons.battery_charging_full);

  const MetricId(this.key, this.name, this.unit, this.icon);

  /// La clé du contrat JSON. Écrite à la main plutôt que dérivée du nom Dart :
  /// renommer une valeur Dart ne doit pas casser les documents déjà servis par
  /// le site.
  final String key;

  /// Le nom de la mesure, ex. « Cardio » — l'étiquette d'un bloc `metric` qui
  /// en pose une (voir [DashboardBlock]/`MetricLayoutToken.label`). Distinct
  /// d'[unit] depuis la disposition libre du tableau de bord : avant, un seul
  /// champ faisait les deux, tantôt un nom tantôt une unité selon la mesure.
  final String name;

  /// L'unité physique, ex. « bpm » — vide pour les mesures qui n'en ont pas
  /// (une durée, une position de plateau…). Ce qui s'écrit sous le chiffre
  /// (`MetricView`) ou à côté du nom, selon la disposition composée.
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

  /// La plage de [MetricMode.dynamicGauge] : `null` tant qu'elle n'a pas
  /// encore de sens plutôt que d'en inventer une — mêmes gardes que [read].
  ///
  /// Deux natures de plage, selon la mesure :
  /// - cadence / cardio / puissance / vitesse / pente : le min et le max
  ///   observés depuis le départ ([RideStats]) — une plage qui s'élargit en
  ///   roulant, pas un réglage de l'éditeur.
  /// - distance / durée : la progression sur l'itinéraire suivi, de 0 au
  ///   total (parcouru/écoulé + ce que [NavState] dit encore restant) — ces
  ///   deux mesures sont des cumuls, un min/max « observé » n'y voudrait rien
  ///   dire (le min vaudrait toujours 0, le max toujours la valeur du moment).
  (double, double)? liveRangeOf(MetricSources sources) {
    // Un tour a sa propre plage : le min/max observés depuis l'ouverture du
    // tour, pas depuis le départ de la sortie — même source que [read].
    final stats = sources.lap?.stats ?? sources.recorder.stats;
    return switch (this) {
      MetricId.cadence =>
        _bounds(stats.minCadence?.toDouble(), stats.maxCadence?.toDouble()),
      MetricId.heartRate =>
        _bounds(stats.minHeartRate?.toDouble(), stats.maxHeartRate?.toDouble()),
      MetricId.power => _bounds(stats.minPower?.toDouble(), stats.maxPower?.toDouble()),
      // km/h, comme MetricReading.numericValue de `speed` (cf. `_speedReading`).
      MetricId.speed => _bounds(
          stats.minSpeedMps == null ? null : stats.minSpeedMps! * 3.6,
          stats.maxSpeedMps == null ? null : stats.maxSpeedMps! * 3.6,
        ),
      MetricId.grade => _bounds(stats.minGrade, stats.maxGrade),
      MetricId.distance => _routeDistanceRange(sources),
      MetricId.duration => _routeDurationRange(sources),
      // 0 → W′₀ : la jauge se vide dans les efforts au-dessus de la CP et se
      // recharge en dessous. Plage fixe (pas « observée ») — le maximum, c'est
      // la réserve pleine, connue d'avance.
      MetricId.wprimeBalance => _wprimeRange(sources),
      _ => null,
    };
  }

  static (double, double)? _wprimeRange(MetricSources sources) {
    final full = sources.wPrime?.wPrimeJ;
    if (full == null || full <= 0) return null;
    return (0, full / 1000);
  }

  static (double, double)? _bounds(double? min, double? max) =>
      min == null || max == null || min >= max ? null : (min, max);

  /// 0 → distance totale de l'itinéraire suivi, déduite sans rien demander de
  /// plus à la page web : ce qui a été parcouru ([RideRecorder.distanceM]) plus
  /// ce qu'elle dit encore restant ([NavState.remainingM]) — pas besoin d'un
  /// total publié séparément.
  static (double, double)? _routeDistanceRange(MetricSources sources) {
    final nav = sources.nav?.value;
    if (nav == null || !nav.onRoute || nav.isStale(DateTime.now())) return null;
    if (!sources.recorder.gpsEnabled) return null;
    final totalM = sources.recorder.distanceM + nav.remainingM;
    if (totalM <= 0) return null;
    return (0, totalM / 1000);
  }

  /// 0 → durée totale estimée de l'itinéraire suivi : le temps déjà écoulé
  /// plus le même calcul que [_eta] pour ce qu'il en reste. Comme [routeEta],
  /// cette borne haute se redéfinit à chaque tick avec l'allure — ce n'est pas
  /// un total figé au départ.
  static (double, double)? _routeDurationRange(MetricSources sources) {
    final nav = sources.nav?.value;
    if (nav == null || !nav.onRoute || nav.isStale(DateTime.now())) return null;
    final stats = sources.recorder.stats;
    final speedMps = _movingAvgSpeedMps(stats);
    if (speedMps == null || speedMps <= 0) return null;
    final elapsedS = sources.recorder.recorded.inMilliseconds / 1000;
    final remainingS = nav.remainingM / speedMps;
    final totalS = elapsedS + remainingS;
    if (totalS <= 0) return null;
    return (0, totalS);
  }

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
      // Le W′ balance suit son propre modèle (capteur de puissance + seuils) —
      // `riderProfile` en plus pour la plage de la jauge, qui dépend de W′₀.
      MetricId.wprimeBalance => [
          if (sources.wPrime != null) sources.wPrime!,
          sources.riderProfile,
        ],
      MetricId.cadence => [sources.hub.latestCadence],
      MetricId.powerBalance => [sources.hub.latestPowerBalance],
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
      // L'heure d'arrivée en sort par simple addition (`now + reste`), mêmes
      // sources.
      MetricId.routeEta || MetricId.routeArrivalTime => [sources.recorder, if (nav != null) nav],
      // Le chiffre ne dépend que de l'enregistreur, mais la plage de la jauge
      // dynamique (parcouru → total de l'itinéraire) suit aussi la page :
      // c'est elle qui publie ce qu'il en reste ([liveRangeOf]).
      MetricId.distance || MetricId.duration => [sources.recorder, if (nav != null) nav],
      _ => [sources.recorder],
    };
  }

  /// La valeur du moment, mise en forme.
  ///
  /// `null` veut dire « pas de mesure », ce que le rendu écrit **`—` et jamais
  /// `0`** : un zéro se lit comme une mesure, et un capteur muet ne mesure pas
  /// zéro, il ne mesure rien.
  MetricReading read(
    MetricSources sources, {
    DurationFormat format = DurationFormat.hm,
  }) {
    // Une page Tours pose ce même catalogue sur le tour choisi plutôt que sur
    // la sortie entière (`LapListBody._block`) : `sources.lap` porte alors ce
    // tour, et c'est lui qui fait foi pour tout ce qui est cumulé — durée,
    // distance, moyennes, dénivelé, calories, TSS. `RideLap.stats` est nourri
    // exactement comme celui de la sortie (même doc sur `RideLap`), donc tout
    // ce qui se lit déjà sur `stats` ci-dessous suit sans rien changer de plus
    // ; seules la durée et la distance n'y sont pas et gardent leur propre
    // repli. Les mesures instantanées (cardio, cadence, vitesse, altitude…)
    // restent celles du hub/GPS : un tour n'a pas de « cardio de l'instant »
    // distinct de celui de la sortie.
    final lap = sources.lap;
    final stats = lap?.stats ?? sources.recorder.stats;
    final active = sources.recorder.isActive;
    final profile = sources.riderProfile.profile;
    final rideDuration =
        lap != null ? Duration(seconds: lap.pointCount) : sources.recorder.recorded;
    final rideDistanceM = lap != null ? lap.distanceM : sources.recorder.distanceM;
    String fmt(Duration d) =>
        format == DurationFormat.hms ? formatDurationHms(d) : formatDurationHm(d);

    return switch (this) {
      // Durée et distance viennent de l'enregistreur (ou du tour) et pas de la
      // page : hors enregistrement elles n'existent pas, et un zéro ferait
      // croire à un compteur remis à zéro plutôt qu'à une sortie non lancée.
      MetricId.duration => MetricReading(active ? fmt(rideDuration) : null),
      MetricId.movingTime =>
        MetricReading(active ? fmt(stats.movingTime) : null),
      // Le complément de la durée en mouvement : arrêts aux feux, ravito,
      // discussion sur le bas-côté. Les deux viennent de la même horloge —
      // `rideDuration` ne tourne pas non plus pendant une pause manuelle — donc
      // la soustraction ne peut pas passer sous zéro.
      MetricId.pauseTime => MetricReading(
          active ? fmt(rideDuration - stats.movingTime) : null,
        ),
      // Sans GPS (home-trainer), la distance n'a pas de source : un « 0 m » se
      // lirait comme « je n'ai pas bougé », alors que la question ne se pose
      // même pas. Le tiret dit la bonne chose — on ne mesure pas ça ici.
      MetricId.distance => MetricReading(
          active && sources.recorder.gpsEnabled ? formatKm(rideDistanceM) : null,
          numericValue:
              active && sources.recorder.gpsEnabled ? rideDistanceM / 1000 : null,
        ),
      MetricId.speed => _speedReading(sources),
      // Moyenne en roulant, pas la moyenne des échantillons bruts : sans ça,
      // un feu rouge dilue la case pendant que la sortie continue.
      MetricId.speedAvg => MetricReading(
          _kmh(_movingAvgSpeedMps(stats)),
          numericValue: _kmhValue(_movingAvgSpeedMps(stats)),
        ),
      MetricId.speedMax => MetricReading(
          _kmh(stats.maxSpeedMps),
          numericValue: _kmhValue(stats.maxSpeedMps),
        ),
      MetricId.speedMin => MetricReading(
          _kmh(stats.minSpeedMps),
          numericValue: _kmhValue(stats.minSpeedMps),
        ),
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
      MetricId.hrAvg => MetricReading(
          stats.avgHeartRate?.toString(),
          numericValue: stats.avgHeartRate?.toDouble(),
          zoneKey: stats.avgHeartRate == null ? null : profile.hrZoneFor(stats.avgHeartRate!)?.key,
        ),
      MetricId.hrMax => MetricReading(
          stats.maxHeartRate?.toString(),
          numericValue: stats.maxHeartRate?.toDouble(),
          zoneKey: stats.maxHeartRate == null ? null : profile.hrZoneFor(stats.maxHeartRate!)?.key,
        ),
      MetricId.hrMin => MetricReading(
          stats.minHeartRate?.toString(),
          numericValue: stats.minHeartRate?.toDouble(),
          zoneKey: stats.minHeartRate == null ? null : profile.hrZoneFor(stats.minHeartRate!)?.key,
        ),
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
      MetricId.powerAvg => MetricReading(
          stats.avgPower?.toString(),
          numericValue: stats.avgPower?.toDouble(),
          zoneKey: stats.avgPower == null ? null : profile.powerZoneFor(stats.avgPower!)?.key,
        ),
      MetricId.powerNormalized => MetricReading(
          stats.normalizedPowerW?.toString(),
          numericValue: stats.normalizedPowerW?.toDouble(),
          zoneKey: stats.normalizedPowerW == null ? null : profile.powerZoneFor(stats.normalizedPowerW!)?.key,
        ),
      MetricId.powerMax => MetricReading(
          stats.maxPower?.toString(),
          numericValue: stats.maxPower?.toDouble(),
          zoneKey: stats.maxPower == null ? null : profile.powerZoneFor(stats.maxPower!)?.key,
        ),
      MetricId.powerMin => MetricReading(
          stats.minPower?.toString(),
          numericValue: stats.minPower?.toDouble(),
          zoneKey: stats.minPower == null ? null : profile.powerZoneFor(stats.minPower!)?.key,
        ),
      MetricId.powerBalance =>
        _balanceReading(sources.hub.latestPowerBalance.value),
      MetricId.cadence => MetricReading(
          sources.hub.latestCadence.value?.round().toString(),
          numericValue: sources.hub.latestCadence.value,
        ),
      MetricId.cadenceAvg => MetricReading(
          stats.avgCadence?.toString(),
          numericValue: stats.avgCadence?.toDouble(),
        ),
      MetricId.cadenceMax => MetricReading(
          stats.maxCadence?.toString(),
          numericValue: stats.maxCadence?.toDouble(),
        ),
      MetricId.cadenceMin => MetricReading(
          stats.minCadence?.toString(),
          numericValue: stats.minCadence?.toDouble(),
        ),
      // Le dénivelé n'a de sens qu'une fois la sortie lancée : c'est un cumul,
      // et un cumul avant le départ vaut « rien », pas « zéro mètre ».
      MetricId.ascent => MetricReading(
          active && sources.recorder.gpsEnabled
              ? stats.ascentM.round().toString()
              : null,
          numericValue: active && sources.recorder.gpsEnabled ? stats.ascentM : null,
        ),
      // Mesure instantanée (voir la tête de [read]) : toujours celle de la
      // sortie entière, jamais celle d'un tour qu'on est en train de
      // consulter. Baromètre préféré au GPS dès qu'il y en a un, même
      // préférence collante que [RideStats.ascentM] — sinon la valeur
      // sauterait de plusieurs mètres au moment même où le baromètre prend le
      // relais.
      MetricId.altitude => MetricReading(
          sources.recorder.stats.currentAltitudeM?.round().toString(),
          numericValue: sources.recorder.stats.currentAltitudeM,
        ),
      MetricId.altitudeAvg => MetricReading(
          stats.avgAltitudeM?.round().toString(),
          numericValue: stats.avgAltitudeM,
        ),
      MetricId.altitudeMax => MetricReading(
          stats.maxAltitudeM?.round().toString(),
          numericValue: stats.maxAltitudeM,
        ),
      // La pente vient de l'enregistreur et pas du dernier point : c'est un
      // rapport entre deux endroits du parcours, elle n'existe pas avant le
      // départ ni sur un rouleau, où l'on ne se déplace pas.
      MetricId.grade => _gradeReading(active ? stats.gradePercent : null),
      // Mêmes bornes que la pente instantanée : hors sortie, ou sur un
      // rouleau sans distance parcourue, la fenêtre ne s'est jamais remplie.
      MetricId.gradeAvg => _gradeReading(active ? stats.avgGrade : null),
      MetricId.gradeMax => _gradeReading(active ? stats.maxGrade : null),
      MetricId.gradeMin => _gradeReading(active ? stats.minGrade : null),
      // Même garde que la pente : la vitesse ascensionnelle se lit sur la même
      // fenêtre, qui reste naturellement vide sans altitude.
      MetricId.climbRate => MetricReading(
          active ? stats.climbRateMph?.round().toString() : null,
          numericValue: active ? stats.climbRateMph : null,
        ),
      MetricId.climbRateAvg => MetricReading(
          active ? stats.avgClimbRateMph?.round().toString() : null,
          numericValue: active ? stats.avgClimbRateMph : null,
        ),
      MetricId.climbRateMax => MetricReading(
          active ? stats.maxClimbRateMph?.round().toString() : null,
          numericValue: active ? stats.maxClimbRateMph : null,
        ),
      MetricId.calories => MetricReading(
          stats.calories?.toString(),
          numericValue: stats.calories?.toDouble(),
        ),
      MetricId.caloriesPerHour => _caloriesPerHourReading(stats),
      MetricId.tss => _tssReading(stats, profile),
      MetricId.gears => MetricReading(_gears(sources)),
      MetricId.chainringPosition => MetricReading(
          sources.hub.latestGears.value?.frontPosition.toString(),
          numericValue: sources.hub.latestGears.value?.frontPosition.toDouble(),
        ),
      MetricId.sprocketPosition => MetricReading(
          sources.hub.latestGears.value?.rearPosition.toString(),
          numericValue: sources.hub.latestGears.value?.rearPosition.toDouble(),
        ),
      MetricId.gearRatio => _gearRatioReading(sources),
      MetricId.routeRemaining => _remainingReading(sources),
      MetricId.routeRemainingGain => _remainingGainReading(sources),
      MetricId.routeEta => MetricReading(_eta(sources, fmt)),
      MetricId.routeArrivalTime => MetricReading(_arrivalTime(sources)),
      MetricId.daylightRemaining => _daylightRemainingReading(sources, fmt),
      MetricId.efficiencyFactor => _efficiencyFactorReading(stats),
      MetricId.variabilityIndex => _variabilityIndexReading(stats),
      MetricId.aerobicDecoupling => _decouplingReading(stats),
      MetricId.wprimeBalance => _wprimeReading(sources),
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
  static MetricReading _speedReading(MetricSources sources) {
    final now = DateTime.now();
    final nav = sources.nav?.value;
    if (nav != null && !nav.isStale(now)) {
      return MetricReading(_decimal(nav.speedKmh), numericValue: nav.speedKmh);
    }

    final fix = sources.recorder.lastFix;
    if (fix == null || now.difference(fix.at) > RideRecorder.fixTtl) {
      return const MetricReading(null);
    }
    return MetricReading(_kmh(fix.speedMps), numericValue: _kmhValue(fix.speedMps));
  }

  /// La pente à l'entier près, signe compris.
  ///
  /// Pas de décimale : la fenêtre qui la mesure ne la donne qu'à un demi-point
  /// près (cf. [RideStats.defaultGradeWindowM]), et une décimale qui danse
  /// pendant qu'on la lit afficherait une précision qu'on n'a pas. Le signe, lui,
  /// reste — c'est la seule chose qui distingue un mur d'un plongeon.
  static String? _roundedGrade(double? value) => value?.round().toString();

  /// La pente (instantanée, moyenne ou maximum), sa case peinte de la couleur
  /// de sa tranche de difficulté — même table que le profil des cols
  /// (`gradeColorOf`) : on doit reconnaître un mur avant de déchiffrer le
  /// chiffre, comme sur le profil altimétrique.
  static MetricReading _gradeReading(double? value) => MetricReading(
        _roundedGrade(value),
        background: value == null ? null : gradeColorOf(value),
      );

  static MetricReading _remainingReading(MetricSources sources) {
    final nav = sources.nav?.value;
    if (nav == null || !nav.onRoute || nav.isStale(DateTime.now())) {
      return const MetricReading(null);
    }
    return MetricReading(formatKm(nav.remainingM), numericValue: nav.remainingM / 1000);
  }

  static MetricReading _remainingGainReading(MetricSources sources) {
    final nav = sources.nav?.value;
    if (nav == null || !nav.onRoute || nav.isStale(DateTime.now())) {
      return const MetricReading(null);
    }
    return MetricReading(nav.remainingGainM.round().toString(), numericValue: nav.remainingGainM);
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
  static MetricReading _caloriesPerHourReading(RideStats stats) {
    final calories = stats.calories;
    if (calories == null) return const MetricReading(null);
    final movingHours = stats.movingTime.inMilliseconds / 1000 / 3600;
    if (movingHours <= 0) return const MetricReading(null);
    final value = calories / movingHours;
    return MetricReading(value.round().toString(), numericValue: value);
  }

  /// Le TSS de la sortie en cours, arrondi — même cascade que le budget de
  /// charge (cf. `rideTss`) : puissance normalisée sur FTP, puis cardio moyen
  /// sur seuil, puis l'intensité par défaut du vélo. `null` tant qu'il n'y a
  /// pas eu de mouvement, jamais un zéro qui se lirait comme un score nul.
  static MetricReading _tssReading(RideStats stats, RiderProfile profile) {
    final tss = rideTss(stats, profile)?.tss;
    return MetricReading(tss?.round().toString(), numericValue: tss);
  }

  /// Temps restant estimé sur l'itinéraire : la distance qui reste (la page)
  /// divisée par la vitesse moyenne en roulant (l'enregistreur). `null` sans
  /// itinéraire suivi, ou tant qu'on n'a pas encore de vitesse à projeter.
  static Duration? _etaDuration(MetricSources sources) {
    final nav = sources.nav?.value;
    if (nav == null || !nav.onRoute || nav.isStale(DateTime.now())) return null;

    final speedMps = _movingAvgSpeedMps(sources.recorder.stats);
    if (speedMps == null || speedMps <= 0) return null;

    return Duration(seconds: (nav.remainingM / speedMps).round());
  }

  static String? _eta(MetricSources sources, String Function(Duration) fmt) {
    final eta = _etaDuration(sources);
    return eta == null ? null : fmt(eta);
  }

  /// L'heure murale d'arrivée : maintenant plus le temps restant de [_eta].
  /// Une horloge (`15:42`), pas un compte à rebours — d'où [formatClockHm] et
  /// non le formateur de durée. `null` dans les mêmes cas que [_eta].
  static String? _arrivalTime(MetricSources sources) {
    final eta = _etaDuration(sources);
    return eta == null ? null : formatClockHm(DateTime.now().add(eta));
  }

  /// La lumière du jour qu'il reste avant le coucher du soleil, à la position
  /// GPS de l'enregistreur. `null` sans GPS (home-trainer) et une fois le
  /// soleil couché : un « 00:00 » se lirait comme un compte à rebours qui
  /// vient d'expirer, pas comme « il fait nuit ».
  static MetricReading _daylightRemainingReading(
    MetricSources sources,
    String Function(Duration) fmt,
  ) {
    if (!sources.recorder.gpsEnabled) return const MetricReading(null);
    final fix = sources.recorder.lastFix;
    if (fix == null) return const MetricReading(null);

    final now = DateTime.now();
    final sunset =
        Sun.nextSetUtc(from: now, latitude: fix.lat, longitude: fix.lng);
    if (sunset == null) return const MetricReading(null);

    final remaining = sunset.difference(now);
    if (remaining <= Duration.zero) return const MetricReading(null);
    return MetricReading(fmt(remaining));
  }

  /// Le facteur d'efficacité : puissance normalisée (à défaut moyenne)
  /// rapportée au cardio moyen — des watts par battement, qui montent quand la
  /// forme s'améliore à cardio égal. `null` sans les deux capteurs.
  static MetricReading _efficiencyFactorReading(RideStats stats) {
    final power = stats.normalizedPowerW ?? stats.avgPower;
    final hr = stats.avgHeartRate;
    if (power == null || hr == null || hr <= 0) return const MetricReading(null);
    final value = power / hr;
    return MetricReading(_decimal2(value), numericValue: value);
  }

  /// L'indice de variabilité : puissance normalisée sur puissance moyenne —
  /// 1,00 pour un effort parfaitement lissé, davantage pour une sortie hachée.
  /// `null` sans capteur de puissance.
  static MetricReading _variabilityIndexReading(RideStats stats) {
    final np = stats.normalizedPowerW;
    final avg = stats.avgPower;
    if (np == null || avg == null || avg <= 0) return const MetricReading(null);
    final value = np / avg;
    return MetricReading(_decimal2(value), numericValue: value);
  }

  static String _decimal2(double value) =>
      value.toStringAsFixed(2).replaceAll('.', ',');

  /// Le découplage aérobie, signe compris — `+4,2` se lit « la fatigue
  /// commence », `-1,0` « encore frais ». Comme la pente, le signe porte
  /// l'essentiel de l'information. `null` tant que la sortie est trop courte
  /// (voir [RideStats.aerobicDecouplingPercent]).
  static MetricReading _decouplingReading(RideStats stats) {
    final value = stats.aerobicDecouplingPercent;
    if (value == null) return const MetricReading(null);
    final sign = value > 0 ? '+' : '';
    return MetricReading('$sign${_decimal(value)}', numericValue: value);
  }

  /// La réserve W′ restante, en kilojoules. `null` sans capteur de puissance
  /// déclaré, ou tant que la CP n'est pas connue — jamais une réserve devinée
  /// sur un seuil par défaut.
  static MetricReading _wprimeReading(MetricSources sources) {
    final balanceJ = sources.wPrime?.balanceJ;
    if (balanceJ == null) return const MetricReading(null);
    final kj = balanceJ / 1000;
    return MetricReading(_decimal(kj), numericValue: kj);
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
  static MetricReading _gearRatioReading(MetricSources sources) {
    final gears = sources.hub.latestGears.value;
    if (gears == null) return const MetricReading(null);
    final ratio = sources.drivetrain.ratio(gears);
    return MetricReading(ratio == null ? null : _decimal(ratio), numericValue: ratio);
  }

  /// L'équilibre gauche/droite sous la forme lue sur un compteur — les deux
  /// pourcentages côte à côte, pas un seul chiffre qu'il faudrait soustraire
  /// de 100 pour connaître l'autre jambe.
  static MetricReading _balanceReading(double? leftPercent) {
    if (leftPercent == null) return const MetricReading(null);
    final left = leftPercent.round();
    return MetricReading('$left / ${100 - left}', numericValue: leftPercent);
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

  static double? _kmhValue(double? metresPerSecond) =>
      metresPerSecond == null ? null : metresPerSecond * 3.6;

  static String? _kmh(double? metresPerSecond) {
    final value = _kmhValue(metresPerSecond);
    return value == null ? null : _decimal(value);
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
    this.climb,
    this.upcomingClimb,
    this.climbProfile,
    this.routeProfile,
    this.wPrime,
    this.lap,
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

  /// Le col en cours, **stabilisé** — jamais `nav.value?.climb` en direct
  /// (voir `RideShellPage.ClimbEdgePolicy`, `climb_edge_policy.dart`) : brut,
  /// ce champ peut flickerer `null`/non-`null` d'une trame à l'autre près de
  /// la frontière du col (position simulée surtout), ce qui faisait battre la
  /// pastille et retomber `ClimbProfileCard` sur « Aucun col en cours »
  /// pendant que la pastille, elle, restait allumée. **Nul dans un profil
  /// sans carte**, même raison que [routeClimbs].
  final ValueListenable<NavClimb?>? climb;

  /// Le prochain col, à moins de 500 m de son départ — `null` sinon, ou une
  /// fois qu'on y est (voir `RideShellPage._upcomingClimb`). Sert à
  /// préremplir `LapClimbProfileCard` (page Tours)
  /// pendant l'approche, avant que le tour du col ne soit ouvert : sans lui,
  /// cette carte n'a rien à montrer tant qu'on n'y est pas, alors que la page
  /// s'ouvre déjà avant. **Nul dans un profil sans carte**, même raison que
  /// [routeClimbs].
  final ValueListenable<RouteClimb?>? upcomingClimb;

  /// Le profil gradué du col en cours, poussé une fois par col. **Nul dans un
  /// profil sans carte**, même raison que [routeClimbs] — voir
  /// [ClimbProfileBlock].
  final ValueListenable<ClimbProfile?>? climbProfile;

  /// Le profil d'altitude du tracé entier, poussé une fois par (re)chargement.
  /// **Nul dans un profil sans carte**, même raison que [routeClimbs] — mais
  /// contrairement à lui, son absence n'empêche pas [AltitudeProfileBlock] de
  /// s'afficher : il se rabat alors sur `recorder.elevationTrack`.
  final ValueListenable<RouteProfile?>? routeProfile;

  /// Le W′ balance en direct, calculé sur le téléphone à partir du capteur de
  /// puissance et des seuils du site ([WPrimeBalance]). **Nul dans un profil
  /// sans capteur de puissance déclaré** ; son *contenu* peut aussi manquer
  /// (pas de CP connue), et [MetricId.read] le dit alors — jamais une réserve
  /// devinée. Ride-wide, jamais recadré sur un tour (comme [nav]).
  final WPrimeBalance? wPrime;

  /// Le tour affiché par une page Tours ([LapListPageSpec]), `null` partout
  /// ailleurs. Quand il est posé, [MetricId.read]/[MetricId.liveRangeOf]
  /// lisent leurs mesures cumulées sur **ce tour** plutôt que sur la sortie
  /// entière — voir [forLap].
  final RideLap? lap;

  /// La même source, bornée à [lap] — voir `LapListBody._block`. Rien d'autre
  /// ne change : le hub, le GPS et la page web restent ceux de la sortie en
  /// cours, seules les mesures cumulées ([MetricId.read]) suivent le tour.
  MetricSources forLap(RideLap lap) => MetricSources(
        hub: hub,
        recorder: recorder,
        riderProfile: riderProfile,
        trainingBudget: trainingBudget,
        drivetrain: drivetrain,
        nav: nav,
        routeClimbs: routeClimbs,
        climb: climb,
        upcomingClimb: upcomingClimb,
        climbProfile: climbProfile,
        routeProfile: routeProfile,
        wPrime: wPrime,
        lap: lap,
      );
}

/// Une mesure prête à peindre : son texte, et la zone qui la colore.
@immutable
class MetricReading {
  const MetricReading(this.value, {this.zoneKey, this.background, this.numericValue});

  /// `null` = pas de mesure. Le rendu écrit alors `—`, jamais `0`.
  final String? value;

  /// `z1`…`z7`, ou `null` pour laisser la case sur le fond du tableau de bord.
  /// Une couleur inventée serait pire qu'une couleur absente.
  final String? zoneKey;

  /// Couleur de fond directe, pour les mesures qui ne se rangent pas en zones
  /// d'entraînement — la pente, dont la couleur vient de sa tranche de
  /// difficulté ([gradeColorOf]) et non des seuils du cycliste.
  /// Mutuellement exclusif avec [zoneKey] : aucune mesure n'a besoin des deux.
  final Color? background;

  /// La même valeur que [value], non mise en forme — pour les seules mesures
  /// de la jauge à plage libre ([MetricView._rangeGauge]), qui a besoin d'un
  /// nombre pour situer le chiffre entre les bornes du bloc, pas d'un texte
  /// portant une unité ou une décimale à la française.
  final double? numericValue;

  @override
  bool operator ==(Object other) =>
      other is MetricReading &&
      other.value == value &&
      other.zoneKey == zoneKey &&
      other.background == background &&
      other.numericValue == numericValue;

  @override
  int get hashCode => Object.hash(value, zoneKey, background, numericValue);
}
