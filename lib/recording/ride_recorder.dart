import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../ble/samples.dart';
import '../ble/sensor_hub.dart';
import '../dashboard/ride_preset.dart';
import '../drivetrain.dart';
import '../phone/barometric_altitude.dart';
import '../phone/phone_sensors.dart';
import 'gps_fix.dart';
import 'gps_source.dart';
import 'ride_elevation_track.dart';
import 'ride_lap.dart';
import 'ride_session.dart';
import 'ride_stats.dart';
import 'ride_store.dart';
import 'track_point.dart';

enum RecorderState { idle, recording, paused }

/// Enregistre une sortie : GPS et capteurs réunis, une ligne par seconde.
///
/// Il vit au niveau de l'application, à côté du [SensorHub] et pour la même
/// raison : une sortie ne doit pas s'arrêter parce qu'on ouvre la navigation ou
/// qu'on revient à l'écran des capteurs. Personne d'autre ne tient l'état de
/// l'enregistrement.
///
/// Le cadencement est régulier (un tic par seconde) et non déclenché par le
/// GPS : à l'arrêt à un feu, ou sous un tunnel, la trace continue de porter le
/// cardio et la puissance. Un point sans position est une information, pas un
/// trou.
class RideRecorder extends ChangeNotifier {
  RideRecorder({
    required this.hub,
    required this.store,
    this.gps = const GeolocatorGpsSource(),
    this.phone,
    this.drivetrain = Drivetrain.road,
    Duration? tickPeriod,
  }) : tickPeriod = tickPeriod ?? const Duration(seconds: 1);

  final SensorHub hub;
  final RideStore store;
  final GpsSource gps;

  /// Les capteurs du téléphone, pour le seul baromètre. Nul sur un appareil qui
  /// n'en a pas — et l'enregistrement tourne alors exactement comme avant, sur
  /// l'altitude GPS.
  final PhoneSensors? phone;

  /// La transmission, pour sa seule circonférence de roue : c'est elle qui
  /// traduit les tours du capteur de vitesse en mètres par seconde. Même source
  /// que le pont vers la page de navigation, pour ne pas mesurer deux vitesses
  /// différentes sur le même vélo.
  final Drivetrain drivetrain;

  /// Réglable pour les tests seulement — en usage réel, une seconde.
  final Duration tickPeriod;

  /// Périodicité de réécriture du résumé de session. Assez rare pour ne pas
  /// écrire un fichier par seconde, assez fréquent pour qu'une batterie vide ne
  /// coûte qu'une demi-minute de compteurs (les points, eux, sont intacts).
  static const metaPeriod = Duration(seconds: 30);

  /// Au-delà, une mesure de capteur est considérée périmée : mieux vaut un trou
  /// dans la trace qu'un cardio figé pendant vingt minutes parce que la ceinture
  /// s'est décrochée. Les positions Di2, elles, n'expirent pas : un braquet reste
  /// engagé tant qu'on ne change pas de vitesse.
  static const sensorTtl = Duration(seconds: 10);

  /// Idem pour la position : un point GPS plus vieux que ça n'est plus la
  /// position du cycliste.
  static const fixTtl = Duration(seconds: 8);

  /// Précision au-delà de laquelle un déplacement ne compte pas dans la
  /// distance. Un point à ±100 m « saute » de dizaines de mètres à l'arrêt et
  /// gonflerait la sortie de kilomètres imaginaires.
  static const _maxAccuracyM = 25.0;

  /// Plancher de déplacement, contre la dérive du GPS à l'arrêt. En dessous, le
  /// point de référence n'est pas déplacé : une progression lente finit donc par
  /// être comptée, elle n'est pas perdue.
  static const _minStepM = 1.0;

  /// Plafond de vitesse plausible (144 km/h). Au-delà c'est un saut de
  /// récepteur, pas un cycliste : on se recale sans compter la distance.
  static const _maxStepMps = 40.0;

  RecorderState _state = RecorderState.idle;
  RideSession? _session;
  IOSink? _sink;
  Timer? _timer;
  StreamSubscription<GpsFix>? _gpsSub;
  StreamSubscription<SensorSample>? _samplesSub;
  StreamSubscription<double>? _pressureSub;
  bool _disposed = false;

  /// L'altimètre barométrique de la sortie en cours. Une instance par sortie :
  /// sa référence est calée sur le premier point GPS exploitable du jour.
  final _altimeter = BarometricAltimeter();
  DateTime? _pressureAt;

  double _distanceM = 0;
  int _pointCount = 0;
  int _recordedSeconds = 0;
  DateTime _lastMetaSave = DateTime.fromMillisecondsSinceEpoch(0);

  GpsFix? _lastFix;
  GpsFix? _referenceFix;

  int? _heartRate;
  DateTime? _heartRateAt;
  int? _power;
  DateTime? _powerAt;
  double? _cadence;
  DateTime? _cadenceAt;
  double? _wheelSpeedMps;
  DateTime? _wheelSpeedAt;
  int? _gearFront;
  int? _gearRear;

  RecorderState get state => _state;
  bool get isActive => _state != RecorderState.idle;
  RideSession? get session => _session;

  /// Distance parcourue depuis le départ, en mètres.
  double get distanceM => _distanceM;

  /// Temps effectivement enregistré, pauses exclues (une seconde par point).
  Duration get recorded => Duration(seconds: _recordedSeconds);

  int get pointCount => _pointCount;

  /// Agrégats de la sortie en cours (moyennes, maxima, dénivelé, puissance
  /// normalisée). Mis à jour à chaque point, avec le même code que celui qui
  /// résume la sortie à l'export : l'écran et le `.fit` ne peuvent pas diverger.
  final stats = RideStats();

  /// Le profil (distance, altitude) de la sortie en cours, pour le composant
  /// « Profil d'altitude » quand aucun tracé n'est chargé — voir
  /// `ride_elevation_track.dart`. Local au téléphone, jamais transmis.
  final elevationTrack = RideElevationTrack();

  /// Les séries de tours de la sortie en cours, par clé de série. Plusieurs
  /// séries tournent en parallèle sans se fermer l'une l'autre — voir
  /// [markLap]. Connues dès [start] (le paramètre `lapSeries`) : une série
  /// apparue seulement à son premier tour marqué perdrait tout ce qui la
  /// précède, qu'on veut pourtant pouvoir lire (« avant la première côte »).
  final Map<String, List<RideLap>> _series = {};

  /// Les tours de [series], du premier au tour courant (le dernier de la
  /// liste, toujours ouvert). Vide si la série n'a pas été déclarée au départ
  /// ou si rien n'est enregistré.
  List<RideLap> lapsOf(String series) =>
      List.unmodifiable(_series[series] ?? const []);

  /// Dernière position connue, même périmée — l'UI s'en sert pour dire si le
  /// GPS a accroché.
  GpsFix? get lastFix => _lastFix;

  /// Les capteurs que le profil de sortie retient. Fixés au démarrage et non
  /// relus ensuite : couper le GPS en pleine sortie couperait la trace en deux.
  SensorSettings _sensors = const SensorSettings();

  /// La sortie en cours enregistre-t-elle une position ?
  ///
  /// Ce que ça change à l'écran : distance et dénivelé n'ont plus de source, et
  /// s'affichent **`—` plutôt que `0`** — un zéro se lirait comme « je n'ai pas
  /// bougé » alors que la question ne se pose pas sur un home-trainer.
  bool get gpsEnabled => _sensors.gps;

  /// Démarre une sortie.
  ///
  /// Lève [GpsUnavailable] si la position est demandée mais indisponible : sans
  /// trace, un enregistrement qui ne dirait rien serait pire qu'un refus franc.
  /// Les capteurs, eux, sont facultatifs — on peut enregistrer un parcours sans
  /// aucun capteur connecté.
  ///
  /// **Sans GPS ([SensorSettings.gps] à faux), rien de tout ça n'a lieu** : ni
  /// permission, ni service au premier plan, ni attente d'une première position.
  /// La sortie démarre sur-le-champ et écrit des points sans coordonnées, ce que
  /// le format admet déjà — un point sans position est une information, pas un
  /// trou. C'est le home-trainer : la trace ne dirait rien, le cardio et la
  /// puissance disent tout.
  Future<RideSession> start({
    SensorSettings sensors = const SensorSettings(),
    Set<String> lapSeries = const {},
  }) async {
    final existing = _session;
    if (existing != null) return existing;

    _sensors = sensors;
    if (sensors.gps) await gps.ensureReady();

    final session = await store.create();
    _session = session;
    _sink = await store.openPoints(session.id);

    _distanceM = 0;
    _pointCount = 0;
    _recordedSeconds = 0;
    stats.reset();
    elevationTrack.reset();
    _lastFix = null;
    _referenceFix = null;
    _lastMetaSave = DateTime.now();

    // Un tour 0 par série dès le départ, jamais au premier tour marqué : sinon
    // ce premier tour perdrait tout ce qui le précède.
    final now = DateTime.now();
    _series
      ..clear()
      ..addEntries(lapSeries.map(
        (key) => MapEntry(key, [RideLap(index: 0, startedAt: now, startDistanceM: 0)]),
      ));

    _altimeter.reset();
    _pressureAt = null;

    _samplesSub = hub.samples.listen(handleSample, onError: (Object e) {
      debugPrint('[recorder] capteur en erreur : $e');
    });
    // Le baromètre ne tourne que pendant l'enregistrement : hors sortie il n'y a
    // pas de dénivelé à mesurer, et un capteur branché réveille le processeur.
    // Sans GPS, il ne tourne pas du tout : sa référence se cale sur le premier
    // point GPS exploitable, et sans elle il ne rend que des pressions.
    _pressureSub = sensors.barometer && sensors.gps
        ? phone?.pressureHpa().listen(handlePressure, onError: (Object e) {
            debugPrint('[recorder] baromètre en erreur : $e');
          })
        : null;
    _gpsSub = sensors.gps
        ? gps.watch().listen(handleFix, onError: (Object e) {
            // Un récepteur qui tombe ne doit pas arrêter la sortie : le cardio
            // et la puissance continuent d'être enregistrés, et la position
            // reprendra.
            debugPrint('[recorder] position en erreur : $e');
          })
        : null;

    _state = RecorderState.recording;
    _timer = Timer.periodic(tickPeriod, (_) => tick());
    _notify();
    return session;
  }

  /// Suspend l'écriture sans fermer la sortie.
  ///
  /// Le GPS reste abonné : reprendre est instantané, la notification de service
  /// reste affichée, et surtout le récepteur garde son accroche — la
  /// redemander coûterait une minute de dérive au redémarrage.
  void pause() {
    if (_state != RecorderState.recording) return;
    _state = RecorderState.paused;
    _notify();
  }

  void resume() {
    if (_state != RecorderState.paused) return;
    _state = RecorderState.recording;
    _notify();
  }

  /// Clôt le tour courant de [series] et en ouvre un nouveau. Le tour clos ne
  /// reçoit plus aucun point ; ses stats sont figées telles quelles.
  ///
  /// Sans effet — jamais une exception — si [series] n'a pas été déclarée à
  /// [start] (profil différent de celui attendu) ou si rien n'est enregistré :
  /// un tap égaré ne doit jamais faire tomber la sortie.
  void markLap(String series) {
    final laps = _series[series];
    if (!isActive || laps == null) return;
    laps.add(RideLap(
      index: laps.length,
      startedAt: DateTime.now(),
      startDistanceM: _distanceM,
    ));
    _notify();
  }

  /// Étiquette le tour courant de [series] avec l'identifiant d'un col — voir
  /// [RideLap.climbId]. Toujours le **dernier** tour de la série : un profil
  /// de col arrive juste après le tour que le front montant du col vient
  /// d'ouvrir (`RideShellPage._onPageMessage`), jamais avant, donc jamais sur
  /// un tour déjà clos.
  ///
  /// Sans effet — jamais une exception — si [series] n'a pas été déclarée ou
  /// si rien n'est enregistré, même garde que [markLap].
  void tagClimb(String series, int climbId) {
    final laps = _series[series];
    if (!isActive || laps == null || laps.isEmpty) return;
    laps.last.climbId = climbId;
    _notify();
  }

  /// Termine la sortie et renvoie son résumé, prêt à être exporté.
  Future<RideSession?> stop() async {
    final session = _session;
    if (session == null) return null;

    _timer?.cancel();
    _timer = null;
    await _gpsSub?.cancel();
    await _samplesSub?.cancel();
    await _pressureSub?.cancel();
    _gpsSub = null;
    _samplesSub = null;
    _pressureSub = null;

    final sink = _sink;
    _sink = null;
    if (sink != null) {
      try {
        await sink.flush();
        await sink.close();
      } catch (e) {
        debugPrint('[recorder] fermeture du fichier de points : $e');
      }
    }

    final finished = session.copyWith(
      endedAt: DateTime.now().toUtc(),
      pointCount: _pointCount,
      distanceM: _distanceM,
      movingSeconds: _recordedSeconds,
    );
    await store.save(finished);

    _session = null;
    _state = RecorderState.idle;
    _resetSensors();
    _notify();
    return finished;
  }

  /// Une position vient d'arriver.
  ///
  /// C'est ici, et pas au tic, que la distance s'accumule : le GPS livre ses
  /// points à son rythme, et compter au tic reviendrait à ignorer ce qui s'est
  /// passé entre deux secondes.
  @visibleForTesting
  void handleFix(GpsFix fix) {
    _lastFix = fix;

    // Cale l'altitude barométrique absolue sur le premier point assez précis.
    // Sans effet passé le premier calage réussi : recaler en route fabriquerait
    // du dénivelé (cf. BarometricAltimeter.calibrateWith).
    final altitude = fix.altitudeM;
    if (altitude != null) {
      _altimeter.calibrateWith(
          gpsAltitudeM: altitude, accuracyM: fix.accuracyM);
    }

    // En pause, on suit la position sans la compter : reprendre après dix
    // minutes de café ne doit pas ajouter la ligne droite jusqu'au bar.
    if (_state != RecorderState.recording) {
      _referenceFix = fix;
      return;
    }

    final reference = _referenceFix;
    if (reference == null) {
      _referenceFix = fix;
      return;
    }

    final accuracy = fix.accuracyM;
    if (accuracy != null && accuracy > _maxAccuracyM) return;

    final seconds = fix.at.difference(reference.at).inMilliseconds / 1000;
    if (seconds <= 0) return;

    final step = reference.distanceTo(fix);
    if (step / seconds > _maxStepMps) {
      _referenceFix = fix;
      return;
    }
    if (step < _minStepM) return;

    _distanceM += step;
    _referenceFix = fix;
  }

  /// Écrit le point de la seconde écoulée.
  @visibleForTesting
  void tick() {
    if (_state != RecorderState.recording) return;
    final sink = _sink;
    if (sink == null) return;

    final now = DateTime.now();
    final point = capture(now);
    // Avant l'écriture : un disque plein ne doit pas effacer le point de
    // l'affichage, où il vient tout juste d'être mesuré.
    stats.add(point);
    // Même préférence de source que RideStats._addAltitude : une fois le
    // baromètre vu, il ne rend jamais la main au GPS, même sur un point où il
    // manque — deux sources décalées de plusieurs mètres feraient une marche.
    final altitude = stats.hasBaroAltitude ? point.baroAltitudeM : point.altitudeM;
    if (altitude != null) elevationTrack.add(point.distanceM, altitude);
    for (final laps in _series.values) {
      final lap = laps.last;
      lap.stats.add(point);
      lap.pointCount++;
    }

    try {
      sink.writeln(jsonEncode(point.toJson()));
      _pointCount++;
      _recordedSeconds++;
      // Une seconde d'écriture bufferisée ne vaut pas un appel système par
      // point : on force le vidage toutes les cinq secondes, ce qui borne la
      // perte à cinq points en cas de coupure brutale.
      if (_pointCount % 5 == 0) unawaited(sink.flush());
    } catch (e) {
      debugPrint('[recorder] point non écrit : $e');
    }

    final session = _session;
    if (session != null && now.difference(_lastMetaSave) >= metaPeriod) {
      _lastMetaSave = now;
      unawaited(store.save(session.copyWith(
        pointCount: _pointCount,
        distanceM: _distanceM,
        movingSeconds: _recordedSeconds,
      )));
    }

    _notify();
  }

  /// L'état instantané, tel qu'il sera écrit. Séparé de [tick] pour être
  /// vérifiable sans fichier ni horloge.
  @visibleForTesting
  TrackPoint capture(DateTime now) {
    final fix = _fresh(_lastFix, _lastFix?.at, now, fixTtl);
    // Le baromètre périme comme les autres capteurs : une altitude figée ne se
    // verrait pas, elle se lirait comme un plateau parfaitement plat.
    final pressure = _fresh(_altimeter.pressureHpa, _pressureAt, now, sensorTtl);

    return TrackPoint(
      at: now,
      distanceM: _distanceM,
      lat: fix?.lat,
      lng: fix?.lng,
      altitudeM: fix?.altitudeM,
      baroAltitudeM: pressure == null ? null : _altimeter.altitudeM,
      pressureHpa: pressure,
      accuracyM: fix?.accuracyM,
      speedMps: fix?.speedMps,
      heartRate: _fresh(_heartRate, _heartRateAt, now, sensorTtl),
      power: _fresh(_power, _powerAt, now, sensorTtl),
      cadence: _fresh(_cadence, _cadenceAt, now, sensorTtl),
      wheelSpeedMps: _fresh(_wheelSpeedMps, _wheelSpeedAt, now, sensorTtl),
      gearFront: _gearFront,
      gearRear: _gearRear,
      laps: {
        for (final entry in _series.entries)
          if (entry.value.length > 1) entry.key: entry.value.length - 1,
      },
    );
  }

  /// Une pression vient d'arriver. Le lissage et la conversion en mètres sont
  /// dans [BarometricAltimeter] — ici on ne fait que dater la mesure.
  @visibleForTesting
  void handlePressure(double hpa) {
    _altimeter.addPressure(hpa);
    _pressureAt = DateTime.now();
  }

  /// Une mesure de capteur vient d'arriver. Retenue avec sa date : c'est elle
  /// qui dira, au tic suivant, si la valeur est encore d'actualité.
  @visibleForTesting
  void handleSample(SensorSample sample) {
    switch (sample) {
      case HeartRateSample(:final bpm):
        _heartRate = bpm;
        _heartRateAt = sample.at;
      case PowerSample(:final watts):
        _power = watts;
        _powerAt = sample.at;
      case CadenceSample(:final rpm):
        _cadence = rpm;
        _cadenceAt = sample.at;
      case WheelSpeedSample(:final revolutionsPerSecond):
        _wheelSpeedMps = revolutionsPerSecond * drivetrain.wheelCircumference;
        _wheelSpeedAt = sample.at;
      case GearSample(:final gears):
        _gearFront = gears.frontPosition;
        _gearRear = gears.rearPosition;
      case RadarSample():
        // Le radar dit ce qui arrive derrière, pas ce que fait le cycliste :
        // rien à enregistrer dans la trace.
        break;
      case RemoteButtonSample():
        // Un geste sur le tableau de bord, pas une mesure de la sortie.
        break;
      case BatterySample():
        // L'état d'un capteur, pas une mesure de la sortie — voir
        // `BatteryStatusNotifier`.
        break;
    }
  }

  static T? _fresh<T>(T? value, DateTime? at, DateTime now, Duration ttl) {
    if (value == null || at == null) return null;
    return now.difference(at) <= ttl ? value : null;
  }

  void _resetSensors() {
    _heartRate = null;
    _heartRateAt = null;
    _power = null;
    _powerAt = null;
    _cadence = null;
    _cadenceAt = null;
    _wheelSpeedMps = null;
    _wheelSpeedAt = null;
    _gearFront = null;
    _gearRear = null;
    _lastFix = null;
    _referenceFix = null;
    _altimeter.reset();
    _pressureAt = null;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    unawaited(_gpsSub?.cancel());
    unawaited(_samplesSub?.cancel());
    unawaited(_pressureSub?.cancel());
    // Le fichier est fermé au mieux : l'appli se termine, les points déjà
    // écrits sont sur le disque et la sortie apparaîtra comme interrompue.
    unawaited(_sink?.close());
    super.dispose();
  }
}
