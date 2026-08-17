import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../ble/samples.dart';
import '../ble/sensor_connection.dart';
import '../ble/sensor_hub.dart';
import '../ble/sensor_profile.dart';
import '../ui/power_calibration_dialog.dart';
import '../ui/sensor_icons.dart';
import 'device_linker.dart';
import 'known_device.dart';
import 'known_devices_store.dart';
import 'sensor_link_status.dart';
import 'sensor_status_strip.dart';

/// Appairage des capteurs : chercher, connecter, oublier.
///
/// Sous-page et non écran d'accueil : on n'appaire qu'une fois par capteur,
/// alors qu'on part rouler tous les jours. L'accueil ne garde que l'état des
/// capteurs connus (voir `SensorStatusStrip`), et c'est ici qu'on vient quand
/// une pastille reste orange.
///
/// C'est aussi l'outil de dépannage : voir qui répond, ce qu'on décode, et les
/// trames brutes pour finir de décoder les octets Di2 encore inconnus
/// (offset 3, offset 15).
class SensorsPage extends StatefulWidget {
  const SensorsPage({
    super.key,
    required this.devices,
    required this.hub,
    required this.linker,
  });

  final KnownDevicesStore devices;

  /// Le hub appartient à l'application, pas à cet écran : les capteurs restent
  /// connectés quand on revient à l'accueil et pendant toute la sortie.
  final SensorHub hub;

  /// Le rattachement, partagé lui aussi : le scan lancé ici nourrit le même
  /// guetteur de trames de publicité, donc un capteur connu vu pendant qu'on
  /// cherche autre chose se rattache sans qu'on ait à le taper.
  final DeviceLinker linker;

  @override
  State<SensorsPage> createState() => _SensorsPageState();
}

class _SensorsPageState extends State<SensorsPage> {
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
  DeviceLinker get _linker => widget.linker;

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
    _adapterSub = FlutterBluePlus.adapterState.listen((state) {
      if (mounted) setState(() => _adapterState = state);
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
    // Le scan n'est **pas** arrêté ici : il porte son propre délai, et le
    // couper d'autorité tuerait aussi le balayage de rattachement du linker,
    // qui n'appartient pas à cet écran. Le hub non plus n'est pas fermé — il
    // survit à cette page.
    super.dispose();
  }

  void _onDevicesChanged() {
    if (mounted) setState(() {});
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

  /// Connecte un appareil sur un geste explicite : ici, un échec se dit.
  Future<void> _connect(BluetoothDevice device, {String? label}) async {
    await FlutterBluePlus.stopScan();

    try {
      await _linker.connect(device, label: label);
      if (mounted) setState(() {});
    } catch (e) {
      _toast('Connexion échouée : $e');
    }
  }

  Future<void> _forget(KnownDevice known) async {
    await _linker.forget(known);
    if (mounted) setState(() {});
  }

  /// Un nom plus simple que ce que le capteur annonce lui-même — souvent une
  /// suite de lettres et de chiffres. Disponible connecté ou non : c'est un
  /// libellé qu'on choisit une fois pour toutes, pas un réglage de la
  /// connexion en cours.
  Future<void> _rename(KnownDevice known) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _RenameDialog(
        initialName: known.name,
        originalName: known.originalName,
      ),
    );
    if (name == null) return; // annulé
    await _devices.rename(known.remoteId, name);
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => _screen(context);

  Widget _screen(BuildContext context) {
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
        padding: EdgeInsets.fromLTRB(
          12,
          12,
          12,
          12 + MediaQuery.paddingOf(context).bottom,
        ),
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
          _sectionTitle('Mes capteurs'),
          if (known.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Aucun capteur appairé. Réveille-les puis lance un scan.',
                textAlign: TextAlign.center,
              ),
            ),
          for (final device in known) _knownTile(device),
          const SizedBox(height: 16),
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

  /// Un capteur mémorisé, connecté ou non.
  ///
  /// La ligne existe même quand l'appareil est éteint : c'est tout l'intérêt de
  /// s'en souvenir, on voit ce qui manque avant de partir.
  Widget _knownTile(KnownDevice known) {
    final connection = _hub.connectionFor(DeviceIdentifier(known.remoteId));

    Widget tile(SensorStatus? status) {
      // L'icône dit *ce qu'est* le capteur, la couleur dit s'il répond : deux
      // informations dans un seul point de l'écran, lisible en roulant.
      return ListTile(
        dense: true,
        // La même pastille qu'à l'accueil, barre comprise : l'écran où l'on
        // coupe la connexion auto doit montrer ce que ça donnera là où on la
        // relira.
        leading: SensorLinkDot(
          icon: iconForDevice(known.kinds),
          name: known.name,
          status: status,
          autoConnect: known.autoConnect,
          size: 24,
        ),
        title: Text(known.name.isEmpty ? '(sans nom)' : known.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SensorKindIcons(known.kinds),
            Text(sensorStatusLabel(status, autoConnect: known.autoConnect)),
          ],
        ),
        isThreeLine: true,
        trailing: PopupMenuButton<String>(
          // `onSelected` se déclenche pendant que la route du menu se referme
          // encore (son animation de sortie n'est pas finie) : y ouvrir une
          // autre route dans la foulée — notre boîte « Renommer » — plante
          // Flutter (`_dependents.isEmpty is not true`, bug connu du
          // framework, cf. flutter/flutter#127519 et consorts). Un cran de
          // délai suffit à laisser la première route disparaître avant d'en
          // pousser une seconde.
          onSelected: (action) => Future.delayed(Duration.zero, () {
            if (!mounted) return;
            switch (action) {
              case 'forget':
                _forget(known);
              case 'rename':
                _rename(known);
              case 'auto':
                _devices.setAutoConnect(known.remoteId, !known.autoConnect);
              case 'connect':
                _connect(
                  BluetoothDevice.fromId(known.remoteId),
                  label: known.name.isEmpty ? null : known.name,
                );
              case 'calibrate':
                showPowerCalibrationFor(context, connection);
            }
          }),
          itemBuilder: (context) => [
            if (connection == null)
              const PopupMenuItem(value: 'connect', child: Text('Connecter')),
            // Un capteur de puissance ne se calibre que connecté, et seulement
            // s'il expose le Control Point : proposer la commande à un boîtier
            // qui ne sait pas répondre ferait passer un refus de protocole pour
            // un capteur en panne.
            if (connection?.canCalibratePower.value == true &&
                status == SensorStatus.connected)
              const PopupMenuItem(
                  value: 'calibrate', child: Text('Calibrer la puissance')),
            const PopupMenuItem(value: 'rename', child: Text('Renommer')),
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
          leading: Icon(iconForDevice(kinds), color: sensorLinkColor(status)),
          title: Text(connection.name.isEmpty ? '(sans nom)' : connection.name),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (kinds.isNotEmpty) SensorKindIcons(kinds),
              Text(sensorStatusLabel(status)),
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
        '${_frameTime(frame.at)}  ${frame.hex}',
        style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
      ),
    );
  }

  // Précision à la milliseconde : le seul moyen de voir, à l'œil, si un
  // appui maintenu répète des trames ou n'en envoie qu'une — la question qui
  // tranche si un « appui long » est détectable côté Di2 (voir
  // `ble/decoders/di2_buttons.dart`).
  String _frameTime(DateTime at) =>
      '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}:'
      '${at.second.toString().padLeft(2, '0')}.'
      '${at.millisecond.toString().padLeft(3, '0')}';
}

/// La boîte de dialogue « Renommer », à part pour une seule raison : le
/// `TextEditingController` doit se fermer sur le cycle de vie **du widget qui
/// l'utilise**, pas sur celui de l'appelant. `await showDialog(...)` rend la
/// main dès que la boîte se referme (`Navigator.pop`), mais elle reste montée
/// et visible pendant son animation de sortie — un `dispose()` appelé juste
/// après cet `await` désarme donc le contrôleur pendant que le `TextField`
/// s'en sert encore le temps de l'animation (« A TextEditingController was
/// used after being disposed »). Un `State.dispose()` propre, lui, n'arrive
/// que lorsque le widget est réellement retiré de l'arbre.
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initialName, required this.originalName});

  final String initialName;

  /// Ce que le capteur annonçait à sa toute première connexion — voir
  /// `KnownDevice.originalName`. Sert seulement à l'indication sous le champ ;
  /// c'est `KnownDevicesStore.rename` qui restaure réellement ce nom-là si le
  /// champ est vidé.
  final String originalName;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _controller = TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Rien à dire si le nom courant est déjà l'original : vider le champ ne
    // « restaurerait » alors rien de différent.
    final helperText = widget.originalName.isNotEmpty &&
            widget.originalName != widget.initialName
        ? 'Laisser vide pour revenir à « ${widget.originalName} »'
        : null;

    return AlertDialog(
      title: const Text('Renommer'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          hintText: 'Nom du capteur',
          helperText: helperText,
          helperMaxLines: 2,
        ),
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}
