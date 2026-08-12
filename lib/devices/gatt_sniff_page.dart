import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../ble/sensor_hub.dart';

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

  @override
  void dispose() {
    for (final sub in _subs) {
      unawaited(sub.cancel());
    }
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

  static _Frame _format(BluetoothCharacteristic c, List<int> data) {
    final now = DateTime.now();
    final time = '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}.'
        '${now.millisecond.toString().padLeft(3, '0')}';
    final hex = data
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join('-');
    return _Frame(time: time, uuid: c.uuid.str, hex: hex);
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
        Expanded(
          child: _entries.isEmpty
              ? const Center(child: Text('En attente d\'une trame…'))
              : ListView.builder(
                  itemCount: _entries.length,
                  itemBuilder: (_, i) {
                    final frame = _entries[i];
                    return InkWell(
                      onTap: () => _mute(frame),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 3),
                        child: Text(
                          '$frame',
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 12),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// Une trame reçue, horodatée.
class _Frame {
  const _Frame({required this.time, required this.uuid, required this.hex});

  final String time;
  final String uuid;
  final String hex;

  @override
  String toString() => '$time  $uuid  $hex';
}
