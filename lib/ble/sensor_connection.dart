import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'characteristic_decoder.dart';
import 'samples.dart';

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
class SensorConnection {
  SensorConnection({
    required this.device,
    required this.decoders,
    this.label,
  });

  final BluetoothDevice device;
  final List<CharacteristicDecoder> decoders;
  final String? label;

  final _samples = StreamController<SensorSample>.broadcast();
  final _rawFrames = StreamController<RawFrame>.broadcast();
  final status = ValueNotifier<SensorStatus>(SensorStatus.disconnected);

  Stream<SensorSample> get samples => _samples.stream;
  Stream<RawFrame> get rawFrames => _rawFrames.stream;

  String get name => label ?? device.platformName;

  final _subscriptions = <StreamSubscription<dynamic>>[];
  StreamSubscription<BluetoothConnectionState>? _connectionSub;
  Timer? _retryTimer;
  int _attempt = 0;
  bool _disposed = false;

  static const _maxBackoff = Duration(seconds: 30);

  Future<void> start() async {
    _connectionSub ??= device.connectionState.listen((state) {
      if (_disposed) return;
      if (state == BluetoothConnectionState.disconnected &&
          status.value == SensorStatus.connected) {
        status.value = SensorStatus.reconnecting;
        _resetDecoders();
        _scheduleRetry();
      }
    });
    await _connect();
  }

  Future<void> _connect() async {
    if (_disposed) return;
    status.value = _attempt == 0 ? SensorStatus.connecting : SensorStatus.reconnecting;

    try {
      await device.connect(timeout: const Duration(seconds: 15));
      await _subscribeAll();
      _attempt = 0;
      status.value = SensorStatus.connected;
    } catch (e) {
      debugPrint('[ble] $name: échec de connexion ($e)');
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

    for (final decoder in decoders) {
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

    // Backoff exponentiel plafonné : un capteur éteint en fin de sortie ne doit
    // pas vider la batterie du téléphone en scannant en boucle.
    final delay = Duration(
      milliseconds: (500 * (1 << _attempt.clamp(0, 6))).clamp(500, _maxBackoff.inMilliseconds),
    );
    _attempt++;
    _retryTimer = Timer(delay, _connect);
  }

  void _resetDecoders() {
    for (final decoder in decoders) {
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
  }
}
