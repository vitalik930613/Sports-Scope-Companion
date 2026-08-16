import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../ble/sensor_hub.dart';
import '../navigation/screen_dimmer.dart';

/// Outil de rétro-ingénierie temporaire : s'abonne à **toutes** les
/// caractéristiques notifiantes d'un appareil déjà connecté, connues ou non
/// des profils de l'appli, et affiche chaque trame brute au fur et à mesure.
///
/// Sert aujourd'hui à identifier la caractéristique D-Fly des boutons
/// satellites/sprinter du Di2 (protocole non documenté par Shimano) — voir le
/// TODO dans `ble/decoders/di2.dart`. `SensorConnection` ne s'abonne, lui,
/// qu'aux caractéristiques déjà répertoriées dans `sensorProfiles` : c'est
/// pour ça que la caractéristique cherchée ne paraît jamais dans le panneau
/// « Trames brutes » de `SensorsPage`, réservé à ce qui est déjà décodé.
///
/// À retirer une fois la caractéristique identifiée et le vrai décodeur
/// écrit : ce n'est pas une fonctionnalité de l'appli, c'est un banc d'essai.
class GattSniffPage extends StatefulWidget {
  const GattSniffPage({super.key, required this.hub});

  final SensorHub hub;

  @override
  State<GattSniffPage> createState() => _GattSniffPageState();
}

class _GattSniffPageState extends State<GattSniffPage> {
  BluetoothDevice? _target;
  String? _status;
  final _entries = <_Frame>[];
  final _subs = <StreamSubscription<List<int>>>[];

  /// En pause, les trames arrivent toujours (l'abonnement GATT ne bouge pas —
  /// le couper perdrait des pressions pendant l'analyse) mais ne s'affichent
  /// plus : c'est le figeage de la liste qui manquait, pas l'arrêt du capteur.
  bool _paused = false;

  /// UUID des caractéristiques désignées comme du bruit — le cardio, la
  /// cadence, tout ce qui parle en continu sans rapport avec ce qu'on cherche.
  /// Toute la caractéristique, pas une trame précise : un compteur qui
  /// s'incrémente à chaque trame (le cas du Di2) ne répéterait jamais le même
  /// contenu, un filtre par contenu ne l'aurait donc jamais tu. Le tap sert
  /// autant à nettoyer l'écran qu'à ne garder, dans le terminal `flutter run`,
  /// que ce qu'on peut coller tel quel.
  final _muted = <String>{};

  /// Ce qu'on est en train de faire, tapé à la main juste avant de le faire
  /// (« double clic channel1 ») puis juste après (« double clic channel1
  /// fait ») : deux repères qui encadrent le geste dans le journal, pour
  /// retrouver après coup *quelles* trames lui appartiennent sans avoir à
  /// deviner sur l'horodatage seul.
  final _markerController = TextEditingController();

  final _screen = ScreenDimmer();

  @override
  void initState() {
    super.initState();
    // Un essai de geste se joue sur plusieurs dizaines de secondes — bien
    // au-delà du délai de veille du téléphone — et un écran qui s'éteint en
    // plein test coupe l'abonnement aux notifications GATT en même temps que
    // la capture qu'on est venu faire.
    unawaited(_screen.setKeepScreenOn(true));
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      unawaited(sub.cancel());
    }
    unawaited(_screen.setKeepScreenOn(false));
    _markerController.dispose();
    super.dispose();
  }

  Future<void> _sniff(BluetoothDevice device) async {
    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();
    setState(() {
      _target = device;
      _entries.clear();
      _status = 'Découverte des services…';
    });

    final services = await device.discoverServices();
    var listened = 0;
    for (final service in services) {
      for (final characteristic in service.characteristics) {
        if (!characteristic.properties.notify &&
            !characteristic.properties.indicate) {
          continue;
        }
        listened++;
        _subs.add(characteristic.onValueReceived.listen((data) {
          final frame = _format(characteristic, data);
          // Une caractéristique tue par un tap précédent n'est ni affichée ni
          // journalisée : une fois identifiée comme du bruit, elle n'a plus
          // rien à apprendre à personne.
          if (_muted.contains(frame.uuid)) return;
          // Sur l'écran pour l'usage normal, dans les logs pour que ça reste
          // consultable après coup (via `adb logcat`) sans avoir à photographier
          // le téléphone.
          debugPrint('[sniff] $frame');
          if (!mounted || _paused) return;
          setState(() => _entries.insert(0, frame));
        }));
        // Best-effort : une caractéristique qui refuse l'abonnement (droits,
        // firmware capricieux) ne doit pas empêcher les autres de parler.
        try {
          await characteristic.setNotifyValue(true);
        } catch (e) {
          debugPrint('[sniff] ${characteristic.uuid}: abonnement refusé ($e)');
        }
      }
    }
    if (!mounted) return;
    setState(() => _status =
        '${services.length} service(s), $listened caractéristique(s) écoutée(s) '
        '— presse les boutons maintenant');
  }

  static _Frame _format(BluetoothCharacteristic c, List<int> data) =>
      _Frame(time: _timeNow(), uuid: c.uuid.str, bytes: data);

  static String _timeNow() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}.'
        '${now.millisecond.toString().padLeft(3, '0')}';
  }

  /// Insère le texte tapé comme repère, à l'instant présent — même liste que
  /// les trames, pour rester dans le même ordre chronologique une fois
  /// exporté.
  void _addMarker() {
    final text = _markerController.text.trim();
    if (text.isEmpty) return;
    final marker = _Frame.marker(time: _timeNow(), note: text);
    debugPrint('[sniff] $marker');
    setState(() => _entries.insert(0, marker));
    _markerController.clear();
  }

  /// Le journal entier (trames et repères), dans l'ordre chronologique —
  /// [_entries] est le plus récent en tête, l'export le remet à l'endroit —
  /// partagé comme le `.fit` d'une sortie (`RidesPage._export`) : un fichier
  /// jetable dans le dossier temporaire, puis la main au partage d'Android.
  Future<void> _export() async {
    if (_entries.isEmpty) return;
    final lines = [for (final frame in _entries.reversed) frame.toString()];
    final directory = await getTemporaryDirectory();
    final file = File(p.join(directory.path, 'sniff_di2.txt'));
    await file.writeAsString(lines.join('\n'), flush: true);

    if (!mounted) return;
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'text/plain')],
      fileNameOverrides: ['sniff_di2.txt'],
      subject: 'Sniff GATT Di2',
    ));
  }

  /// La trame précédente **du même canal** (même caractéristique) : c'est
  /// elle qui sert de référence pour la mise en évidence, un compteur qui
  /// tourne sur le cardio n'ayant rien à dire de ce qui bouge sur le Di2. La
  /// liste est la plus récente en tête, donc « précédente » se cherche après
  /// l'index courant. `null` sur la toute première trame d'une
  /// caractéristique : rien à comparer, donc rien à surligner.
  _Frame? _previousOf(int index) {
    final uuid = _entries[index].uuid;
    for (var j = index + 1; j < _entries.length; j++) {
      if (_entries[j].uuid == uuid) return _entries[j];
    }
    return null;
  }

  /// Tait toute la caractéristique de cette trame : plus jamais affichée ni
  /// journalisée tant que le filtre n'est pas réinitialisé, et les occurrences
  /// déjà à l'écran disparaissent avec elle — c'est ce qui rend le tap
  /// immédiatement lisible.
  void _mute(_Frame frame) {
    setState(() {
      _muted.add(frame.uuid);
      _entries.removeWhere((e) => e.uuid == frame.uuid);
    });
  }

  @override
  Widget build(BuildContext context) {
    final target = _target;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sniff GATT (dev)'),
        actions: [
          if (target != null) ...[
            IconButton(
              onPressed: () => setState(() => _paused = !_paused),
              icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
              tooltip: _paused ? 'Reprendre' : 'Mettre en pause',
            ),
            IconButton(
              onPressed: () => setState(() => _entries.clear()),
              icon: const Icon(Icons.clear_all),
              tooltip: 'Vider',
            ),
            if (_muted.isNotEmpty)
              IconButton(
                onPressed: () => setState(_muted.clear),
                icon: const Icon(Icons.filter_alt_off),
                tooltip: 'Réafficher les ${_muted.length} caractéristique(s) tues',
              ),
            IconButton(
              onPressed: _entries.isEmpty ? null : () => unawaited(_export()),
              icon: const Icon(Icons.ios_share),
              tooltip: 'Exporter le journal',
            ),
          ],
        ],
      ),
      body: target == null ? _deviceList() : _log(),
    );
  }

  Widget _deviceList() {
    final connections = widget.hub.connections;
    if (connections.isEmpty) {
      return const Center(child: Text('Aucun capteur connecté.'));
    }
    return ListView(
      children: [
        for (final connection in connections)
          ListTile(
            leading: const Icon(Icons.bluetooth_connected),
            title: Text(connection.name),
            subtitle: Text(connection.status.value.name),
            onTap: () => unawaited(_sniff(connection.device)),
          ),
      ],
    );
  }

  Widget _log() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_status ?? '', style: Theme.of(context).textTheme.bodySmall),
              if (_muted.isNotEmpty)
                Text(
                  '${_muted.length} caractéristique(s) tue(s) — '
                  'tap sur une ligne pour taire la sienne',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _markerController,
                  decoration: const InputDecoration(
                    hintText: 'Repère — ex. « double clic channel1 »',
                    isDense: true,
                  ),
                  onSubmitted: (_) => _addMarker(),
                ),
              ),
              IconButton(
                onPressed: _addMarker,
                icon: const Icon(Icons.add_circle_outline),
                tooltip: 'Ajouter le repère',
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: _entries.isEmpty
              ? const Center(child: Text('En attente d\'une trame…'))
              : ListView.builder(
                  itemCount: _entries.length,
                  itemBuilder: (_, i) {
                    final frame = _entries[i];
                    if (frame.note case final note?) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 3),
                        child: Text(
                          '${frame.time}  ** $note',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.secondary,
                          ),
                        ),
                      );
                    }
                    final previous = _previousOf(i);
                    return InkWell(
                      onTap: () => _mute(frame),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 3),
                        child: Text.rich(
                          TextSpan(
                            style: const TextStyle(
                                fontFamily: 'monospace', fontSize: 12),
                            children: [
                              TextSpan(text: '${frame.time}  ${frame.uuid}  '),
                              ..._hexSpans(context, frame.bytes, previous?.bytes),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// Les octets en hexa, un `TextSpan` chacun : ceux qui diffèrent de
  /// [previous] à la même position ressortent en gras et dans la couleur
  /// d'accent du thème — c'est ce qui permet de voir d'un coup d'œil, pendant
  /// un appui maintenu sur le Di2, quel octet bouge (le compteur du canal) et
  /// lesquels restent immobiles. Un octet au-delà de la longueur de
  /// [previous] compte comme changé : une trame plus longue que la précédente
  /// n'a rien à comparer sur sa queue.
  List<TextSpan> _hexSpans(
    BuildContext context,
    List<int> bytes,
    List<int>? previous,
  ) {
    final changedStyle = TextStyle(
      color: Theme.of(context).colorScheme.primary,
      fontWeight: FontWeight.bold,
    );
    return [
      for (var i = 0; i < bytes.length; i++) ...[
        if (i > 0) const TextSpan(text: '-'),
        TextSpan(
          text: bytes[i].toRadixString(16).padLeft(2, '0').toUpperCase(),
          style:
              previous != null && (i >= previous.length || bytes[i] != previous[i])
                  ? changedStyle
                  : null,
        ),
      ],
    ];
  }
}

/// Une trame reçue, horodatée — ou un repère tapé à la main ([marker]),
/// distingué par [note] non nul plutôt que par une sous-classe : les deux
/// vivent dans la même liste chronologique et le même export, seul le rendu
/// diffère.
class _Frame {
  const _Frame({required this.time, required this.uuid, required this.bytes})
      : note = null;

  const _Frame.marker({required this.time, required this.note})
      : uuid = '',
        bytes = const [];

  final String time;
  final String uuid;
  final List<int> bytes;
  final String? note;

  String get hex => bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join('-');

  @override
  String toString() => note != null ? '$time  ** $note' : '$time  $uuid  $hex';
}
