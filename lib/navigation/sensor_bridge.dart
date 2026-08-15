import 'dart:async';
import 'dart:convert';

import '../ble/samples.dart';
import '../ble/sensor_connection.dart';
import '../ble/sensor_hub.dart';
import '../ble/sensor_profile.dart';
import '../dashboard/ride_preset.dart' show TraveledPathSettings;
import '../drivetrain.dart';
import '../phone/debug_log.dart';
import '../phone/rider_compass.dart';
import '../recording/gps_fix.dart';
import 'traveled_path_tracker.dart';

/// Pousse les mesures des capteurs BLE dans la page de navigation.
///
/// L'appli web sait déjà afficher un radar (elle le lit en Web Bluetooth), mais
/// pas le Di2 ni les capteurs que le navigateur ne peut pas ouvrir. Le pont
/// inverse la responsabilité : c'est Flutter qui tient le Bluetooth, et la page
/// n'a plus qu'à recevoir un état déjà décodé.
///
/// Contrat côté page : une fonction globale
/// `window.sportsScopeCompanion.push(payload)`. Si elle n'existe pas — page pas
/// encore chargée, version du site plus ancienne — l'envoi est simplement perdu,
/// jamais une erreur : la navigation doit marcher sans capteurs.
class SensorBridge {
  SensorBridge({
    required this.hub,
    required this.send,
    this.compass,
    this.drivetrain = Drivetrain.road,
    this.latestFix = _noFix,
    this.rideSessionId = _noSession,
    this.traveledPath = const TraveledPathSettings(),
  });

  static GpsFix? _noFix() => null;
  static Object? _noSession() => null;

  final SensorHub hub;

  /// La dernière position acceptée par l'enregistreur. Une fonction plutôt
  /// qu'un `RideRecorder` direct : le pont reste testable sans construire un
  /// enregistreur complet (GPS, disque), comme [send] reste testable sans
  /// WebView. Par défaut, aucune position — un test qui ne s'intéresse pas au
  /// trajet parcouru n'a rien à fournir.
  final GpsFix? Function() latestFix;

  /// Identifie la sortie en cours (`RideSession.id`), pour repérer qu'une
  /// nouvelle sortie a démarré sans reconstruire le pont et effacer l'ancien
  /// trajet plutôt que de l'allonger.
  final Object? Function() rideSessionId;

  /// Couleur, largeur, opacité de la ligne du trajet parcouru — vient du
  /// profil de sortie, transmise telle quelle à la page.
  final TraveledPathSettings traveledPath;

  final _pathTracker = TraveledPathTracker();
  Object? _lastSessionId;
  bool _forcePathReset = false;

  /// La boussole du téléphone. Elle n'a rien d'un capteur BLE, mais elle voyage
  /// par le même pont et pour la même raison : le navigateur ne sait pas la
  /// lire. Nulle sur un appareil sans magnétomètre.
  final RiderCompass? compass;

  /// La transmission sert à traduire une position Di2 en dents et en
  /// développement. Le Di2 ne publie que des positions, et la page web n'a
  /// aucun moyen de savoir ce qu'il y a sur le vélo : c'est ici qu'on le sait.
  final Drivetrain drivetrain;

  /// Exécute du JavaScript dans la page. Séparé du WebView pour que le pont
  /// reste testable sans moteur de rendu.
  final Future<void> Function(String javascript) send;

  /// Cadence d'envoi des mesures continues. Le cardio et la puissance changent
  /// en permanence ; les rafraîchir plus vite qu'une fois par seconde
  /// n'apporterait rien de lisible et réveillerait le moteur JS pour rien.
  static const _period = Duration(seconds: 1);

  /// Plancher entre deux envois immédiats, pour qu'une rafale de trames radar
  /// ne noie pas la page.
  static const _minGap = Duration(milliseconds: 200);

  StreamSubscription<SensorSample>? _samplesSub;
  Timer? _timer;
  DateTime _lastSend = DateTime.fromMillisecondsSinceEpoch(0);
  bool _dirty = false;
  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;

    _samplesSub = hub.samples.listen((sample) {
      _dirty = true;
      // Le radar et les changements de vitesse sont des événements, pas des
      // mesures continues : les retenir jusqu'au prochain tic ferait afficher
      // une voiture avec une seconde de retard.
      if (sample is RadarSample || sample is GearSample) _flush();
    });

    _timer = Timer.periodic(_period, (_) => _flush());
    // Un premier envoi immédiat : la page doit connaître l'état des capteurs
    // dès son chargement, sans attendre une trame.
    _dirty = true;
    _flush();
    // Le style ne voyage pas dans le tic périodique (il ne change pas d'un
    // tic à l'autre) : un appel à part, comme `setOccluded`.
    _sendTraveledPathConfig();
  }

  /// Envoi immédiat, sans attendre le tic ni le plancher.
  ///
  /// Utilisé pour des raisons qui n'ont rien à voir avec le trajet parcouru
  /// (un capteur vient de se connecter, un cap a été forcé) : il ne force
  /// donc **pas** un renvoi complet du trajet, seulement des mesures
  /// scalaires. Voir [notifyPageReloaded] pour le cas où c'est justement
  /// l'état de la page qu'il faut considérer perdu.
  void pushNow() {
    _dirty = true;
    _lastSend = DateTime.fromMillisecondsSinceEpoch(0);
    _flush();
  }

  /// La page vient d'être (re)chargée : son état JavaScript est reparti de
  /// zéro, y compris ce qu'elle savait du trajet parcouru et de son style.
  /// À appeler depuis `onPageFinished` et à la réception du message `ready`
  /// — jamais depuis un envoi forcé ordinaire, qui n'a aucune raison de
  /// réexpédier tout l'historique du trajet à chaque connexion de capteur.
  void notifyPageReloaded() {
    _forcePathReset = true;
    pushNow();
    _sendTraveledPathConfig();
  }

  void _flush() {
    if (!_dirty) return;
    final now = DateTime.now();
    if (now.difference(_lastSend) < _minGap) return;
    _lastSend = now;
    _dirty = false;

    // Une nouvelle sortie a démarré sans que le pont soit reconstruit :
    // l'ancien trajet ne concerne plus celle-ci.
    final sessionId = rideSessionId();
    if (sessionId != _lastSessionId) {
      _lastSessionId = sessionId;
      _pathTracker.reset();
      _forcePathReset = true;
    }
    _pathTracker.addFix(latestFix());
    final pathPayload = _pathTracker.drain(forceFull: _forcePathReset);
    _forcePathReset = false;

    final data = snapshot(traveledPathPayload: pathPayload);
    // TEMPORAIRE — diagnostic du verrouillage boussole, à retirer une fois
    // vérifié que le cap forcé atteint bien la page.
    DebugLog.instance.add('[bridge] envoi headingDeg=${data['headingDeg']} '
        'headingForced=${data['headingForced']}');
    final payload = jsonEncode(data);
    // `?.` : la page peut ne pas (encore) exposer le pont, ce n'est pas une
    // erreur. `void` évite que la valeur de retour remonte au moteur.
    send('void (window.sportsScopeCompanion?.push($payload));').catchError((e) {
      // Page en cours de rechargement, WebView détruit : sans intérêt, la
      // prochaine mesure repartira.
      DebugLog.instance.add('[bridge] envoi ignoré : $e');
    });
  }

  /// Envoi one-off de la couleur/largeur/opacité du trajet parcouru — même
  /// patron que `setOccluded` (`NavigationWebController`) : une valeur qui ne
  /// change pas d'un tic à l'autre n'a pas sa place dans `push()`.
  void _sendTraveledPathConfig() {
    final payload = jsonEncode({
      'color': traveledPath.color,
      'width': traveledPath.width,
      'opacity': traveledPath.opacity,
    });
    send('void (window.sportsScopeCompanion?.configureTraveledPath?.($payload));')
        .catchError((e) {
      DebugLog.instance.add('[bridge] envoi du style trajet ignoré : $e');
    });
  }

  /// L'état complet des capteurs, tel qu'envoyé à la page.
  ///
  /// Toujours complet, jamais un delta : la page peut être rechargée à tout
  /// moment (perte de réseau, retour arrière) et doit se retrouver à jour au
  /// premier message qui suit.
  ///
  /// Exception assumée : le trajet parcouru, qui grossirait sans borne sur
  /// une sortie de plusieurs heures si on le renvoyait en entier à chaque
  /// tic — voir `TraveledPathTracker`. Fourni par l'appelant plutôt que
  /// recalculé ici, pour que `snapshot()` reste un aperçu pur, appelable
  /// directement (comme le font les tests) sans faire avancer le suivi du
  /// trajet.
  Map<String, dynamic> snapshot({Map<String, dynamic>? traveledPathPayload}) {
    final radar = hub.latestRadar.value;
    final gears = hub.latestGears.value;
    // À l'arrêt, ou si le cycliste a forcé la boussole (pastille de la
    // carte, utile sous un couvert forestier) : la boussole. Sinon en
    // roulant, la page a sa propre course GPS, meilleure que n'importe
    // quelle boussole, et lui pousser un cap concurrent ne ferait que faire
    // vibrer la flèche entre deux sources.
    final heading = compass?.pushHeadingDeg;
    // La page a sa propre priorité GPS/déplacement (`updateBearing`, dépôt
    // Rails) qui ne cède à `headingDeg` qu'à sa propre estimation d'arrêt —
    // jamais nulle sous un couvert forestier, exactement le cas qu'on veut
    // couvrir. Ce drapeau lui dit explicitement de shunter ses propres
    // paliers : sans lui, un cap forcé mais publié en mouvement reste
    // silencieusement ignoré.
    final forced = compass?.forced ?? false;

    return {
      'at': DateTime.now().toIso8601String(),
      'source': 'sports-scope-companion',
      if (heading != null) 'headingDeg': heading,
      if (heading != null && forced) 'headingForced': true,
      'heartRate': hub.latestHeartRate.value,
      'power': hub.latestPower.value,
      'cadence': hub.latestCadence.value,
      if (gears != null)
        'gears': {
          'front': gears.frontPosition,
          'rear': gears.rearPosition,
          'frontCount': gears.frontCount,
          'rearCount': gears.rearCount,
          // Nuls si la transmission configurée ne couvre pas cette position :
          // la page affiche alors la position seule plutôt qu'un braquet faux.
          'frontTeeth': drivetrain.chainringTeeth(gears),
          'rearTeeth': drivetrain.sprocketTeeth(gears),
          'ratio': drivetrain.ratio(gears),
          'developmentM': drivetrain.development(gears),
        },
      // `connected` distingue « pas de radar » de « radar connecté, voie
      // dégagée » — l'appli web n'affiche son bandeau que dans le second cas.
      'radar': {
        'connected': _hasConnected(SensorKind.radar),
        'targets': [
          for (final target in radar?.targets ?? const [])
            {
              'id': target.id,
              'distanceM': target.distanceM,
              // Unité non établie côté Varia (cf. decoders/varia.dart) — on
              // envoie la valeur brute sous le nom attendu par la page, qui
              // ne s'en sert que pour trier et alerter.
              'speedMps': target.approachSpeedRaw,
            },
        ],
      },
      'sensors': [
        for (final connection in hub.connections)
          {
            'name': connection.name,
            'connected': connection.status.value == SensorStatus.connected,
            'kinds': [for (final kind in connection.detectedKinds.value) kind.name],
          },
      ],
      if (traveledPathPayload != null) 'traveledPath': traveledPathPayload,
    };
  }

  bool _hasConnected(SensorKind kind) => hub.connections.any((connection) =>
      connection.status.value == SensorStatus.connected &&
      connection.detectedKinds.value.contains(kind));

  Future<void> dispose() async {
    _timer?.cancel();
    await _samplesSub?.cancel();
    _started = false;
  }
}
