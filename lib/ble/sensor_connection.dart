import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'characteristic_decoder.dart';
import 'samples.dart';
import 'sensor_profile.dart';

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

  /// Décodeurs effectivement branchés, reconstruits à chaque (re)connexion.
  var _decoders = <CharacteristicDecoder>[];

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
      } catch (e) {
        // Découverte impossible (appareil parti en cours de route) : le système
        // finira par signaler la déconnexion, qui relancera le cycle.
        debugPrint('[ble] $name: découverte échouée ($e)');
      }
      return;
    }

    await _cancelCharacteristicSubs();
    _resetDecoders();
    if (_disposed) return;
    status.value =
        _everConnected ? SensorStatus.reconnecting : SensorStatus.connecting;
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
  }
}
