import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../ble/sensor_profile.dart';
import 'known_device.dart';

/// Les appareils appairés, persistés dans un JSON du dossier applicatif.
///
/// Pas de Drift ici volontairement : la liste tient en quelques lignes, elle
/// est lue une fois au démarrage et écrite à chaque connexion. Drift reste pour
/// les sessions, où le volume et les requêtes le justifient.
///
/// La liste vit en mémoire ([devices]) et sert de source de vérité à l'UI ; le
/// disque n'est qu'une copie de sauvegarde réécrite en entier à chaque
/// changement.
class KnownDevicesStore extends ChangeNotifier {
  KnownDevicesStore(this._file);

  /// Ouvre le magasin standard de l'appli. À n'appeler qu'après
  /// `WidgetsFlutterBinding.ensureInitialized()`.
  static Future<KnownDevicesStore> open() async {
    final directory = await getApplicationSupportDirectory();
    final store = KnownDevicesStore(File(p.join(directory.path, _fileName)));
    await store.load();
    return store;
  }

  static const _fileName = 'known_devices.json';

  final File _file;
  var _devices = <KnownDevice>[];

  /// Les appareils connus, du plus récemment connecté au plus ancien.
  List<KnownDevice> get devices => List.unmodifiable(_devices);

  KnownDevice? byId(String remoteId) {
    for (final device in _devices) {
      if (device.remoteId == remoteId) return device;
    }
    return null;
  }

  Future<void> load() async {
    _devices = await _read();
    notifyListeners();
  }

  Future<List<KnownDevice>> _read() async {
    try {
      if (!await _file.exists()) return [];
      final decoded = jsonDecode(await _file.readAsString());
      if (decoded is! List) return [];

      final devices = [
        for (final entry in decoded)
          if (KnownDevice.fromJson(entry) case final device?) device,
      ];
      _sort(devices);
      return devices;
    } catch (e) {
      // Fichier tronqué par une coupure de courant, JSON d'une version
      // incompatible : on repart d'une liste vide plutôt que de bloquer le
      // démarrage. Le fichier n'est pas supprimé — il sera écrasé à la
      // prochaine connexion, et reste inspectable d'ici là.
      debugPrint('[devices] catalogue illisible, ignoré : $e');
      return [];
    }
  }

  /// Enregistre un appareil, ou met à jour celui qu'on connaissait déjà.
  ///
  /// [kinds] n'écrase les capacités mémorisées que s'il apporte quelque chose :
  /// une connexion coupée avant la découverte des services ne doit pas effacer
  /// ce qu'on savait de l'appareil.
  Future<KnownDevice> remember(
    String remoteId, {
    required String name,
    Set<SensorKind> kinds = const {},
    DateTime? at,
  }) async {
    final existing = byId(remoteId);
    final device = (existing ??
            KnownDevice(remoteId: remoteId, name: name))
        .copyWith(
      // Un capteur renommé garde son nom précédent tant qu'il n'en annonce pas
      // un nouveau : `platformName` est vide quand l'appareil n'a pas répondu.
      name: name.isNotEmpty ? name : null,
      kinds: kinds.isNotEmpty ? kinds : null,
      lastConnectedAt: at ?? DateTime.now(),
    );

    _devices.removeWhere((d) => d.remoteId == remoteId);
    _devices.add(device);
    await _flush();
    return device;
  }

  Future<void> forget(String remoteId) async {
    final before = _devices.length;
    _devices.removeWhere((d) => d.remoteId == remoteId);
    if (_devices.length == before) return;
    await _flush();
  }

  Future<void> setAutoConnect(String remoteId, bool autoConnect) async {
    final index = _devices.indexWhere((d) => d.remoteId == remoteId);
    if (index < 0) return;
    _devices[index] = _devices[index].copyWith(autoConnect: autoConnect);
    await _flush();
  }

  /// Les écritures en attente, mises à la queue leu leu.
  ///
  /// Elles arrivent par rafales — plusieurs capteurs qui se connectent en même
  /// temps, chacun notifiant deux fois (état puis capacités). Menées en
  /// parallèle, elles se disputaient le **même fichier temporaire** : la
  /// première le renommait, la suivante ne le trouvait plus et perdait son
  /// écriture (`PathNotFoundException` sur le `rename`, vu en vrai au
  /// lancement). La file garantit un seul écrivain à la fois, et c'est la
  /// dernière image de la liste qui gagne.
  Future<void> _writing = Future<void>.value();

  Future<void> _flush() async {
    _sort(_devices);
    notifyListeners();
    // Copie : l'écriture est différée, et la liste peut bouger d'ici là.
    final snapshot = [..._devices];
    _writing = _writing.then((_) => _write(snapshot));
    await _writing;
  }

  Future<void> _write(List<KnownDevice> devices) async {
    try {
      await _file.parent.create(recursive: true);
      // Écriture en deux temps : une coupure pendant le `writeAsString` ne doit
      // pas laisser un JSON tronqué à la place d'un catalogue valide.
      final temporary = File('${_file.path}.tmp');
      await temporary.writeAsString(
        jsonEncode([for (final device in devices) device.toJson()]),
        flush: true,
      );
      await temporary.rename(_file.path);
    } catch (e) {
      // Perdre la persistance ne doit pas faire tomber une sortie en cours :
      // la liste en mémoire reste juste, seul le prochain démarrage l'oubliera.
      debugPrint('[devices] écriture impossible : $e');
    }
  }

  /// Plus récemment connecté en tête ; les jamais-connectés à la fin.
  static void _sort(List<KnownDevice> devices) {
    devices.sort((a, b) {
      final left = a.lastConnectedAt;
      final right = b.lastConnectedAt;
      if (left == null && right == null) return a.name.compareTo(b.name);
      if (left == null) return 1;
      if (right == null) return -1;
      return right.compareTo(left);
    });
  }
}
