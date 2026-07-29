import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'rider_profile.dart';

/// Le dernier profil connu du cycliste, gardé sur disque.
///
/// Il est mis en cache parce qu'il arrive tard et rarement : c'est la page de
/// navigation qui le pousse, une fois chargée et une fois connectée. Sans cache,
/// une sortie démarrée hors ligne — le cas normal en montagne — n'aurait aucune
/// zone à afficher, alors que ces chiffres ne bougent qu'une fois par mois.
///
/// Même forme que [SiteSession] : un fichier JSON, réécrit en entier, via un
/// temporaire renommé pour qu'une coupure ne laisse jamais un fichier à moitié
/// écrit.
class RiderProfileStore extends ChangeNotifier {
  RiderProfileStore(this._file);

  /// À n'appeler qu'après `WidgetsFlutterBinding.ensureInitialized()`.
  static Future<RiderProfileStore> open() async {
    final directory = await getApplicationSupportDirectory();
    final store = RiderProfileStore(File(p.join(directory.path, _fileName)));
    await store.load();
    return store;
  }

  static const _fileName = 'rider_profile.json';

  final File _file;

  RiderProfile _profile = RiderProfile.empty;
  DateTime? _updatedAt;

  RiderProfile get profile => _profile;

  /// Quand le site l'a dit pour la dernière fois. `null` si on n'a jamais rien
  /// reçu — l'appli vient d'être installée, ou personne ne s'est connecté.
  DateTime? get updatedAt => _updatedAt;

  Future<void> load() async {
    try {
      if (await _file.exists()) {
        final decoded = jsonDecode(await _file.readAsString());
        if (decoded is Map) {
          _profile = RiderProfile.fromJson(decoded['profile']);
          _updatedAt = DateTime.tryParse(decoded['updated_at'] as String? ?? '');
        }
      }
    } catch (e) {
      // Un profil illisible n'est pas un profil faux : on repart sur « inconnu »,
      // que la prochaine page du site corrigera.
      debugPrint('[profil] profil illisible, ignoré : $e');
    }
    notifyListeners();
  }

  /// Enregistre ce que la page vient de publier.
  ///
  /// Un profil entièrement vide est ignoré : il veut dire « le site n'a rien pu
  /// dire » (compte anonyme, aucune sortie avec puissance), et l'écraser ferait
  /// perdre des zones parfaitement valables reçues la veille.
  Future<void> record(RiderProfile profile) async {
    if (profile.ftpWatts == null &&
        profile.lthr == null &&
        !profile.hasPowerZones &&
        !profile.hasHrZones) {
      return;
    }

    _profile = profile;
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
          'profile': _profile.toJson(),
          'updated_at': _updatedAt?.toIso8601String(),
        }),
        flush: true,
      );
      await temporary.rename(_file.path);
    } catch (e) {
      // Perdre la persistance ne coûte qu'un « FTP inconnue » au prochain
      // démarrage : rien qui mérite de remonter à l'utilisateur.
      debugPrint('[profil] écriture impossible : $e');
    }
  }
}
