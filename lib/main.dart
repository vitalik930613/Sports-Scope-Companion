import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'ble/samples.dart';
import 'ble/sensor_connection.dart';
import 'ble/sensor_hub.dart';
import 'ble/sensor_profile.dart';
import 'devices/known_device.dart';
import 'devices/known_devices_store.dart';
import 'drivetrain.dart';
import 'navigation/navigation_page.dart';
import 'navigation/navigation_target.dart';
import 'ui/sensor_icons.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Le catalogue est lu avant le premier écran : la liste des capteurs connus
  // doit être là dès l'affichage, sinon elle apparaîtrait après coup.
  final devices = await KnownDevicesStore.open();
  runApp(SportsScopeApp(devices: devices));
}

class SportsScopeApp extends StatefulWidget {
  const SportsScopeApp({super.key, required this.devices});

  final KnownDevicesStore devices;

  @override
  State<SportsScopeApp> createState() => _SportsScopeAppState();
}

class _SportsScopeAppState extends State<SportsScopeApp> {
  /// Le hub vit au-dessus des écrans : les capteurs restent connectés quand on
  /// passe de la page de diagnostic à la navigation, et un lien entrant peut
  /// ouvrir la navigation sans repasser par la page des capteurs.
  final _hub = SensorHub();
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSub;

  @override
  void initState() {
    super.initState();
    _listenForLinks();
  }

  /// « Ouvrir dans l'appli » depuis le site, ou un lien d'itinéraire partagé.
  Future<void> _listenForLinks() async {
    _linkSub = _appLinks.uriLinkStream.listen(_openLink);
    // L'appli lancée *par* le lien : le flux n'en garde pas trace, il faut le
    // réclamer explicitement.
    final initial = await _appLinks.getInitialLink();
    if (initial != null) await _openLink(initial);
  }

  Future<void> _openLink(Uri uri) async {
    final target = NavigationTarget.parse(uri);
    if (target == null) {
      debugPrint('[links] lien ignoré : $uri');
      return;
    }
    await openNavigation(_navigatorKey.currentContext, target, _hub);
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    _hub.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sports Scope',
      navigatorKey: _navigatorKey,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: SensorsPage(devices: widget.devices, hub: _hub),
    );
  }
}

/// Ouvre la navigation, après avoir obtenu la position.
///
/// La permission est demandée ici et pas dans la page : le WebView ne sait pas
/// la réclamer lui-même, il se contente de relayer une autorisation que
/// l'application doit déjà détenir. Sans elle, la carte s'afficherait sans
/// jamais suivre le cycliste — une panne silencieuse.
Future<void> openNavigation(
  BuildContext? context,
  NavigationTarget target,
  SensorHub hub,
) async {
  if (context == null || !context.mounted) return;

  final status = await Permission.location.request();
  if (!context.mounted) return;

  if (!status.isGranted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Sans autorisation de position, la navigation ne peut pas '
          'te suivre.'),
    ));
    return;
  }

  await Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => NavigationPage(target: target, hub: hub),
  ));
}

/// Écran de diagnostic des capteurs : scanner, connecter, afficher en direct.
///
/// Ce n'est pas l'écran de sortie — la navigation, elle, est dans
/// [NavigationPage]. Celui-ci reste l'outil de dépannage : voir qui répond, ce
/// qu'on décode, et les trames brutes pour finir de décoder les octets Di2
/// encore inconnus (offset 3, offset 15).
class SensorsPage extends StatefulWidget {
  const SensorsPage({super.key, required this.devices, required this.hub});

  final KnownDevicesStore devices;

  /// Le hub appartient à l'application, pas à cet écran : les capteurs doivent
  /// rester connectés quand on passe en navigation.
  final SensorHub hub;

  @override
  State<SensorsPage> createState() => _SensorsPageState();
}

class _SensorsPageState extends State<SensorsPage> {
  final _drivetrain = Drivetrain.road;
  final _recentFrames = <RawFrame>[];

  List<ScanResult> _results = const [];
  bool _scanning = false;
  var _adapterState = BluetoothAdapterState.unknown;
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<bool>? _scanStateSub;
  StreamSubscription<BluetoothAdapterState>? _adapterSub;
  StreamSubscription<RawFrame>? _frameSub;

  KnownDevicesStore get _devices => widget.devices;
  SensorHub get _hub => widget.hub;

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

    // La reconnexion est déclenchée par l'état de l'adaptateur, pas par
    // `initState` : au lancement, `adapterStateNow` vaut encore `unknown` — il
    // n'est renseigné qu'une fois le flux écouté. Tester l'état ici ne
    // reconnectait donc jamais rien.
    //
    // Passer par le flux couvre aussi le Bluetooth allumé après coup, cas
    // banal : on ouvre l'appli, puis on active le Bluetooth.
    _adapterSub = FlutterBluePlus.adapterState.listen((state) {
      if (!mounted) return;
      setState(() => _adapterState = state);
      if (state == BluetoothAdapterState.on) _reconnectKnownDevices();
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
    _devices.removeListener(_onDevicesChanged);
    _scanSub?.cancel();
    _scanStateSub?.cancel();
    _adapterSub?.cancel();
    _frameSub?.cancel();
    // Le hub n'est pas fermé ici : il survit à cet écran.
    super.dispose();
  }

  void _onDevicesChanged() {
    if (mounted) setState(() {});
  }

  /// Reprend contact avec les capteurs connus, sans scan préalable.
  ///
  /// Un scan est inutile pour se rattacher à une adresse déjà connue. Les
  /// demandes partent toutes en même temps : elles rendent la main aussitôt,
  /// le système rattachant chaque capteur au fur et à mesure qu'il réapparaît.
  ///
  /// Idempotent : le hub renvoie la connexion existante si l'appareil est déjà
  /// suivi, ce qui permet de rappeler la méthode à chaque allumage du
  /// Bluetooth.
  Future<void> _reconnectKnownDevices() async {
    if (!await FlutterBluePlus.isSupported) return;

    for (final known in _devices.devices) {
      if (!known.autoConnect) continue;
      unawaited(_connect(
        BluetoothDevice.fromId(known.remoteId),
        label: known.name.isEmpty ? null : known.name,
        announce: false,
      ));
    }
  }

  Future<void> _startScan() async {
    if (!await FlutterBluePlus.isSupported) {
      _toast('Bluetooth non supporté sur cet appareil');
      return;
    }
    if (_adapterState != BluetoothAdapterState.on) {
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

  /// Choix de ce qu'on navigue.
  ///
  /// Le chemin normal reste le lien depuis le site (« Ouvrir dans l'appli »),
  /// qui arrive en lien entrant. Ce panneau est là pour les deux cas qu'un lien
  /// ne couvre pas : partir sans itinéraire, et ouvrir un lien reçu ailleurs.
  Future<void> _chooseNavigation() async {
    final controller = TextEditingController();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.explore),
              title: const Text('Navigation libre'),
              subtitle: const Text('Carte et position, sans itinéraire'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                openNavigation(context, const NavigationTarget.free(), _hub);
              },
            ),
            const Divider(),
            TextField(
              controller: controller,
              autocorrect: false,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Lien d\'un itinéraire partagé',
                hintText: 'https://sports.logicraft.ch/routes/…',
              ),
              onSubmitted: (value) => _openPastedLink(sheetContext, value),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => _openPastedLink(sheetContext, controller.text),
              icon: const Icon(Icons.navigation),
              label: const Text('Naviguer cet itinéraire'),
            ),
          ],
        ),
      ),
    );

    controller.dispose();
  }

  void _openPastedLink(BuildContext sheetContext, String value) {
    final uri = Uri.tryParse(value.trim());
    final target = uri == null ? null : NavigationTarget.parse(uri);
    if (target == null) {
      _toast('Ce lien ne mène pas à un itinéraire.');
      return;
    }
    Navigator.of(sheetContext).pop();
    openNavigation(context, target, _hub);
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _chooseNavigation,
        icon: const Icon(Icons.navigation),
        label: const Text('Naviguer'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // Bluetooth éteint, capteurs muets : autant le dire, sinon la page
          // ressemble à une panne de l'appli.
          if (_adapterState == BluetoothAdapterState.off)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
                leading: const Icon(Icons.bluetooth_disabled),
                title: const Text('Bluetooth éteint'),
                subtitle: const Text(
                    'Les capteurs se rattacheront seuls une fois activé.'),
                trailing: TextButton(
                  onPressed: () => FlutterBluePlus.turnOn(),
                  child: const Text('Activer'),
                ),
              ),
            ),
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
                _metric(_hub.latestHeartRate, 'bpm',
                    iconFor(SensorKind.heartRate)),
                _metric(_hub.latestPower, 'W', iconFor(SensorKind.power)),
                _metric(_hub.latestCadence, 'tr/min',
                    iconFor(SensorKind.speedCadence),
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
                final ratio = _drivetrain.ratio(gears);
                final dev = _drivetrain.development(gears);
                return Column(
                  children: [
                    Text('$gears',
                        style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 4),
                    Text(
                      front != null && rear != null && ratio != null && dev != null
                          // Le ratio se compare d'un vélo à l'autre, le
                          // développement dépend des pneus : les deux servent,
                          // et pas aux mêmes questions.
                          ? '$front × $rear dents · ratio ${ratio.toStringAsFixed(2)} · ${dev.toStringAsFixed(2)} m/tour'
                          : 'dents inconnues pour cette position',
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
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

    Widget tile(SensorStatus? status) {
      final connected = status == SensorStatus.connected;
      // L'icône dit *ce qu'est* le capteur, la couleur dit s'il répond : deux
      // informations dans un seul point de l'écran, lisible en roulant.
      final color = connected
          ? Colors.teal
          : (status == null ? Colors.grey : Colors.orange);

      return ListTile(
        dense: true,
        leading: Icon(iconForDevice(known.kinds), color: color),
        title: Text(known.name.isEmpty ? '(sans nom)' : known.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SensorKindIcons(known.kinds),
            Text(_statusLabel(status, known)),
          ],
        ),
        isThreeLine: true,
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
      builder: (context, status, _) => ValueListenableBuilder<Set<SensorKind>>(
        // Les capacités n'arrivent qu'à la découverte des services : l'icône
        // passe donc du bluetooth générique au capteur reconnu en cours de
        // connexion.
        valueListenable: connection.detectedKinds,
        builder: (context, kinds, _) => ListTile(
          dense: true,
          leading: Icon(
            iconForDevice(kinds),
            color:
                status == SensorStatus.connected ? Colors.teal : Colors.orange,
          ),
          title: Text(connection.name.isEmpty ? '(sans nom)' : connection.name),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (kinds.isNotEmpty) SensorKindIcons(kinds),
              Text(_statusLabel(status, null)),
            ],
          ),
          isThreeLine: kinds.isNotEmpty,
        ),
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
      leading: Icon(iconForDevice(kinds), color: Colors.grey),
      title: Text(name.isEmpty ? '(sans nom)' : name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${result.device.remoteId} · ${result.rssi} dBm'),
          if (kinds.isNotEmpty) SensorKindIcons(kinds),
        ],
      ),
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
