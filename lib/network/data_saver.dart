import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Interrupteur global « économie de données » : coupe les requêtes non
/// essentielles (tuiles live, POI, météo, catalogues, contrôle de version…)
/// une fois la carte hors ligne téléchargée, typiquement en itinérance avec un
/// forfait limité. Le GPS, le Bluetooth et l'envoi de la sortie enregistrée ne
/// sont volontairement PAS concernés — ce n'est pas un mode avion, seulement un
/// filtre sur ce que l'appli irait chercher sur le réseau de son propre chef.
///
/// Statique plutôt qu'injecté partout : les clients réseau (`RainviewerClient`,
/// `RouteCatalogFetch`, `UpdateChecker`…) sont construits à la volée à de
/// nombreux endroits de l'appli, souvent en `const Xxx()`, et leur faire porter
/// une dépendance de plus pour un réglage qui ne varie qu'au fil d'un
/// interrupteur casserait cette constance pour peu de gain. Chaque site d'appel
/// se contente de lire [dataSaverEnabled] avant de partir sur le réseau.
class NetworkPolicy {
  NetworkPolicy._();

  static bool dataSaverEnabled = false;
}

/// Persiste [NetworkPolicy.dataSaverEnabled] d'un lancement à l'autre — même
/// patron que `KnownDevicesStore` (JSON minimal sur disque, réécrit en entier à
/// chaque changement), réduit ici à un unique booléen.
class DataSaverStore extends ChangeNotifier {
  DataSaverStore(this._file);

  /// Ouvre le magasin standard de l'appli. À n'appeler qu'après
  /// `WidgetsFlutterBinding.ensureInitialized()`.
  static Future<DataSaverStore> open() async {
    final directory = await getApplicationSupportDirectory();
    final store = DataSaverStore(File(p.join(directory.path, _fileName)));
    await store._load();
    return store;
  }

  static const _fileName = 'data_saver.json';

  final File _file;

  bool get enabled => NetworkPolicy.dataSaverEnabled;

  Future<void> setEnabled(bool value) async {
    if (NetworkPolicy.dataSaverEnabled == value) return;
    NetworkPolicy.dataSaverEnabled = value;
    notifyListeners();
    try {
      await _file.parent.create(recursive: true);
      await _file.writeAsString(jsonEncode({'enabled': value}));
    } catch (e) {
      // Perdre la persistance ne doit pas faire tomber une sortie en cours :
      // le réglage reste juste pour cette session, seul le prochain lancement
      // l'oubliera.
      debugPrint('[économie de données] écriture impossible : $e');
    }
  }

  Future<void> _load() async {
    try {
      if (!await _file.exists()) return;
      final decoded = jsonDecode(await _file.readAsString());
      if (decoded is Map && decoded['enabled'] is bool) {
        NetworkPolicy.dataSaverEnabled = decoded['enabled'] as bool;
      }
    } catch (e) {
      // Fichier tronqué ou d'une version incompatible : on repart de l'état
      // d'usine (désactivé) plutôt que de bloquer le démarrage.
      debugPrint('[économie de données] lecture impossible : $e');
    }
  }
}
