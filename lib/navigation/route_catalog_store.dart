import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'route_summary.dart';

/// Les itinéraires du compte, gardés sur disque.
///
/// Mis en cache pour la même raison que les seuils du cycliste : ils viennent du
/// site, et le moment où on en a besoin — le départ — est justement celui où le
/// réseau manque le plus souvent. Un parking de col n'a pas de 4G, et c'est là
/// qu'on choisit son tracé.
///
/// Le cache fait donc autorité pour l'affichage : la liste connue s'affiche tout
/// de suite, et le rafraîchissement la corrige quand il aboutit. L'inverse —
/// attendre le réseau pour montrer quelque chose — donnerait une feuille vide
/// pendant deux secondes à chaque départ, et rien du tout hors ligne.
///
/// Même forme que [SiteSession] et `RiderProfileStore` : un fichier JSON réécrit
/// en entier, via un temporaire renommé pour qu'une coupure ne laisse jamais un
/// fichier à moitié écrit.
class RouteCatalogStore extends ChangeNotifier {
  RouteCatalogStore(this._file);

  /// À n'appeler qu'après `WidgetsFlutterBinding.ensureInitialized()`.
  static Future<RouteCatalogStore> open() async {
    final directory = await getApplicationSupportDirectory();
    final store = RouteCatalogStore(File(p.join(directory.path, _fileName)));
    await store.load();
    return store;
  }

  static const _fileName = 'route_catalog.json';

  final File _file;

  List<RouteSummary> _routes = const [];
  DateTime? _updatedAt;

  List<RouteSummary> get routes => List.unmodifiable(_routes);

  /// Quand cette liste a été rapportée du site. `null` si on n'a jamais rien
  /// reçu — c'est ce qui distingue « aucun itinéraire » de « jamais consulté ».
  DateTime? get updatedAt => _updatedAt;

  bool get isEmpty => _routes.isEmpty;

  Future<void> load() async {
    try {
      if (await _file.exists()) {
        final decoded = jsonDecode(await _file.readAsString());
        if (decoded is Map) {
          _routes = RouteSummary.listFromPayload(decoded['routes']);
          _updatedAt =
              DateTime.tryParse(decoded['updated_at'] as String? ?? '');
        }
      }
    } catch (e) {
      // Un cache illisible n'est pas un cache faux : on repart de rien, que le
      // prochain rafraîchissement remplira.
      debugPrint('[itinéraires] cache illisible, ignoré : $e');
    }
    notifyListeners();
  }

  /// Enregistre ce que le site vient de dire.
  ///
  /// Une liste **vide est enregistrée** — contrairement au profil cycliste, où
  /// le vide veut dire « le site n'a rien su dire ». Ici il veut dire « ce
  /// compte n'a pas d'itinéraire », ce qui est une réponse ; et un itinéraire
  /// supprimé sur le site doit disparaître de l'appli.
  Future<void> record(List<RouteSummary> routes) async {
    _routes = List.of(routes);
    _updatedAt = DateTime.now();
    notifyListeners();
    await _write();
  }

  Future<void> _write() async {
    try {
      await _file.parent.create(recursive: true);
      final temporary = File('${_file.path}.tmp');
      await temporary.writeAsString(
        jsonEncode({
          'routes': [for (final route in _routes) route.toJson()],
          'updated_at': _updatedAt?.toIso8601String(),
        }),
        flush: true,
      );
      await temporary.rename(_file.path);
    } catch (e) {
      // Perdre la persistance ne coûte qu'un rafraîchissement de plus au
      // prochain départ : rien qui mérite de remonter au cycliste.
      debugPrint('[itinéraires] écriture impossible : $e');
    }
  }
}
