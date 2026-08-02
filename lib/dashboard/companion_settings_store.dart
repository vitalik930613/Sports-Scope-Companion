import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'companion_settings.dart';
import 'ride_preset.dart';

/// Les profils de sortie du compte, gardés sur disque, **et le profil choisi**.
///
/// Mis en cache pour la même raison que les seuils du cycliste et le catalogue
/// d'itinéraires : ils viennent du site, et le moment où on en a besoin — le
/// départ — est celui où le réseau manque le plus souvent. Le cache fait donc
/// autorité pour l'affichage ; le rafraîchissement le corrige quand il aboutit.
///
/// **C'est le document brut qui est gardé, pas le modèle décodé.** Une version
/// plus récente de l'appli comprendra alors des composants qu'une version plus
/// ancienne avait rapportés sans savoir les lire — sans quoi une mise à jour
/// obligerait à repasser par le réseau pour retrouver ce qui était déjà sur le
/// téléphone.
///
/// Le profil choisi, lui, est **local** : c'est un geste du cycliste au départ,
/// pas une donnée du compte. Le garder ici plutôt que dans un écran, c'est ce
/// qui fait qu'un enregistrement lancé depuis l'accueil part avec les mêmes
/// capteurs que la navigation ouverte deux minutes plus tard.
///
/// Même forme d'écriture que [RouteCatalogStore] et `SiteSession` : un fichier
/// JSON réécrit en entier, via un temporaire renommé pour qu'une coupure ne
/// laisse jamais un fichier à moitié écrit.
class CompanionSettingsStore extends ChangeNotifier {
  CompanionSettingsStore(this._file);

  /// À n'appeler qu'après `WidgetsFlutterBinding.ensureInitialized()`.
  static Future<CompanionSettingsStore> open() async {
    final directory = await getApplicationSupportDirectory();
    final store = CompanionSettingsStore(File(p.join(directory.path, _fileName)));
    await store.load();
    return store;
  }

  static const _fileName = 'companion_settings.json';

  final File _file;

  Object? _document;
  CompanionSettings _settings = CompanionSettings.fallback;
  String? _selectedKey;
  DateTime? _updatedAt;

  CompanionSettings get settings => _settings;

  /// Le profil de la sortie. Jamais nul : à défaut de choix, ou si le site a
  /// supprimé celui qu'on avait retenu, c'est le premier de la liste.
  RidePreset get preset => _settings.select(_selectedKey);

  /// La clé retenue, `null` tant que le cycliste n'a rien choisi.
  String? get selectedKey => _selectedKey;

  /// Quand le site a dit ça pour la dernière fois. `null` si on n'a jamais rien
  /// reçu — appli fraîchement installée, ou personne jamais connecté.
  DateTime? get updatedAt => _updatedAt;

  /// Y a-t-il un choix à proposer ? À une seule entrée, le sélecteur du départ
  /// n'est que du bruit sur l'écran d'avant-départ.
  bool get hasChoice => _settings.presets.length > 1;

  Future<void> load() async {
    try {
      if (await _file.exists()) {
        final decoded = jsonDecode(await _file.readAsString());
        if (decoded is Map) {
          _document = decoded['document'];
          _settings = CompanionSettings.parse(_document);
          _selectedKey = decoded['selected'] as String?;
          _updatedAt = DateTime.tryParse(decoded['updated_at'] as String? ?? '');
        }
      }
    } catch (e) {
      // Un cache illisible n'est pas un cache faux : on repart du tableau de
      // bord intégré, que le prochain rafraîchissement corrigera.
      debugPrint('[profils] cache illisible, ignoré : $e');
    }
    notifyListeners();
  }

  /// Enregistre le document que le site vient de servir.
  ///
  /// Un document **sans profil exploitable est refusé**, contrairement au
  /// catalogue d'itinéraires où le vide veut dire « ce compte n'a pas
  /// d'itinéraire ». Ici il veut dire « le site n'a rien su dire » — endpoint
  /// absent sur une version plus ancienne, réponse tronquée — et l'écraser
  /// ferait perdre des profils parfaitement valables reçus la veille.
  Future<void> record(Object? document) async {
    final parsed = CompanionSettings.parse(document);
    if (identical(parsed, CompanionSettings.fallback)) {
      debugPrint('[profils] document sans profil exploitable, cache conservé');
      return;
    }

    _document = document;
    _settings = parsed;
    _updatedAt = DateTime.now();
    notifyListeners();
    await _write();
  }

  /// Le cycliste choisit son profil.
  ///
  /// La clé est gardée telle quelle, même si elle ne désigne rien : le site peut
  /// la rétablir demain, et [preset] sait déjà retomber sur le premier profil en
  /// attendant.
  Future<void> select(String key) async {
    if (_selectedKey == key) return;
    _selectedKey = key;
    notifyListeners();
    await _write();
  }

  Future<void> _write() async {
    try {
      await _file.parent.create(recursive: true);
      final temporary = File('${_file.path}.tmp');
      await temporary.writeAsString(
        jsonEncode({
          'document': _document,
          'selected': _selectedKey,
          'updated_at': _updatedAt?.toIso8601String(),
        }),
        flush: true,
      );
      await temporary.rename(_file.path);
    } catch (e) {
      // Perdre la persistance coûte un rafraîchissement de plus au prochain
      // lancement, et le profil par défaut en attendant : rien qui mérite de
      // remonter au cycliste avant une sortie.
      debugPrint('[profils] écriture impossible : $e');
    }
  }
}
