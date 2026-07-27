import '../ble/samples.dart';
import 'sun.dart';

/// Mode du feu arrière.
///
/// Décrit une *intention*, pas une commande : la traduction en octets dépend du
/// matériel et vit dans `light_controller.dart`.
enum RearLightMode {
  off,

  /// Clignotement diurne, haute intensité : le plus visible de jour.
  dayFlash,

  /// Feu fixe. Mode de nuit par défaut — voir [LightingConfig.flashAtNight].
  nightSteady,

  /// Clignotement nocturne. À n'utiliser qu'en connaissance de cause.
  nightFlash,

  /// Escalade : un véhicule approche par l'arrière, maximum de visibilité.
  alert,
}

/// Mode du phare avant.
///
/// Enum distincte du feu arrière, parce que le métier n'est pas le même : le
/// feu arrière sert à **être vu**, le phare sert à **voir** autant qu'à être vu.
/// Fusionner les deux obligerait à des modes qui n'ont de sens que d'un côté.
enum FrontLightMode {
  off,

  /// Feu de jour : être vu des véhicules d'en face, sans éclairer la route.
  dayRunning,

  /// Faisceau de nuit, position basse — le mode normal en circulation.
  nightLow,

  /// Plein phare. Reste **manuel** : sans capteur vers l'avant, on ne sait pas
  /// détecter un véhicule d'en face à qui il faudrait se rabaisser.
  nightHigh,
}

/// Décision complète, une entrée par lampe.
///
/// Un champ `null` signifie « pas d'avis » — position inconnue, par exemple —
/// et non « éteindre ». La nuance compte : on ne coupe pas un phare parce que
/// le GPS a décroché.
class LightingDecision {
  const LightingDecision({this.front, this.rear});

  final FrontLightMode? front;
  final RearLightMode? rear;

  bool get isEmpty => front == null && rear == null;

  @override
  String toString() => 'avant=${front?.name ?? '—'} arrière=${rear?.name ?? '—'}';
}

class LightingConfig {
  const LightingConfig({
    this.dayElevationDeg = 6.0,
    this.minimumDwell = const Duration(seconds: 90),
    this.alertDistanceM = 150,
    this.alertHold = const Duration(seconds: 12),
    this.flashAtNight = false,
    this.offInDaylight = false,
    this.frontDayRunning = true,
  });

  /// Hauteur du soleil au-dessus de laquelle on considère qu'il fait jour.
  ///
  /// 6° et non 0° : au ras de l'horizon la lumière est déjà rasante et le
  /// contraste mauvais. Basculer en mode nuit avant le coucher, pas après.
  final double dayElevationDeg;

  /// Durée minimale avant d'accepter un nouveau changement jour/nuit.
  ///
  /// Sans ça, une hauteur solaire qui oscille autour du seuil ferait battre les
  /// lampes au crépuscule. Ne s'applique **pas** à l'escalade radar, qui doit
  /// être immédiate.
  final Duration minimumDwell;

  /// Distance en deçà de laquelle un véhicule déclenche l'escalade arrière.
  final int alertDistanceM;

  /// Durée pendant laquelle l'escalade se maintient après la dernière
  /// détection. Évite de retomber en mode normal entre deux trames alors que
  /// la voiture est toujours là.
  final Duration alertHold;

  /// Autoriser le clignotement du feu arrière la nuit.
  ///
  /// Faux par défaut, et c'est un choix : dans plusieurs pays européens — dont
  /// la France — le feu arrière réglementaire doit être **fixe**, un clignotant
  /// ne pouvant être qu'un complément. Vérifie la règle applicable là où tu
  /// roules avant de passer ça à `true`. La même logique vaut pour l'avant, où
  /// aucun mode clignotant n'est proposé du tout.
  final bool flashAtNight;

  /// Éteindre le feu arrière en plein jour au lieu de clignoter.
  final bool offInDaylight;

  /// Garder le phare allumé en feu de jour. À couper si l'autonomie prime.
  final bool frontDayRunning;
}

/// Ce que la politique observe à un instant donné.
class LightingContext {
  const LightingContext({
    required this.at,
    this.latitude,
    this.longitude,
    this.radar,
    this.frontOverride,
    this.rearOverride,
  });

  /// Instant de la décision, **en UTC**.
  final DateTime at;

  /// Position courante. Sans elle, on ne sait pas s'il fait jour : la politique
  /// s'abstient plutôt que de deviner.
  final double? latitude;
  final double? longitude;

  final RadarSample? radar;

  /// Choix explicites du cycliste. Court-circuitent tout le reste —
  /// l'automatisme ne doit jamais reprendre la main sur une décision humaine.
  final FrontLightMode? frontOverride;
  final RearLightMode? rearOverride;
}

/// Décide de l'éclairage. Pur calcul, aucune dépendance matérielle.
///
/// Objet à état : l'hystérésis et le maintien d'escalade ont besoin de se
/// souvenir de la décision précédente. Une instance par sortie.
class AutoLightingPolicy {
  AutoLightingPolicy({this.config = const LightingConfig()});

  final LightingConfig config;

  final _front = _ModeLatch<FrontLightMode>();
  final _rear = _ModeLatch<RearLightMode>();
  DateTime? _lastThreatAt;

  FrontLightMode? get currentFront => _front.current;
  RearLightMode? get currentRear => _rear.current;

  LightingDecision decide(LightingContext ctx) {
    final daylight = _isDaylight(ctx);
    final threat = _threatActive(ctx);

    return LightingDecision(
      front: _decideFront(ctx, daylight),
      rear: _decideRear(ctx, daylight, threat),
    );
  }

  FrontLightMode? _decideFront(LightingContext ctx, bool? daylight) {
    if (ctx.frontOverride != null) {
      return _front.commit(ctx.frontOverride!, ctx.at,
          config.minimumDwell, force: true);
    }

    // Volontairement indifférent au radar : une voiture qui arrive par
    // l'arrière ne justifie pas de toucher au faisceau avant.
    if (daylight == null) return _front.current;

    final mode = daylight
        ? (config.frontDayRunning ? FrontLightMode.dayRunning : FrontLightMode.off)
        : FrontLightMode.nightLow;

    return _front.commit(mode, ctx.at, config.minimumDwell);
  }

  RearLightMode? _decideRear(
      LightingContext ctx, bool? daylight, bool threat) {
    if (ctx.rearOverride != null) {
      return _rear.commit(ctx.rearOverride!, ctx.at,
          config.minimumDwell, force: true);
    }

    if (threat) {
      // L'escalade ignore l'hystérésis : la sécurité ne se temporise pas.
      return _rear.commit(RearLightMode.alert, ctx.at, config.minimumDwell,
          force: true);
    }

    if (daylight == null) return _rear.current;

    final mode = daylight
        ? (config.offInDaylight ? RearLightMode.off : RearLightMode.dayFlash)
        : (config.flashAtNight
            ? RearLightMode.nightFlash
            : RearLightMode.nightSteady);

    // On quitte une escalade sans attendre : elle est censée être brève.
    final leavingAlert = _rear.current == RearLightMode.alert;
    return _rear.commit(mode, ctx.at, config.minimumDwell, force: leavingAlert);
  }

  /// `null` si la position est inconnue.
  bool? _isDaylight(LightingContext ctx) {
    final lat = ctx.latitude;
    final lon = ctx.longitude;
    if (lat == null || lon == null) return null;

    final elevation = Sun.elevationDeg(
      utc: ctx.at.toUtc(),
      latitude: lat,
      longitude: lon,
    );
    return elevation >= config.dayElevationDeg;
  }

  bool _threatActive(LightingContext ctx) {
    final radar = ctx.radar;
    if (radar != null && !radar.isClear) {
      final nearest = radar.nearest!;
      if (nearest.distanceM <= config.alertDistanceM) {
        _lastThreatAt = ctx.at;
        return true;
      }
    }

    final last = _lastThreatAt;
    if (last == null) return false;
    return ctx.at.difference(last) < config.alertHold;
  }
}

/// Retient un mode et refuse d'en changer trop vite.
class _ModeLatch<T> {
  T? _current;
  DateTime? _changedAt;

  T? get current => _current;

  T commit(T mode, DateTime at, Duration dwell, {bool force = false}) {
    if (_current == null) {
      _current = mode;
      _changedAt = at;
      return mode;
    }
    if (mode == _current) return _current as T;

    if (!force && at.difference(_changedAt!) < dwell) {
      return _current as T;
    }

    _current = mode;
    _changedAt = at;
    return mode;
  }
}
