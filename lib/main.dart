import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ble/characteristic_decoder.dart';
import 'ble/samples.dart';
import 'ble/sensor_connection.dart';
import 'ble/sensor_hub.dart';
import 'drivetrain.dart';

void main() => runApp(const SportsScopeApp());

class SportsScopeApp extends StatelessWidget {
  const SportsScopeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sports Scope',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const SensorSpikePage(),
    );
  }
}

/// Écran de spike : scanner, connecter, afficher en direct.
///
/// Pas d'enregistrement ici — l'objectif est de valider que les quatre capteurs
/// parlent, et de voir défiler les trames brutes pour finir de décoder les
/// octets Di2 encore inconnus (offset 3, offset 15).
class SensorSpikePage extends StatefulWidget {
  const SensorSpikePage({super.key});

  @override
  State<SensorSpikePage> createState() => _SensorSpikePageState();
}

class _SensorSpikePageState extends State<SensorSpikePage> {
  final _hub = SensorHub();
  final _drivetrain = Drivetrain.road;
  final _recentFrames = <RawFrame>[];

  List<ScanResult> _results = const [];
  bool _scanning = false;
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<bool>? _scanStateSub;
  StreamSubscription<RawFrame>? _frameSub;

  @override
  void initState() {
    super.initState();

    _scanSub = FlutterBluePlus.onScanResults.listen((results) {
      if (mounted) setState(() => _results = results);
    });
    _scanStateSub = FlutterBluePlus.isScanning.listen((scanning) {
      if (mounted) setState(() => _scanning = scanning);
    });

    // Les dernières trames brutes restent à l'écran : c'est l'outil de reverse,
    // et ça montre immédiatement si un capteur n'émet que du silence.
    _frameSub = _hub.rawFrames.listen((frame) {
      if (!mounted) return;
      setState(() {
        _recentFrames.insert(0, frame);
        if (_recentFrames.length > 12) _recentFrames.removeLast();
      });
    });
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _scanStateSub?.cancel();
    _frameSub?.cancel();
    _hub.dispose();
    super.dispose();
  }

  Future<void> _startScan() async {
    if (!await FlutterBluePlus.isSupported) {
      _toast('Bluetooth non supporté sur cet appareil');
      return;
    }
    if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
      try {
        await FlutterBluePlus.turnOn();
      } catch (_) {
        _toast('Active le Bluetooth pour scanner');
        return;
      }
    }

    setState(() => _results = const []);
    // Scan large, sans filtre de service : le Di2 n'annonce pas forcément son
    // service propriétaire dans ses trames de publicité.
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
  }

  Future<void> _connect(BluetoothDevice device) async {
    await FlutterBluePlus.stopScan();
    try {
      await _hub.add(device, [
        HeartRateCharacteristic(),
        CyclingPowerCharacteristic(),
        CscCharacteristic(),
        Di2Characteristic(),
        VariaRadarCharacteristic(),
      ]);
      if (mounted) setState(() {});
    } catch (e) {
      _toast('Connexion échouée : $e');
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Capteurs'),
        actions: [
          IconButton(
            onPressed: _scanning ? FlutterBluePlus.stopScan : _startScan,
            icon: Icon(_scanning ? Icons.stop : Icons.search),
            tooltip: _scanning ? 'Arrêter' : 'Scanner',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _liveValues(),
          const SizedBox(height: 12),
          _radar(),
          const SizedBox(height: 16),
          if (_hub.connections.isNotEmpty) ...[
            _sectionTitle('Connectés'),
            for (final connection in _hub.connections)
              _connectionTile(connection),
            const SizedBox(height: 16),
          ],
          _sectionTitle(_scanning ? 'Scan en cours…' : 'Appareils détectés'),
          if (_results.isEmpty && !_scanning)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('Réveille tes capteurs puis lance un scan.',
                  textAlign: TextAlign.center),
            ),
          for (final result in _results) _scanTile(result),
          if (_recentFrames.isNotEmpty) ...[
            const SizedBox(height: 16),
            _sectionTitle('Trames brutes'),
            for (final frame in _recentFrames) _frameTile(frame),
          ],
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );

  Widget _liveValues() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _metric(_hub.latestHeartRate, 'bpm', Icons.favorite),
                _metric(_hub.latestPower, 'W', Icons.bolt),
                _metric(_hub.latestCadence, 'tr/min', Icons.autorenew,
                    format: (v) => (v as double).round().toString()),
              ],
            ),
            const Divider(height: 32),
            ValueListenableBuilder(
              valueListenable: _hub.latestGears,
              builder: (context, gears, _) {
                if (gears == null) {
                  return const Text('Vitesses : —');
                }
                final front = _drivetrain.chainringTeeth(gears);
                final rear = _drivetrain.sprocketTeeth(gears);
                final dev = _drivetrain.development(gears);
                return Column(
                  children: [
                    Text('$gears',
                        style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 4),
                    Text(
                      front != null && rear != null && dev != null
                          ? '$front × $rear dents · ${dev.toStringAsFixed(2)} m/tour'
                          : 'dents inconnues pour cette position',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Le radar mérite son propre bloc : la donnée est une liste, et l'affichage
  /// doit distinguer « route dégagée » de « pas de radar ».
  Widget _radar() {
    return ValueListenableBuilder<RadarSample?>(
      valueListenable: _hub.latestRadar,
      builder: (context, radar, _) {
        if (radar == null) {
          return const SizedBox.shrink();
        }

        final nearest = radar.nearest;
        final color = radar.isClear
            ? Colors.teal
            : (nearest!.distanceM < 40 ? Colors.red : Colors.orange);

        return Card(
          color: color.withValues(alpha: 0.12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(radar.isClear ? Icons.check_circle : Icons.warning,
                    color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: radar.isClear
                      ? const Text('Route dégagée')
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${radar.targets.length} véhicule(s)',
                                style:
                                    Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 4),
                            for (final t in radar.targets)
                              Text('$t',
                                  style: const TextStyle(
                                      fontFamily: 'monospace', fontSize: 12)),
                          ],
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _metric(
    ValueListenable<Object?> listenable,
    String unit,
    IconData icon, {
    String Function(Object)? format,
  }) {
    return ValueListenableBuilder<Object?>(
      valueListenable: listenable,
      builder: (context, value, _) => Column(
        children: [
          Icon(icon, size: 20),
          const SizedBox(height: 4),
          Text(
            value == null ? '—' : (format?.call(value) ?? value.toString()),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          Text(unit, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _connectionTile(SensorConnection connection) {
    return ValueListenableBuilder<SensorStatus>(
      valueListenable: connection.status,
      builder: (context, status, _) => ListTile(
        dense: true,
        leading: Icon(
          status == SensorStatus.connected
              ? Icons.bluetooth_connected
              : Icons.bluetooth_searching,
          color: status == SensorStatus.connected ? Colors.teal : Colors.orange,
        ),
        title: Text(connection.name.isEmpty ? '(sans nom)' : connection.name),
        subtitle: Text(status.name),
      ),
    );
  }

  Widget _scanTile(ScanResult result) {
    final name = result.advertisementData.advName.isNotEmpty
        ? result.advertisementData.advName
        : result.device.platformName;
    return ListTile(
      dense: true,
      title: Text(name.isEmpty ? '(sans nom)' : name),
      subtitle: Text('${result.device.remoteId} · ${result.rssi} dBm'),
      trailing: const Icon(Icons.link),
      onTap: () => _connect(result.device),
    );
  }

  Widget _frameTile(RawFrame frame) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(
        frame.hex,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
      ),
    );
  }
}
