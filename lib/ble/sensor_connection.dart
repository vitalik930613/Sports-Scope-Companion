import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'characteristic_decoder.dart';
import 'power_calibration.dart';
import 'samples.dart';
import 'sensor_profile.dart';
import 'sensor_uuids.dart';

enum SensorStatus { disconnected, connecting, connected, reconnecting, failed }

/// Connexion à un capteur, avec reconnexion automatique.
///
/// Une sortie dure des heures : un capteur *va* décrocher — batterie faible,
/// passage hors de portée, interférence en peloton. La reconnexion n'est donc
/// pas une option ajoutée après coup, c'est le comportement normal, et une
/// coupure ne doit jamais interrompre l'enregistrement des autres capteurs.
///
/// Chaque trame reçue est publiée deux fois : décodée sur [samples], et brute
/// sur [rawFrames]. L'appelant persiste les deux.
///
/// Ce qu'on lit sur l'appareil n'est pas dicté par l'appelant : les capacités
/// sont *découvertes* à la connexion (voir [detectedKinds]) et confrontées au
/// registre des profils. Un capteur de puissance qui publie aussi la cadence
/// est donc exploité en entier sans que personne ait eu à le déclarer.
class SensorConnection {
  SensorConnection({
    required this.device,
    this.label,
  });

  final BluetoothDevice device;
  final String? label;

  final _samples = StreamController<SensorSample>.broadcast();
  final _rawFrames = StreamController<RawFrame>.broadcast();
  final status = ValueNotifier<SensorStatus>(SensorStatus.disconnected);

  /// Capacités reconnues sur l'appareil, remplies après la découverte des
  /// services. Vide tant qu'on n'a pas été connecté au moins une fois.
  final detectedKinds = ValueNotifier<Set<SensorKind>>(const {});

  /// Vrai quand l'appareil expose le Control Point de puissance : ce capteur-là
  /// sait se calibrer depuis l'appli. Un `ValueNotifier` parce que la réponse
  /// n'arrive qu'à la découverte des services, longtemps après le tap qui a
  /// lancé la connexion.
  final canCalibratePower = ValueNotifier<bool>(false);

  /// Décodeurs effectivement branchés, reconstruits à chaque (re)connexion.
  var _decoders = <CharacteristicDecoder>[];

  /// Les caractéristiques de la connexion en cours, par UUID. Vidées à chaque
  /// coupure : les handles GATT d'une connexion morte ne valent plus rien, et
  /// écrire dessus lève au lieu de rendre une erreur exploitable.
  final _characteristics = <Guid, BluetoothCharacteristic>{};

  Stream<SensorSample> get samples => _samples.stream;
  Stream<RawFrame> get rawFrames => _rawFrames.stream;

  String get name => label ?? device.platformName;

  final _subscriptions = <StreamSubscription<dynamic>>[];
  StreamSubscription<BluetoothConnectionState>? _connectionSub;
  Timer? _retryTimer;
  int _attempt = 0;
  bool _disposed = false;
  bool _everConnected = false;

  static const _maxBackoff = Duration(seconds: 30);

  /// Ouvre la connexion et la maintient.
  ///
  /// Retourne dès que la demande est passée au système, *pas* quand le capteur
  /// répond : un capteur endormi peut mettre des minutes, et rien ne doit
  /// attendre après lui.
  Future<void> start() async {
    // C'est l'état de connexion qui pilote tout, jamais le retour de
    // `connect()` : en mode auto-connexion le système rattache l'appareil dans
    // notre dos, et une reconnexion doit rebrancher les notifications même si
    // personne ne l'a demandée.
    _connectionSub ??= device.connectionState.listen(_onConnectionState);
    await _connect();
  }

  Future<void> _onConnectionState(BluetoothConnectionState state) async {
    if (_disposed) return;

    if (state == BluetoothConnectionState.connected) {
      try {
        await _subscribeAll();
        if (_disposed) return;
        _everConnected = true;
        _attempt = 0;
        status.value = SensorStatus.connected;
        debugPrint('[ble] $name: connecté '
            '(${detectedKinds.value.map((k) => k.name).join(', ')})');
      } catch (e) {
        // Découverte impossible (appareil parti en cours de route) : le système
        // finira par signaler la déconnexion, qui relancera le cycle.
        debugPrint('[ble] $name: découverte échouée ($e)');
      }
      return;
    }

    await _cancelCharacteristicSubs();
    _resetDecoders();
    // Les caractéristiques meurent avec la connexion ; la *capacité* à se
    // calibrer, elle, est une propriété de l'appareil et reste vraie — sans
    // quoi la commande disparaîtrait de l'écran à chaque passage sous un pont.
    _characteristics.clear();
    if (_disposed) return;
    status.value =
        _everConnected ? SensorStatus.reconnecting : SensorStatus.connecting;
    // Sans cette ligne, un capteur qui n'arrive jamais et un capteur qui
    // décroche en boucle donnent le même écran : une pastille orange.
    debugPrint('[ble] $name: ${status.value.name} ($state)');
  }

  Future<void> _connect() async {
    if (_disposed) return;
    status.value =
        _everConnected ? SensorStatus.reconnecting : SensorStatus.connecting;

    try {
      // `autoConnect` délègue la reconnexion à la pile Bluetooth du téléphone :
      // elle rattache le capteur dès qu'il réapparaît, sans que l'appli scanne
      // en boucle. C'est ce qui permet de lancer l'appli à la maison et de voir
      // les capteurs arriver seuls une fois sur le vélo.
      //
      // Corollaire : l'appel rend la main immédiatement et ne lève pas si le
      // capteur est absent — il n'y a donc pas d'« échec de connexion » à
      // traiter ici, seulement des échecs d'appel système.
      //
      // `mtu: null` est imposé par flutter_blue_plus, incompatible avec
      // `autoConnect`. Sans conséquence : les trames des capteurs tiennent
      // largement dans la MTU par défaut.
      await device.connect(autoConnect: true, mtu: null);
    } catch (e) {
      debugPrint('[ble] $name: demande de connexion refusée ($e)');
      status.value = SensorStatus.failed;
      _scheduleRetry();
    }
  }

  Future<void> _subscribeAll() async {
    await _cancelCharacteristicSubs();

    final services = await device.discoverServices();
    // Les handles GATT peuvent changer d'une connexion à l'autre, pas les
    // UUID : on ne résout que par UUID.
    final characteristics = {
      for (final service in services)
        for (final c in service.characteristics) c.uuid: c,
    };
    _characteristics
      ..clear()
      ..addAll(characteristics);
    canCalibratePower.value =
        characteristics.containsKey(BleCharacteristics.cyclingPowerControlPoint);

    // Le tri se fait sur ce qui est réellement exposé, pas sur ce qui a été
    // annoncé au scan : le Di2 ne publie pas son service propriétaire, et une
    // découverte reste la seule source fiable.
    final kinds = kindsFromCharacteristics(characteristics.keys);
    detectedKinds.value = kinds;
    // Décodeurs neufs à chaque abonnement : ils portent des compteurs cumulés
    // qu'une coupure a pu laisser à cheval.
    _decoders = decodersFor(kinds);

    if (_decoders.isEmpty) {
      debugPrint('[ble] $name: aucun profil connu sur cet appareil');
    }

    for (final decoder in _decoders) {
      final characteristic = characteristics[decoder.characteristic];
      if (characteristic == null) {
        debugPrint('[ble] $name: ${decoder.characteristic} absente');
        continue;
      }

      if (characteristic.properties.notify ||
          characteristic.properties.indicate) {
        _subscriptions.add(
          characteristic.onValueReceived.listen(
            (data) => _handle(decoder, data),
          ),
        );
        await characteristic.setNotifyValue(true);
      }

      if (decoder.readOnConnect && characteristic.properties.read) {
        try {
          _handle(decoder, await characteristic.read());
        } catch (e) {
          // Un READ refusé n'est pas bloquant : la première notification
          // fournira l'état, simplement plus tard.
          debugPrint('[ble] $name: read initial refusé ($e)');
        }
      }
    }
  }

  void _handle(CharacteristicDecoder decoder, List<int> data) {
    if (data.isEmpty || _disposed) return;
    final at = DateTime.now();

    _rawFrames.add(RawFrame(at, decoder.characteristic.str, data));

    for (final sample in decoder.decode(data, at)) {
      _samples.add(sample);
    }
  }

  /// Calibre le capteur de puissance : compensation d'offset, « mise à zéro ».
  ///
  /// Trois temps imposés par le profil, dans cet ordre : s'abonner aux
  /// indications du Control Point, écrire l'octet, attendre la réponse.
  /// L'abonnement d'abord, sinon la plupart des capteurs refusent l'écriture —
  /// ils n'ont personne à qui répondre.
  ///
  /// Ne lève jamais : tout ce qui peut mal tourner ressort en
  /// [PowerCalibrationResult], parce que l'appelant est une boîte de dialogue
  /// ouverte au bord de la route, pas un `catch`.
  ///
  /// Le délai est long à dessein — une jauge met plusieurs secondes à se
  /// stabiliser, et abandonner trop tôt afficherait un échec sur une
  /// calibration qui a réussi.
  Future<PowerCalibrationResult> calibratePower({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (status.value != SensorStatus.connected) {
      return const PowerCalibrationFailed(PowerCalibrationError.notConnected);
    }

    final control = _characteristics[BleCharacteristics.cyclingPowerControlPoint];
    if (control == null) {
      return const PowerCalibrationFailed(PowerCalibrationError.notSupported);
    }

    final answer = Completer<PowerCalibrationResult>();
    StreamSubscription<List<int>>? sub;
    try {
      sub = control.onValueReceived.listen((data) {
        // Publiée comme n'importe quelle trame : la réponse d'un capteur qui
        // refuse est exactement ce qu'on veut relire dans « Trames brutes ».
        _rawFrames.add(RawFrame(DateTime.now(), control.uuid.str, data));
        final result = calibrationResponseOf(data);
        if (result != null && !answer.isCompleted) answer.complete(result);
      });
      await control.setNotifyValue(true);
      await control.write([startOffsetCompensation]);

      return await answer.future.timeout(
        timeout,
        onTimeout: () =>
            const PowerCalibrationFailed(PowerCalibrationError.noAnswer),
      );
    } catch (e) {
      debugPrint('[ble] $name: calibration refusée ($e)');
      return PowerCalibrationFailed(PowerCalibrationError.refused,
          detail: '$e');
    } finally {
      await sub?.cancel();
      // Les indications sont coupées derrière : le Control Point n'a plus rien
      // à dire jusqu'à la prochaine demande, et un abonnement oublié survivrait
      // à toutes les sorties suivantes.
      try {
        await control.setNotifyValue(false);
      } catch (_) {
        // Capteur déjà reparti : sans conséquence, la connexion emporte tout.
      }
    }
  }

  void _scheduleRetry() {
    if (_disposed) return;
    _retryTimer?.cancel();

    // Ne concerne plus l'absence du capteur — le système s'en charge — mais le
    // refus de l'appel lui-même : Bluetooth coupé au mauvais moment, pile déjà
    // occupée. Backoff exponentiel plafonné, pour ne pas insister à vide.
    final delay = Duration(
      milliseconds: (500 * (1 << _attempt.clamp(0, 6))).clamp(500, _maxBackoff.inMilliseconds),
    );
    _attempt++;
    _retryTimer = Timer(delay, _connect);
  }

  void _resetDecoders() {
    for (final decoder in _decoders) {
      decoder.reset();
    }
  }

  Future<void> _cancelCharacteristicSubs() async {
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
  }

  Future<void> dispose() async {
    _disposed = true;
    _retryTimer?.cancel();
    await _cancelCharacteristicSubs();
    await _connectionSub?.cancel();
    try {
      await device.disconnect();
    } catch (_) {
      // Déjà déconnecté : sans intérêt.
    }
    await _samples.close();
    await _rawFrames.close();
    status.dispose();
    detectedKinds.dispose();
    canCalibratePower.dispose();
  }
}
