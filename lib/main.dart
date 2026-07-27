import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ble/samples.dart';
import 'ble/sensor_connection.dart';
import 'ble/sensor_hub.dart';
import 'ble/sensor_profile.dart';
import 'devices/known_device.dart';
import 'devices/known_devices_store.dart';
import 'drivetrain.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Le catalogue est lu avant le premier écran : la liste des capteurs connus
  // doit être là dès l'affichage, sinon elle apparaîtrait après coup.
  final devices = await KnownDevicesStore.open();
  runApp(SportsScopeApp(devices: devices));
}

class SportsScopeApp extends StatelessWidget {
  const SportsScopeApp({super.key, required this.devices});

  final KnownDevicesStore devices;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sports Scope',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: SensorSpikePage(devices: devices),
    );
  }
}

/// Écran de spike : scanner, connecter, afficher en direct.
///
/// Pas d'enregistrement ici — l'objectif est de valider que les quatre capteurs
/// parlent, et de voir défiler les trames brutes pour finir de décoder les
/// octets Di2 encore inconnus (offset 3, offset 15).
class SensorSpikePage extends StatefulWidget {
  const SensorSpikePage({super.key, required this.devices});

  final KnownDevicesStore devices;

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

  KnownDevicesStore get _devices => widget.devices;

  @override
  void initState() {
    super.initState();

    _devices.addListener(_onDevicesChanged);

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

    _reconnectKnownDevices();
  }

  @override
  void dispose() {
    _devices.removeListener(_onDevicesChanged);
    _scanSub?.cancel();
    _scanStateSub?.cancel();
    _frameSub?.cancel();
    _hub.dispose();
    super.dispose();
  }

  void _onDevicesChanged() {
    if (mounted) setState(() {});
  }

  /// Reprend contact avec les capteurs connus, sans scan préalable.
  ///
  /// Un scan n'est pas nécessaire pour se connecter à une adresse déjà connue,
  /// et il coûterait plusieurs secondes au démarrage. Les capteurs hors de
  /// portée échouent puis repassent par le backoff de [SensorConnection] : au
  /// moment d'enfourcher le vélo, ils se rattachent tout seuls.
  Future<void> _reconnectKnownDevices() async {
    if (!await FlutterBluePlus.isSupported) return;
    if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) return;

    for (final known in _devices.devices) {
      if (!known.autoConnect) continue;
      await _connect(
        BluetoothDevice.fromId(known.remoteId),
        label: known.name.isEmpty ? null : known.name,
        announce: false,
      );
    }
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

  /// Connecte un appareil et le retient dès qu'il a répondu.
  ///
  /// [announce] distingue le geste explicite (tap sur un résultat de scan, où
  /// un échec mérite un message) de la reconnexion silencieuse au démarrage.
  Future<void> _connect(
    BluetoothDevice device, {
    String? label,
    bool announce = true,
  }) async {
    if (announce) await FlutterBluePlus.stopScan();

    try {
      final connection = await _hub.add(device, label: label);
      _rememberOnConnect(connection);
      if (mounted) setState(() {});
    } catch (e) {
      if (announce) _toast('Connexion échouée : $e');
    }
  }

  /// Écrit l'appareil au catalogue à chaque fois qu'il passe à *connecté*.
  ///
  /// À la connexion, pas au tap : tant que l'appareil n'a pas répondu on ne
  /// connaît ni son nom ni ses capacités, et mémoriser une adresse qui ne
  /// répond jamais encombrerait la liste. Les reconnexions repassent par là,
  /// ce qui rafraîchit la date et suffit à trier la liste par usage.
  void _rememberOnConnect(SensorConnection connection) {
    void persist() {
      if (connection.status.value != SensorStatus.connected) return;
      _devices.remember(
        connection.device.remoteId.str,
        name: connection.name,
        kinds: connection.detectedKinds.value,
      );
    }

    connection.status.addListener(persist);
    // Les capacités arrivent à la découverte des services, parfois après le
    // passage à « connecté » : les deux notifications déclenchent l'écriture.
    connection.detectedKinds.addListener(persist);
    persist();
  }

  Future<void> _forget(KnownDevice known) async {
    await _hub.remove(DeviceIdentifier(known.remoteId));
    await _devices.forget(known.remoteId);
    if (mounted) setState(() {});
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final known = _devices.devices;
    // Un capteur déjà connu n'a rien à faire dans les résultats de scan : il
    // est déjà listé au-dessus, avec son état réel.
    final knownIds = {for (final device in known) device.remoteId};
    final discovered = [
      for (final result in _results)
        if (!knownIds.contains(result.device.remoteId.str)) result,
    ];

    // Un appareil qu'on vient de taper n'est pas encore au catalogue — il n'y
    // entre qu'une fois connecté. Sans cette section, la connexion en cours
    // n'aurait aucun retour visuel.
    final pending = [
      for (final connection in _hub.connections)
        if (!knownIds.contains(connection.device.remoteId.str)) connection,
    ];

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
          if (known.isNotEmpty) ...[
            _sectionTitle('Mes capteurs'),
            for (final device in known) _knownTile(device),
            const SizedBox(height: 16),
          ],
          if (pending.isNotEmpty) ...[
            _sectionTitle('Connexion en cours'),
            for (final connection in pending) _connectionTile(connection),
            const SizedBox(height: 16),
          ],
          _sectionTitle(_scanning ? 'Scan en cours…' : 'Appareils détectés'),
          if (discovered.isEmpty && !_scanning)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('Réveille tes capteurs puis lance un scan.',
                  textAlign: TextAlign.center),
            ),
          for (final result in discovered) _scanTile(result),
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

  /// Un capteur mémorisé, connecté ou non.
  ///
  /// La ligne existe même quand l'appareil est éteint : c'est tout l'intérêt de
  /// s'en souvenir, on voit ce qui manque avant de partir.
  Widget _knownTile(KnownDevice known) {
    final connection = _hub.connectionFor(DeviceIdentifier(known.remoteId));
    final capabilities = known.kinds.isEmpty
        ? 'capacités inconnues'
        : known.kinds.map(labelFor).join(' · ');

    Widget tile(SensorStatus? status) {
      final connected = status == SensorStatus.connected;
      return ListTile(
        dense: true,
        leading: Icon(
          connected
              ? Icons.bluetooth_connected
              : (status == null
                  ? Icons.bluetooth_disabled
                  : Icons.bluetooth_searching),
          color: connected
              ? Colors.teal
              : (status == null ? Colors.grey : Colors.orange),
        ),
        title: Text(known.name.isEmpty ? '(sans nom)' : known.name),
        subtitle: Text(
          '$capabilities · ${_statusLabel(status, known)}',
          maxLines: 2,
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (action) => switch (action) {
            'forget' => _forget(known),
            'auto' => _devices.setAutoConnect(known.remoteId, !known.autoConnect),
            'connect' => _connect(
                BluetoothDevice.fromId(known.remoteId),
                label: known.name.isEmpty ? null : known.name,
              ),
            _ => null,
          },
          itemBuilder: (context) => [
            if (connection == null)
              const PopupMenuItem(value: 'connect', child: Text('Connecter')),
            PopupMenuItem(
              value: 'auto',
              child: Text(known.autoConnect
                  ? 'Ne plus connecter automatiquement'
                  : 'Connecter automatiquement'),
            ),
            const PopupMenuItem(value: 'forget', child: Text('Oublier')),
          ],
        ),
      );
    }

    if (connection == null) return tile(null);
    return ValueListenableBuilder<SensorStatus>(
      valueListenable: connection.status,
      builder: (context, status, _) => tile(status),
    );
  }

  String _statusLabel(SensorStatus? status, KnownDevice? known) {
    // Pas de connexion ouverte : l'appareil est simplement absent, ou on a
    // décidé de ne plus le solliciter.
    if (status == null) {
      return known?.autoConnect == false
          ? 'connexion auto désactivée'
          : 'hors ligne';
    }
    return switch (status) {
      SensorStatus.connected => 'connecté',
      SensorStatus.connecting => 'connexion…',
      SensorStatus.reconnecting => 'reconnexion…',
      SensorStatus.disconnected => 'déconnecté',
      SensorStatus.failed => 'échec',
    };
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
        subtitle: Text(_statusLabel(status, null)),
      ),
    );
  }

  Widget _scanTile(ScanResult result) {
    final name = result.advertisementData.advName.isNotEmpty
        ? result.advertisementData.advName
        : result.device.platformName;
    // Ce que l'appareil annonce savoir faire — indicatif seulement, plusieurs
    // capteurs (dont le Di2) n'annoncent pas leur service propriétaire.
    final kinds = kindsFromServices(result.advertisementData.serviceUuids);

    return ListTile(
      dense: true,
      title: Text(name.isEmpty ? '(sans nom)' : name),
      subtitle: Text([
        '${result.device.remoteId} · ${result.rssi} dBm',
        if (kinds.isNotEmpty) kinds.map(labelFor).join(' · '),
      ].join('\n')),
      isThreeLine: kinds.isNotEmpty,
      trailing: const Icon(Icons.link),
      onTap: () => _connect(result.device, label: name),
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
